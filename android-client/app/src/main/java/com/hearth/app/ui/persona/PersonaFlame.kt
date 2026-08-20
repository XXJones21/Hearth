package com.hearth.app.ui.persona

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import com.hearth.core.models.HearthState
import com.hearth.core.persona.FlameProfile

/**
 * Sulivan's fire, drawn with vector primitives -- no shader, no 3D. Ported
 * from the iOS `PersonaFlameCanvas.swift`.
 *
 * THE PRECEDENT IS THE ORB: a radial gradient for the halo, filled circles for
 * the particles, a gradient for the body. Nobody looking at the phone and the
 * headset thinks the bead is two characters. The bar here is the same -- the
 * same character, not the same pixels -- and what carries it is the shape, the
 * palette and the motion, all three of which port exactly.
 *
 * WHAT IT GIVES UP, stated so nobody chases it: the headset's fire gets its
 * fine grain from a five-octave domain-warped fbm evaluated per pixel. Broad
 * strokes give broad structure. Colour bands are level here where a computed
 * flame's wander. There is no parallax between the near and far walls of the
 * flame, because there are no walls. See `wiki/raw/persona-flame-spec.md`.
 *
 * ONE CLOCK THROUGH EVERY LAYER. Seven effects on seven clocks are seven
 * effects near each other; seven on one clock are one fire.
 */
@Composable
fun PersonaFlame(
    state: HearthState,
    /** TTS amplitude 0..1 while speaking, mic level while listening. */
    pulse: Float = 0f,
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    // A CANVAS DOES NOT ANIMATE ITSELF, and this is the one bug every canvas
    // port hits. If the clock is read where the drawing is CONSTRUCTED rather
    // than supplied by a per-frame timer, the flame moves only when something
    // else happens to invalidate the composable: stationary, then a lurch. On
    // iOS the answer is a TimelineView; here it is the frame clock, the same
    // one PersonaFace already runs on.
    //
    // Note also, before measuring anything: a frame-rate readout with its own
    // clock will report the display refresh whatever the drawing beside it is
    // doing. The iOS one confidently said 60fps for a completely frozen flame.
    // Judge motion by eye.
    val clock = remember { FlameClock() }
    var frameTick by remember { mutableIntStateOf(0) }

    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            clock.phase = 0.0
            frameTick++
            return@LaunchedEffect
        }
        while (true) {
            withFrameMillis { ms ->
                if (clock.origin == 0L) clock.origin = ms
                // Seconds since the first frame. The absolute origin does not
                // matter -- every term is a sine of the phase -- and starting
                // near zero keeps the doubles small.
                clock.phase = (ms - clock.origin) / 1000.0
                frameTick++
            }
        }
    }

    // The inputs the draw reads, held rather than closed over, so a changing
    // amplitude does not restart anything.
    val inputs = remember { FlameInputs() }
    inputs.state = state
    inputs.pulse = pulse.toDouble()
    inputs.reduceMotion = reduceMotion

    Canvas(modifier = modifier) {
        @Suppress("UNUSED_EXPRESSION")
        frameTick
        drawFlame(clock.phase, inputs)
    }
}

/** The frame clock's own state, mutated outside recomposition. */
private class FlameClock {
    var origin: Long = 0
    var phase: Double = 0.0
}

private class FlameInputs {
    var state: HearthState = HearthState.IDLE
    var pulse: Double = 0.0
    var reduceMotion: Boolean = false
}

// ---- the palette ---------------------------------------------------------
// The five colour stops, straight from the headset's `fire_kernel`. Copied
// exactly: the spec is explicit that these and their positions are not
// platform-specific.
//
// Yellow where the flame is fed, red where it is spending itself. The
// near-white heart this started with claimed too much of the height and left
// the body looking bleached.

internal val FlameStraw = Color(1.00f, 0.88f, 0.42f)
internal val FlameGold = Color(1.00f, 0.66f, 0.18f)
internal val FlameAmber = Color(1.00f, 0.38f, 0.07f)
internal val FlameRed = Color(0.86f, 0.13f, 0.04f)
internal val FlameAsh = Color(0.45f, 0.06f, 0.03f)

/**
 * The stop POSITIONS are the kernel's `heat` thresholds. What a gradient
 * cannot do is the kernel's noise perturbation of them, which is why a drawn
 * flame's colour boundaries are level where a computed one's wander. That is
 * the largest single visual difference between the two implementations and it
 * is acceptable.
 */
private val RAMP = arrayOf(
    0.00f to FlameStraw,
    0.28f to FlameGold,
    0.58f to FlameAmber,
    0.85f to FlameRed,
    1.00f to FlameAsh,
)

/** Forty points a side is plenty for the silhouette. */
private const val RINGS = 40

