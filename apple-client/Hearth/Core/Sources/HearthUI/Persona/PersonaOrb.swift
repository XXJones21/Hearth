//
//  PersonaOrb.swift
//  Hearth  (shared by the app target AND the Hearth WidgetExtension target)
//
//  The actual Canvas drawing of Sulivan's sphere_particle persona — a single
//  frame for a given animation time. The app wraps this in a TimelineView for
//  live animation (PersonaCanvasView); widgets render one static frame (they
//  can't run TimelineView(.animation)). Ported from Echo's PersonaCanvas.kt.
//
//  IMPORTANT: tick this file into the Hearth WidgetExtension target membership
//  in Xcode (it is reused by PersonaStatusWidget).
//

import SwiftUI
import HearthCore

public struct PersonaOrb: View {
    public var state: HearthState
    /// TTS amplitude 0..1 (drives the speaking waveform).
    var pulse: Double = 0
    /// Animation time source. Use `.now` while animating; any fixed date when static.
    var date: Date = .distantPast
    /// 0 = orbit, 1 = speaking waveform (the app animates this; widgets pass 0).
    var waveBlend: Double = 0
    var reducedMotion: Bool = false

    /// The persona's orb colours, data-driven from its config. Defaults to the
    /// warm HearthPalette fallback so widgets (which have no live connection)
    /// render warm too; the app injects the live palette via PersonaCanvasView.
    public var palette: PersonaPalette = .fallback

    private let particles = PersonaParticle.field()

    /// Explicit, because a public struct's synthesized memberwise initializer is
    /// internal and would leave this View visible from the app targets but not
    /// constructible by them.
    public init(
        state: HearthState,
        pulse: Double = 0,
        date: Date = .distantPast,
        waveBlend: Double = 0,
        reducedMotion: Bool = false,
        palette: PersonaPalette = .fallback
    ) {
        self.state = state
        self.pulse = pulse
        self.date = date
        self.waveBlend = waveBlend
        self.reducedMotion = reducedMotion
        self.palette = palette
    }

    public var body: some View {
        Canvas { ctx, size in draw(into: ctx, size: size) }
    }

