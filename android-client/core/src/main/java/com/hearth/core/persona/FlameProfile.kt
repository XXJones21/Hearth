package com.hearth.core.persona

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * The flame's SHAPE as pure arithmetic, with no renderer in it. Ported from
 * the iOS `FlameProfile.swift`, which is itself lifted unchanged from the
 * headset's `FlameMesh`.
 *
 * WHY THE SAME NUMBERS APPEAR ON EVERY CLIENT, and it is the whole reason a 2D
 * flame is cheap: the silhouette is not an approximation of the headset's, it
 * is the SAME curve. A surface of revolution seen from the front has its
 * outline at the two meridians where x is extremal -- angle 0 and angle pi --
 * so a 2D client evaluates exactly what a 3D client evaluates, at two angles
 * instead of forty-four.
 *
 * It lives in `core` rather than beside the Canvas for the same reason
 * [com.hearth.core.persona.face.FaceDirector] does: it is arithmetic anyone
 * can test, and a widget will need it without an Activity.
 *
 * Doubles rather than floats, matching iOS -- the trigonometry is evaluated
 * eighty times a frame, which is nothing, and drifting from the reference
 * numbers to save arithmetic nobody is counting is a bad trade.
 *
 * See `wiki/raw/persona-flame-spec.md` for the full walkthrough and for what a
 * 2D drawing gives up (fine grain, depth, any path to rotating it).
 */
data class FlameProfile(
    /** Half-width at the flame's widest, in whatever units the caller draws in. */
    var radius: Double,
    /** Total height, same units. */
    var height: Double,
    /**
     * How much the silhouette wanders. Zero is a smooth teardrop -- useful for
     * seeing the profile on its own, useless as fire.
     */
    var turbulence: Double = 0.28,
    /**
     * How far the tip leans as it rises, which is what stops a flame reading
     * as a symmetrical vase.
     */
    var sway: Double = 0.16,
) {

    /**
     * How wide the flame is at a given height parameter, where `v` runs 0 at
     * the base to 1 at the tip.
     *
     * Two pieces, because the base and the body want different curves: a
     * hemisphere below [DOME_TOP], then a rounded shoulder and a long taper.
     *
     * Squaring `t` inside the taper is what keeps the flame near full width
     * through its lower third. Without it the silhouette is a cone -- `pow(1-t,
     * n)` is very nearly a straight line near the base. The exponent is the
     * top's width, and LOWER is wider.
     *
     * A flame is fattest LOW, just above whatever it is burning on. Widest near
     * the top drawing to a point at the bottom is a light bulb.
     */
    fun width(v: Double, phase: Double): Double {
        // Almost invisible on purpose. A flame does not pulse as a whole; its
        // EDGES move, and that is the turbulence's job. At 0.06 this swelled
        // the silhouette enough to swallow the face on every cycle.
        val breath = 1 + 0.012 * sin(phase * 1.6)
        if (v < DOME_TOP) {
            val t = v / DOME_TOP
            return radius * sin(t * PI / 2) * breath
        }
        val t = (v - DOME_TOP) / (1 - DOME_TOP)
        return radius * max(1 - t * t, 0.0).pow(0.45) * breath
    }

    /**
     * How high up the flame a given `v` sits. Not linear: across the dome the
     * height follows the same quarter circle the width does, so the two
     * together describe a hemisphere rather than a spike. A profile that simply
     * goes to zero at v = 0 gives a spike.
     */
    fun rise(v: Double): Double {
        val base = -radius * DOME_DEPTH
        if (v < DOME_TOP) {
            val t = v / DOME_TOP
            return base + radius * DOME_DEPTH * (1 - cos(t * PI / 2))
        }
        val t = (v - DOME_TOP) / (1 - DOME_TOP)
        return base + radius * DOME_DEPTH + (height - radius * DOME_DEPTH) * t
    }

    /**
     * How far the flame leans sideways at a given height. Nothing at the base
     * -- it is attached to something -- growing with the square of the height,
     * so the lean is all in the top third.
     */
    fun lean(v: Double, phase: Double): Double = sway * radius * v * v * sin(phase * 1.7)

    /** The surface's distance from the axis, on one meridian, right now. */
    fun surface(v: Double, angle: Double, phase: Double): Double {
        val wobble = 1 + turbulence * noise(angle, v, phase)
        return width(v, phase) * max(wobble, 0.05)
    }

    /**
     * The VISIBLE top, not the geometric one. The mesh runs to a point and the
     * density has faded it to nothing well before that, so the tip is drawn and
     * never seen. Anything hung above the persona has to clear what people can
     * SEE. If [FADE_END] moves, this moves with it.
     */
    val visibleTop: Double get() = rise(0.95)

    companion object {
        /** Where the rounded base gives way to the taper. */
        const val DOME_TOP = 0.3
        /** How deep that base hangs below the origin, as a fraction of radius. */
        const val DOME_DEPTH = 0.95

        /** Where the density feather takes the flame to nothing. */
        const val FADE_START = 0.88
        const val FADE_END = 0.99

        /**
         * Cheap, seamless, deterministic wobble.
         *
         * Trigonometric rather than a noise table: sines of INTEGER multiples
         * of the angle agree at 0 and 2pi for free, which a body that closes on
         * itself needs.
         *
         * THE DAMPING IS NOT OPTIONAL. A flame is held steady by whatever it is
         * burning on; the first run's wobble ran all the way down and chewed
         * the dome into a knot of folds.
         */
        fun noise(angle: Double, v: Double, phase: Double): Double {
            val a = sin(3 * angle + phase * 2.1 + v * 5.0)
            val b = sin(5 * angle - phase * 1.6 + v * 8.0) * 0.55
            val c = sin(8 * angle + phase * 2.9 - v * 3.0) * 0.3
            return (a + b + c) / 1.85 * smoothstep(DOME_TOP, 1.0, v)
        }

        /**
         * How opaque the flame is at a given height -- the tip feather only.
         * The interior noise that tatters a real flame's upper half is what a
         * 2D drawing gives up.
         */
        fun opacity(v: Double): Double = 1 - smoothstep(FADE_START, FADE_END, v)

        fun smoothstep(edge0: Double, edge1: Double, x: Double): Double {
            val t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
            return t * t * (3 - 2 * t)
        }

        /**
         * The shader's own hash, so the ember field is the SAME field on every
         * client rather than merely a similar one.
         */
        fun hash(x: Double): Double {
            val v = sin(x * 12.9898) * 43758.5453
            return v - floor(v)
        }

        /**
         * Three sines at incommensurable rates -- the same correlation the rig
         * uses to make its light breathe with the fire rather than beside it.
         * A fire's signature is that its light is never still.
         */
        fun flicker(t: Double): Double {
            val wobble = sin(t * 2.7) * 0.5 + sin(t * 4.3 + 1.7) * 0.3 + sin(t * 9.1 + 0.4) * 0.2
            return 0.5 + 0.5 * max(-1.0, min(1.0, wobble))
        }
    }
}
