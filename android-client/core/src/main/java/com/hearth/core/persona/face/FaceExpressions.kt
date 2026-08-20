package com.hearth.core.persona.face

/**
 * The expression library for procedural_face personas. Ported value for value
 * from the iOS `FaceExpressions.swift`, which is itself a port of the desktop
 * client's `lib/face/expressions.ts`: all three clients must perform the SAME
 * face, and the numbers are the tuned truth. Change them in one place only
 * after changing them everywhere.
 *
 * Every entry is a set of DELTAS against the persona's own geometry:
 * `listening` lengthens whatever eyes that persona has rather than setting
 * them equal, which is why a persona authors a dozen numbers instead of an
 * animation set.
 *
 * The face is EYES-FIRST: two vertical capsules carry the character, there
 * are no brows, and the mouth only appears when speech amplitude or a
 * transient opens it.
 *
 * Two kinds of delta, chosen per channel:
 *   scale -- multiplicative, for sizes: v * (1 + delta * weight)
 *   add   -- additive, for positions, angles, and pose channels
 *
 * Sign conventions:
 *   eyeTilt     radians, positive leans both capsules clockwise
 *   mouthCurve  positive = smile
 *   headTilt    radians, positive = clockwise on screen
 *   gazeX/Y     head-normalised offset, positive = right/down
 *   eyelid      0 open .. 1 closed
 *   mouthOpen   0 closed .. 1 wide; speech amplitude drives it live
 *
 * Pure data plus one pure function. No Compose, no time.
 */

/** Every channel a pose carries: geometry first, then motion-only. */
enum class PoseChannel {
    // geometry
    HEAD_WIDTH, HEAD_HEIGHT, HEAD_ROUNDNESS,
    EYE_SIZE, EYE_SPACING, EYE_HEIGHT, EYE_LENGTH, EYE_TILT,
    MOUTH_WIDTH, MOUTH_THICKNESS, MOUTH_CURVE,

    // motion-only
    EYELID_L, EYELID_R, EYE_ARC, FOCUS, HEAD_BOB,
    EYE_SCALE_L, EYE_SCALE_R, EYE_TILT_L, EYE_TILT_R, EYE_RAISE_L, EYE_RAISE_R,
    GAZE_X, GAZE_Y, HEAD_TILT, MOUTH_OPEN, MOUTH_ROUND,
}

/**
 * Geometry plus the channels only motion owns. A channel map rather than 27
 * fields so the director's easing and [applyExpression] can iterate.
 */
data class FacePose(val values: Map<PoseChannel, Double>) {

    operator fun get(c: PoseChannel): Double = values[c] ?: 0.0

    fun with(c: PoseChannel, v: Double): FacePose =
        FacePose(values.toMutableMap().apply { put(c, v) })

    val headWidth get() = this[PoseChannel.HEAD_WIDTH]
    val headHeight get() = this[PoseChannel.HEAD_HEIGHT]
    val headRoundness get() = this[PoseChannel.HEAD_ROUNDNESS]
    val eyeSize get() = this[PoseChannel.EYE_SIZE]
    val eyeSpacing get() = this[PoseChannel.EYE_SPACING]
    val eyeHeight get() = this[PoseChannel.EYE_HEIGHT]
    val eyeLength get() = this[PoseChannel.EYE_LENGTH]
    val eyeTilt get() = this[PoseChannel.EYE_TILT]
    val mouthWidth get() = this[PoseChannel.MOUTH_WIDTH]
    val mouthThickness get() = this[PoseChannel.MOUTH_THICKNESS]
    val mouthCurve get() = this[PoseChannel.MOUTH_CURVE]
    val eyelidL get() = this[PoseChannel.EYELID_L]
    val eyelidR get() = this[PoseChannel.EYELID_R]
    val eyeArc get() = this[PoseChannel.EYE_ARC]
    val focus get() = this[PoseChannel.FOCUS]
    val headBob get() = this[PoseChannel.HEAD_BOB]
    val eyeScaleL get() = this[PoseChannel.EYE_SCALE_L]
    val eyeScaleR get() = this[PoseChannel.EYE_SCALE_R]
    val eyeTiltL get() = this[PoseChannel.EYE_TILT_L]
    val eyeTiltR get() = this[PoseChannel.EYE_TILT_R]
    val eyeRaiseL get() = this[PoseChannel.EYE_RAISE_L]
    val eyeRaiseR get() = this[PoseChannel.EYE_RAISE_R]
    val gazeX get() = this[PoseChannel.GAZE_X]
    val gazeY get() = this[PoseChannel.GAZE_Y]
    val headTilt get() = this[PoseChannel.HEAD_TILT]
    val mouthOpen get() = this[PoseChannel.MOUTH_OPEN]
    val mouthRound get() = this[PoseChannel.MOUTH_ROUND]
}

