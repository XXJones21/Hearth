//
//  PersonaFlameCanvas.swift
//  HearthUI
//
//  Route A of the iOS renderer investigation: Sulivan's fire drawn with vector
//  primitives, no shader and no 3D.
//
//  THE PRECEDENT IS `PersonaOrb`, in this same folder: a radial gradient for
//  the halo, filled circles for the particles, a radial gradient for the body.
//  Nobody looking at the phone and the headset thinks the bead is two
//  characters. The bar here is the same -- the same character, not the same
//  pixels -- and what carries it is the shape, the palette and the motion.
//
//  THIS HAS TO EXIST WHATEVER THE APP DOES. Widgets can host neither a
//  RealityView nor a compute pass, so if Sulivan is ever to appear in one, a
//  shader-free flame is the only way. That reframes the A/B: the question is
//  not "which do we build" but "given this is being built anyway, does the live
//  app use it or the rig".
//
//  WHAT IT GIVES UP, stated so nobody chases it: the headset's fire gets its
//  fine grain from a five-octave domain-warped fbm evaluated per pixel. Broad
//  strokes give broad structure. There is no parallax between the near and far
//  walls of the flame, because there are no walls. See
//  wiki/raw/persona-flame-spec.md.
//

import SwiftUI
import HearthCore

public struct PersonaFlameCanvas: View {
    public var state: HearthState
    /// TTS amplitude 0..1 while speaking, mic level while listening.
    public var pulse: Double
    /// Animation clock. `.now` while animating; any fixed date for a widget's
    /// single static frame.
    public var date: Date
    public var reducedMotion: Bool
    public var palette: PersonaPalette
    /// The persona's face, drawn ON the flame. Nil draws a fire with no face,
    /// which is the honest state for a config that carried no geometry.
    public var faceGeometry: FaceGeometry?

    public init(state: HearthState,
                pulse: Double = 0,
                date: Date = .distantPast,
                reducedMotion: Bool = false,
                palette: PersonaPalette = .fallback,
                faceGeometry: FaceGeometry? = nil) {
        self.state = state
        self.pulse = pulse
        self.date = date
        self.reducedMotion = reducedMotion
        self.palette = palette
        self.faceGeometry = faceGeometry
    }

    public var body: some View {
        ZStack {
            Canvas { ctx, size in draw(into: ctx, size: size) }
            // THE FACE, COMPOSITED ON TOP -- which is the whole 2D shortcut.
            //
            // The headset needs a curved card that rides the flame's moving
            // surface, because a flat card in front of a round body either
            // hovers or sinks, and because the viewer can walk around it. A
            // window has one viewpoint and no depth to fight over, so the same
            // face is simply drawn over the fire. No curvature, no surface
            // tracking, no sort group.
            //
            // It is the SAME view the shipped persona uses, driven by the same
            // director -- so the eyes blink and the mouth follows the voice
            // here exactly as they do everywhere else.
            if let faceGeometry {
                PersonaFaceView(geometry: faceGeometry,
                                state: state,
                                palette: palette,
                                reducedMotion: reducedMotion)
                    .scaleEffect(0.42)
                    .offset(y: Self.faceDrop)
                    .allowsHitTesting(false)
            }
        }
    }

    /// How far below centre the eyes sit, as a fraction of the view. The
    /// headset puts them at a quarter of the bead's radius above the flame's
    /// origin, which is low in the body -- a flame's face belongs where the
    /// fire is widest, not up in the taper.
    private static let faceDrop: CGFloat = 26

    // MARK: - The five colour stops, straight from `fire_kernel`

    private static let straw = Color(red: 1.00, green: 0.88, blue: 0.42)
    private static let gold  = Color(red: 1.00, green: 0.66, blue: 0.18)
    private static let amber = Color(red: 1.00, green: 0.38, blue: 0.07)
    private static let red   = Color(red: 0.86, green: 0.13, blue: 0.04)
    private static let ash   = Color(red: 0.45, green: 0.06, blue: 0.03)

    /// Yellow where the flame is fed, red where it is spending itself. The
    /// stop POSITIONS are the kernel's `heat` thresholds; what a gradient
    /// cannot do is the kernel's noise perturbation of them, which is why a
    /// drawn flame's colour boundaries are level where a computed one's wander.
    private static let ramp = Gradient(stops: [
        .init(color: straw, location: 0.00),
        .init(color: gold,  location: 0.28),
        .init(color: amber, location: 0.58),
        .init(color: red,   location: 0.85),
        .init(color: ash,   location: 1.00),
    ])

