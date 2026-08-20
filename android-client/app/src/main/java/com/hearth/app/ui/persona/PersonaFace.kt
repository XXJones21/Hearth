package com.hearth.app.ui.persona

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.translate
import com.hearth.core.models.HearthState
import com.hearth.core.persona.PersonaPalette
import com.hearth.core.persona.Rgb
import com.hearth.core.persona.Scene
import com.hearth.core.persona.face.FaceCue
import com.hearth.core.persona.face.FaceDirector
import com.hearth.core.persona.face.FaceGeometry
import com.hearth.core.persona.face.FacePose
import com.hearth.core.persona.face.FaceState
import com.hearth.core.persona.face.LookTarget
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * The face, drawn. Ported from the iOS `PersonaFaceView.swift`, which is
 * itself a port of the desktop's `geometry.ts` plus `PersonaFace.tsx`.
 *
 * All BEHAVIOUR -- playlists, blink, saccades, transients, the amplitude
 * mouth -- lives in [FaceDirector] in `core`. This file's whole job is
 * ticking it and turning one pose into paths, which is why nothing here is
 * per-frame state pushed through recomposition: a sixty-per-second mouth must
 * not drive Compose's diff. [withFrameMillis] gives the tick, and the Canvas
 * reads the pose that came back.
 *
 * Shape choices (the eyes-first register):
 *   head   a squircle: four cubics whose handle length morphs with roundness
 *          (0.5523 draws a circle; shorter handles go boxy)
 *   eyes   two vertical capsules; the whole character lives here. A closing
 *          lid collapses the capsule at its own width, so a closed eye reads
 *          as a stubby DASH rather than a missing element
 *   brows  none. Deliberate: brows are where an abstract face starts looking
 *          like a judging human
 *   mouth  hidden at rest, fading in with whatever opens it
 */
@Composable
fun PersonaFace(
    geometry: FaceGeometry,
    state: HearthState,
    palette: PersonaPalette = PersonaPalette.fallback,
    speechLevel: Float = 0f,
    cue: Pair<String, Long>? = null,
    composerUp: Boolean = false,
    reduceMotion: Boolean = false,
    /**
     * Whether to paint the head under the features. True is the persona as
     * this has always drawn it: a filled squircle with eyes on it.
     *
     * FALSE IS FOR A FACE WORN BY SOMETHING ELSE. The headset draws Sulivan as
     * a flame and puts his eyes on it, and what makes that work is that its
     * face texture is mostly TRANSPARENT, with ink only where the features
     * are. This is not: composited over a fire with the head on, it drew a
     * solid cream squircle in front of the flame -- a persona standing in
     * front of a fire rather than a fire with a face.
     *
     * The features are unchanged either way, so a persona wearing a body
     * blinks exactly as it does wearing a head.
     */
    drawsHead: Boolean = true,
    modifier: Modifier = Modifier,
) {
    // Rebuilt only when the geometry changes: the director is a live thing
    // with a clock of its own, not a value to recreate per frame.
    val director = remember(geometry) { FaceDirector(geometry, now = nowMs()) }

    // The loop reads its inputs from here rather than being KEYED on them.
    // Keying meant the coroutine was cancelled and restarted on every change
    // of speechLevel, which changes continuously while the house talks.
    val inputs = remember { FaceInputs() }
    inputs.state = faceStateFor(state, composerUp)
    inputs.speechLevel = speechLevel.toDouble()
    inputs.reduceMotion = reduceMotion
    inputs.composerUp = composerUp
    if (cue != null && cue.second != inputs.cueStamp) {
        inputs.cueStamp = cue.second
        inputs.cue = FaceCue(cue.first, cue.second.toDouble())
    }

    // One pose instance, mutated by the director and read by the Canvas. The
    // frame counter is what recomposes: an Int changing is cheap where a new
    // 27-channel object every frame is not.
    val pose = remember { FacePose() }
    var frameTick by remember { mutableIntStateOf(0) }

    // Starts ONCE and runs for the life of the composable.
    LaunchedEffect(director) {
        while (true) {
            withFrameMillis {
                pose.setFrom(
                    director.tick(
                        now = nowMs(),
                        state = inputs.state,
                        cue = inputs.cue,
                        speechLevel = inputs.speechLevel,
                        reduceMotion = inputs.reduceMotion,
                        lookTarget = if (inputs.composerUp) KEYBOARD_TARGET else null,
                    )
                )
                frameTick++
            }
        }
    }

    Canvas(modifier = modifier) {
        // Read the counter so the draw is tied to the frame clock; the pose
        // itself is mutable and Compose cannot see into it.
        @Suppress("UNUSED_EXPRESSION")
        frameTick
        drawFace(pose, palette, state, size, drawsHead)
    }
}

