//
//  FaceExpressions.swift
//  Hearth
//
//  The expression library for procedural_face personas. A port of the desktop
//  client's `lib/face/expressions.ts`, value for value: the two clients must
//  perform the SAME face, and the numbers there are the tuned truth.
//
//  Every entry is a set of DELTAS against the persona's own geometry:
//  `listening` lengthens whatever eyes that persona has rather than setting
//  them equal, which is the whole reason a persona authors a dozen numbers
//  instead of an animation set.
//
//  The face is EYES-FIRST: two vertical capsules carry the character (the
//  grok-bot register -- squints, dashes, leans), there are no brows, and the
//  mouth only appears when speech amplitude or a transient opens it. So
//  expressions do their acting in the eye channels; mouth deltas exist for the
//  moments the mouth is on screen.
//
//  Two kinds of delta, chosen per channel:
//    scale -- multiplicative, for sizes: v * (1 + delta * weight). A big eye
//             and a small eye change by the same PROPORTION.
//    add   -- additive, for positions, angles, and pose channels:
//             v + delta * weight. Normalised head units, same as geometry.
//
//  Sign conventions:
//    eyeTilt     radians, positive leans both capsules clockwise (italic)
//    mouthCurve  positive = smile (the crescent's belly dips DOWN on screen)
//    headTilt    radians, positive = clockwise on screen
//    gazeX/Y     head-normalised offset, positive = right/down
//    eyelid      0 open .. 1 closed; closing collapses the capsule toward a
//                horizontal dash rather than shrinking it to nothing
//    mouthOpen   0 closed .. 1 wide; speech amplitude drives it live
//
//  Pure data plus one pure function. No SwiftUI, no time.
//

import Foundation

/// Every channel a pose carries: the geometry ones a persona authors, then the
/// ones only motion ever writes.
public enum PoseChannel: String, CaseIterable, Sendable {
    // geometry
    case headWidth, headHeight, headRoundness
    case eyeSize, eyeSpacing, eyeHeight, eyeLength, eyeTilt
    case mouthWidth, mouthThickness, mouthCurve
    // motion-only
    case eyelidL, eyelidR, eyeArc, focus, headBob
    case eyeScaleL, eyeScaleR, eyeTiltL, eyeTiltR, eyeRaiseL, eyeRaiseR
    case gazeX, gazeY, headTilt, mouthOpen, mouthRound
}

/// Geometry plus the channels only motion owns.
///
/// Kept as a channel map rather than 27 stored properties so `applyExpression`
/// and the director's easing can iterate; the accessors below keep the call
/// sites readable. The TypeScript is an object with the same keys, and the
/// director eases "every key" there too.
public struct FacePose: Sendable {
    public var values: [PoseChannel: Double]

    public init(values: [PoseChannel: Double]) { self.values = values }

    public subscript(_ c: PoseChannel) -> Double {
        get { values[c] ?? 0 }
        set { values[c] = newValue }
    }

    public var headWidth: Double { self[.headWidth] }
    public var headHeight: Double { self[.headHeight] }
    public var headRoundness: Double { self[.headRoundness] }
    public var eyeSize: Double { self[.eyeSize] }
    public var eyeSpacing: Double { self[.eyeSpacing] }
    public var eyeHeight: Double { self[.eyeHeight] }
    public var eyeLength: Double { self[.eyeLength] }
    public var eyeTilt: Double { self[.eyeTilt] }
    public var mouthWidth: Double { self[.mouthWidth] }
    public var mouthThickness: Double { self[.mouthThickness] }
    public var mouthCurve: Double { self[.mouthCurve] }
    public var eyelidL: Double { self[.eyelidL] }
    public var eyelidR: Double { self[.eyelidR] }
    public var eyeArc: Double { self[.eyeArc] }
    public var focus: Double { self[.focus] }
    public var headBob: Double { self[.headBob] }
    public var eyeScaleL: Double { self[.eyeScaleL] }
    public var eyeScaleR: Double { self[.eyeScaleR] }
    public var eyeTiltL: Double { self[.eyeTiltL] }
    public var eyeTiltR: Double { self[.eyeTiltR] }
    public var eyeRaiseL: Double { self[.eyeRaiseL] }
    public var eyeRaiseR: Double { self[.eyeRaiseR] }
    public var gazeX: Double { self[.gazeX] }
    public var gazeY: Double { self[.gazeY] }
    public var headTilt: Double { self[.headTilt] }
    public var mouthOpen: Double { self[.mouthOpen] }
    public var mouthRound: Double { self[.mouthRound] }
}

