//
//  FaceDirector.swift
//  Hearth
//
//  Everything about WHEN, nothing about HOW it is drawn. A port of the desktop
//  client's `lib/face/director.ts`, timing table for timing table.
//
//  An animation here is a looping playlist of expression presets with per-beat
//  hold times, an energy-tiered blink schedule, and perpetual micro-motion on
//  the gaze -- the avatar-lab model, mapped onto the four states the house
//  already emits.
//
//  Renderer-free by design: PersonaFaceView ticks it once per frame and draws
//  the pose it returns, exactly as the SVG component does on desktop and as a
//  future RealityKit face would. Time arrives as an argument so the director is
//  testable without a clock, which is what FaceDirectorTests exists to use.
//
//  Composition order per tick, each layer recomputed from scratch so nothing
//  accumulates: eased playlist pose -> look target -> saccade drift -> transient
//  cue -> blink -> speech mouth.
//

import Foundation

public enum FaceState: Sendable {
    case idle, listening, thinking, speaking
}

/// A transient the harness named, and when it fired (ms, same clock as `tick`).
public struct FaceCue: Sendable, Equatable {
    public let name: String
    public let at: Double

    public init(name: String, at: Double) {
        self.name = name
        self.at = at
    }
}

/// A focal point in gaze space: x/y in [-1, 1] (right/down positive), focus
/// 0..1 nearness. The renderer's host decides where it is -- the desktop points
/// it at the composer input, a phone points it down at its own keyboard -- and
/// the director looks there while listening.
public struct LookTarget: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var focus: Double

    public init(x: Double, y: Double, focus: Double) {
        self.x = x
        self.y = y
        self.focus = focus
    }
}

private struct Beat {
    let expr: FaceExpression
    let ms: Double
}

private struct BlinkTier {
    /// ms until the first blink after entering the state
    let first: Double
    /// randomized interval bounds, ms
    let min: Double
    let max: Double
    /// full close-and-open time, ms
    let duration: Double
}

private struct FaceAnimation {
    let beats: [Beat]
    let blink: BlinkTier
}

/// A state pose with extra deltas layered on, as one beat's target.
private func variant(_ base: ExpressionName, _ extra: FaceExpression) -> FaceExpression {
    (FACE_EXPRESSIONS[base] ?? FaceExpression()).merging(extra)
}

/* Timing lifted from the reference: calm states hold long beats and blink
   slowly; busy states change often and blink quickly. */
private let CALM = BlinkTier(first: 2600, min: 3400, max: 6200, duration: 280)
private let ATTENTIVE = BlinkTier(first: 3200, min: 4800, max: 7200, duration: 240)
private let BUSY = BlinkTier(first: 2100, min: 2800, max: 5000, duration: 260)

/* Theatrical register (operator's choice 2026-08-15): each state has a
   silhouette you can name from across the room, full-cartoon gaze travel, and
   thinking changes fast. Gaze values here are in the renderer's clamped
   head-normalised space; +-1 is a hard look to one side. */