/**
 * What the frame loop reads. A holder rather than loop keys, so the
 * coroutine starts once instead of restarting sixty times a second.
 */
private class FaceInputs {
    var state: FaceState = FaceState.IDLE
    var speechLevel: Double = 0.0
    var reduceMotion: Boolean = false
    var composerUp: Boolean = false
    var cue: FaceCue? = null
    var cueStamp: Long = 0
}

private fun nowMs(): Double = System.currentTimeMillis().toDouble()

/**
 * Where the face looks while the composer is up. iOS measures the composer's
 * real frame against the face's; a phone's composer is always below the face,
 * so the constant says the same thing without the geometry plumbing.
 */
private val KEYBOARD_TARGET = LookTarget(x = 0.0, y = 0.9, focus = 0.5)

/**
 * The face's own reading of the turn.
 *
 * The composer being up counts as listening even though the state only says
 * LISTENING while the microphone is live. But it only outranks IDLE: someone
 * typing a follow-up mid-reply must not cost the thinking and speaking beats.
 * LOADING idles, because a face that has not heard anything yet is idle.
 */
internal fun faceStateFor(state: HearthState, composerUp: Boolean): FaceState = when (state) {
    HearthState.LISTENING -> FaceState.LISTENING
    HearthState.THINKING -> FaceState.THINKING
    HearthState.SPEAKING -> FaceState.SPEAKING
    HearthState.IDLE, HearthState.LOADING ->
        if (composerUp) FaceState.LISTENING else FaceState.IDLE
}

// ---- colours -------------------------------------------------------------
// The ink leans toward the active state's colour so the state is legible in
// peripheral vision, over a parchment head. Same wash as iOS, same palette.

private fun Rgb.toColor() = Color(r, g, b, 1f)

