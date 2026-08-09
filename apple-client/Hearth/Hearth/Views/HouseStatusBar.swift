//
//  HouseStatusBar.swift
//  Hearth
//
//  The quiet strip above the composer: who in the house is doing what, right
//  now. Persona state + live tool activity (`pipeline_stage`), on one line.
//  Swift port of `hearth-client/src/components/feed/StatusBar.tsx`.
//
//  Valinor also polled `/mentat/state` here and appended a second line for it.
//  Mentat is one house's internal agent, not a Hearth surface, and the route
//  does not exist on this backend -- the poller would have run forever against
//  a 404 to append a line that never arrives.
//
//  It renders NOTHING when the house is idle — the resting screen stays calm,
//  and the bar never reserves space it isn't using.
//

import SwiftUI
import HearthCore

struct HouseStatusBar: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        let items = statusItems
        Group {
            if !items.isEmpty {
                HStack(spacing: 16) {
                    ForEach(items, id: \.self) { text in
                        HStack(spacing: 6) {
                            PulsingDot()
                            Text(text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(HearthPalette.fawn)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items)
    }

    /// Tool line wins over the generic persona state — "Setting up the easel"
    /// is strictly more informative than "Sulivan is thinking".
    private var statusItems: [String] {
        var items: [String] = []
        let persona = viewModel.currentPersonaName

        if let tool = Self.toolLabel(viewModel.activeTools) {
            items.append("\(tool)…")
        } else {
            switch viewModel.hearthState {
            case .THINKING:  items.append("\(persona) is thinking…")
            case .SPEAKING:  items.append("\(persona) is speaking")
            case .LISTENING: items.append("Listening")
            default:
                if viewModel.isWaitingForResponse {
                    items.append("\(persona) is thinking…")
                }
            }
        }

        return items
    }

    /// House language for the tools, mirroring the desktop's table. An unmapped
    /// tool still says something honest rather than going silent.
    ///
    /// Four rows came out with the house they belonged to: `consult_liara`
    /// ("Ringing the trading desk"), `mentat_`, `wright` and `uefn_`. The table
    /// is data, so dropping them is a four-line deletion -- but it had to
    /// actually happen, or a Hearth user would occasionally be told the house
    /// is ringing a trading desk that does not exist. An unmapped tool now
    /// falls through to "Working: <name>", which is honest.
    private static let toolLabels: [(prefix: String, label: String)] = [
        ("consult_memory", "Consulting Selene in the library"),
        ("recall", "Leafing through memory"),
        ("remember", "Leafing through memory"),
        ("forge_card", "Commissioning the workshop"),
        ("list_cards", "Checking the workshop inventory"),
        ("generate_image", "Setting up the easel"),
        ("check_image", "Checking the easel"),
        ("get_weather", "Checking the weather"),
        ("web_search", "Looking that up"),
        ("news_headlines", "Looking that up"),
        ("set_timer", "Minding the timers"),
        ("list_timers", "Minding the timers"),
        ("cancel_timer", "Minding the timers"),
    ]

    static func toolLabel(_ names: [String]) -> String? {
        for name in names {
            if let match = toolLabels.first(where: { name.hasPrefix($0.prefix) }) {
                return match.label
            }
        }
        return names.first.map { "Working: \($0)" }
    }
}

/// The 6pt fennec dot that breathes while something is running.
private struct PulsingDot: View {
    @State private var faded = false

    var body: some View {
        Circle()
            .fill(HearthPalette.fennec)
            .frame(width: 6, height: 6)
            .opacity(faded ? 0.35 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    faded = true
                }
            }
    }
}
