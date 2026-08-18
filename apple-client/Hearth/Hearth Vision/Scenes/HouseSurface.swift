//
//  HouseSurface.swift
//  Hearth Vision
//
//  The house's destinations, and the shelf that opens them.
//
//  Four of the five the phone's HouseShelf carries: Journal, Persona, Apps,
//  Settings. The phone puts them in a drawer that slides over the stage; here
//  they get the desktop's arrangement instead, and that is a deliberate borrow
//  rather than a third invention.
//
//  SESSIONS IS NOT HERE, and its absence is the borrow being taken seriously.
//  On the desktop, Sessions is the right rail's first tab and has never been a
//  centre-column destination -- so putting it on the bottom shelf as well would
//  be the same content in two places, reached two ways, with two ideas about
//  where it lives. It moved to HouseRail, which is where the desktop keeps it.
//
//  THE DESKTOP'S SHAPE. `AppFrame` is three slots -- the persona stage on the
//  left, the active view in the centre, the rail on the right -- and a volume
//  is the one Apple surface with room for it. So opening a destination slides
//  the orb to the left of the box and puts the view in the middle, which is
//  what the desktop has looked like all along. The phone cannot do this because
//  a phone has one column; the headset should not pretend it has the same
//  constraint.
//
//  What is NOT here: new views. Every panel below is the shared surface the
//  phone renders, from HearthUI, unchanged. That was the whole point of pulling
//  them out of the iOS target in phase 0, and a Vision-shaped copy of Settings
//  would be the second settings screen to keep in step with the first.
//

import SwiftUI
import HearthCore
import HearthUI

/// One destination off the shelf.
enum HouseSurface: String, CaseIterable, Identifiable {
    case journal
    case persona
    case apps
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal:  return "Journal"
        case .persona:  return "Persona"
        case .apps:     return "Apps"
        case .settings: return "Settings"
        }
    }

    /// The phone's icons, from the shared brand set, so the two shelves are
    /// recognisably the same shelf.
    @ViewBuilder
    var icon: some View {
        switch self {
        case .journal:  HearthIcon(shape: BookIcon())
        case .persona:  HearthIcon(shape: PersonIcon())
        case .apps:     HearthIcon(shape: GridIcon())
        case .settings: HearthIcon(shape: GearIcon())
        }
    }
}

/// The centre slot: whichever destination is open.
struct HouseSurfacePanel: View {
    @ObservedObject var viewModel: ChatViewModel
    let surface: HouseSurface
    /// How wide the centre slot is allowed to be.
    ///
    /// The desktop's three columns are a grid: opening the right rail takes its
    /// width out of the centre rather than covering it. A volume has the same
    /// finite width and no scrollbar to hide behind, so the centre narrows for
    /// the rail exactly as it does at the desk -- otherwise the rail either
    /// stands in front of the panel or pushes past the box's right face.
    var width: CGFloat = 560
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The panel's own way out.
            //
            // The shared views used to carry their own "Hearth" back button
            // inside a NavigationStack, which in an attachment was worse than
            // useless: `dismiss` had no presentation to pop, and visionOS drew
            // the navigation container's material as a glass slab IN FRONT of
            // the content that swallowed every pinch. The panel now asks for
            // `.bare` chrome and wears this header instead. See
            // HearthUI/Surfaces/SurfaceChrome.swift.
            HStack {
                Text(surface.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HearthPalette.roast)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(surface.title)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(HearthPalette.parchment)

            Divider()

            content
        }
        .frame(width: width, height: 720)
        .background(HearthPalette.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // The two halves of the fix: draw no navigation chrome, and give the
        // shared views a way out that works here.
        .environment(\.hearthSurfaceChrome, .bare)
        .environment(\.hearthSurfaceClose, onClose)
    }

    @ViewBuilder
    private var content: some View {
        switch surface {
        // Journal never reaches here: it opens the library VOLUME instead, so
        // its books can be real entities on real shelves. MainVolume
        // intercepts it. This case exists so the switch stays exhaustive and
        // the enum stays one list of destinations.
        case .journal:  EmptyView()
        case .persona:  PersonaView(viewModel: viewModel)
        case .apps:     AppsView(viewModel: viewModel)
        case .settings: HearthSettingsView(viewModel: viewModel)
        }
    }
}

/// The shelf: four icons, and which one is lit.
struct HouseShelfOrnament: View {
    @Binding var active: HouseSurface?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HouseSurface.allCases) { surface in
                Button {
                    // Pressing the lit one puts it away, which is the same
                    // gesture doing the same thing in both directions.
                    active = (active == surface) ? nil : surface
                } label: {
                    surface.icon
                        .frame(width: 20, height: 20)
                        .foregroundStyle(active == surface
                                         ? HearthPalette.ember
                                         : HearthPalette.roast)
                        .padding(9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(surface.title)
                .accessibilityAddTraits(active == surface ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassBackgroundEffect()
    }
}