private fun DrawScope.drawFace(
    pose: FacePose,
    palette: PersonaPalette,
    state: HearthState,
    size: Size,
    drawsHead: Boolean,
) {
    val glow = palette.glow(state)
    // FLAT BLACK WHEN THERE IS NO HEAD, and it is a contrast decision rather
    // than a stylistic one. On a cream head the warm brown belongs to the same
    // palette family as everything around it, which is what makes the face
    // read as drawn rather than stuck on. On a FLAME the background is bright
    // saturated gold, and a brown that was two steps from cream is barely one
    // step from fire -- the eyes wash out exactly where the body is brightest,
    // which is where they sit. The headset's face kernel draws flat black on
    // the flame for the same reason.
    val ink = if (drawsHead) glow.mix(Scene.roast, 0.62f).toColor() else Color.Black
    val rim = glow.mix(Scene.roast, 0.38f).toColor()
    val headFill = glow.mix(Scene.cream, 0.84f).toColor()
    val glint = Scene.honey.mix(Scene.fluff, 0.75f).toColor()

    val side = min(size.width, size.height)
    val cx = size.width / 2
    val cy = size.height / 2
    // The head's half-extents. 0.38 leaves air for head tilt.
    val hw = side * 0.38f * pose.headWidth.toFloat()
    val hh = side * 0.38f * pose.headHeight.toFloat()

    // Whole-face transform: the bob lifts, then the tilt leans about centre.
    translate(top = (pose.headBob * hh).toFloat()) {
        rotateRad(pose.headTilt.toFloat(), pivot = Offset(cx, cy)) {

            if (drawsHead) {
                val head = squircle(cx, cy, hw, hh, pose.headRoundness.toFloat())
                drawPath(head, headFill)
                drawPath(head, rim, style = Stroke(width = max(1f, side * 0.015f)))
            }

            // Eyes: vertical capsules, each with its own lid, size, lean and
            // lift -- matched eyes read as a machine, mismatched as a creature.
            val eyeY = cy - hh + pose.eyeHeight.toFloat() * (2 * hh)
            val eyeDx = pose.eyeSpacing.toFloat() * hw
            val baseHalfW = pose.eyeSize.toFloat() * hw

            // Theatrical gaze travel, clamped so the eyes never cross the
            // head's outline at the height they sit at.
            val dyEye = min(0.95f, abs(cy - eyeY) / hh)
            val halfWidthAtEye = hw * sqrt(max(0.05f, 1 - dyEye * dyEye))
            val gxMax = max(0f, halfWidthAtEye - eyeDx - baseHalfW * 1.6f)
            val gx = (pose.gazeX.toFloat() * hw * 0.45f).coerceIn(-gxMax, gxMax)
            val gy = pose.gazeY.toFloat() * hh * 0.3f
            val arc = pose.eyeArc.toFloat().coerceIn(-1f, 1f)

            // Vergence: focus pulls both eyes toward a shared near point, so a
            // focused face converges instead of staring past you.
            val converge = pose.focus.toFloat() * baseHalfW * 0.55f
            val leftC = Offset(
                cx - eyeDx + gx + converge,
                eyeY + gy + pose.eyeRaiseL.toFloat() * (2 * hh),
            )
            val rightC = Offset(
                cx + eyeDx + gx - converge,
                eyeY + gy + pose.eyeRaiseR.toFloat() * (2 * hh),
            )

            val maxLid = max(pose.eyelidL, pose.eyelidR).toFloat()
            val glintR = baseHalfW * 0.3f
            val glintDx = -baseHalfW * 0.28f + pose.gazeX.toFloat() * baseHalfW * 0.35f
            val glintDy = -baseHalfW * max(0.2f, pose.eyeLength.toFloat()) * 0.42f +
                pose.gazeY.toFloat() * baseHalfW * 0.3f
            val glintAlpha = max(0f, 1 - maxLid * 2)

            for ((center, lid, scale, ownTilt) in listOf(
                Quad(leftC, pose.eyelidL, pose.eyeScaleL, pose.eyeTiltL),
                Quad(rightC, pose.eyelidR, pose.eyeScaleR, pose.eyeTiltR),
            )) {
                // Each capsule leans about its own centre.
                rotateRad((pose.eyeTilt + ownTilt).toFloat(), pivot = center) {
                    drawPath(
                        eyeShape(
                            center, lid.toFloat(), scale.toFloat(), arc,
                            baseHalfW, pose.eyeLength.toFloat(),
                        ),
                        ink,
                    )
                    if (glintAlpha > 0) {
                        drawPath(
                            capsule(center.x + glintDx, center.y + glintDy, glintR, glintR),
                            glint,
                            alpha = glintAlpha,
                        )
                    }
                }
            }

            // Mouth: hidden at rest, and the two shapes CROSSFADE rather than
            // morph -- a crescent that had to become an "o" path-by-path was
            // how the first cut ended up looking like a beak.
            val visibility = min(1f, pose.mouthOpen.toFloat() * 4)
            if (visibility <= 0f) return@rotateRad

            val mouthY = cy + hh * 0.42f
            val mouthHalf = pose.mouthWidth.toFloat() * hw
            // Positive mouthCurve pushes the crescent's belly DOWN on screen.
            val curve = pose.mouthCurve.toFloat() * hh * 0.5f
            val thickness = max(side * 0.008f, pose.mouthThickness.toFloat() * 2 * hh)
            val open = pose.mouthOpen.toFloat() * hh * 0.42f

            val crescentAlpha = visibility * (1 - pose.mouthRound.toFloat())
            if (crescentAlpha > 0) {
                val crescent = Path().apply {
                    moveTo(cx - mouthHalf, mouthY)
                    quadraticBezierTo(cx, mouthY + curve, cx + mouthHalf, mouthY)
                    quadraticBezierTo(
                        cx, mouthY + curve + thickness + open, cx - mouthHalf, mouthY,
                    )
                    close()
                }
                drawPath(crescent, ink, alpha = crescentAlpha)
            }

            val roundAlpha = visibility * pose.mouthRound.toFloat()
            if (roundAlpha > 0) {
                val roundH = max(1.5f, (thickness + open) * 0.55f)
                val roundW = mouthHalf * 0.5f
                drawPath(
                    capsule(cx, mouthY + roundH * 0.25f, roundW, roundH),
                    ink,
                    alpha = roundAlpha,
                )
            }
        }
    }
}

