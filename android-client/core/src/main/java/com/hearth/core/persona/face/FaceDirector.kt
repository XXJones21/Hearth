package com.hearth.core.persona.face

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

/**
 * Everything about WHEN, nothing about HOW it is drawn. Ported timing table for
 * timing table from the iOS `FaceDirector.swift`, itself a port of the desktop
 * client's `lib/face/director.ts`.
 *
 * An animation here is a looping playlist of expression presets with per-beat
 * hold times, an energy-tiered blink schedule, and perpetual micro-motion on
 * the gaze, mapped onto the four states the house already emits.
 *
 * Renderer-free by design: the Compose face ticks it once per frame and draws
 * the pose it returns. Time arrives as an argument so the director is testable
 * without a clock, which is what FaceDirectorTest exists to use.
 *
 * Composition order per tick, each layer recomputed from scratch so nothing
 * accumulates: eased playlist pose -> look target -> saccade drift -> transient
 * cue -> blink -> speech mouth.
 */

enum class FaceState { IDLE, LISTENING, THINKING, SPEAKING }

/** A transient the harness named, and when it fired (ms, same clock as tick). */
data class FaceCue(val name: String, val at: Double)

/**
 * A focal point in gaze space: x/y in [-1, 1] (right/down positive), focus
 * 0..1 nearness. The renderer's host decides where it is -- a phone points it
 * down at its own keyboard -- and the director looks there while listening.
 */
data class LookTarget(val x: Double, val y: Double, val focus: Double)

private data class Beat(val expr: FaceExpression, val ms: Double)

private data class BlinkTier(
    /** ms until the first blink after entering the state */
    val first: Double,
    /** randomized interval bounds, ms */
    val min: Double,
    val max: Double,
    /** full close-and-open time, ms */
    val duration: Double,
)

private data class FaceAnimation(val beats: List<Beat>, val blink: BlinkTier)

/** A state pose with extra deltas layered on, as one beat's target. */
private fun variant(base: ExpressionName, extra: FaceExpression): FaceExpression =
    (FACE_EXPRESSIONS[base] ?: FaceExpression()).merging(extra)

/* Timing lifted from the reference: calm states hold long beats and blink
   slowly; busy states change often and blink quickly. */
private val CALM = BlinkTier(first = 2600.0, min = 3400.0, max = 6200.0, duration = 280.0)
private val ATTENTIVE = BlinkTier(first = 3200.0, min = 4800.0, max = 7200.0, duration = 240.0)
private val BUSY = BlinkTier(first = 2100.0, min = 2800.0, max = 5000.0, duration = 260.0)

/* Theatrical register (operator's choice 2026-08-15): each state has a
   silhouette you can name from across the room, full-cartoon gaze travel, and
   thinking changes fast. */
