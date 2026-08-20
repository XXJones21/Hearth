package com.hearth.core.transport

import org.json.JSONObject

/**
 * Everything the house can say, as one closed set.
 *
 * The iOS client carries this as ~30 nullable callback properties; a Kotlin
 * flow of a sealed type says the same thing and makes the `when` exhaustive at
 * compile time. The unknown case is deliberate and load-bearing: a house one
 * version ahead names an action this client has not learned, and the client
 * must go on rather than error. Every unknown is logged, never thrown.
 */
sealed interface HearthEvent {

    // ---- connection ----

    /** The handshake landed; the house named its capabilities. */
    data class ClientInfoAck(val serverCapabilities: JSONObject?) : HearthEvent

    /** The socket closed. [authRejected] means 1008: the token was refused. */
    data class Closed(val code: Int, val reason: String, val authRejected: Boolean) : HearthEvent

    data class Failure(val message: String) : HearthEvent

    // ---- the turn ----

    /** The canonical full text of a reply. Replaces any streamed line by id. */
    data class AiResponse(val text: String, val persona: String) : HearthEvent

    data class ErrorMessage(val text: String) : HearthEvent

    /**
     * A speech segment is starting.
     *
     * [text] is that sentence's caption and [expression] the face cue the
     * harness resolved from its non-verbal tag. Both carry [segIdx] because
     * the house pushes every segment of a reply within a second or two while
     * speaking them takes far longer: they wait for their audio, and the
     * karaoke clock in the player is what releases them.
     */
    data class TtsChunkStart(
        val segIdx: Int,
        val sampleRate: Int,
        val text: String?,
        val expression: String?,
    ) : HearthEvent

    data class TtsChunkEnd(val segIdx: Int) : HearthEvent

    /** Raw float32 PCM for the segment in flight. */
    data class PcmChunk(val bytes: ByteArray) : HearthEvent {
        override fun equals(other: Any?): Boolean =
            this === other || (other is PcmChunk && bytes.contentEquals(other.bytes))

        override fun hashCode(): Int = bytes.contentHashCode()
    }

    data object SpeakingComplete : HearthEvent

    data class TtsError(val text: String) : HearthEvent

    /**
     * A named performance starting or ending, emitted at tool boundaries.
     * Unlike a face cue this belongs to the TURN, not a sentence, so it fires
     * when the house starts doing the thing rather than waiting for audio.
     */
    data class BehaviorCue(val name: String, val phase: String) : HearthEvent

    // ---- personas ----

    data class PersonasList(val names: List<String>, val current: String) : HearthEvent

    data class PersonaSwitched(val name: String) : HearthEvent

    /** The whole `config` block, forwarded verbatim for tolerant decode. */
    data class PersonaConfig(val name: String, val config: JSONObject) : HearthEvent

    // ---- state and surfaces ----

    /** `{state, stage}`: thinking (transcribing|deciding|acting) or idle. */
    data class StateUpdate(val state: String, val stage: String?) : HearthEvent

    /** A card, raw. The store decides upsert/clear/clear_all and ttl. */
    data class UiComponent(val payload: JSONObject) : HearthEvent

    data class PipelineStage(val stage: String, val tools: List<String>) : HearthEvent

    data class SessionEnded(val reason: String, val summary: String?) : HearthEvent

    /** Always preceded by [SessionEnded]; the handler repaints from these. */
    data class SessionResumed(
        val slug: String,
        val turns: List<Pair<String, String>>,
    ) : HearthEvent

    data class TopicSession(val name: String) : HearthEvent

    // ---- memory (logged today, as on iOS) ----

    data class EngramContext(val project: String, val loaded: Boolean) : HearthEvent

    data class EngramSaved(val thoughtSlug: String, val saved: Boolean) : HearthEvent

    /** An action this client has not learned. Never an error. */
    data class Unknown(val action: String) : HearthEvent
}
