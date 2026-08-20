package com.hearth.core.persona

import com.hearth.core.models.HearthState
import org.json.JSONObject

/**
 * A colour per turn state, from the persona's own config. Ported from the iOS
 * `PersonaPalette.swift`.
 *
 * Colours live here as plain RGB triples rather than Compose Colors so this
 * module stays free of the UI toolkit; the face converts at draw time. The
 * face and the orb read the SAME palette on purpose: a face that invented its
 * own colours would drift from the orb it replaces.
 */
data class Rgb(val r: Float, val g: Float, val b: Float) {

    /** Linear blend, [t] toward [other]. The whole of the desktop's color-mix. */
    fun mix(other: Rgb, t: Float): Rgb = Rgb(
        r * (1 - t) + other.r * t,
        g * (1 - t) + other.g * t,
        b * (1 - t) + other.b * t,
    )

    companion object {
        fun hex(value: Int): Rgb = Rgb(
            ((value shr 16) and 0xFF) / 255f,
            ((value shr 8) and 0xFF) / 255f,
            (value and 0xFF) / 255f,
        )

        /** `[r, g, b]` in 0..1, as persona configs carry it. */
        fun from(list: List<Double>?): Rgb? {
            if (list == null || list.size < 3) return null
            return Rgb(list[0].toFloat(), list[1].toFloat(), list[2].toFloat())
        }
    }
}

/** The brand's scene tokens, the single source both clients draw from. */
object Scene {
    val cream = Rgb.hex(0xFAF4EA)
    val fluff = Rgb.hex(0xFFFFFF)
    val fennec = Rgb.hex(0xE39A5B)
    val ember = Rgb.hex(0xC97F45)
    val honey = Rgb.hex(0xFFB84D)
    val roast = Rgb.hex(0x3B2B20)
}

data class PersonaPalette(
    /** The core bead body. */
    val sphere: Rgb,
    /** The orbiting particle field. */
    val particle: Rgb,
    val idle: Rgb,
    val listening: Rgb,
    val thinking: Rgb,
    val speaking: Rgb,
) {
    fun glow(state: HearthState): Rgb = when (state) {
        HearthState.LISTENING -> listening
        HearthState.THINKING -> thinking
        HearthState.SPEAKING -> speaking
        else -> idle // LOADING / IDLE
    }

    companion object {
        /**
         * Warm Hearth brand colours: the base a SERVER payload fills in over,
         * so a persona that ships no palette gets these rather than another
         * persona's.
         */
        val fallback = PersonaPalette(
            sphere = Scene.fennec,
            particle = Scene.honey,
            idle = Scene.fennec,
            listening = Scene.honey,
            thinking = Scene.fennec.mix(Scene.ember, 0.5f),
            speaking = Scene.ember,
        )

        /**
         * Decode the server's `visualization` block. Any missing field keeps
         * the fallback, so partial and legacy configs are safe.
         *
         * THE WIRE SHAPE IS AN OBJECT, `{"r":..,"g":..,"b":..}`, and this read
         * an ARRAY until 2026-08-20 -- so every lookup missed and every persona
         * silently wore the brand defaults. Sulivan's own colours had never
         * reached this client. Nothing failed loudly, because falling back to a
         * warm palette is indistinguishable from a persona that asked for one.
         */
        fun from(visualization: JSONObject?): PersonaPalette {
            if (visualization == null) return fallback
            var p = fallback

            rgb(visualization.optJSONObject("sphere")?.opt("color"))
                ?.let { p = p.copy(sphere = it) }
            rgb(visualization.optJSONObject("particle_system")?.opt("color"))
                ?.let { p = p.copy(particle = it) }

            val states = visualization.optJSONObject("state_colors")
            if (states != null) {
                rgb(states.opt("idle"))?.let { p = p.copy(idle = it) }
                rgb(states.opt("listening"))?.let { p = p.copy(listening = it) }
                rgb(states.opt("thinking"))?.let { p = p.copy(thinking = it) }
                rgb(states.opt("speaking"))?.let { p = p.copy(speaking = it) }

                // A face-era config carries state_colors and no sphere or
                // particle_system objects at all. The orb-fallback paths -- a
                // model persona whose asset has not arrived, a face whose
                // geometry has not, a widget -- still deserve the persona's OWN
                // colours, so the bead borrows the idle glow and the particles
                // the listening glow rather than degrading to brand defaults.
                if (!visualization.has("sphere")) {
                    rgb(states.opt("idle"))?.let { p = p.copy(sphere = it) }
                }
                if (!visualization.has("particle_system")) {
                    rgb(states.opt("listening"))?.let { p = p.copy(particle = it) }
                }
            }
            return p
        }

        /** An `{r,g,b}` colour object; alpha is ignored, the bead is solid. */
        private fun rgb(any: Any?): Rgb? {
            val d = any as? JSONObject ?: return null
            if (!d.has("r") || !d.has("g") || !d.has("b")) return null
            return Rgb(
                d.optDouble("r").toFloat(),
                d.optDouble("g").toFloat(),
                d.optDouble("b").toFloat(),
            )
        }
    }
}
