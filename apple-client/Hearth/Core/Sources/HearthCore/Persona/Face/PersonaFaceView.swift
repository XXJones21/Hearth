//
//  PersonaFaceView.swift
//  Hearth
//
//  The face, drawn. A port of the desktop client's `lib/face/geometry.ts` (pose
//  -> shapes) and `PersonaFace.tsx` (the loop and the colours) onto the orb's
//  own template: a TimelineView driving a pure Canvas draw.
//
//  All behaviour -- playlists, blink, saccades, transients, the amplitude mouth
//  -- lives in FaceDirector. This file's whole job is ticking it and turning
//  one pose into paths, which is why there is no per-frame @Published anything:
//  a sixty-per-second mouth must not push the stage through SwiftUI's diff.
//
//  Shape choices (the eyes-first, grok-bot register):
//    head   a squircle: four cubics whose handle length morphs with roundness
//           (0.5523 draws a circle; shorter handles go boxy).
//    eyes   two vertical capsules; the whole character lives here. A closing
//           lid collapses the capsule's height at its own width, so a closed
//           eye reads as a stubby DASH rather than a missing element.
//    brows  none. Deliberate: brows are where an abstract face starts looking
//           like a judging human.
//    mouth  hidden at rest. It fades in with whatever opens it -- speech
//           amplitude or a transient -- and vanishes after.
//

import SwiftUI
import simd

/// Holds the director across body re-evaluations, and rebuilds it when the
/// persona's geometry changes. A class because @State must not be written
/// from inside a Canvas draw, and because the director is a live thing with a
/// clock of its own rather than a value.
private final class DirectorBox {
    private var director: FaceDirector?
    private var builtFor: FaceGeometry?

    func director(for geometry: FaceGeometry, now: Double) -> FaceDirector {
        if let director, builtFor == geometry { return director }
        let fresh = FaceDirector(geometry: geometry, now: now)
        director = fresh
        builtFor = geometry
        return fresh
    }
}

public struct PersonaFaceView: View {
    let geometry: FaceGeometry
    let state: HearthState
    let palette: PersonaPalette
    let reducedMotion: Bool

    @State private var box = DirectorBox()

    public init(
        geometry: FaceGeometry,
        state: HearthState,
        palette: PersonaPalette = .fallback,
        reducedMotion: Bool = false
    ) {
        self.geometry = geometry
        self.state = state
        self.palette = palette
        self.reducedMotion = reducedMotion
    }