private let ANIMATIONS: [FaceState: FaceAnimation] = [
    /* Soft and unhurried, but never frozen: long holds, then a frank look
       away somewhere, once with a lazy half-lid. */
    .idle: FaceAnimation(
        beats: [
            Beat(expr: FACE_EXPRESSIONS[.neutral]!, ms: 4200),
            Beat(expr: variant(.neutral, FaceExpression(
                add: [.gazeX: -0.85, .gazeY: 0.1, .eyeTilt: -0.04, .headTilt: -0.02])), ms: 3200),
            Beat(expr: FACE_EXPRESSIONS[.neutral]!, ms: 4200),
            Beat(expr: variant(.neutral, FaceExpression(
                add: [.gazeX: 0.7, .eyelidL: 0.25, .eyelidR: 0.25, .headTilt: 0.02])), ms: 2800),
        ],
        blink: CALM),
    /* Attention, near the idle silhouette: a modest lift and a lean-in tilt;
       the look-target (the input box) does most of the telling. */
    .listening: FaceAnimation(
        beats: [
            Beat(expr: variant(.listening, FaceExpression(
                scale: [.eyeLength: 0.18, .eyeSize: 0.06],
                add: [.headTilt: 0.05])), ms: 2000),
            Beat(expr: variant(.listening, FaceExpression(
                scale: [.eyeLength: 0.22, .eyeSize: 0.08],
                add: [.gazeY: -0.1, .headTilt: 0.04])), ms: 2000),
            Beat(expr: variant(.listening, FaceExpression(
                scale: [.eyeLength: 0.15, .eyeSize: 0.05],
                add: [.gazeX: 0.15, .eyeRaiseL: -0.015, .headTilt: 0.06])), ms: 2000),
        ],
        blink: ATTENTIVE),
    /* Half-height eyes thrown up and to the sides, quick asymmetric beats,
       one flat-dash "processing" hold. */
    .thinking: FaceAnimation(
        beats: [
            Beat(expr: variant(.thinking, FaceExpression(
                scale: [.eyeLength: -0.15],
                add: [.gazeX: 0.9, .gazeY: -0.55])), ms: 1500),
            Beat(expr: variant(.thinking, FaceExpression(
                add: [.gazeX: -0.95, .gazeY: -0.5, .eyeRaiseR: -0.03, .headTilt: -0.04])), ms: 1500),
            Beat(expr: variant(.thinking, FaceExpression(
                add: [.eyelidL: 0.6, .eyeScaleR: 0.25, .gazeX: 0.5, .gazeY: -0.4])), ms: 1400),
            Beat(expr: variant(.thinking, FaceExpression(
                add: [.eyelidL: 0.75, .eyelidR: 0.75, .gazeX: 0, .gazeY: 0])), ms: 1300),
            Beat(expr: variant(.thinking, FaceExpression(
                add: [.gazeX: -0.6, .gazeY: -0.6, .eyeTiltL: 0.08, .headTilt: 0.04])), ms: 1500),
        ],
        blink: BUSY),
    /* The mouth does the talking; the eyes stay engaged and mobile. */
    .speaking: FaceAnimation(
        beats: [
            Beat(expr: variant(.speaking, FaceExpression(scale: [.eyeSize: 0.1])), ms: 1800),
            Beat(expr: variant(.speaking, FaceExpression(
                scale: [.eyeSize: 0.12],
                add: [.gazeX: 0.3, .eyeTilt: -0.03, .headTilt: 0.02])), ms: 1800),
            Beat(expr: variant(.speaking, FaceExpression(
                scale: [.eyeSize: 0.08],
                add: [.gazeX: -0.25, .eyeRaiseL: -0.015, .headTilt: -0.02])), ms: 1800),
        ],
        blink: BUSY),
]

/// ms of eased approach toward the current beat's pose.
private let EASE_TAU: Double = 140

/* A transient is a little performance, not just a pose: each cue carries a
   full envelope -- lerp IN over `attack`, hold, lerp OUT over `decay` -- so
   reactions ease into the face and chain together naturally instead of
   popping. Ramps are smoothstepped. An optional motion layer (bounce, nod)
   rides on top; t is ms since the cue fired, w the current weight. */
private struct TransientProfile {
    let attack: Double
    let hold: Double
    let decay: Double
    var motion: (@Sendable (Double, Double) -> FaceExpression)?

    init(attack: Double, hold: Double, decay: Double,
         motion: (@Sendable (Double, Double) -> FaceExpression)? = nil) {
        self.attack = attack
        self.hold = hold
        self.decay = decay
        self.motion = motion
    }
}

private let DEFAULT_TRANSIENT = TransientProfile(attack: 140, hold: 260, decay: 950)

private let TRANSIENTS: [String: TransientProfile] = [
    /* A physical chuckle: the whole face bounces fast and small while the
       happy arcs hold, like laughter shaking through the body. */
    "laughter": TransientProfile(attack: 120, hold: 1600, decay: 650) { t, w in
        FaceExpression(add: [
            .headBob: sin((t / 135) * .pi * 2) * 0.04 * w,
            .headTilt: sin((t / 270) * .pi * 2) * 0.018 * w,
        ])
    },
    /* The yes-nod: two slow downward bobs under the contented arc-squint. */
    "confirmation": TransientProfile(attack: 150, hold: 1250, decay: 500) { t, w in
        FaceExpression(add: [.headBob: ((1 - cos((t / 620) * .pi * 2)) / 2) * 0.11 * w])
    },
    /* A sigh settles in slowly and takes its time leaving. */
    "sigh": TransientProfile(attack: 400, hold: 900, decay: 1100),
    /* The startle: eyes lerp wide, hold a beat, lerp back. */
    "surprise": TransientProfile(attack: 150, hold: 700, decay: 450),
    /* A deliberate blink at REAL blink speed. Without this entry the
       Animations panel's blink chip fell through to the default envelope and
       played a ~1.35s eyes-closed performance -- five times slower than the
       blinkWeight blink the stage actually does, on the screen whose purpose
       is showing what the stage will show. Not a name the harness sends;
       ambient blinks come from the state tier's schedule. */
    "blink": TransientProfile(attack: 110, hold: 40, decay: 140),
]

