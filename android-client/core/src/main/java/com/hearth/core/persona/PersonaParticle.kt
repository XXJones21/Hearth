package com.hearth.core.persona

import kotlin.math.PI

/**
 * One dot in the orb's field. Ported from the iOS `PersonaParticle`, which
 * came from Echo's `PersonaCanvas.kt` -- so this is the field returning to the
 * platform it was born on.
 *
 * The field is CHOREOGRAPHED rather than simulated: every dot's position is
 * stated each frame from its own constants and one clock. That is the only way
 * to draw a ring or spell out a waveform, which is what SPEAKING needs. The
 * flame's embers are simulated instead, and the spec is firm that a look picks
 * one mechanism and answers every turn state with it -- switching mid-turn
 * reads as a glitch rather than as a state change.
 */
data class PersonaParticle(
    val baseAngle: Double,
    val ringRadius: Double,
    val ringEccentricity: Double,
    val angularSpeed: Double,
    val sizeFactor: Double,
    val phase: Double,
) {
    companion object {
        const val COUNT = 96

        /**
         * A deterministic LCG-seeded field, so the orb looks the same on every
         * launch and on every client. The seed and the constants are the iOS
         * ones, which are Echo's -- a field that merely looked similar would
         * make the same persona two characters.
         */
        fun field(): List<PersonaParticle> {
            // Kotlin's Int arithmetic wraps, which is what Swift spells `&*`
            // and `&+`; `ushr` is the unsigned shift its UInt32 view takes.
            var seed = 0x9E37_79B9.toInt()
            fun next(): Double {
                seed = seed * 1103515245 + 12345
                return (((seed ushr 8) and 0xFFFF).toDouble()) / 65535.0
            }
            val twoPi = 2 * PI
            return List(COUNT) {
                PersonaParticle(
                    baseAngle = next() * twoPi,
                    ringRadius = 0.45 + next() * 0.55,
                    ringEccentricity = 0.55 + next() * 0.35,
                    angularSpeed = (0.4 + next() * 0.9) * (if (next() > 0.5) 1.0 else -1.0),
                    sizeFactor = 0.4 + next() * 0.6,
                    phase = next() * twoPi,
                )
            }
        }
    }
}