    public var body: some View {
        // Never paused, even under reduce motion: the director suppresses
        // blink, saccades and sway itself, and the mouth still has to follow
        // the voice. A paused timeline would freeze the speech too.
        // The face has to know where it is on screen to work out where the
        // composer is relative to it, and Canvas only reports its own size.
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                Canvas { ctx, size in
                    let nowMs = timeline.date.timeIntervalSinceReferenceDate * 1000
                    let feed = FaceFeed.shared
                    let director = box.director(for: geometry, now: nowMs)
                    let pose = director.tick(
                        now: nowMs,
                        state: faceState,
                        cue: feed.cue,
                        speechLevel: feed.speechLevel,
                        reduceMotion: reducedMotion,
                        lookTarget: Self.lookTarget(
                            face: proxy.frame(in: .global),
                            composer: feed.composerUp ? feed.composerFrame : nil))
                    draw(pose, into: ctx, size: size)
                }
            }
        }
        // The stage is tap-to-talk. A face that ate the tap would break the
        // one gesture the whole app is built on.
        .allowsHitTesting(false)
        .accessibilityLabel("Persona face")
    }

    private var faceState: FaceState {
        Self.faceState(for: state, composerUp: FaceFeed.shared.composerUp)
    }

    /// The face's own reading of the turn. Pure and internal so the rule can
    /// be asserted rather than eyeballed on a phone.
    ///
    /// The composer being up counts as listening even though `hearthState`
    /// only says LISTENING while the microphone is live -- someone typing is
    /// someone talking to it, and the listening pose plus the look target is
    /// what makes the face watch the keyboard.
    ///
    /// But it only outranks IDLE. A live turn wins, which is the same rule the
    /// stage already applies to the easel override: someone typing a follow-up
    /// while the house is mid-reply must not cost the thinking and speaking
    /// beats -- the face would sit there listening through the whole answer it
    /// was giving. LOADING idles: a face that has not heard anything yet is
    /// idle, not thinking.
    static func faceState(for state: HearthState, composerUp: Bool) -> FaceState {
        switch state {
        case .LISTENING: return .listening
        case .THINKING: return .thinking
        case .SPEAKING: return .speaking
        case .IDLE, .LOADING: return composerUp ? .listening : .idle
        }
    }

    /// Where to look, in gaze space: the composer's centre relative to the
    /// face's, normalised by the face's own size, clamped to the head.
    ///
    /// The same arithmetic the desktop does against DOM rects. The 0.9 keeps
    /// a fully off-screen target from pinning the eyes to the very edge, and
    /// focus 0.5 converges them part way -- reading something a foot away, not
    /// staring through it.
    static func lookTarget(face: CGRect, composer: CGRect?) -> LookTarget? {
        guard let composer, face.width > 0, face.height > 0 else { return nil }
        let dx = (composer.midX - face.midX) / face.width
        let dy = (composer.midY - face.midY) / face.height
        return LookTarget(
            x: min(1, max(-1, dx * 0.9)),
            y: min(1, max(-1, dy * 0.9)),
            focus: 0.5)
    }

    // MARK: - Colours
    //
    // The desktop leans the face's ink toward the active state's colour so the
    // state is legible in peripheral vision, over a parchment head. Same wash
    // here, from the same per-state palette the orb reads -- a face that
    // invented its own colours would drift from the orb it replaces.

    private func inkColor() -> Color {
        Self.color(mix(palette.glow(for: state), HearthPalette.Scene.roast, t: 0.62))
    }

    private func rimColor() -> Color {
        Self.color(mix(palette.glow(for: state), HearthPalette.Scene.roast, t: 0.38))
    }

    private func headFill() -> Color {
        Self.color(mix(palette.glow(for: state), HearthPalette.Scene.cream, t: 0.84))
    }

    private func glintColor() -> Color {
        Self.color(mix(HearthPalette.Scene.honey, HearthPalette.Scene.fluff, t: 0.75))
    }

    /// Linear blend, `t` toward `b`. The whole of the desktop's color-mix.
    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a * (1 - t) + b * t
    }

    private static func color(_ c: SIMD3<Float>) -> Color {
        Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: 1)
    }

    // MARK: - Drawing

    private func draw(_ pose: FacePose, into ctx: GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let cx = size.width / 2
        let cy = size.height / 2
        // The head's half-extents. 0.38 leaves air for head tilt.
        let hw = side * 0.38 * pose.headWidth
        let hh = side * 0.38 * pose.headHeight

        var ctx = ctx
        // Whole-face transform: the bob lifts, then the tilt leans about the
        // head's centre.
        ctx.translateBy(x: 0, y: pose.headBob * hh)
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: .radians(pose.headTilt))
        ctx.translateBy(x: -cx, y: -cy)

        ctx.fill(squircle(cx: cx, cy: cy, rx: hw, ry: hh, roundness: pose.headRoundness),
                 with: .color(headFill()))
        ctx.stroke(squircle(cx: cx, cy: cy, rx: hw, ry: hh, roundness: pose.headRoundness),
                   with: .color(rimColor()), lineWidth: max(1, side * 0.015))

        // Eyes: vertical capsules, each with its own lid, size, lean and lift
        // -- matched eyes read as a machine, mismatched ones as a creature.
        let eyeY = cy - hh + pose.eyeHeight * (2 * hh)
        let eyeDx = pose.eyeSpacing * hw
        let baseHalfW = pose.eyeSize * hw
        // Theatrical gaze travel: the eyes genuinely move around the face,
        // clamped so they never cross the head's outline at the height they
        // sit at.
        let dyEye = min(0.95, abs(cy - eyeY) / hh)
        let halfWidthAtEye = hw * max(0.05, 1 - dyEye * dyEye).squareRoot()
        let gxMax = max(0, halfWidthAtEye - eyeDx - baseHalfW * 1.6)
        let gx = min(gxMax, max(-gxMax, pose.gazeX * hw * 0.45))
        let gy = pose.gazeY * hh * 0.3
        let arc = min(1, max(-1, pose.eyeArc))

        // Vergence: focus pulls both eyes toward a shared near point, so a
        // focused face converges slightly instead of staring past you.
        let converge = pose.focus * baseHalfW * 0.55
        let leftC = CGPoint(x: cx - eyeDx + gx + converge,
                            y: eyeY + gy + pose.eyeRaiseL * (2 * hh))
        let rightC = CGPoint(x: cx + eyeDx + gx - converge,
                             y: eyeY + gy + pose.eyeRaiseR * (2 * hh))

        let ink = inkColor()
        let maxLid = max(pose.eyelidL, pose.eyelidR)
        let glintR = baseHalfW * 0.3
        let glintDx = -baseHalfW * 0.28 + pose.gazeX * baseHalfW * 0.35
        let glintDy = -baseHalfW * max(0.2, pose.eyeLength) * 0.42 + pose.gazeY * baseHalfW * 0.3
        let glintOpacity = max(0, 1 - maxLid * 2)
        let glint = glintColor()

        for (center, lid, scale, ownTilt) in [
            (leftC, pose.eyelidL, pose.eyeScaleL, pose.eyeTiltL),
            (rightC, pose.eyelidR, pose.eyeScaleR, pose.eyeTiltR),
        ] {
            // Each capsule leans about its own centre -- a path cannot lean
            // itself, so the layer does it.
            ctx.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(pose.eyeTilt + ownTilt))
                layer.translateBy(x: -center.x, y: -center.y)
                layer.fill(
                    eyeShape(center: center, lid: lid, scale: scale, arc: arc,
                             baseHalfW: baseHalfW, eyeLength: pose.eyeLength),
                    with: .color(ink))
                if glintOpacity > 0 {
                    layer.opacity = glintOpacity
                    layer.fill(
                        capsule(cx: center.x + glintDx, cy: center.y + glintDy,
                                halfW: glintR, halfH: glintR),
                        with: .color(glint))
                }
            }
        }

        // Mouth: hidden at rest, and the two shapes crossfade rather than
        // morph -- a crescent that had to become an "o" path-by-path was how
        // the first cut ended up looking like a beak.
        let visibility = min(1, pose.mouthOpen * 4)
        guard visibility > 0 else { return }
        let mouthY = cy + hh * 0.42
        let mouthHalf = pose.mouthWidth * hw
        // A smile's corners turn up and its centre dips below them: positive
        // mouthCurve pushes the crescent's belly DOWN in screen space.
        let curve = pose.mouthCurve * hh * 0.5
        let thickness = max(side * 0.008, pose.mouthThickness * 2 * hh)
        let open = pose.mouthOpen * hh * 0.42

        let crescentOpacity = visibility * (1 - pose.mouthRound)
        if crescentOpacity > 0 {
            var crescent = Path()
            crescent.move(to: CGPoint(x: cx - mouthHalf, y: mouthY))
            crescent.addQuadCurve(to: CGPoint(x: cx + mouthHalf, y: mouthY),
                                  control: CGPoint(x: cx, y: mouthY + curve))
            crescent.addQuadCurve(to: CGPoint(x: cx - mouthHalf, y: mouthY),
                                  control: CGPoint(x: cx, y: mouthY + curve + thickness + open))
            crescent.closeSubpath()
            ctx.drawLayer { layer in
                layer.opacity = crescentOpacity
                layer.fill(crescent, with: .color(ink))
            }
        }

        let roundOpacity = visibility * pose.mouthRound
        if roundOpacity > 0 {
            let roundH = max(1.5, (thickness + open) * 0.55)
            let roundW = mouthHalf * 0.5
            ctx.drawLayer { layer in
                layer.opacity = roundOpacity
                layer.fill(capsule(cx: cx, cy: mouthY + roundH * 0.25,
                                   halfW: roundW, halfH: roundH),
                           with: .color(ink))
            }
        }
    }

    /// One eye: a capsule, or -- once a lid closes over an arc -- the happy
    /// `^` / pensive droop band.
    private func eyeShape(
        center: CGPoint, lid: Double, scale: Double, arc: Double,
        baseHalfW: Double, eyeLength: Double
    ) -> Path {
        let l = min(1, lid)
        let s = max(0.2, scale)
        let halfW = baseHalfW * s
        let closedness = l * abs(arc)
        if closedness > 0.35 {
            // A thick band bowing UP for joy or DOWN for the droop, scaled by
            // how closed the lid is so it eases in rather than popping.
            let sign: Double = arc < 0 ? -1 : 1
            let w = halfW * 1.45
            let lift = halfW * 1.5 * l * sign
            let band = max(2, halfW * 0.62)
            let endY = center.y + band * 0.4 * sign
            var path = Path()
            path.move(to: CGPoint(x: center.x - w, y: endY))
            path.addQuadCurve(to: CGPoint(x: center.x + w, y: endY),
                              control: CGPoint(x: center.x, y: center.y - lift))
            path.addQuadCurve(to: CGPoint(x: center.x - w, y: endY),
                              control: CGPoint(x: center.x, y: center.y - lift + band))
            path.closeSubpath()
            return path
        }
        // Neutral close: the capsule collapses to a thick stubby bar at its
        // own width -- never a spindly hyphen (the first cut widened while it
        // thinned, and mid-blink read as a rendering bug).
        let halfH = max(halfW * 0.55, halfW * max(0.2, eyeLength) * (1 - l * 0.95))
        return capsule(cx: center.x, cy: center.y, halfW: halfW, halfH: halfH)
    }

    /// Rounded rect that degrades to a capsule in either orientation.
    private func capsule(cx: Double, cy: Double, halfW: Double, halfH: Double) -> Path {
        let w = max(0.5, halfW)
        let h = max(0.5, halfH)
        return Path(roundedRect: CGRect(x: cx - w, y: cy - h, width: w * 2, height: h * 2),
                    cornerRadius: min(w, h))
    }

    /// Squircle: four cubics, handle length morphing circle -> rounded box.
    private func squircle(cx: Double, cy: Double, rx: Double, ry: Double,
                          roundness: Double) -> Path {
        let t = min(1, max(0, roundness))
        // 0.5523 is the magic circle constant; 0.30 reads as a soft rectangle.
        let k = 0.3 + (0.5523 - 0.3) * t
        let kx = rx * (1 - k)
        let ky = ry * (1 - k)
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - ry))
        path.addCurve(to: CGPoint(x: cx + rx, y: cy),
                      control1: CGPoint(x: cx + rx - kx, y: cy - ry),
                      control2: CGPoint(x: cx + rx, y: cy - ry + ky))
        path.addCurve(to: CGPoint(x: cx, y: cy + ry),
                      control1: CGPoint(x: cx + rx, y: cy + ry - ky),
                      control2: CGPoint(x: cx + rx - kx, y: cy + ry))
        path.addCurve(to: CGPoint(x: cx - rx, y: cy),
                      control1: CGPoint(x: cx - rx + kx, y: cy + ry),
                      control2: CGPoint(x: cx - rx, y: cy + ry - ky))
        path.addCurve(to: CGPoint(x: cx, y: cy - ry),
                      control1: CGPoint(x: cx - rx, y: cy - ry + ky),
                      control2: CGPoint(x: cx - rx + kx, y: cy - ry))
        path.closeSubpath()
        return path
    }
}

// The face with nothing else on screen, which is how every question about it
// ("is the arc too high", "is the mouth too low") actually gets answered.
//
// reducedMotion is on so each frame SNAPS to its state's beat pose: a preview
// renders one frame, and eased over 140ms that frame would be four identical
// neutral faces. Under reduce motion it is four silhouettes you can tell apart.
#Preview("Persona face, per state") {
    let states: [(String, HearthState)] = [
        ("idle", .IDLE), ("listening", .LISTENING),
        ("thinking", .THINKING), ("speaking", .SPEAKING),
    ]
    return VStack(spacing: 8) {
        ForEach(states, id: \.0) { label, state in
            HStack(spacing: 12) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(HearthPalette.fawn)
                    .frame(width: 70, alignment: .trailing)
                PersonaFaceView(geometry: FaceGeometry(), state: state, reducedMotion: true)
                    .frame(width: 130, height: 130)
            }
        }
    }
    .padding()
    .background(HearthPalette.cream)
}