private val ANIMATIONS: Map<FaceState, FaceAnimation> = mapOf(
    // Soft and unhurried, but never frozen: long holds, then a frank look
    // away somewhere, once with a lazy half-lid.
    FaceState.IDLE to FaceAnimation(
        beats = listOf(
            Beat(FACE_EXPRESSIONS[ExpressionName.NEUTRAL]!!, 4200.0),
            Beat(
                variant(
                    ExpressionName.NEUTRAL,
                    FaceExpression(
                        add = mapOf(
                            PoseChannel.GAZE_X to -0.85,
                            PoseChannel.GAZE_Y to 0.1,
                            PoseChannel.EYE_TILT to -0.04,
                            PoseChannel.HEAD_TILT to -0.02,
                        )
                    )
                ),
                3200.0,
            ),
            Beat(FACE_EXPRESSIONS[ExpressionName.NEUTRAL]!!, 4200.0),
            Beat(
                variant(
                    ExpressionName.NEUTRAL,
                    FaceExpression(
                        add = mapOf(
                            PoseChannel.GAZE_X to 0.7,
                            PoseChannel.EYELID_L to 0.25,
                            PoseChannel.EYELID_R to 0.25,
                            PoseChannel.HEAD_TILT to 0.02,
                        )
                    )
                ),
                2800.0,
            ),
        ),
        blink = CALM,
    ),
    // Attention, near the idle silhouette: a modest lift and a lean-in tilt;
    // the look-target does most of the telling.
    FaceState.LISTENING to FaceAnimation(
        beats = listOf(
            Beat(
                variant(
                    ExpressionName.LISTENING,
                    FaceExpression(
                        scale = mapOf(
                            PoseChannel.EYE_LENGTH to 0.18,
                            PoseChannel.EYE_SIZE to 0.06,
                        ),
                        add = mapOf(PoseChannel.HEAD_TILT to 0.05),
                    )
                ),
                2000.0,
            ),
            Beat(
                variant(
                    ExpressionName.LISTENING,
                    FaceExpression(
                        scale = mapOf(
                            PoseChannel.EYE_LENGTH to 0.22,
                            PoseChannel.EYE_SIZE to 0.08,
                        ),
                        add = mapOf(
                            PoseChannel.GAZE_Y to -0.1,
                            PoseChannel.HEAD_TILT to 0.04,
                        ),
                    )
                ),
                2000.0,
            ),
            Beat(
                variant(
                    ExpressionName.LISTENING,
                    FaceExpression(
                        scale = mapOf(
                            PoseChannel.EYE_LENGTH to 0.15,
                            PoseChannel.EYE_SIZE to 0.05,
                        ),
                        add = mapOf(
                            PoseChannel.GAZE_X to 0.15,
                            PoseChannel.EYE_RAISE_L to -0.015,
                            PoseChannel.HEAD_TILT to 0.06,
                        ),
                    )
                ),
                2000.0,
            ),
        ),
        blink = ATTENTIVE,
    ),
    // Half-height eyes thrown up and to the sides, quick asymmetric beats,
    // one flat-dash "processing" hold.
    FaceState.THINKING to FaceAnimation(
        beats = listOf(
            Beat(
                variant(
                    ExpressionName.THINKING,
                    FaceExpression(
                        scale = mapOf(PoseChannel.EYE_LENGTH to -0.15),
                        add = mapOf(
                            PoseChannel.GAZE_X to 0.9,
                            PoseChannel.GAZE_Y to -0.55,
                        ),
                    )
                ),
                1500.0,
            ),
            Beat(
                variant(
                    ExpressionName.THINKING,
                    FaceExpression(
                        add = mapOf(
                            PoseChannel.GAZE_X to -0.95,
                            PoseChannel.GAZE_Y to -0.5,
                            PoseChannel.EYE_RAISE_R to -0.03,
                            PoseChannel.HEAD_TILT to -0.04,
                        )
                    )
                ),
                1500.0,
            ),
            Beat(
                variant(
                    ExpressionName.THINKING,
                    FaceExpression(
                        add = mapOf(
                            PoseChannel.EYELID_L to 0.6,
                            PoseChannel.EYE_SCALE_R to 0.25,
                            PoseChannel.GAZE_X to 0.5,
                            PoseChannel.GAZE_Y to -0.4,
                        )
                    )
                ),
                1400.0,
            ),
            Beat(
                variant(
                    ExpressionName.THINKING,
                    FaceExpression(
                        add = mapOf(
                            PoseChannel.EYELID_L to 0.75,
                            PoseChannel.EYELID_R to 0.75,
                            PoseChannel.GAZE_X to 0.0,
                            PoseChannel.GAZE_Y to 0.0,
                        )
                    )
                ),
                1300.0,
            ),
            Beat(
                variant(
                    ExpressionName.THINKING,
                    FaceExpression(
                        add = mapOf(
                            PoseChannel.GAZE_X to -0.6,
                            PoseChannel.GAZE_Y to -0.6,
                            PoseChannel.EYE_TILT_L to 0.08,
                            PoseChannel.HEAD_TILT to 0.04,
                        )
                    )
                ),
                1500.0,
            ),
        ),
        blink = BUSY,
    ),
    // The mouth does the talking; the eyes stay engaged and mobile.
    FaceState.SPEAKING to FaceAnimation(
        beats = listOf(
            Beat(
                variant(
                    ExpressionName.SPEAKING,
                    FaceExpression(scale = mapOf(PoseChannel.EYE_SIZE to 0.1))
                ),
                1800.0,
            ),
            Beat(
                variant(
                    ExpressionName.SPEAKING,
                    FaceExpression(
                        scale = mapOf(PoseChannel.EYE_SIZE to 0.12),
                        add = mapOf(
                            PoseChannel.GAZE_X to 0.3,
                            PoseChannel.EYE_TILT to -0.03,
                            PoseChannel.HEAD_TILT to 0.02,
                        ),
                    )
                ),
                1800.0,
            ),
            Beat(
                variant(
                    ExpressionName.SPEAKING,
                    FaceExpression(
                        scale = mapOf(PoseChannel.EYE_SIZE to 0.08),
                        add = mapOf(
                            PoseChannel.GAZE_X to -0.25,
                            PoseChannel.EYE_RAISE_L to -0.015,
                            PoseChannel.HEAD_TILT to -0.02,
                        ),
                    )
                ),
                1800.0,
            ),
        ),
        blink = BUSY,
    ),
)