/** Destructurable eye tuple; Kotlin's Pair only carries two. */
private data class Quad(
    val center: Offset,
    val lid: Double,
    val scale: Double,
    val tilt: Double,
)

/**
 * One eye: a capsule, or -- once a lid closes over an arc -- the happy `^` or
 * pensive droop band.
 */
private fun eyeShape(
    center: Offset,
    lid: Float,
    scale: Float,
    arc: Float,
    baseHalfW: Float,
    eyeLength: Float,
): Path {
    val l = min(1f, lid)
    val s = max(0.2f, scale)
    val halfW = baseHalfW * s
    val closedness = l * abs(arc)
    if (closedness > 0.35f) {
        // A thick band bowing UP for joy or DOWN for the droop, scaled by how
        // closed the lid is so it eases in rather than popping.
        val sign = if (arc < 0) -1f else 1f
        val w = halfW * 1.45f
        val lift = halfW * 1.5f * l * sign
        val band = max(2f, halfW * 0.62f)
        val endY = center.y + band * 0.4f * sign
        return Path().apply {
            moveTo(center.x - w, endY)
            quadraticBezierTo(center.x, center.y - lift, center.x + w, endY)
            quadraticBezierTo(center.x, center.y - lift + band, center.x - w, endY)
            close()
        }
    }
    // Neutral close: the capsule collapses to a thick stubby bar at its own
    // width -- never a spindly hyphen, which mid-blink reads as a render bug.
    val halfH = max(halfW * 0.55f, halfW * max(0.2f, eyeLength) * (1 - l * 0.95f))
    return capsule(center.x, center.y, halfW, halfH)
}

/** Rounded rect that degrades to a capsule in either orientation. */
private fun capsule(cx: Float, cy: Float, halfW: Float, halfH: Float): Path {
    val w = max(0.5f, halfW)
    val h = max(0.5f, halfH)
    val r = min(w, h)
    return Path().apply {
        addRoundRect(
            androidx.compose.ui.geometry.RoundRect(
                Rect(cx - w, cy - h, cx + w, cy + h),
                androidx.compose.ui.geometry.CornerRadius(r, r),
            )
        )
    }
}

/** Squircle: four cubics, handle length morphing circle to rounded box. */
private fun squircle(cx: Float, cy: Float, rx: Float, ry: Float, roundness: Float): Path {
    val t = roundness.coerceIn(0f, 1f)
    // 0.5523 is the magic circle constant; 0.30 reads as a soft rectangle.
    val k = 0.3f + (0.5523f - 0.3f) * t
    val kx = rx * (1 - k)
    val ky = ry * (1 - k)
    return Path().apply {
        moveTo(cx, cy - ry)
        cubicTo(cx + rx - kx, cy - ry, cx + rx, cy - ry + ky, cx + rx, cy)
        cubicTo(cx + rx, cy + ry - ky, cx + rx - kx, cy + ry, cx, cy + ry)
        cubicTo(cx - rx + kx, cy + ry, cx - rx, cy + ry - ky, cx - rx, cy)
        cubicTo(cx - rx, cy - ry + ky, cx - rx + kx, cy - ry, cx, cy - ry)
        close()
    }
}
