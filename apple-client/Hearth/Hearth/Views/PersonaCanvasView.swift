//
//  PersonaCanvasView.swift
//  Hearth
//
//  Animated wrapper around PersonaOrb (the shared Canvas drawer) for the live
//  app UI: a TimelineView drives the orbit/breath/shimmer/wave clocks, and the
//  particle field eases into the speaking waveform (waveBlend) while SPEAKING.
//  Widgets render PersonaOrb directly as a single static frame instead.
//
//  Chosen over RealityKit for Sulivan because: (1) it matches Echo's painterly
//  glow (RealityKit has no bloom/additive blend), (2) the speaking waveform is
//  trivial here, and (3) it is reusable in WidgetKit widgets (iOS + visionOS),
//  which render static SwiftUI and cannot host a live RealityView. RealityKit
//  stays for the visionOS immersive window and glb personas (Selene).
//

import SwiftUI
import HearthCore

struct PersonaCanvasView: View {
    let state: HearthState
    /// TTS amplitude 0..1 (drives the speaking waveform). 0 when not speaking.
    var pulse: Double = 0
    var reducedMotion: Bool = false
    /// The active persona's orb colours (data-driven from its config).
    var palette: PersonaPalette = .fallback

    @State private var waveBlend: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reducedMotion)) { timeline in
            PersonaOrb(
                state: state,
                pulse: pulse,
                date: timeline.date,
                waveBlend: waveBlend,
                reducedMotion: reducedMotion,
                palette: palette
            )
        }
        .onChange(of: state) { _, newState in
            withAnimation(.easeInOut(duration: 0.32)) {
                waveBlend = (newState == .SPEAKING && !reducedMotion) ? 1 : 0
            }
        }
        .onAppear {
            waveBlend = (state == .SPEAKING && !reducedMotion) ? 1 : 0
        }
    }
}
