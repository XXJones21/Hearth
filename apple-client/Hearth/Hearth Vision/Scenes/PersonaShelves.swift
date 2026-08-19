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

            ForEach(Self.destinations) { surface in
                PersonaShelfButton(icon: surface.icon,
                                   title: surface.title,
                                   isActive: active == surface) {
                    active = (active == surface) ? nil : surface
                }
            }
        }
    }

    /// Journal is absent, and absent rather than present-and-dead.
    ///
    /// Its centre slot is not a panel: it is the library's ENTITIES, and the
    /// room has none yet. A bookcase in a room is a different object from a
    /// bookcase in a box -- life size rather than 0.765, standing on the floor,
    /// with the clipping and the drag-to-scroll taken OFF because you walk to
    /// it instead. That is its own piece of work; until it lands, an icon that
    /// lights and shows nothing would be worse than an icon that is not there.
    static var destinations: [HouseSurface] {
        HouseSurface.allCases.filter { $0 != .journal }
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
/// drawer draws it, and only a menu at all when there is something to choose.
/// A menu that opens onto one disabled row is a control that lied about being
/// one.
private struct PersonaSwitchButton: View {
    @ObservedObject var viewModel: ChatViewModel

    private var canSwitch: Bool {
        viewModel.connectionStatus == .connected && viewModel.availablePersonas.count > 1
    }

    var body: some View {
        Group {
            if canSwitch {
                Menu {
                    ForEach(viewModel.availablePersonas, id: \.self) { name in
                        Button {
                            viewModel.switchPersona(name)
                        } label: {
                            if name == viewModel.selectedPersona {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    face
                }
                .buttonStyle(.plain)
            } else {
                face
            }
        }
        .accessibilityLabel("Persona: \(viewModel.currentPersonaName). Switch.")
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