/// Smoothstepped 0..1 envelope for a transient's age. Negative age is a cue
/// stamped between frames (or a backwards clock) -- weight zero, because the
/// smoothstep is positive for negative inputs and would pre-fire the
/// reaction at partial (or, after a clock jump, absurd) weight.
private func transientWeight(_ age: Double, _ p: TransientProfile) -> Double {
    guard age >= 0 else { return 0 }
    var w: Double
    if age <= p.attack {
        w = p.attack > 0 ? age / p.attack : 1
    } else if age <= p.attack + p.hold {
        w = 1
    } else {
        w = max(0, 1 - (age - p.attack - p.hold) / p.decay)
    }
    return w * w * (3 - 2 * w)
}

/// Quick close, slower open; nil when the blink is over.
private func blinkWeight(_ sinceStart: Double, _ duration: Double) -> Double? {
    if sinceStart < 0 { return nil }
    let close = duration * 0.42
    if sinceStart < close { return sinceStart / close }
    if sinceStart < duration { return 1 - (sinceStart - close) / (duration - close) }
    return nil
}

/// Micro-saccades: small, quick, irregular. The gaze never sits dead.
private let SACCADE_MIN_MS: Double = 900
private let SACCADE_MAX_MS: Double = 2600
private let SACCADE_AMP_X: Double = 0.18
private let SACCADE_AMP_Y: Double = 0.1
/// A slow breathing sway on the whole head -- the lab's "subtle living
/// presence". Radians of head tilt, sinusoidal.
private let SWAY_AMP: Double = 0.014
private let SWAY_PERIOD_MS: Double = 5200

/// Plain class, no actor: it is only ever touched from the render loop, one
/// tick at a time, and an actor would put an await inside a Canvas draw.
public final class FaceDirector {
    private let geometry: FaceGeometry
    private var pose: FacePose
    private var state: FaceState = .idle
    private var beatIndex = 0
    private var beatStartedAt: Double
    private var blinkStartedAt: Double = -1
    private var nextBlinkAt: Double
    /// The tier duration CAPTURED when the blink started, so a state change
    /// mid-blink cannot re-measure a half-closed lid against a shorter tier
    /// and snap it open in one frame.
    private var blinkDuration: Double = CALM.duration
    private var saccade = (x: 0.0, y: 0.0)
    private var nextSaccadeAt: Double
    private var last: Double

    public init(geometry: FaceGeometry, now: Double) {
        self.geometry = geometry
        self.pose = neutralPose(geometry)
        self.beatStartedAt = now
        self.nextBlinkAt = now + (ANIMATIONS[.idle]?.blink.first ?? CALM.first)
        self.nextSaccadeAt = now + SACCADE_MIN_MS
        self.last = now
    }

