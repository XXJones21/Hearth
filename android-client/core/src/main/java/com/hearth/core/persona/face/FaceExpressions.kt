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
 * Geometry plus the channels only motion owns.
 *
 * A flat [DoubleArray] indexed by [PoseChannel.ordinal], NOT a Map. The face
 * ticks sixty times a second and every layer used to copy a 27-entry map:
 * roughly two hundred allocations per frame, which the emulator hid and a
 * real device did not. The array is mutable in place and the director keeps
 * one scratch instance, so a frame allocates nothing.
 *
 * The read surface is unchanged, so the drawing code and the tests do not
 * know the difference.
 */
class FacePose(internal val v: DoubleArray = DoubleArray(CHANNEL_COUNT)) {

    operator fun get(c: PoseChannel): Double = v[c.ordinal]

    operator fun set(c: PoseChannel, value: Double) {
        v[c.ordinal] = value
    }

    /** A detached copy. Used where a pose must outlive the scratch buffer. */
    fun copy(): FacePose = FacePose(v.copyOf())

    /** Overwrite this pose from another, without allocating. */
    fun setFrom(other: FacePose) {
        other.v.copyInto(v)
    }

    val headWidth get() = v[PoseChannel.HEAD_WIDTH.ordinal]
    val headHeight get() = v[PoseChannel.HEAD_HEIGHT.ordinal]
    val headRoundness get() = v[PoseChannel.HEAD_ROUNDNESS.ordinal]
    val eyeSize get() = v[PoseChannel.EYE_SIZE.ordinal]
    val eyeSpacing get() = v[PoseChannel.EYE_SPACING.ordinal]
    val eyeHeight get() = v[PoseChannel.EYE_HEIGHT.ordinal]
    val eyeLength get() = v[PoseChannel.EYE_LENGTH.ordinal]
    val eyeTilt get() = v[PoseChannel.EYE_TILT.ordinal]
    val mouthWidth get() = v[PoseChannel.MOUTH_WIDTH.ordinal]
    val mouthThickness get() = v[PoseChannel.MOUTH_THICKNESS.ordinal]
    val mouthCurve get() = v[PoseChannel.MOUTH_CURVE.ordinal]
    val eyelidL get() = v[PoseChannel.EYELID_L.ordinal]
    val eyelidR get() = v[PoseChannel.EYELID_R.ordinal]
    val eyeArc get() = v[PoseChannel.EYE_ARC.ordinal]
    val focus get() = v[PoseChannel.FOCUS.ordinal]
    val headBob get() = v[PoseChannel.HEAD_BOB.ordinal]
    val eyeScaleL get() = v[PoseChannel.EYE_SCALE_L.ordinal]
    val eyeScaleR get() = v[PoseChannel.EYE_SCALE_R.ordinal]
    val eyeTiltL get() = v[PoseChannel.EYE_TILT_L.ordinal]
    val eyeTiltR get() = v[PoseChannel.EYE_TILT_R.ordinal]
    val eyeRaiseL get() = v[PoseChannel.EYE_RAISE_L.ordinal]
    val eyeRaiseR get() = v[PoseChannel.EYE_RAISE_R.ordinal]
    val gazeX get() = v[PoseChannel.GAZE_X.ordinal]
    val gazeY get() = v[PoseChannel.GAZE_Y.ordinal]
    val headTilt get() = v[PoseChannel.HEAD_TILT.ordinal]
    val mouthOpen get() = v[PoseChannel.MOUTH_OPEN.ordinal]
    val mouthRound get() = v[PoseChannel.MOUTH_ROUND.ordinal]

    companion object {
        val CHANNELS = PoseChannel.entries.toTypedArray()
        val CHANNEL_COUNT = CHANNELS.size
    }
}

/** A geometry at rest: motion channels zeroed, sizes at their resting 1. */
fun neutralPose(g: FaceGeometry): FacePose = FacePose().also { writeNeutral(g, it) }

/** The same, into an existing pose, so a frame allocates nothing. */
fun writeNeutral(g: FaceGeometry, into: FacePose) {
    val v = into.v
    java.util.Arrays.fill(v, 0.0)
    v[PoseChannel.HEAD_WIDTH.ordinal] = g.headWidth
    v[PoseChannel.HEAD_HEIGHT.ordinal] = g.headHeight
    v[PoseChannel.HEAD_ROUNDNESS.ordinal] = g.headRoundness
    v[PoseChannel.EYE_SIZE.ordinal] = g.eyeSize
    v[PoseChannel.EYE_SPACING.ordinal] = g.eyeSpacing
    v[PoseChannel.EYE_HEIGHT.ordinal] = g.eyeHeight
    v[PoseChannel.EYE_LENGTH.ordinal] = g.eyeLength
    v[PoseChannel.EYE_TILT.ordinal] = g.eyeTilt
    v[PoseChannel.MOUTH_WIDTH.ordinal] = g.mouthWidth
    v[PoseChannel.MOUTH_THICKNESS.ordinal] = g.mouthThickness
    v[PoseChannel.MOUTH_CURVE.ordinal] = g.mouthCurve
    v[PoseChannel.EYE_SCALE_L.ordinal] = 1.0
    v[PoseChannel.EYE_SCALE_R.ordinal] = 1.0
}

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
 * Layer an expression onto a pose, IN PLACE. Weight 0 leaves it untouched; 1
 * is the full expression. Layering is applying again: state pose first, then
 * a transient, then blink, each with its own weight.
 *
 * Mutating rather than returning a new pose is what keeps a frame free of
 * allocation; the director layers roughly six times per tick.
 */
fun applyExpression(pose: FacePose, e: FaceExpression, weight: Double) {
    if (weight == 0.0) return
    val w = weight.coerceIn(0.0, 1.0)
    val v = pose.v
    for ((c, d) in e.scale) v[c.ordinal] = v[c.ordinal] * (1 + d * w)
    for ((c, d) in e.add) v[c.ordinal] = v[c.ordinal] + d * w
    // Channels with hard physical ranges stay in them, whatever was layered.
    v[PoseChannel.EYELID_L.ordinal] = v[PoseChannel.EYELID_L.ordinal].coerceIn(0.0, 1.0)
    v[PoseChannel.EYELID_R.ordinal] = v[PoseChannel.EYELID_R.ordinal].coerceIn(0.0, 1.0)
    v[PoseChannel.EYE_ARC.ordinal] = v[PoseChannel.EYE_ARC.ordinal].coerceIn(-1.0, 1.0)
    v[PoseChannel.FOCUS.ordinal] = v[PoseChannel.FOCUS.ordinal].coerceIn(0.0, 1.0)
    v[PoseChannel.MOUTH_OPEN.ordinal] = v[PoseChannel.MOUTH_OPEN.ordinal].coerceIn(0.0, 1.0)
    v[PoseChannel.MOUTH_ROUND.ordinal] = v[PoseChannel.MOUTH_ROUND.ordinal].coerceIn(0.0, 1.0)
}

/**
 * Resolve a name from the harness. Unknown names are neutral: a house ahead of
 * this client names an expression it has not learned, and the face must go on
 * rather than break.
 */
fun applyNamedExpression(pose: FacePose, name: String, weight: Double) {
    val named = ExpressionName.fromWire(name) ?: return
    val e = FACE_EXPRESSIONS[named] ?: return
    applyExpression(pose, e, weight)
}