/** ms of eased approach toward the current beat's pose. */
private const val EASE_TAU = 140.0

/*
 * A transient is a little performance, not just a pose: each cue carries a
 * full envelope -- lerp IN over attack, hold, lerp OUT over decay -- so
 * reactions ease into the face and chain naturally instead of popping. Ramps
 * are smoothstepped. An optional motion layer (bounce, nod) rides on top; t is
 * ms since the cue fired, w the current weight.
 */
private data class TransientProfile(
    val attack: Double,
    val hold: Double,
    val decay: Double,
    val motion: ((Double, Double) -> FaceExpression)? = null,
)

private val DEFAULT_TRANSIENT = TransientProfile(attack = 140.0, hold = 260.0, decay = 950.0)

private val TRANSIENTS: Map<String, TransientProfile> = mapOf(
    // A physical chuckle: the whole face bounces fast and small while the
    // happy arcs hold, like laughter shaking through the body.
    "laughter" to TransientProfile(120.0, 1600.0, 650.0) { t, w ->
        FaceExpression(
            add = mapOf(
                PoseChannel.HEAD_BOB to sin((t / 135) * PI * 2) * 0.04 * w,
                PoseChannel.HEAD_TILT to sin((t / 270) * PI * 2) * 0.018 * w,
            )
        )
    },
    // The yes-nod: two slow downward bobs under the contented arc-squint.
    "confirmation" to TransientProfile(150.0, 1250.0, 500.0) { t, w ->
        FaceExpression(
            add = mapOf(
                PoseChannel.HEAD_BOB to ((1 - cos((t / 620) * PI * 2)) / 2) * 0.11 * w
            )
        )
    },
    // A sigh settles in slowly and takes its time leaving.
    "sigh" to TransientProfile(400.0, 900.0, 1100.0),
    // The startle: eyes lerp wide, hold a beat, lerp back.
    "surprise" to TransientProfile(150.0, 700.0, 450.0),
    // A deliberate blink at REAL blink speed. Not a name the harness sends;
    // ambient blinks come from the state tier's schedule. The entry exists so
    // a test-bench blink chip does not fall through to the default envelope
    // and play a ~1.35s eyes-closed performance.
    "blink" to TransientProfile(110.0, 40.0, 140.0),
)

/**
 * Smoothstepped 0..1 envelope for a transient's age. Negative age is a cue
 * stamped between frames (or a backwards clock) -- weight zero, because the
 * smoothstep is positive for negative inputs and would pre-fire the reaction.
 */
