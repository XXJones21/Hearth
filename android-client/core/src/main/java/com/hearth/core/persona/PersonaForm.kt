package com.hearth.core.persona

/**
 * How a persona wants to be DRAWN, straight from its own config.
 *
 * THE RENDERER IS CHOSEN BY TYPE, NEVER BY NAME. Nothing in a client says "if
 * Sulivan": a persona declares what it is and the stage honours it, which is
 * what lets Sage arrive with no code change. Ported from the iOS
 * `PersonaVisualization.Kind`, and the two must carry the same spellings or
 * one client will silently draw a different character.
 */
enum class PersonaForm(val wire: String) {
    /** The bead in its particle field. The default, and every other form's
     *  fallback when what it needs has not arrived. */
    SPHERE_PARTICLE("sphere_particle"),

    /** A character model: Selene, and Sage when she arrives. */
    GLB_ANIMATED("glb_animated"),

    /** The eyes-first procedural face on a drawn head. */
    PROCEDURAL_FACE("procedural_face"),

    /**
     * Sulivan's fire, with the face worn ON it. A screen draws it with vector
     * primitives; a headset builds it as a mesh with a compute kernel and a
     * light in the room. Same character, same arithmetic, two implementations
     * -- which is exactly why this is one name rather than `canvas_flame`.
     * Spec: `wiki/raw/persona-flame-spec.md`.
     */
    FLAME("flame");

    /** Whether this form wears the persona's drawn face. */
    val wearsFace: Boolean get() = this == PROCEDURAL_FACE || this == FLAME

    companion object {
        /**
         * An unknown type draws the orb, which is the honest thing for a house
         * one field ahead of this client -- but SAY SO. Silence here costs an
         * hour, because an unrecognised type is indistinguishable from a
         * persona that asked for the orb.
         */
        fun from(raw: String?): PersonaForm {
            if (raw.isNullOrBlank()) return SPHERE_PARTICLE
            return entries.firstOrNull { it.wire == raw } ?: run {
                println("PersonaForm: unknown type '$raw'; drawing the orb")
                SPHERE_PARTICLE
            }
        }
    }
}
