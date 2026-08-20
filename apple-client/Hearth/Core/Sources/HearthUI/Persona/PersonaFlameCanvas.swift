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
        GeometryReader { proxy in
        let field = min(proxy.size.width, proxy.size.height)
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
                                reducedMotion: reducedMotion,
                                // FEATURES ONLY. With the head on, this drew a
                                // solid cream squircle in front of the fire --
                                // a persona standing before a flame rather than
                                // a flame with a face.
                                drawsHead: false)
                    // Framed rather than scaled. `scaleEffect` shrinks the
                    // stroke widths and the blur radii with the drawing; a
                    // frame lets the face lay itself out at the size it is
                    // actually being shown, which is what its own geometry
                    // numbers are relative to.
                    .frame(width: field * Self.faceSpan, height: field * Self.faceSpan)
                    .offset(y: field * Self.faceDrop)
                    .allowsHitTesting(false)
            }
        }
        }
    }

    /// How much of the view the face's own square occupies.
    ///
    /// The face places its eyes at a fraction of its half-extents, so this is
    /// really a statement about how far apart the eyes sit: big enough that
    /// they span the flame's body, small enough that they stay inside its
    /// silhouette at the height they sit at.
    private static let faceSpan: CGFloat = 0.44

    /// How far below the view's centre the eyes sit, as a fraction of the
    /// view. Derived from the same place the headset gets it -- the flame's
    /// base sits low in the frame and the eyes ride a quarter of a radius above
    /// its origin, which is DOWN in the body where the fire is widest, not up
    /// in the taper.
    private static let faceDrop: CGFloat = 0.02

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
        let unit = field * 0.155
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

    /// The embers.
    ///
    /// REWRITTEN AFTER THE FIRST SIDE-BY-SIDE, where they read as a scatter of
    /// crumbs around the mouth. Three faults, and only the last one was a
    /// number:
    ///
    /// 1. **They were born at the axis.** Their sideways drift came from
    ///    `FlameProfile.noise`, which is damped to nothing below `domeTop` --
    ///    correct for a silhouette that must stay attached to its base, wrong
    ///    for a particle, which spends its early life exactly there. Every
    ///    ember therefore started on the centre line and stayed near it.
    /// 2. **They were drawn INSIDE the body.** An opaque amber dot on a bright
    ///    gold flame is mud. The headset never has this problem because its
    ///    embers are additive: inside the fire they are indistinguishable from
    ///    it, and outside they glow. Same fix here -- `plusLighter`.
    /// 3. They were small and too few.
    ///
    /// So they are now born ACROSS the flame's upper body, rise past its tip,
    /// and widen as they go -- which is what the plume does on the headset and
    /// what makes it read as coming off a fire rather than sitting on one.
    private func drawEmbers(into ctx: GraphicsContext, flame: FlameProfile,
                            cx: Double, baseY: Double, elapsed: Double,
                            state: HearthState, pulse: Double) {
        guard !reducedMotion else { return }
        var ctx = ctx
        // ADDITIVE, for the same reason the headset's are: adding light to
        // light is order-independent, so nothing has to be sorted, and it is
        // what fire actually does.
        ctx.blendMode = .plusLighter

        let count = 26
        let sink = flame.radius * FlameProfile.domeDepth
        let speaking = state == .SPEAKING
        let listening = state == .LISTENING

        for i in 0..<count {
            let r0 = Self.hash(Double(i) * 1.13)
            let r1 = Self.hash(Double(i) * 2.71 + 5.2)
            let r2 = Self.hash(Double(i) * 4.37 + 11.9)

            let life = 2.2 + r1 * 1.4
            // Listening draws the plume up faster and narrower; idle is slow
            // and wide. The same distinction the emitter makes between the two.
            let speed = listening ? 1.35 : 1.0
            let t = (((elapsed * speed) / life) + r0).truncatingRemainder(dividingBy: 1.0)

            var x: Double, y: Double, size: Double, alpha: Double

            if speaking {
                // THE SHELL, opened by the voice -- the headset's speaking
                // state in two dimensions. A ring rather than a plume, because
                // what carries the amplitude is its RADIUS.
                let angle = (Double(i) / Double(count)) * 2 * .pi + elapsed * 0.25
                let shell = flame.radius * (1.55 + 0.95 * pulse) * (0.9 + r2 * 0.2)
                x = cx + cos(angle) * shell
                y = baseY - sink - flame.height * 0.30 + sin(angle) * shell * 0.85
                size = flame.radius * (0.05 + r2 * 0.03)
                alpha = 0.55 + 0.45 * pulse
            } else {
                // BORN ACROSS THE BODY, not on the axis. `r2` places the birth
                // meridian and the silhouette gives the width there, so an
                // ember starts somewhere on the fire rather than in the middle
                // of it.
                let birthV = 0.25 + r2 * 0.5
                let halfWidth = flame.surface(at: birthV, angle: r2 * 6.28, phase: elapsed)
                let birthX = cx + (r0 - 0.5) * 2 * halfWidth * 0.85
                let birthY = baseY - (flame.rise(at: birthV) + sink)

                // Rise past the tip, and WIDEN on the way -- a plume opens.
                let climb = flame.height * (0.55 + r1 * 0.55) * t
                let spread = flame.radius * (0.35 + r2 * 0.5) * t * t
                let sway = sin(elapsed * (0.7 + r1) + Double(i)) * spread
                x = birthX + sway
                y = birthY - climb
                // Shrink as they cool, which is what stops a fading dot leaving
                // a ghost of its original size.
                size = flame.radius * (0.055 + r1 * 0.045) * (1 - t * 0.75)
                // In over the first fifth, out over the last half.
                alpha = min(t / 0.2, 1) * (1 - FlameProfile.smoothstep(0.5, 1.0, t))
            }

            // Hot at birth, cooling to ember red -- the ramp the kernel runs,
            // with the middle taken out because a spark's whole life is short.
            let colour = t < 0.5 ? Self.straw : Self.amber
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - size, y: y - size,
                                       width: size * 2, height: size * 2)),
                with: .color(colour.opacity(min(max(alpha, 0), 1) * 0.7))
            )
        }
    }

    /// The shader's own hash, so the field is the same field on every client
    /// rather than merely a similar one.
    private static func hash(_ x: Double) -> Double {
        let v = sin(x * 12.9898) * 43758.5453
        return v - v.rounded(.down)
    }

    /// Three sines at incommensurable rates -- the same correlation the rig
    /// uses to make its light breathe with the fire rather than beside it.
    private static func flicker(_ t: Double) -> Double {
        let wobble = sin(t * 2.7) * 0.5 + sin(t * 4.3 + 1.7) * 0.3 + sin(t * 9.1 + 0.4) * 0.2
        return 0.5 + 0.5 * max(-1, min(1, wobble))
    }
}