private fun DrawScope.drawFlame(phase: Double, inputs: FlameInputs) {
    val field = minOf(size.width, size.height).toDouble()

    // Proportioned like the headset's: the flame is 1.05 of the bead's radius
    // wide and 3.4 of it tall, so width and height stay in the same ratio to
    // each other whatever this view is given.
    val unit = field * 0.155
    val flame = FlameProfile(radius = unit * 1.05, height = unit * 3.4)
    if (inputs.reduceMotion) {
        flame.turbulence = 0.0
        flame.sway = 0.0
    }

    val cx = size.width / 2.0
    // Sit the flame's base a little below centre so the taper has room.
    val baseY = size.height / 2.0 + flame.height * 0.42

    // THE HALO, and it is here on purpose. The headset switches its painted
    // glow OFF when the lantern lights, because a real light doing real work on
    // real walls does that job better. A screen has no walls, so nothing does
    // that job -- and without the halo the fire reads flatter than the orb it
    // replaces. It is the compensation for the one thing this port LOSES
    // rather than saves: the flicker on the room.
    val flicker = if (inputs.reduceMotion) 0.5 else FlameProfile.flicker(phase)
    val haloR = flame.radius * 4.2
    val haloCenter = Offset(cx.toFloat(), (baseY - flame.height * 0.55).toFloat())
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                FlameAmber.copy(alpha = (0.30 + 0.16 * flicker).toFloat()),
                FlameAmber.copy(alpha = 0f),
            ),
            center = haloCenter,
            radius = haloR.toFloat(),
        ),
        radius = haloR.toFloat(),
        center = haloCenter,
    )

    val body = outline(flame, phase, cx, baseY)
    val sink = flame.radius * FlameProfile.DOME_DEPTH
    fun heightOf(v: Double) = (baseY - (flame.rise(v) + sink)).toFloat()

    // THE BODY, THE LICKS AND THE FEATHER GO IN ONE LAYER, because the feather
    // ERASES and an erase has to be bounded. Drawn straight onto the canvas it
    // would take the halo with it and leave a hole in the glow where the tip
    // should be.
    drawIntoCanvas { canvas ->
        canvas.saveLayer(Rect(Offset.Zero, size), Paint())

        // THE BODY. One closed path from the same arithmetic the mesh uses,
        // walked up the right meridian and back down the left. Angle 0 and
        // angle pi are where a surface of revolution's outline lives, so these
        // two edges are the headset's silhouette EXACTLY -- and they wobble
        // independently, because the noise is per-meridian. A body that is
        // round from every angle reads as a vase, not a fire.
        drawPath(
            path = body,
            brush = Brush.linearGradient(
                colorStops = RAMP,
                start = Offset(cx.toFloat(), baseY.toFloat()),
                end = Offset(cx.toFloat(), (baseY - flame.height).toFloat()),
            ),
        )

        // THE LICKS. What the shader gets from a five-octave domain-warped fbm
        // evaluated per pixel, a handful of narrower flames give in outline:
        // each is the same profile at a fraction of the width, shifted along
        // its own meridian so it leans differently, drawn lighter.
        //
        // THREE, and the number is the finding. Three reads as structure; more
        // turns the body back into a wash.
        clipPath(body) {
            for (i in 0 until 3) {
                val seed = i * 2.4 + 1.1
                val inner = flame.copy(
                    radius = flame.radius * (0.30 + 0.12 * i),
                    height = flame.height * (0.72 + 0.08 * i),
                )
                val offset =
                    FlameProfile.noise(seed, 0.7, phase * 0.6) * flame.radius * 0.42
                drawPath(
                    path = outline(inner, phase + seed, cx + offset, baseY),
                    brush = Brush.linearGradient(
                        colorStops = arrayOf(
                            0.00f to FlameStraw.copy(alpha = 0.55f),
                            0.55f to FlameGold.copy(alpha = 0.16f),
                            1.00f to FlameGold.copy(alpha = 0f),
                        ),
                        start = Offset(cx.toFloat(), baseY.toFloat()),
                        end = Offset(cx.toFloat(), (baseY - inner.height).toFloat()),
                    ),
                )
            }
        }

        // THE TIP FEATHER, and it is not decoration. The profile puts ALL its
        // narrowing in the last five per cent of the height -- still 59% wide
        // at v=0.88 -- so the raw geometry is an egg with a spike on it, which
        // is exactly how it read on the headset before this. A point is the one
        // shape a flame never has.
        //
        // The same window the kernel uses, 0.88 to 0.99. Three per cent of the
        // height is a cut rather than a feather.
        //
        // DstOut subtracts alpha, which is the clean version of what iOS has to
        // fake -- a SwiftUI Canvas cannot take alpha back out of a fill it has
        // already made, so it washes the tip toward ash instead. Here the tip
        // genuinely goes to nothing and the halo shows through it.
        val fadeTop = heightOf(FlameProfile.FADE_END)
        val fadeBottom = heightOf(FlameProfile.FADE_START)
        val overshoot = (flame.height * 0.1).toFloat()
        drawRect(
            brush = Brush.linearGradient(
                colors = listOf(Color.Black, Color.Transparent),
                start = Offset(cx.toFloat(), fadeTop - overshoot),
                end = Offset(cx.toFloat(), fadeBottom),
            ),
            topLeft = Offset(0f, 0f),
            size = androidx.compose.ui.geometry.Size(size.width, fadeBottom),
            blendMode = BlendMode.DstOut,
        )

        canvas.restore()
    }
}

/** One closed path: up the right meridian, back down the left. */
private fun outline(
    flame: FlameProfile,
    phase: Double,
    cx: Double,
    baseY: Double,
): Path {
    val sink = flame.radius * FlameProfile.DOME_DEPTH
    val path = Path()

    fun x(v: Double, angle: Double): Float {
        val r = flame.surface(v, angle, phase)
        return (cx + (if (angle == 0.0) r else -r) + flame.lean(v, phase)).toFloat()
    }

    fun y(v: Double): Float = (baseY - (flame.rise(v) + sink)).toFloat()

    path.moveTo(x(0.0, 0.0), y(0.0))
    for (i in 1..RINGS) {
        val v = i.toDouble() / RINGS
        path.lineTo(x(v, 0.0), y(v))
    }
    for (i in RINGS downTo 0) {
        val v = i.toDouble() / RINGS
        path.lineTo(x(v, Math.PI), y(v))
    }
    path.close()
    return path
}
