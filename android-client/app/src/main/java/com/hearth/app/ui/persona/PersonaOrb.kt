package com.hearth.app.ui.persona

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import com.hearth.core.models.HearthState
import com.hearth.core.persona.PersonaParticle
import com.hearth.core.persona.PersonaPalette
import com.hearth.core.persona.Rgb
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The `sphere_particle` persona: a bead in a field of orbiting dots. Ported
 * from the iOS `PersonaOrb` and `PersonaCanvasView`, which came from Echo's
 * `PersonaCanvas.kt`.
 *
 * THIS IS THE DEFAULT APPEARANCE, and it is what everything else falls back
 * to: a model persona whose asset has not arrived, a face whose geometry has
 * not, a persona the house knows nothing about yet. Android's fallback used to
 * be a flat filled circle, which is indistinguishable from a rendering failure.
 *
 * The field is choreographed rather than simulated, which is what lets it ease
 * from an orbit into a speaking waveform: at rest the dots ride elliptical
 * rings, and while SPEAKING they lay themselves out left to right along a sine
 * whose amplitude is the voice. The blend between the two is animated over a
 * third of a second so the change reads as a transition rather than a cut.
 */
@Composable
fun PersonaOrb(
    state: HearthState,
    /** TTS amplitude 0..1; drives the speaking waveform. */
    pulse: Float = 0f,
    palette: PersonaPalette = PersonaPalette.fallback,
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    // Same frame clock as the flame, for the same reason: a Canvas does not
    // animate itself.
    val clock = remember { OrbClock() }
    var frameTick by remember { mutableIntStateOf(0) }

    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            clock.elapsed = 0.0
            frameTick++
            return@LaunchedEffect
        }
        while (true) {
            withFrameMillis { ms ->
                if (clock.origin == 0L) clock.origin = ms
                clock.elapsed = (ms - clock.origin) / 1000.0
                frameTick++
            }
        }
    }

    // The one value that is NOT on the frame clock: how far the field has
    // travelled from orbit toward waveform. It is a transition between two
    // layouts rather than a continuous motion, so it gets a real animation.
    val waveBlend by animateFloatAsState(
        targetValue = if (state == HearthState.SPEAKING && !reduceMotion) 1f else 0f,
        animationSpec = tween(durationMillis = 320),
        label = "waveBlend",
    )

    val field = remember { PersonaParticle.field() }
    val inputs = remember { OrbInputs() }
    inputs.state = state
    inputs.pulse = pulse.toDouble()
    inputs.reduceMotion = reduceMotion
    inputs.palette = palette
    inputs.waveBlend = waveBlend.toDouble()

    Canvas(modifier = modifier) {
        @Suppress("UNUSED_EXPRESSION")
        frameTick
        drawOrb(clock.elapsed, field, inputs)
    }
}

private class OrbClock {
    var origin: Long = 0
    var elapsed: Double = 0.0
}

private class OrbInputs {
    var state: HearthState = HearthState.IDLE
    var pulse: Double = 0.0
    var reduceMotion: Boolean = false
    var waveBlend: Double = 0.0
    var palette: PersonaPalette = PersonaPalette.fallback
}

/** What a turn state does to the bead. Colours are the persona's; the
 *  choreography is the same on every client. */
private class Visual(
    val core: Rgb,
    val glow: Rgb,
    val edge: Rgb,
    val brightness: Double,
    val swell: Double,
    val spread: Double,
    val motion: Double,
)