/** A geometry at rest: motion channels zeroed, sizes at their resting 1. */
fun neutralPose(g: FaceGeometry): FacePose = FacePose(
    mapOf(
        PoseChannel.HEAD_WIDTH to g.headWidth,
        PoseChannel.HEAD_HEIGHT to g.headHeight,
        PoseChannel.HEAD_ROUNDNESS to g.headRoundness,
        PoseChannel.EYE_SIZE to g.eyeSize,
        PoseChannel.EYE_SPACING to g.eyeSpacing,
        PoseChannel.EYE_HEIGHT to g.eyeHeight,
        PoseChannel.EYE_LENGTH to g.eyeLength,
        PoseChannel.EYE_TILT to g.eyeTilt,
        PoseChannel.MOUTH_WIDTH to g.mouthWidth,
        PoseChannel.MOUTH_THICKNESS to g.mouthThickness,
        PoseChannel.MOUTH_CURVE to g.mouthCurve,
        PoseChannel.EYELID_L to 0.0,
        PoseChannel.EYELID_R to 0.0,
        PoseChannel.EYE_ARC to 0.0,
        PoseChannel.FOCUS to 0.0,
        PoseChannel.HEAD_BOB to 0.0,
        PoseChannel.EYE_SCALE_L to 1.0,
        PoseChannel.EYE_SCALE_R to 1.0,
        PoseChannel.EYE_TILT_L to 0.0,
        PoseChannel.EYE_TILT_R to 0.0,
        PoseChannel.EYE_RAISE_L to 0.0,
        PoseChannel.EYE_RAISE_R to 0.0,
        PoseChannel.GAZE_X to 0.0,
        PoseChannel.GAZE_Y to 0.0,
        PoseChannel.HEAD_TILT to 0.0,
        PoseChannel.MOUTH_OPEN to 0.0,
        PoseChannel.MOUTH_ROUND to 0.0,
    )
)

data class FaceExpression(
    /** multiplicative: v * (1 + delta * weight) */
    val scale: Map<PoseChannel, Double> = emptyMap(),
    /** additive: v + delta * weight */
    val add: Map<PoseChannel, Double> = emptyMap(),
) {
    /**
     * This expression with extra deltas layered over it, as one beat's target.
     * The director's playlists are written this way: a state pose plus the
     * beat's own variation, rather than eleven near-copies of one table.
     */
    fun merging(extra: FaceExpression): FaceExpression = FaceExpression(
        scale = scale + extra.scale,
        add = add + extra.add,
    )
}

enum class ExpressionName {
    NEUTRAL, LISTENING, THINKING, SPEAKING, BLINK,
    LAUGHTER, SIGH, SURPRISE, QUESTION, CONFIRMATION, DISSATISFACTION;

    companion object {
        /** Wire names arrive lowercase on `tts_chunk_start.expression`. */
        fun fromWire(raw: String): ExpressionName? =
            entries.firstOrNull { it.name.equals(raw.trim(), ignoreCase = true) }
    }
}

