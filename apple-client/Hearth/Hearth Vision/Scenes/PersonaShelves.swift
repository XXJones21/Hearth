//
//  PersonaShelves.swift
//  Hearth Vision
//
//  The house's controls, in a room, attached to the persona.
//
//  THE PROBLEM THEY SOLVE. Every control the volume has -- house status, the
//  four-icon shelf, the right rail, the composer -- is an ORNAMENT on a window,
//  and an `ImmersiveSpace` has no ornaments. Dismissing the volume for the room
//  took the entire client interface with it and left a persona standing in a
//  room with no way to reach anything.
//
//  THE ANSWER, and it is the operator's rather than any of the three this file
//  was originally going to choose between: the controls belong to the PERSONA.
//  Not to a window, which the room does not have, and not to the room, which
//  would leave them behind when she moves. They hang off `personaAnchor` like
//  the cards and the caption already do, so they travel with her, turn with
//  her, and are wherever she is when you want them.
//
//  Left is where you GO -- the four destinations, and which persona is home.
//  Right is mission control -- the desktop rail's three tabs. The same split
//  the box has, turned ninety degrees and stood either side of her instead of
//  along two edges of a box that is no longer there.
//
//  MOSTLY HIDDEN, AND THE CONSTRAINT THAT SHAPES IT. A room should hold a
//  persona, not a persona and a control panel, so the shelves rest nearly
//  invisible and come up when looked at. That is `CustomHoverEffect`, and it is
//  the only way to do it: gaze is private, there is no API that reports it, and
//  the docs are explicit that a hover effect "may be applied to a view
//  out-of-process" so its "current phase may not be visible within your app".
//
//  Two things follow. The fade is PURELY presentational -- the buttons stay
//  hit-testable at rest, which is fine because a pinch lands where you are
//  looking. And nothing in app logic may ever ask whether a shelf is showing,
//  because nothing can.
//
//  `hoverEffectGroup()` is what makes the shelf one object rather than five
//  icons that light individually: a look anywhere on it brings all of it up.
//

import SwiftUI
import HearthCore
import HearthUI

/// A column of controls beside the persona, resting almost invisible.
struct PersonaSideShelf<Content: View>: View {
    @ViewBuilder var content: Content

    /// How visible the shelf is when nobody is looking at it.
    ///
    /// Not zero, and that is the judgement in this file. Invisible until looked
    /// at means invisible until GUESSED at -- there would be nothing to tell a
    /// person the controls exist or where. A faint presence is a thing you can
    /// learn the position of once and then find; nothing is a thing you have to
    /// be told about.
    private static var restingOpacity: Double { 0.14 }

    var body: some View {
        VStack(spacing: 6) {
            content
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .glassBackgroundEffect()
        .hoverEffect { effect, isActive, _ in
            effect.animation(.easeOut(duration: 0.22)) {
                $0.opacity(isActive ? 1 : Self.restingOpacity)
            }
        }
        // One object, not five. A look anywhere on the shelf raises all of it.
        .hoverEffectGroup()
    }
}

/// One icon on a shelf, lit when its thing is open.
struct PersonaShelfButton<Icon: View>: View {
    let icon: Icon
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: 20, height: 20)
                .foregroundStyle(isActive ? HearthPalette.ember : HearthPalette.roast)
                .padding(9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

/// Where you GO: the four destinations, and who is home.
struct PersonaDestinationShelf: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var active: HouseSurface?

    /// Pull the journal off the shelf. See `PersonaShelfDragOut` for why this
    /// destination works differently from the other three.
    var onSpawnLibrary: () -> Void = {}
    /// Whether the bookcase is already standing in the room.
    var libraryPlaced = false

    var body: some View {
        PersonaSideShelf {
            // Persona switching lives here rather than on a status strip.
            //
            // In the box it hung off the strip that was already naming the
            // persona, where a menu on that name cost nothing. A room has no
            // strip, and switching is a thing you go and do rather than a thing
            // you notice in passing -- so it goes where going and doing lives.
            PersonaSwitchButton(viewModel: viewModel)

            Divider()
                .frame(width: 22)
                .padding(.vertical, 2)

            // Journal is not a panel and never was: its centre slot is a
            // BOOKCASE. In a box that had to be a scaled-down thing inside the
            // window; in a room it is furniture you put somewhere and walk to,
            // which is what pulling it off the shelf means.
            PersonaShelfDragOut(icon: HouseSurface.journal.icon,
                                title: HouseSurface.journal.title,
                                isActive: libraryPlaced,
                                onPullOut: onSpawnLibrary)

            ForEach(Self.destinations) { surface in
                PersonaShelfButton(icon: surface.icon,
                                   title: surface.title,
                                   isActive: active == surface) {
                    active = (active == surface) ? nil : surface
                }
            }
        }
    }

    /// The three that open a PANEL. Journal is handled above, because it does
    /// not open a panel -- it puts a bookcase in your room.
    static var destinations: [HouseSurface] {
        HouseSurface.allCases.filter { $0 != .journal }
    }
}

/// An icon you PULL something out of, rather than press.
///
/// The gesture the operator described, and the one this whole design has been
/// building toward: pinch the icon, drag away from the shelf, and once the grab
/// has left the icon behind, the thing it stands for is spawned into the room
/// for you to place. A press puts a panel in front of you; a pull puts an
/// object in your space.
///
/// The threshold is measured as DISTANCE DRAGGED rather than as leaving a
/// collision box, which is the same idea expressed in the units a SwiftUI
/// attachment actually has. An attachment is a plane hosting a view; its
/// buttons know how far a drag has travelled and not where its collision shape
/// ends.
///
/// Fires ONCE per gesture. Without the latch a slow drag past the threshold
/// spawns a bookcase on every frame it keeps moving.
struct PersonaShelfDragOut<Icon: View>: View {
    let icon: Icon
    let title: String
    let isActive: Bool
    let onPullOut: () -> Void