private fun transientWeight(age: Double, p: TransientProfile): Double {
    if (age < 0) return 0.0
    val w: Double = when {
        age <= p.attack -> if (p.attack > 0) age / p.attack else 1.0
        age <= p.attack + p.hold -> 1.0
        else -> maxOf(0.0, 1 - (age - p.attack - p.hold) / p.decay)
    }
    return w * w * (3 - 2 * w)
}

/** Quick close, slower open; null when the blink is over. */
private fun blinkWeight(sinceStart: Double, duration: Double): Double? {
    if (sinceStart < 0) return null
    val close = duration * 0.42
    if (sinceStart < close) return sinceStart / close
    if (sinceStart < duration) return 1 - (sinceStart - close) / (duration - close)
    return null
}

/** Micro-saccades: small, quick, irregular. The gaze never sits dead. */
private const val SACCADE_MIN_MS = 900.0
private const val SACCADE_MAX_MS = 2600.0
private const val SACCADE_AMP_X = 0.18
private const val SACCADE_AMP_Y = 0.1

/** A slow breathing sway on the whole head. Radians of head tilt, sinusoidal. */
private const val SWAY_AMP = 0.014
private const val SWAY_PERIOD_MS = 5200.0

/**
 * Touched only from the render loop, one tick at a time.
 *
 * @param random injectable so tests can pin saccade and blink scheduling.
 */
