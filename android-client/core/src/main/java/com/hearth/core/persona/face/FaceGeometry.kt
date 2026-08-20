package com.hearth.core.persona.face

import org.json.JSONObject

/**
 * Appearance only, normalised to the head's own bounding box. Ported from the
 * iOS `PersonaVisualization.swift`.
 *
 * Motion never lives here -- the director owns every channel that moves, which
 * is what lets a persona's dozen numbers drive the whole expression library
 * instead of authoring an animation set. Defaults are the warm_round
 * archetype, so a partial block still renders a face rather than a pile of
 * zeroes. Spec: wiki/raw/persona-face-spec.md.
 */
data class FaceGeometry(
    val headWidth: Double = 1.0,
    val headHeight: Double = 1.05,
    val headRoundness: Double = 0.8,
    val eyeSize: Double = 0.1,
    val eyeSpacing: Double = 0.38,
    val eyeHeight: Double = 0.45,
    val eyeLength: Double = 2.4,
    val eyeTilt: Double = 0.0,
    val mouthWidth: Double = 0.34,
    val mouthThickness: Double = 0.05,
    val mouthCurve: Double = 0.26,
) {
    companion object {
        /**
         * Decode a persona's `geometry` block. Every field falls back to its
         * archetype default: a house one field ahead of this client must still
         * render a face.
         */
        fun from(geo: JSONObject?): FaceGeometry {
            if (geo == null) return FaceGeometry()
            val d = FaceGeometry()
            fun f(key: String, fallback: Double): Double =
                if (geo.has(key) && !geo.isNull(key)) geo.optDouble(key, fallback) else fallback
            return FaceGeometry(
                headWidth = f("head_width", d.headWidth),
                headHeight = f("head_height", d.headHeight),
                headRoundness = f("head_roundness", d.headRoundness),
                eyeSize = f("eye_size", d.eyeSize),
                eyeSpacing = f("eye_spacing", d.eyeSpacing),
                eyeHeight = f("eye_height", d.eyeHeight),
                eyeLength = f("eye_length", d.eyeLength),
                eyeTilt = f("eye_tilt", d.eyeTilt),
                mouthWidth = f("mouth_width", d.mouthWidth),
                mouthThickness = f("mouth_thickness", d.mouthThickness),
                mouthCurve = f("mouth_curve", d.mouthCurve),
            )
        }
    }
}
