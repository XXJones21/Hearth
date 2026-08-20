//
//  RendererAB.swift
//  Hearth
//
//  The A/B harness for the iOS persona renderer investigation. TEMPORARY, and
//  it should leave with the branch: the whole point of the exercise is to end
//  with ONE renderer rather than a preference.
//
//  Two things are being compared and only one of them is "which looks better".
//  The other is what it costs, because the phone is where a Metal kernel and a
//  particle simulator running behind a live conversation shows up first -- and
//  a renderer that wins on looks and loses on battery has not won. So the
//  switch carries a frame-time readout, which is a blunt instrument and enough
//  to tell a 60fps answer from a 40fps one.
//

import SwiftUI

/// Which persona renderer the stage is using.
enum PersonaRenderer: String, CaseIterable, Identifiable {
    /// The shipped SwiftUI Canvas orb.
    case canvas
    /// The headset's rig in a flat RealityView, lights off, embers kept.
    case reality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .canvas:  return "Canvas orb"
        case .reality: return "RealityKit fire"
        }
    }

    static let storageKey = "hearth.investigate.personaRenderer"
}

/// A rolling mean frame time, sampled off the SwiftUI clock.
///
/// NOT an instrument. It measures how often this view is asked to redraw, which
/// on a busy stage is a reasonable stand-in for the frame rate and on an idle
/// one is exactly the display's refresh. It is here to catch a renderer that
/// halves the frame rate, not to report a number anyone should quote.
struct FrameCostReadout: View {
    @State private var last: Date?
    @State private var mean: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let text = mean > 0
                ? String(format: "%.1f ms  ·  %.0f fps", mean * 1000, 1 / mean)
                : "sampling…"
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .onChange(of: timeline.date) { _, now in
                    defer { last = now }
                    guard let last else { return }
                    let dt = now.timeIntervalSince(last)
                    // Ignore the first frame after a stall -- a backgrounded
                    // app returns with a delta of seconds, which would poison
                    // the mean for a minute.
                    guard dt > 0, dt < 0.25 else { return }
                    mean = mean == 0 ? dt : mean * 0.9 + dt * 0.1
                }
        }
    }
}

/// The switch itself. Sits on the stage rather than in Settings, because an
/// A/B you have to go and find is an A/B nobody runs twice.
struct RendererSwitch: View {
    @AppStorage(PersonaRenderer.storageKey) private var raw = PersonaRenderer.canvas.rawValue

    var body: some View {
        VStack(spacing: 4) {
            Picker("Renderer", selection: $raw) {
                ForEach(PersonaRenderer.allCases) { renderer in
                    Text(renderer.title).tag(renderer.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            FrameCostReadout()
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
