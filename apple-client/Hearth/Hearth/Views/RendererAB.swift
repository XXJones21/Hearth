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
    /// Whatever the persona's own config asks for -- for Sulivan today, the
    /// drawn face. The control, not a candidate.
    case shipped
    /// The flame drawn with vector primitives in a SwiftUI Canvas.
    ///
    /// The decision, taken 2026-08-20. The RealityKit route was built, looked
    /// excellent, and lost on the two things that decide a phone: it cost more
    /// (18.2ms against 16.7ms) and it would have been a second persona renderer
    /// on a platform that already needs this one for widgets. One
    /// implementation beats a better-looking second one.
    case canvasFire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shipped:    return "Shipped"
        case .canvasFire: return "Canvas fire"
        }
    }

    static let storageKey = "hearth.investigate.personaRenderer"
}

/// A rolling mean frame time, sampled off the SwiftUI clock.
///
/// READ THE NEXT PARAGRAPH BEFORE BELIEVING THIS NUMBER.
///
/// It measures how often THIS view is asked to redraw, and this view has its
/// own `TimelineView(.animation)`. So it reports the display's refresh whatever
/// the persona beside it is doing -- and on the first device run it duly said
/// 60fps for a canvas flame that was completely frozen. That is not a small
/// caveat, it is the instrument measuring itself.
///
/// It still catches the case it was built for: a renderer heavy enough to stall
/// the whole main thread drags this down with it. What it cannot see is a
/// renderer that is cheap because it is not drawing. Judge motion with your
/// eyes; use this only for cost.
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
    @AppStorage(PersonaRenderer.storageKey) private var raw = PersonaRenderer.shipped.rawValue

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