    private static let rings = 40

    private func draw(into ctx: GraphicsContext, size: CGSize) {
        let elapsed = reducedMotion ? 0 : date.timeIntervalSinceReferenceDate
        let phase = elapsed

        let field = min(size.width, size.height)
        // Proportioned like the headset's: the flame is 1.05 of the bead's
        // radius wide and 3.4 of it tall, so width and height stay in the same
        // ratio to each other whatever this view is given.
        let unit = field * 0.13
        var flame = FlameProfile(radius: unit * 1.05, height: unit * 3.4)
        if reducedMotion { flame.turbulence = 0; flame.sway = 0 }

        let cx = size.width / 2
        // Sit the flame's base a little below centre so the taper has room.
        let baseY = size.height / 2 + flame.height * 0.42

        // THE HALO, and it is here on purpose. The headset switches its painted
        // glow OFF when the lantern lights, because a real light doing real
        // work on real walls does that job better. In a window nothing does, so
        // the drawn flame keeps the halo the headset dropped -- otherwise the
        // fire reads flatter on the phone than the bead it replaced.
        let flicker = reducedMotion ? 0.5 : Self.flicker(elapsed)
        let haloR = flame.radius * 4.2
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - haloR, y: baseY - flame.height * 0.55 - haloR,
                                   width: haloR * 2, height: haloR * 2)),
            with: .radialGradient(
                Gradient(colors: [Self.amber.opacity(0.30 + 0.16 * flicker),
                                  Self.amber.opacity(0)]),
                center: CGPoint(x: cx, y: baseY - flame.height * 0.55),
                startRadius: 0, endRadius: haloR
            )
        )

        // THE BODY. One closed path from the same arithmetic the mesh uses,
        // walked up the right meridian and back down the left. Angle 0 and
        // angle pi are where a surface of revolution's outline lives, so these
        // two edges are the headset's silhouette exactly -- and they wobble
        // independently, because the noise is per-meridian.
        let body = outline(flame, phase: phase, scale: 1, cx: cx, baseY: baseY)
        ctx.fill(body, with: .linearGradient(
            Self.ramp,
            startPoint: CGPoint(x: cx, y: baseY),
            endPoint: CGPoint(x: cx, y: baseY - flame.height)
        ))

        // THE TIP FEATHER. The kernel fades density from 0.88 to 0.99 because
        // the geometry runs to a point and a point is the one shape a flame
        // never has. A drawn flame has the same problem and takes the same
        // window -- painted here as a wash of the background rather than as
        // real transparency, since a Canvas cannot subtract alpha from a fill
        // it has already made.
        let fadeTop = baseY - flame.rise(at: FlameProfile.fadeEnd) - flame.radius * FlameProfile.domeDepth
        let fadeBottom = baseY - flame.rise(at: FlameProfile.fadeStart) - flame.radius * FlameProfile.domeDepth
        ctx.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(
                Path(CGRect(x: cx - flame.radius * 1.6, y: fadeTop - flame.height * 0.1,
                            width: flame.radius * 3.2, height: (fadeBottom - fadeTop) + flame.height * 0.1)),
                with: .linearGradient(
                    Gradient(colors: [Self.ash.opacity(0.85), Self.ash.opacity(0)]),
                    startPoint: CGPoint(x: cx, y: fadeTop - flame.height * 0.1),
                    endPoint: CGPoint(x: cx, y: fadeBottom)
                )
            )
        }

        // THE LICKS. What the fbm gives per pixel, a handful of narrower flames
        // give in outline: each is the same profile at a fraction of the width,
        // shifted along its own meridian so it leans differently, drawn lighter
        // and softly. Three is enough to read as structure and few enough to
        // stay legible; more turns the body back into a wash.
        ctx.drawLayer { layer in
            layer.clip(to: body)
            for i in 0..<3 {
                let seed = Double(i) * 2.4 + 1.1
                var inner = flame
                inner.radius = flame.radius * (0.30 + 0.12 * Double(i))
                inner.height = flame.height * (0.72 + 0.08 * Double(i))
                let offset = FlameProfile.noise(angle: seed, height: 0.7, phase: phase * 0.6)
                    * flame.radius * 0.42
                let lick = outline(inner, phase: phase + seed, scale: 1,
                                   cx: cx + offset, baseY: baseY)
                layer.fill(lick, with: .linearGradient(
                    Gradient(colors: [Self.straw.opacity(0.55), Self.gold.opacity(0.16),
                                      Self.gold.opacity(0)]),
                    startPoint: CGPoint(x: cx, y: baseY),
                    endPoint: CGPoint(x: cx, y: baseY - inner.height)
                ))
            }
        }

        // THE EMBERS. Filled circles rising off the body, exactly as PersonaOrb
        // draws its field -- and driven by the same idea the ember emitter
        // runs on: born low, carried up, shrinking and fading as they cool.
        drawEmbers(into: ctx, flame: flame, cx: cx, baseY: baseY,
                   elapsed: elapsed, state: state, pulse: pulse)
    }

    /// One closed path: up the right meridian, back down the left.
    private func outline(_ flame: FlameProfile, phase: Double, scale: Double,
                         cx: Double, baseY: Double) -> Path {
        var path = Path()
        let sink = flame.radius * FlameProfile.domeDepth
        func point(_ v: Double, _ angle: Double) -> CGPoint {
            let r = flame.surface(at: v, angle: angle, phase: phase) * scale
            let x = cx + (angle == 0 ? r : -r) + flame.lean(at: v, phase: phase)
            let y = baseY - (flame.rise(at: v) + sink)
            return CGPoint(x: x, y: y)
        }
        path.move(to: point(0, 0))
        for i in 1...Self.rings {
            path.addLine(to: point(Double(i) / Double(Self.rings), 0))
        }
        for i in stride(from: Self.rings, through: 0, by: -1) {
            path.addLine(to: point(Double(i) / Double(Self.rings), .pi))
        }
        path.closeSubpath()
        return path
    }

    /// The idle plume. Deterministic per index, so a widget's single frame is
    /// the same frame every client would have drawn.
    private func drawEmbers(into ctx: GraphicsContext, flame: FlameProfile,
                            cx: Double, baseY: Double, elapsed: Double,
                            state: HearthState, pulse: Double) {
        guard !reducedMotion else { return }
        let count = 18
        // SPEAKING gathers them into a shell that pulses with the voice, which
        // is what the headset's embers do -- see EmberField. The other states
        // keep the rising plume; the difference between them is its speed and
        // spread, which is the same distinction the emitter makes.
        let speaking = state == .SPEAKING
        let listening = state == .LISTENING
        let rise = listening ? 0.9 : 0.62
        let spread = listening ? 0.55 : 1.0

        for i in 0..<count {
            let seed = Double(i) * 12.9898
            let r0 = seed.truncatingRemainder(dividingBy: 1.0)
            let r1 = (seed * 1.7).truncatingRemainder(dividingBy: 1.0)
            let life = 2.4 + r1 * 1.1
            let t = ((elapsed * rise + r0 * life) / life).truncatingRemainder(dividingBy: 1.0)

            let x: Double, y: Double
            if speaking {
                // The shell, opened by the amplitude.
                let angle = Double(i) / Double(count) * 2 * .pi
                let shell = flame.radius * (1.7 + 0.85 * pulse)
                x = cx + cos(angle) * shell
                y = baseY - flame.height * 0.42 + sin(angle) * shell
            } else {
                let drift = FlameProfile.noise(angle: seed, height: t, phase: elapsed * 0.4)
                x = cx + drift * flame.radius * 1.3 * spread
                    + (r1 - 0.5) * flame.radius * 0.8 * spread
                y = baseY - flame.height * (0.15 + t * 1.25)
            }
            let fade = speaking ? 1 - abs(0.5 - t) * 0.8 : (1 - t) * (1 - t)
            let dot = flame.radius * 0.055 * (0.5 + r1 * 0.6) * (speaking ? 1 : (1 - t * 0.7))
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2)),
                with: .color(Self.amber.opacity(min(max(fade, 0), 1) * 0.85))
            )
        }
    }

    /// Three sines at incommensurable rates -- the same correlation the rig
    /// uses to make its light breathe with the fire rather than beside it.
    private static func flicker(_ t: Double) -> Double {
        let wobble = sin(t * 2.7) * 0.5 + sin(t * 4.3 + 1.7) * 0.3 + sin(t * 9.1 + 0.4) * 0.2
        return 0.5 + 0.5 * max(-1, min(1, wobble))
    }
}