private fun DrawScope.drawOrb(
    elapsed: Double,
    particles: List<PersonaParticle>,
    inputs: OrbInputs,
) {
    val p = inputs.pulse.coerceIn(0.0, 1.0)
    val still = inputs.reduceMotion
    val t = if (still) 0.0 else elapsed

    val time = (t.mod(12.0) / 12) * 2 * PI
    val breath = if (still) 0.0 else triangle(t, 3.8)
    val shimmer = if (still) 0.5 else triangle(t, 1.6)
    val wave = if (still) 0.0 else t.mod(1.3) / 1.3

    val v = visual(inputs.state, inputs.palette, shimmer, breath, p)

    val cx = size.width / 2.0
    val cy = size.height / 2.0
    val field = minOf(size.width, size.height) / 2.0
    val sphereRadius = field * 0.34 * v.swell
    val orbitRadius = field * 0.92 * v.spread

    // The halo behind the bead.
    val haloR = sphereRadius * 2.6
    val center = Offset(cx.toFloat(), cy.toFloat())
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                v.glow.toColor((0.55 * v.brightness).toFloat()),
                v.glow.toColor(0f),
            ),
            center = center,
            radius = haloR.toFloat(),
        ),
        radius = haloR.toFloat(),
        center = center,
    )

    // The field: an orbit at rest, easing into the speaking waveform.
    val twoPi = 2 * PI
    val waveHalfWidth = field * 0.95
    val waveCycles = 2.4
    val travel = wave * twoPi
    val waveAmp = field * (0.05 + 0.32 * p)
    val lastIdx = max(1, PersonaParticle.COUNT - 1).toDouble()
    val blend = inputs.waveBlend

    particles.forEachIndexed { i, part ->
        val angle = part.baseAngle + time * part.angularSpeed * v.motion
        val r = orbitRadius * part.ringRadius
        val ox = cx + cos(angle) * r
        val oy = cy + sin(angle) * r * part.ringEccentricity
        // Where on its ellipse the dot is, read as depth: the far half is
        // dimmer and smaller, which is the whole of the 2D bead's roundness.
        val depth = sin(angle) * 0.5 + 0.5

        val frac = i / lastIdx
        val phaseArg = frac * waveCycles * twoPi - travel + part.phase * 0.15
        val wx = cx + (frac - 0.5) * 2 * waveHalfWidth
        val wy = cy + sin(phaseArg) * waveAmp * (0.7 + 0.6 * part.sizeFactor) +
            (part.sizeFactor - 0.5) * field * 0.06

        val px = ox + (wx - ox) * blend
        val py = oy + (wy - oy) * blend

        val twinkle = if (still) 0.7 else 0.55 + 0.45 * sin(time + part.phase) * 0.5 + 0.225
        val orbitAlpha = (0.30 + 0.55 * depth) * twinkle
        val crest = 0.5 + 0.5 * sin(phaseArg)
        val waveAlpha = 0.45 + 0.55 * crest * (0.5 + 0.5 * p)
        val alpha = ((orbitAlpha + (waveAlpha - orbitAlpha) * blend) * v.brightness)
            .coerceIn(0.0, 1.0)

        val dotDepth = 0.6 + 0.8 * depth
        val dotR = field * 0.012 *
            (dotDepth + (1.0 - dotDepth) * blend) *
            (0.7 + 0.6 * part.sizeFactor)

        drawCircle(
            color = inputs.palette.particle.toColor(alpha.toFloat()),
            radius = dotR.toFloat(),
            center = Offset(px.toFloat(), py.toFloat()),
        )
    }

    // The bead: a bright core fading to its edge tint at the rim.
    drawCircle(
        brush = Brush.radialGradient(
            colorStops = arrayOf(
                0.00f to v.core.toColor((0.92 * v.brightness).coerceIn(0.0, 1.0).toFloat()),
                0.55f to v.core.toColor((0.65 * v.brightness).coerceIn(0.0, 1.0).toFloat()),
                1.00f to v.edge.toColor((0.45 * v.brightness).coerceIn(0.0, 1.0).toFloat()),
            ),
            center = center,
            radius = sphereRadius.toFloat(),
        ),
        radius = sphereRadius.toFloat(),
        center = center,
    )

    // The edge ring: a REDUNDANT state cue, so the turn is legible in
    // peripheral vision and to anyone who cannot separate the state colours.
    drawCircle(
        color = v.edge.toColor((0.55 * v.brightness).coerceIn(0.0, 1.0).toFloat()),
        radius = sphereRadius.toFloat(),
        center = center,
        style = Stroke(width = (field * 0.012).toFloat()),
    )
}

private fun visual(
    state: HearthState,
    palette: PersonaPalette,
    shimmer: Double,
    breath: Double,
    pulse: Double,
): Visual {
    val core = palette.sphere
    val idle = palette.idle
    return when (state) {
        HearthState.LOADING, HearthState.IDLE -> Visual(
            core = core, glow = idle, edge = idle,
            brightness = 0.45 + 0.10 * breath,
            swell = 1.0 + 0.03 * breath,
            spread = 1.0, motion = 0.35,
        )

        HearthState.LISTENING -> Visual(
            core = core, glow = idle, edge = palette.listening,
            brightness = 0.95, swell = 1.12, spread = 1.22, motion = 1.0,
        )

        HearthState.THINKING -> Visual(
            core = core.mix(palette.thinking, (0.25 * shimmer).toFloat()),
            glow = idle.mix(palette.thinking, shimmer.toFloat()),
            edge = idle.mix(palette.thinking, shimmer.toFloat()),
            brightness = 0.7 + 0.15 * shimmer,
            swell = 1.0 + 0.04 * sin(shimmer * PI),
            spread = 1.05, motion = 0.8,
        )

        HearthState.SPEAKING -> Visual(
            core = core.mix(palette.speaking, 0.2f),
            glow = idle.mix(palette.speaking, (0.4 + 0.4 * pulse).toFloat()),
            edge = idle.mix(palette.speaking, 0.5f),
            brightness = min(1.0, 0.75 + 0.25 * pulse),
            swell = 1.0 + 0.18 * pulse,
            spread = 1.0 + 0.15 * pulse, motion = 1.0,
        )
    }
}

/** A triangle wave: up over [half] seconds, back down over the next. */
private fun triangle(elapsed: Double, half: Double): Double {
    val x = elapsed.mod(2 * half) / half
    return if (x <= 1) x else 2 - x
}

private fun Rgb.toColor(alpha: Float) = Color(r, g, b, alpha.coerceIn(0f, 1f))