/// A geometry at rest: motion channels zeroed, sizes at their resting 1.
public func neutralPose(_ g: FaceGeometry) -> FacePose {
    FacePose(values: [
        .headWidth: g.headWidth, .headHeight: g.headHeight, .headRoundness: g.headRoundness,
        .eyeSize: g.eyeSize, .eyeSpacing: g.eyeSpacing, .eyeHeight: g.eyeHeight,
        .eyeLength: g.eyeLength, .eyeTilt: g.eyeTilt,
        .mouthWidth: g.mouthWidth, .mouthThickness: g.mouthThickness, .mouthCurve: g.mouthCurve,
        .eyelidL: 0, .eyelidR: 0, .eyeArc: 0, .focus: 0, .headBob: 0,
        .eyeScaleL: 1, .eyeScaleR: 1, .eyeTiltL: 0, .eyeTiltR: 0,
        .eyeRaiseL: 0, .eyeRaiseR: 0,
        .gazeX: 0, .gazeY: 0, .headTilt: 0, .mouthOpen: 0, .mouthRound: 0,
    ])
}

public struct FaceExpression: Sendable {
    /// multiplicative: v * (1 + delta * weight)
    public var scale: [PoseChannel: Double]
    /// additive: v + delta * weight
    public var add: [PoseChannel: Double]

    public init(scale: [PoseChannel: Double] = [:], add: [PoseChannel: Double] = [:]) {
        self.scale = scale
        self.add = add
    }

    /// This expression with extra deltas layered over it, as one beat's target.
    /// The director's playlists are written this way: a state pose plus the
    /// beat's own variation, rather than eleven near-copies of the same table.
    func merging(_ extra: FaceExpression) -> FaceExpression {
        FaceExpression(
            scale: scale.merging(extra.scale) { _, new in new },
            add: add.merging(extra.add) { _, new in new })
    }
}

public enum ExpressionName: String, CaseIterable, Sendable {
    case neutral, listening, thinking, speaking, blink
    case laughter, sigh, surprise, question, confirmation, dissatisfaction
}

