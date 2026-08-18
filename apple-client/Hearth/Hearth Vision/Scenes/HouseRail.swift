//
//  HouseRail.swift
//  Hearth Vision
//
//  The right rail: mission control, docked to the right face of the volume.
//
//  THE DESKTOP'S THIRD COLUMN, and this file is a port rather than an
//  invention. `AppFrame` is three slots -- persona stage, active view, rail --
//  and the rail carries three tabs in this order: Sessions, Memory, Routines.
//  Phase 0 gave the volume the first two slots; this is the third, and with it
//  the headset finally has the shape the desktop has had all along.
//
//  WHY IT IS A SHELF AND NOT A TAB ROW. At the desk the rail is always open and
//  its tabs are a row of pills across the top. A volume cannot afford that: the
//  rail is a third of the box's width, and a person who came to look at the orb
//  should not have to look past a sessions list to do it. So the tabs become a
//  VERTICAL button shelf on the right face, mirroring the bottom shelf exactly
//  -- press an icon to open its panel, press the lit one to put it away. The
//  desktop's arrangement, made collapsible because the box is smaller than a
//  monitor.
//
//  Ornaments render OUTSIDE the volume's bounds, which is what makes this
//  affordable: the shelf costs the stage nothing, and only the open panel takes
//  width from the centre slot. That is the same trade the bottom shelf makes.
//

import SwiftUI
import HearthCore
import HearthUI

/// One tab of mission control.
enum HouseRailTab: String, CaseIterable, Identifiable {
    case sessions
    case memory
    case routines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "Sessions"
        case .memory:   return "Memory"
        case .routines: return "Routines"
        }
    }

    /// The desktop labels these in words; a vertical shelf of three words would
    /// be a wall of text next to a shelf of icons, so they get drawings from
    /// the same brand set at the same weight.
    @ViewBuilder
    var icon: some View {
        switch self {
        case .sessions: HearthIcon(shape: BubbleIcon())
        case .memory:   HearthIcon(shape: HeartIcon())
        case .routines: HearthIcon(shape: ClockIcon())
        }
    }
}

/// The shelf itself: three icons stacked, and which one is lit.
///
/// Deliberately the same control as `HouseShelfOrnament` turned on its side --
/// same sizes, same padding, same press-the-lit-one-to-close gesture -- because
/// two shelves that behave differently are two things to learn.
struct HouseRailOrnament: View {
    @Binding var active: HouseRailTab?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(HouseRailTab.allCases) { tab in
                Button {
                    active = (active == tab) ? nil : tab
                } label: {
                    tab.icon
                        .frame(width: 20, height: 20)
                        .foregroundStyle(active == tab
                                         ? HearthPalette.ember
                                         : HearthPalette.roast)
                        .padding(9)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .glassBackgroundEffect()
    }
}

/// The docked panel, when a tab is open.
struct HouseRailPanel: View {
    @ObservedObject var viewModel: ChatViewModel
    let tab: HouseRailTab
    let onClose: () -> Void

    /// Narrower than the centre slot and wider than the desktop's minimum. The
    /// desktop rail defaults to 320px and clamps to [240, 560]; this is one
    /// number rather than a drag because a volume already has a resize gesture
    /// and giving it a second one inside the first is how the scroll got
    /// finicky the first time.
    static let width: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tab.title)
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
                .accessibilityLabel("Close \(tab.title)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(HearthPalette.parchment)

            Divider()

            content
        }
        .frame(width: Self.width, height: 720)
        .background(HearthPalette.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // Same two lines as the centre slot, for the same reason: no navigation
        // chrome in an attachment, and a way out that is not `dismiss`.
        .environment(\.hearthSurfaceChrome, .bare)
        .environment(\.hearthSurfaceClose, onClose)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        // The phone's own sessions screen, unchanged. It was written for a
        // full-width column and reads fine at 320 because every row in it is a
        // stack rather than a table.
        case .sessions: SessionsView(viewModel: viewModel)
        case .memory:   MemoryTabView()
        case .routines: RoutinesNote()
        }
    }
}

/// Routines, and why there are none.
///
/// The desktop's `RoutinesTab` renders three rows -- Morning brief, Wind down,
/// Nightly memory review -- from a `const routines` literal in the client. They
/// are not read from the house, their toggles write nothing, and no route
/// exists behind them. Porting them would put a schedule in front of someone
/// that the house has never agreed to keep, which is the same fault the desktop
/// Memory tab was corrected for on 2026-08-05.
///
/// So the tab exists, because the rail's shape is the desktop's, and it says
/// what is true.
private struct RoutinesNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standing routines")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(HearthPalette.fawn)
            Text("Nothing scheduled yet. When the house can hold a routine, the ones you have set will appear here.")
                .font(.system(size: 12.5))
                .foregroundStyle(HearthPalette.fawn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