    private func draw(into ctx: GraphicsContext, size: CGSize) {
        let p = pulse.clamped(0, 1)

        let elapsed = reducedMotion ? 0 : date.timeIntervalSinceReferenceDate
        let time = (elapsed.truncatingRemainder(dividingBy: 12) / 12) * 2 * .pi
        let breath = reducedMotion ? 0 : triangle(elapsed, half: 3.8)
        let shimmer = reducedMotion ? 0.5 : triangle(elapsed, half: 1.6)
        let wave = reducedMotion ? 0 : elapsed.truncatingRemainder(dividingBy: 1.3) / 1.3

        let v = visual(for: state, shimmer: shimmer, breath: breath, pulse: p)

        let cx = size.width / 2
        let cy = size.height / 2
        let field = min(size.width, size.height) / 2
        let sphereRadius = field * 0.34 * v.swell
        let orbitRadius = field * 0.92 * v.spread

        // Radial glow halo behind the sphere.
        let haloR = sphereRadius * 2.6
        ctx.fill(
            circlePath(cx: cx, cy: cy, r: haloR),
            with: .radialGradient(
                Gradient(colors: [v.glow.opacity(0.55 * v.brightness), v.glow.opacity(0)]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: haloR
            )
        )

        // Particle field (orbit at rest, easing into the speaking waveform).
        let twoPi = 2.0 * Double.pi
        let waveHalfWidth = field * 0.95
        let waveCycles = 2.4
        let travel = wave * twoPi
        let waveAmp = field * (0.05 + 0.32 * p)
        let lastIdx = Double(max(1, PersonaParticle.count - 1))

        for (i, part) in particles.enumerated() {
            let angle = part.baseAngle + time * part.angularSpeed * v.motion
            let r = orbitRadius * part.ringRadius
            let ox = cx + cos(angle) * r
            let oy = cy + sin(angle) * r * part.ringEccentricity
            let depth = sin(angle) * 0.5 + 0.5

            let frac = Double(i) / lastIdx
            let phaseArg = frac * waveCycles * twoPi - travel + part.phase * 0.15
            let wx = cx + (frac - 0.5) * 2 * waveHalfWidth
            let wy = cy + sin(phaseArg) * waveAmp * (0.7 + 0.6 * part.sizeFactor)
                + (part.sizeFactor - 0.5) * field * 0.06

            let px = ox + (wx - ox) * waveBlend
            let py = oy + (wy - oy) * waveBlend

            let twinkle = reducedMotion ? 0.7 : (0.55 + 0.45 * sin(time + part.phase) * 0.5 + 0.225)
            let orbitAlpha = (0.30 + 0.55 * depth) * twinkle
            let crest = 0.5 + 0.5 * sin(phaseArg)
            let waveAlpha = 0.45 + 0.55 * crest * (0.5 + 0.5 * p)
            let alpha = ((orbitAlpha + (waveAlpha - orbitAlpha) * waveBlend) * v.brightness).clamped(0, 1)

            let dotDepth = 0.6 + 0.8 * depth
            let dotR = field * 0.012
                * (dotDepth + (1.0 - dotDepth) * waveBlend)
                * (0.7 + 0.6 * part.sizeFactor)

            ctx.fill(circlePath(cx: px, cy: py, r: dotR), with: .color(palette.particleColor.opacity(alpha)))
        }

        // The sphere: bright core fading to its edge tint at the rim.
        ctx.fill(
            circlePath(cx: cx, cy: cy, r: sphereRadius),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: v.core.opacity((0.92 * v.brightness).clamped(0, 1)), location: 0),
                    .init(color: v.core.opacity((0.65 * v.brightness).clamped(0, 1)), location: 0.55),
                    .init(color: v.edge.opacity((0.45 * v.brightness).clamped(0, 1)), location: 1),
                ]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: sphereRadius
            )
        )

        // Edge ring — redundant state cue (the listening accent while LISTENING,
        // the idle accent otherwise; both from the persona palette).
        ctx.stroke(
            Path(ellipseIn: CGRect(x: cx - sphereRadius, y: cy - sphereRadius,
                                   width: sphereRadius * 2, height: sphereRadius * 2)),
            with: .color(v.edge.opacity((0.55 * v.brightness).clamped(0, 1))),
            lineWidth: field * 0.012
        )
    }

    // MARK: - State visuals

    private struct Visual {
        var core: Color, glow: Color, edge: Color
        var brightness: Double, swell: Double, spread: Double, motion: Double
    }

    private func visual(for state: HearthState, shimmer: Double, breath: Double, pulse: Double) -> Visual {
        // Colours are the persona's palette (data-driven); the brightness/swell/
        // spread/motion choreography is unchanged. `core` is the bead body, `glow`
        // the halo, `edge` the redundant state-cue ring.
        let core = palette.sphereColor
        let idle = palette.idleColor
        switch state {
        case .LOADING, .IDLE:
            return Visual(core: core, glow: idle, edge: idle,
                          brightness: 0.45 + 0.10 * breath, swell: 1.0 + 0.03 * breath,
                          spread: 1.0, motion: 0.35)
        case .LISTENING:
            return Visual(core: core, glow: idle, edge: palette.listeningColor,
                          brightness: 0.95, swell: 1.12, spread: 1.22, motion: 1.0)
        case .THINKING:
            let thinking = palette.thinkingColor
            return Visual(core: blend(core, thinking, 0.25 * shimmer),
                          glow: blend(idle, thinking, shimmer),
                          edge: blend(idle, thinking, shimmer),
                          brightness: 0.7 + 0.15 * shimmer,
                          swell: 1.0 + 0.04 * sin(shimmer * .pi),
                          spread: 1.05, motion: 0.8)
        case .SPEAKING:
            let speaking = palette.speakingColor
            return Visual(core: blend(core, speaking, 0.2),
                          glow: blend(idle, speaking, 0.4 + 0.4 * pulse),
                          edge: blend(idle, speaking, 0.5),
                          brightness: (0.75 + 0.25 * pulse).clamped(0, 1),
                          swell: 1.0 + 0.18 * pulse, spread: 1.0 + 0.15 * pulse, motion: 1.0)
        }
    }

    // MARK: - Helpers

    private func circlePath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private func triangle(_ elapsed: Double, half: Double) -> Double {
        let x = elapsed.truncatingRemainder(dividingBy: 2 * half) / half
        return x <= 1 ? x : 2 - x
    }

    private func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let tt = t.clamped(0, 1)
        let ca = a.rgba, cb = b.rgba
        return Color(red: ca.r + (cb.r - ca.r) * tt,
                     green: ca.g + (cb.g - ca.g) * tt,
                     blue: ca.b + (cb.b - ca.b) * tt)
    }
}

// MARK: - Particle field

struct PersonaParticle {
    let baseAngle: Double
    let ringRadius: Double
    let ringEccentricity: Double
    let angularSpeed: Double
    let sizeFactor: Double
    let phase: Double

    static let count = 96

    /// Deterministic LCG-seeded field (same look every launch), matching Echo.
    static func field() -> [PersonaParticle] {
        var seed = Int32(bitPattern: 0x9E37_79B9)
        func next() -> Double {
            seed = seed &* 1103515245 &+ 12345
            return Double((UInt32(bitPattern: seed) >> 8) & 0xFFFF) / 65535.0
        }
        let twoPi = 2 * Double.pi
        return (0..<count).map { _ in
            PersonaParticle(
                baseAngle: next() * twoPi,
                ringRadius: 0.45 + next() * 0.55,
                ringEccentricity: 0.55 + next() * 0.35,
                angularSpeed: (0.4 + next() * 0.9) * (next() > 0.5 ? 1 : -1),
                sizeFactor: 0.4 + next() * 0.6,
                phase: next() * twoPi
            )
        }
    }
}

// MARK: - Small numeric / colour helpers

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

// `Color.rgba` used to live here. It moved to HearthCore's ColorHex.swift when
// the package split, because HearthPalette.mixed(with:amount:) needs it and
// HearthCore cannot reach up into HearthUI.