val FACE_EXPRESSIONS: Map<ExpressionName, FaceExpression> = mapOf(
    // The identity offset. Applying it at any weight returns the pose given.
    ExpressionName.NEUTRAL to FaceExpression(),

    // ---- resting poses, one per state the house already emits ----

    // Mild on purpose: this is a pose someone LIVES with for whole minutes.
    ExpressionName.LISTENING to FaceExpression(
        scale = mapOf(PoseChannel.EYE_LENGTH to 0.12),
        add = mapOf(PoseChannel.HEAD_TILT to 0.025),
    ),
    // Shortened eyes glancing up and aside, with a small parallel lean.
    ExpressionName.THINKING to FaceExpression(
        scale = mapOf(PoseChannel.EYE_LENGTH to -0.35),
        add = mapOf(
            PoseChannel.EYE_TILT to 0.1,
            PoseChannel.GAZE_X to 0.3,
            PoseChannel.GAZE_Y to -0.2,
        ),
    ),
    // The mouth does the talking (amplitude-driven); the eyes just brighten.
    ExpressionName.SPEAKING to FaceExpression(
        scale = mapOf(PoseChannel.EYE_LENGTH to 0.05),
    ),

    // ---- fired on a timer, not a state ----

    ExpressionName.BLINK to FaceExpression(
        add = mapOf(PoseChannel.EYELID_L to 1.0, PoseChannel.EYELID_R to 1.0),
    ),

    // ---- transients, resolved by the harness from non-verbal tags.
    // EYES-ONLY by decision (2026-08-15): the mouth is reserved for the
    // speech oval, so every reaction carries its meaning in the eyes.
    // Asymmetry is deliberate where it appears: matched eyes read as a
    // machine, mismatched ones read as a creature. ----

    // Full happy arcs with a merry lean; the chuckle bounce rides the
    // transient's motion envelope in the director.
    ExpressionName.LAUGHTER to FaceExpression(
        add = mapOf(
            PoseChannel.EYELID_L to 0.9,
            PoseChannel.EYELID_R to 0.9,
            PoseChannel.EYE_ARC to 1.0,
            PoseChannel.EYE_TILT to -0.1,
            PoseChannel.HEAD_TILT to -0.06,
        ),
    ),
    // The pensive-emoji droop: closed sad arcs, outer ends sinking.
    ExpressionName.SIGH to FaceExpression(
        add = mapOf(
            PoseChannel.EYELID_L to 0.85,
            PoseChannel.EYELID_R to 0.85,
            PoseChannel.EYE_ARC to -0.85,
            PoseChannel.EYE_TILT_L to -0.14,
            PoseChannel.EYE_TILT_R to 0.14,
            PoseChannel.GAZE_Y to 0.15,
            PoseChannel.HEAD_TILT to 0.03,
        ),
    ),
    // The startle: rounder eyes grown clearly larger, slightly raised and
    // converged -- startled AT you.
    ExpressionName.SURPRISE to FaceExpression(
        scale = mapOf(PoseChannel.EYE_LENGTH to -0.3),
        add = mapOf(
            PoseChannel.EYE_SCALE_L to 0.35,
            PoseChannel.EYE_SCALE_R to 0.35,
            PoseChannel.EYE_RAISE_L to -0.012,
            PoseChannel.EYE_RAISE_R to -0.012,
            PoseChannel.FOCUS to 0.3,
        ),
    ),
    // The raised-brow emoji: one eye raised, the other narrowed smaller.
    ExpressionName.QUESTION to FaceExpression(
        scale = mapOf(PoseChannel.EYE_LENGTH to 0.15),
        add = mapOf(
            PoseChannel.EYE_TILT to 0.15,
            PoseChannel.EYE_RAISE_L to -0.04,
            PoseChannel.EYE_SCALE_R to -0.18,
            PoseChannel.EYELID_R to 0.2,
            PoseChannel.HEAD_TILT to 0.08,
            PoseChannel.GAZE_X to 0.2,
        ),
    ),
    // A soft contented arc-squint; the yes-nod rides the motion envelope.
    ExpressionName.CONFIRMATION to FaceExpression(
        add = mapOf(
            PoseChannel.EYELID_L to 0.6,
            PoseChannel.EYELID_R to 0.6,
            PoseChannel.EYE_ARC to 0.9,
            PoseChannel.HEAD_TILT to -0.03,
        ),
    ),
    // The unamused emoji: both eyes equally half-lidded, gaze hard to one
    // side, dead level.
    ExpressionName.DISSATISFACTION to FaceExpression(
        add = mapOf(
            PoseChannel.EYELID_L to 0.55,
            PoseChannel.EYELID_R to 0.55,
            PoseChannel.GAZE_X to 0.65,
        ),
    ),
)

/**
 * Resolve a pose + expression + weight into a pose. Weight 0 is the input
 * unchanged; 1 is the full expression. Layering is applying again: state pose
 * first, then a transient, then blink, each with its own weight.
 */
fun applyExpression(base: FacePose, e: FaceExpression, weight: Double): FacePose {
    if (weight == 0.0) return base
    val w = weight.coerceIn(0.0, 1.0)
    val values = base.values.toMutableMap()
    for ((c, d) in e.scale) values[c] = (values[c] ?: 0.0) * (1 + d * w)
    for ((c, d) in e.add) values[c] = (values[c] ?: 0.0) + d * w
    // Channels with hard physical ranges stay in them, whatever was layered.
    values[PoseChannel.EYELID_L] = (values[PoseChannel.EYELID_L] ?: 0.0).coerceIn(0.0, 1.0)
    values[PoseChannel.EYELID_R] = (values[PoseChannel.EYELID_R] ?: 0.0).coerceIn(0.0, 1.0)
    values[PoseChannel.EYE_ARC] = (values[PoseChannel.EYE_ARC] ?: 0.0).coerceIn(-1.0, 1.0)
    values[PoseChannel.FOCUS] = (values[PoseChannel.FOCUS] ?: 0.0).coerceIn(0.0, 1.0)
    values[PoseChannel.MOUTH_OPEN] = (values[PoseChannel.MOUTH_OPEN] ?: 0.0).coerceIn(0.0, 1.0)
    values[PoseChannel.MOUTH_ROUND] = (values[PoseChannel.MOUTH_ROUND] ?: 0.0).coerceIn(0.0, 1.0)
    return FacePose(values)
}

/**
 * Resolve a name from the harness. Unknown names are neutral: a house ahead of
 * this client names an expression it has not learned, and the face must go on
 * rather than break.
 */
fun applyNamedExpression(base: FacePose, name: String, weight: Double): FacePose {
    val named = ExpressionName.fromWire(name) ?: return base
    val e = FACE_EXPRESSIONS[named] ?: return base
    return applyExpression(base, e, weight)
}