class FaceDirector(
    private val geometry: FaceGeometry,
    now: Double,
    private val random: Random = Random.Default,
) {
    private var pose: FacePose = neutralPose(geometry)
    private var state: FaceState = FaceState.IDLE
    private var beatIndex = 0
    private var beatStartedAt: Double = now
    private var blinkStartedAt: Double = -1.0
    private var nextBlinkAt: Double = now + (ANIMATIONS[FaceState.IDLE]?.blink?.first ?: CALM.first)

    /**
     * The tier duration CAPTURED when the blink started, so a state change
     * mid-blink cannot re-measure a half-closed lid against a shorter tier and
     * snap it open in one frame.
     */
    private var blinkDuration: Double = CALM.duration
    private var saccadeX = 0.0
    private var saccadeY = 0.0
    private var nextSaccadeAt: Double = now + SACCADE_MIN_MS
    private var last: Double = now

    /**
     * One frame. Layers are recomputed every tick; only the eased base pose
     * carries over between frames.
     */
    fun tick(
        now: Double,
        state: FaceState,
        cue: FaceCue?,
        speechLevel: Double,
        reduceMotion: Boolean,
        lookTarget: LookTarget? = null,
    ): FacePose {
        // Clamped BOTH ways: a backwards wall-clock adjustment makes dt
        // negative, which drives every channel AWAY from target, and a large
        // jump overflows exp() into a NaN pose nothing ever clears.
        val dt = (now - last).coerceIn(0.0, 100.0)
        last = now

        val anim = ANIMATIONS[state] ?: return pose
        if (state != this.state) {
            // Entering a state restarts its playlist. The blink COUNTDOWN
            // carries across, only re-tiered: a full re-arm meant any
            // conversation cycling states faster than the tier's `first`
            // never blinked at all. An in-flight blink keeps its captured
            // duration and simply finishes.
            this.state = state
            beatIndex = 0
            beatStartedAt = now
            nextBlinkAt = minOf(nextBlinkAt, now + anim.blink.first)
        }

        // Advance the playlist.
        val beat = anim.beats[beatIndex % anim.beats.size]
        if (now - beatStartedAt >= beat.ms) {
            beatIndex = (beatIndex + 1) % anim.beats.size
            beatStartedAt = now
        }
        val target = applyExpression(neutralPose(geometry), anim.beats[beatIndex].expr, 1.0)

        // Ease every channel toward the beat's pose. Reduce motion snaps.
        val alpha = if (reduceMotion) 1.0 else 1 - exp(-dt / EASE_TAU)
        val eased = pose.values.toMutableMap()
        for (channel in PoseChannel.entries) {
            val current = pose[channel]
            eased[channel] = current + (target[channel] - current) * alpha
        }
        pose = FacePose(eased)

        var frame = pose

        // While listening, the face watches where the words are coming from,
        // converged near. Saccades still ride on top, so the watch stays alive.
        if (state == FaceState.LISTENING && lookTarget != null) {
            frame = applyExpression(
                frame,
                FaceExpression(
                    add = mapOf(
                        PoseChannel.GAZE_X to (lookTarget.x - frame.gazeX) * 0.85,
                        PoseChannel.GAZE_Y to (lookTarget.y - frame.gazeY) * 0.85,
                        PoseChannel.FOCUS to (lookTarget.focus - frame.focus) * 0.85,
                    )
                ),
                1.0,
            )
        }

        // Micro-saccades: the gaze jumps a little at irregular intervals, and
        // the easing above is what makes the jump read as a dart, not a snap.
        if (!reduceMotion) {
            if (now >= nextSaccadeAt) {
                saccadeX = (random.nextDouble() * 2 - 1) * SACCADE_AMP_X
                saccadeY = (random.nextDouble() * 2 - 1) * SACCADE_AMP_Y
                nextSaccadeAt =
                    now + SACCADE_MIN_MS + random.nextDouble() * (SACCADE_MAX_MS - SACCADE_MIN_MS)
            }
            frame = applyExpression(
                frame,
                FaceExpression(
                    add = mapOf(
                        PoseChannel.GAZE_X to saccadeX,
                        PoseChannel.GAZE_Y to saccadeY,
                    )
                ),
                1.0,
            )
            // Breathing sway: continuous, slow, never still.
            frame = applyExpression(
                frame,
                FaceExpression(
                    add = mapOf(
                        PoseChannel.HEAD_TILT to sin((now * 2 * PI) / SWAY_PERIOD_MS) * SWAY_AMP
                    )
                ),
                1.0,
            )
        }

        // The harness's transient cue: full weight through its hold, then a
        // decay -- with the cue's own motion envelope riding on top.
        if (cue != null) {
            val age = now - cue.at
            val profile = TRANSIENTS[cue.name] ?: DEFAULT_TRANSIENT
            val weight = transientWeight(age, profile)
            if (weight > 0) {
                frame = applyNamedExpression(frame, cue.name, weight)
                val motion = profile.motion
                if (motion != null && !reduceMotion) {
                    frame = applyExpression(frame, motion(age, weight), 1.0)
                }
            }
        }

        // Blink, on the state's energy tier. Suppressed under reduce motion;
        // lids still move with expressions that close them.
        if (!reduceMotion) {
            if (blinkStartedAt < 0 && now >= nextBlinkAt) {
                blinkStartedAt = now
                blinkDuration = anim.blink.duration
            }
            if (blinkStartedAt >= 0) {
                val w = blinkWeight(now - blinkStartedAt, blinkDuration)
                if (w != null) {
                    frame = applyExpression(frame, FACE_EXPRESSIONS[ExpressionName.BLINK]!!, w)
                } else {
                    blinkStartedAt = -1.0
                    nextBlinkAt = now + anim.blink.min +
                        random.nextDouble() * (anim.blink.max - anim.blink.min)
                }
            }
        }

        // The mouth follows the sound itself, not the state -- and a talking
        // mouth is a clean round oval whose height rides the amplitude.
        if (speechLevel > 0.01) {
            frame = applyExpression(
                frame,
                FaceExpression(
                    add = mapOf(
                        PoseChannel.MOUTH_OPEN to speechLevel,
                        PoseChannel.MOUTH_ROUND to 1.0,
                    )
                ),
                1.0,
            )
        }

        return frame
    }
}