public let FACE_EXPRESSIONS: [ExpressionName: FaceExpression] = [
    /// The identity offset. Applying it at any weight returns the pose given.
    .neutral: FaceExpression(),

    // ---- resting poses, one per state the house already emits ----

    /* Mild on purpose: focus sits in the message box for whole minutes, so
       this is a pose someone LIVES with. Slightly taller eyes, a hair of tilt. */
    .listening: FaceExpression(
        scale: [.eyeLength: 0.12],
        add: [.headTilt: 0.025]),
    /* Shortened eyes glancing up and aside, with a small parallel lean --
       the capsule equivalent of narrowed eyes looking off-axis. */
    .thinking: FaceExpression(
        scale: [.eyeLength: -0.35],
        add: [.eyeTilt: 0.1, .gazeX: 0.3, .gazeY: -0.2]),
    /* The mouth does the talking (amplitude-driven); the eyes just brighten. */
    .speaking: FaceExpression(
        scale: [.eyeLength: 0.05]),

    // ---- fired on a timer, not a state ----

    .blink: FaceExpression(
        add: [.eyelidL: 1.0, .eyelidR: 1.0]),

    /* ---- transients, resolved by the harness from non-verbal tags.
       EYES-ONLY by decision (2026-08-15): the mouth is reserved for the
       speech oval until it gets a proper design pass, so every reaction
       carries its whole meaning in the eyes -- overly expressive on purpose.
       Asymmetry is deliberate where it appears: matched eyes read as a
       machine, mismatched ones read as a creature. ---- */

    /* Full happy arcs with a merry lean; the chuckle bounce rides on the
       transient's motion envelope in the director. */
    .laughter: FaceExpression(
        add: [.eyelidL: 0.9, .eyelidR: 0.9, .eyeArc: 1, .eyeTilt: -0.1, .headTilt: -0.06]),
    /* The pensive-emoji droop: closed sad arcs, outer ends sinking. */
    .sigh: FaceExpression(
        add: [.eyelidL: 0.85, .eyelidR: 0.85, .eyeArc: -0.85,
              .eyeTiltL: -0.14, .eyeTiltR: 0.14, .gazeY: 0.15, .headTilt: 0.03]),
    /* The startle: rounder eyes grown clearly larger, slightly raised and
       converged -- startled AT you. The director's envelope lerps this in,
       holds a beat, and lerps back out. */
    .surprise: FaceExpression(
        scale: [.eyeLength: -0.3],
        add: [.eyeScaleL: 0.35, .eyeScaleR: 0.35,
              .eyeRaiseL: -0.012, .eyeRaiseR: -0.012, .focus: 0.3]),
    /* The raised-brow emoji: one eye raised, the other narrowed smaller. */
    .question: FaceExpression(
        scale: [.eyeLength: 0.15],
        add: [.eyeTilt: 0.15, .eyeRaiseL: -0.04, .eyeScaleR: -0.18,
              .eyelidR: 0.2, .headTilt: 0.08, .gazeX: 0.2]),
    /* A soft contented arc-squint; the yes-nod rides the motion envelope. */
    .confirmation: FaceExpression(
        add: [.eyelidL: 0.6, .eyelidR: 0.6, .eyeArc: 0.9, .headTilt: -0.03]),
    /* The unamused emoji: both eyes equally half-lidded, gaze hard to one
       side, dead level. */
    .dissatisfaction: FaceExpression(
        add: [.eyelidL: 0.55, .eyelidR: 0.55, .gazeX: 0.65]),
]

/// Resolve a pose + expression + weight into a pose. Weight 0 is the input
/// unchanged; 1 is the full expression. Layering is applying again: state pose
/// first, then a transient, then blink, each with its own weight.
public func applyExpression(_ base: FacePose, _ e: FaceExpression, weight: Double) -> FacePose {
    var pose = base
    if weight == 0 { return pose }
    let w = min(1, max(0, weight))
    for (c, d) in e.scale { pose[c] = pose[c] * (1 + d * w) }
    for (c, d) in e.add { pose[c] = pose[c] + d * w }
    // Channels with hard physical ranges stay in them, whatever was layered.
    pose[.eyelidL] = min(1, max(0, pose[.eyelidL]))
    pose[.eyelidR] = min(1, max(0, pose[.eyelidR]))
    pose[.eyeArc] = min(1, max(-1, pose[.eyeArc]))
    pose[.focus] = min(1, max(0, pose[.focus]))
    pose[.mouthOpen] = min(1, max(0, pose[.mouthOpen]))
    pose[.mouthRound] = min(1, max(0, pose[.mouthRound]))
    return pose
}

/// Resolve a name from the harness. Unknown names are neutral: a house ahead
/// of this client names an expression it has not learned, and the face must go
/// on rather than break.
public func applyNamedExpression(_ base: FacePose, _ name: String, weight: Double) -> FacePose {
    guard let named = ExpressionName(rawValue: name), let e = FACE_EXPRESSIONS[named] else {
        return base
    }
    return applyExpression(base, e, weight: weight)
}