    /// One frame. Layers are recomputed every tick; only the eased base pose
    /// carries over between frames.
    public func tick(
        now: Double,
        state: FaceState,
        cue: FaceCue?,
        speechLevel: Double,
        reduceMotion: Bool,
        lookTarget: LookTarget? = nil
    ) -> FacePose {
        // Clamped BOTH ways. The desktop original ticks on monotonic
        // performance.now(), where a min-only clamp is harmless; this port
        // ticks on wall-clock timeline.date, where a backwards adjustment
        // (NTP, a manual change) makes dt negative -- alpha then drives every
        // channel AWAY from target, and a large jump overflows exp() into a
        // NaN pose nothing ever clears.
        let dt = min(100, max(0, now - last))
        last = now

        guard let anim = ANIMATIONS[state] else { return pose }
        if state != self.state {
            // Entering a state restarts its playlist. The blink COUNTDOWN
            // carries across, only re-tiered: a full re-arm meant any
            // conversation cycling states faster than the tier's `first`
            // (2100-3200ms -- i.e. every normal exchange) never blinked at
            // all. An in-flight blink keeps its captured duration and simply
            // finishes. (Desktop's director.ts has the same starvation;
            // upstream fix noted in tasks/persona-face-ios-review.md.)
            self.state = state
            beatIndex = 0
            beatStartedAt = now
            nextBlinkAt = min(nextBlinkAt, now + anim.blink.first)
        }

        // Advance the playlist.
        let beat = anim.beats[beatIndex % anim.beats.count]
        if now - beatStartedAt >= beat.ms {
            beatIndex = (beatIndex + 1) % anim.beats.count
            beatStartedAt = now
        }
        let target = applyExpression(
            neutralPose(geometry), anim.beats[beatIndex].expr, weight: 1)

        // Ease every channel toward the beat's pose. Reduce motion snaps.
        let alpha = reduceMotion ? 1 : 1 - exp(-dt / EASE_TAU)
        for channel in PoseChannel.allCases {
            pose[channel] += (target[channel] - pose[channel]) * alpha
        }

        var frame = pose

        // While listening, the face watches where the words are coming from:
        // the host's look target (the composer input on desktop, the keyboard
        // area on a phone) mostly overrides the beat's gaze, converged near.
        // Saccades still ride on top, so the watch stays alive.
        if state == .listening, let lookTarget {
            frame = applyExpression(frame, FaceExpression(add: [
                .gazeX: (lookTarget.x - frame.gazeX) * 0.85,
                .gazeY: (lookTarget.y - frame.gazeY) * 0.85,
                .focus: (lookTarget.focus - frame.focus) * 0.85,
            ]), weight: 1)
        }

        // Micro-saccades: the gaze jumps a little at irregular intervals and
        // the easing above is what makes the jump read as a dart, not a snap.
        if !reduceMotion {
            if now >= nextSaccadeAt {
                saccade = (
                    x: Double.random(in: -1...1) * SACCADE_AMP_X,
                    y: Double.random(in: -1...1) * SACCADE_AMP_Y
                )
                nextSaccadeAt = now + SACCADE_MIN_MS
                    + Double.random(in: 0...1) * (SACCADE_MAX_MS - SACCADE_MIN_MS)
            }
            frame = applyExpression(
                frame, FaceExpression(add: [.gazeX: saccade.x, .gazeY: saccade.y]), weight: 1)
            // Breathing sway: continuous, slow, never still.
            frame = applyExpression(frame, FaceExpression(
                add: [.headTilt: sin((now * 2 * .pi) / SWAY_PERIOD_MS) * SWAY_AMP]), weight: 1)
        }

        // The harness's transient cue: full weight through its hold, then a
        // decay -- with the cue's own motion envelope (chuckle bounce, nod)
        // riding on top while it plays.
        if let cue {
            let age = now - cue.at
            let profile = TRANSIENTS[cue.name] ?? DEFAULT_TRANSIENT
            let weight = transientWeight(age, profile)
            if weight > 0 {
                frame = applyNamedExpression(frame, cue.name, weight: weight)
                if let motion = profile.motion, !reduceMotion {
                    frame = applyExpression(frame, motion(age, weight), weight: 1)
                }
            }
        }

        // Blink, on the state's energy tier. Suppressed under reduce motion;
        // lids still move with expressions that close them.
        if !reduceMotion {
            if blinkStartedAt < 0 && now >= nextBlinkAt {
                blinkStartedAt = now
                blinkDuration = anim.blink.duration
            }
            if blinkStartedAt >= 0 {
                if let w = blinkWeight(now - blinkStartedAt, blinkDuration) {
                    frame = applyExpression(frame, FACE_EXPRESSIONS[.blink]!, weight: w)
                } else {
                    blinkStartedAt = -1
                    nextBlinkAt = now + anim.blink.min
                        + Double.random(in: 0...1) * (anim.blink.max - anim.blink.min)
                }
            }
        }

        // The mouth follows the sound itself, not the state -- and a talking
        // mouth is a clean round oval whose height rides the amplitude. A
        // partial crescent underlay looked like a beak; pure oval reads as
        // talking.
        if speechLevel > 0.01 {
            frame = applyExpression(
                frame, FaceExpression(add: [.mouthOpen: speechLevel, .mouthRound: 1]), weight: 1)
        }

        return frame
    }
}