    /// How far the pinch has to travel before it counts as pulling out. Far
    /// enough that a press with a shaky hand is still a press.
    private static var pullThreshold: CGFloat { 44 }

    @State private var pulled = false

    var body: some View {
        icon
            .frame(width: 20, height: 20)
            .foregroundStyle(isActive ? HearthPalette.ember : HearthPalette.roast)
            .padding(9)
            .contentShape(Rectangle())
            .hoverEffect()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !pulled else { return }
                        let travelled = hypot(value.translation.width, value.translation.height)
                        guard travelled > Self.pullThreshold else { return }
                        pulled = true
                        onPullOut()
                    }
                    .onEnded { _ in pulled = false }
            )
            .accessibilityLabel("\(title). Pull out to place it in the room.")
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

/// Mission control: the desktop rail's three tabs.
struct PersonaRailShelf: View {
    @Binding var active: HouseRailTab?

    var body: some View {
        PersonaSideShelf {
            ForEach(HouseRailTab.allCases) { tab in
                PersonaShelfButton(icon: tab.icon,
                                   title: tab.title,
                                   isActive: active == tab) {
                    active = (active == tab) ? nil : tab
                }
            }
        }
    }
}

/// Who is home, and the way to change it.
///
/// The same rules the status ornament settled: a live switch rather than
/// Settings' "Start with" pin, a tick on `selectedPersona` as the phone's
/// drawer draws it, and only offered at all when there is something to choose.
/// A control that opens onto one disabled row is a control that lied about
/// being one.
///
/// NOT A MENU, and that is the room's constraint rather than a preference:
/// "Presentations are not currently supported in Immersive contexts". A `Menu`
/// is a presentation, so in a room it logs that and shows nothing -- the same
/// goes for popovers, sheets and alerts. The shelf therefore grows DOWNWARD
/// instead: pressing the dot unrolls the personas as more rows of the shelf,
/// which is the same list in the same place without asking the system to
/// present anything.
private struct PersonaSwitchButton: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var expanded = false

    private var canSwitch: Bool {
        viewModel.connectionStatus == .connected && viewModel.availablePersonas.count > 1
    }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                guard canSwitch else { return }
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                face
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Persona: \(viewModel.currentPersonaName)"
                                + (canSwitch ? ". Switch." : ""))

            if expanded {
                ForEach(viewModel.availablePersonas, id: \.self) { name in
                    Button {
                        viewModel.switchPersona(name)
                        withAnimation(.easeOut(duration: 0.18)) { expanded = false }
                    } label: {
                        Text(name.prefix(1))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(name == viewModel.selectedPersona
                                             ? HearthPalette.ember
                                             : HearthPalette.roast)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(name == viewModel.selectedPersona ? [.isSelected] : [])
                }
            }
        }
        // A list that stays unrolled behind your back is clutter the next time
        // you look at the shelf.
        .onChange(of: canSwitch) { _, can in if !can { expanded = false } }
    }

    /// A dot in the persona's own accent rather than an icon, because the
    /// question this control answers is "who", and the answer is a colour
    /// before it is a name.
    private var face: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 16, height: 16)
            .padding(11)
    }

    private var dotColor: Color {
        switch viewModel.connectionStatus {
        case .connected:    return HearthPalette.sage
        case .connecting:   return HearthPalette.honey
        case .disconnected: return HearthPalette.clay
        }
    }
}
