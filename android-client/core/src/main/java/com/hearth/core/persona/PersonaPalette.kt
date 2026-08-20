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
            idle = Scene.fennec,
            listening = Scene.honey,
            thinking = Scene.fennec.mix(Scene.ember, 0.5f),
            speaking = Scene.ember,
        )

        /** Decode a persona's `visualization.state_colors` block, tolerantly. */
        fun from(visualization: JSONObject?): PersonaPalette {
            val colors = visualization?.optJSONObject("state_colors") ?: return fallback
            fun pick(key: String, fallbackColor: Rgb): Rgb {
                val arr = colors.optJSONArray(key) ?: return fallbackColor
                if (arr.length() < 3) return fallbackColor
                return Rgb(
                    arr.optDouble(0).toFloat(),
                    arr.optDouble(1).toFloat(),
                    arr.optDouble(2).toFloat(),
                )
            }
            return PersonaPalette(
                idle = pick("idle", fallback.idle),
                listening = pick("listening", fallback.listening),
                thinking = pick("thinking", fallback.thinking),
                speaking = pick("speaking", fallback.speaking),
            )
        }
    }
}
