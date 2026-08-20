package com.hearth.core.transport

import android.util.Log
import com.hearth.core.config.ServerConfig
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * The wire. Ported from the iOS `HearthWebSocketClient.swift`, action for
 * action.
 *
 * OkHttp replaces URLSessionWebSocketTask. The auth token rides the handshake
 * as an `Authorization` header, which is why the request is built through
 * [ServerConfig.authorize] rather than from a bare URL.
 *
 * Text frames are JSON; binary frames are float32 PCM for the segment in
 * flight. Unknown actions log and pass: a house ahead of this client must not
 * break it.
 */
class HearthWebSocketClient(
    private val config: ServerConfig,
    private val client: OkHttpClient = defaultClient(),
) {

    private val _events = MutableSharedFlow<HearthEvent>(
        replay = 0,
        extraBufferCapacity = 256,
        onBufferOverflow = BufferOverflow.SUSPEND,
    )

    /** Everything the house says. Collected by the view model. */
    val events: Flow<HearthEvent> = _events.asSharedFlow()

    private var socket: WebSocket? = null

    /**
     * Called the moment the socket opens, before any frame is read. The
     * handshake goes out from here so `core` never needs an Android context
     * to build its device block.
     */
    var onOpen: (() -> Unit)? = null

    @Volatile
    var isConnected: Boolean = false
        private set

    /** True between `tts_chunk_start` and `speaking_complete`. */
    @Volatile
    var isInPcmStreamMode: Boolean = false
        private set

    /**
     * Dial the house. Returns false when no address is configured, which is a
     * distinct state from a failed connection: an unconfigured client shows
     * first run rather than a retry loop.
     */
    fun connect(): Boolean {
        val url = config.serverUrl ?: run {
            Log.i(TAG, "no house configured; not dialing")
            return false
        }
        disconnect()
        val builder = Request.Builder().url(url)
        config.authorize(builder)
        socket = client.newWebSocket(builder.build(), Listener())
        return true
    }

    fun disconnect() {
        socket?.close(1000, "client closing")
        socket = null
        isConnected = false
        isInPcmStreamMode = false
    }

    // ---- client -> server -------------------------------------------------

    private fun send(payload: JSONObject): Boolean {
        val s = socket ?: return false
        return s.send(payload.toString())
    }

    /**
     * The handshake. Sent the moment the socket opens.
     *
     * Capabilities are NESTED, as iOS sends them: the house reads
     * `cmd.get("capabilities")` and gates features on what it finds there.
     * The first Android cut put these flags at the top level, so the house
     * saw an empty capability set and never emitted a single card, silently
     * and with the voice working perfectly.
     */
    fun sendClientInfo(deviceContext: JSONObject) {
        val capabilities = JSONObject()
            .put("audio", true)
            .put("spatial", false)
            .put("voice_input", true)
            .put("text_input", true)
            .put("vision", false)
            // STT is on-device, as on iOS: audio never leaves the phone,
            // only the text does.
            .put("stt", "local")
            .put("stt_engine", "android_speech")
            .put("ui_render", true)
        send(
            JSONObject()
                .put("action", "client_info")
                .put("platform", "android")
                .put("capabilities", capabilities)
                .put("device_context", deviceContext)
        )
    }

    /** False when there is no socket: the caller must not claim it sent. */
    fun sendTextQuery(text: String): Boolean =
        send(JSONObject().put("action", "text_query").put("text", text))

    /** The transcript of a local recognition. The audio itself never ships. */
    fun sendClientTranscription(text: String): Boolean =
        send(
            JSONObject()
                .put("action", "client_transcription")
                .put("text", text)
                .put("source", "android_speech")
        )

    fun sendPing() = send(JSONObject().put("action", "ping"))

    fun listPersonas() = send(JSONObject().put("action", "list_personas"))

    // The house reads `persona_name` on both of these. It also accepts a
    // bare `name` on switch, but there is no reason to send the spelling the
    // setup flow used when the canonical one works for both.
    fun switchPersona(name: String) =
        send(JSONObject().put("action", "switch_persona").put("persona_name", name))

    fun getPersonaConfig(name: String) =
        send(JSONObject().put("action", "get_persona_config").put("persona_name", name))

    fun newSession() = send(JSONObject().put("action", "new_session"))

    fun resumeSession(sessionId: String? = null, slug: String? = null) {
        val payload = JSONObject().put("action", "resume_session")
        sessionId?.let { payload.put("session_id", it) }
        slug?.let { payload.put("slug", it) }
        send(payload)
    }

    fun startTopicSession(name: String) =
        send(JSONObject().put("action", "start_topic_session").put("name", name))

    fun say(text: String) = send(JSONObject().put("action", "say").put("text", text))

    // ---- server -> client -------------------------------------------------

    private inner class Listener : WebSocketListener() {

        override fun onOpen(webSocket: WebSocket, response: Response) {
            isConnected = true
            Log.i(TAG, "socket open")
            onOpen?.invoke()
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val event = try {
                parse(text)
            } catch (e: Exception) {
                Log.w(TAG, "unparsable frame: ${e.message}")
                null
            }
            if (event != null) _events.tryEmit(event)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            _events.tryEmit(HearthEvent.PcmChunk(bytes.toByteArray()))
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            // 1008 is policy violation: the token was refused. Distinct from a
            // network drop because the fix is different -- re-pair, not retry.
            val authRejected = code == 1008
            isConnected = false
            isInPcmStreamMode = false
            webSocket.close(1000, null)
            _events.tryEmit(HearthEvent.Closed(code, reason, authRejected))
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            isConnected = false
            isInPcmStreamMode = false
            // THE REFUSAL ARRIVES HERE, NOT IN onClosing, and dropping the
            // response is what hid it. The gate closes the handshake BEFORE
            // accepting it, so the house never sends a 1008 close frame -- the
            // upgrade itself answers 403 and OkHttp reports a failure.
            //
            // Left unread, a refused device is indistinguishable from a flaky
            // network: reconnect is never suppressed, so the client redials
            // every thirty seconds forever against a door it has no key for,
            // and the stage says only "not connected".
            val authRejected = response?.code == 403 || response?.code == 401
            if (authRejected) Log.w(TAG, "house refused this device (${response?.code})")
            _events.tryEmit(HearthEvent.Failure(t.message ?: "socket failed", authRejected))
        }
    }

    private fun parse(raw: String): HearthEvent? {
        val json = try {
            JSONObject(raw)
        } catch (e: Exception) {
            // Plain non-JSON text is a transcription, as on iOS.
            return HearthEvent.AiResponse(raw, "")
        }

        return when (val action = json.optString("action")) {
            "client_info_ack" ->
                HearthEvent.ClientInfoAck(json.optJSONObject("server_capabilities"))

            "ai_response" -> HearthEvent.AiResponse(
                json.optString("text"),
                personaField(json),
            )

            "error" -> HearthEvent.ErrorMessage(json.optString("message", json.optString("error")))

            "pong" -> null // logged by the house; nothing for the UI

            "tts_chunk_start" -> HearthEvent.TtsChunkStart(
                segIdx = json.optInt("seg_idx"),
                sampleRate = json.optInt("sample_rate", DEFAULT_SAMPLE_RATE),
                text = json.optString("text").ifEmpty { null },
                expression = json.optString("expression").ifEmpty { null },
            ).also { isInPcmStreamMode = true }

            "tts_chunk_end" -> HearthEvent.TtsChunkEnd(json.optInt("seg_idx"))

            "speaking_complete" -> {
                isInPcmStreamMode = false
                HearthEvent.SpeakingComplete
            }

            "tts_error" -> HearthEvent.TtsError(json.optString("message"))

            "behavior_cue" -> HearthEvent.BehaviorCue(
                json.optString("name"),
                json.optString("phase"),
            )

            "personas_list" -> HearthEvent.PersonasList(
                names = personaNames(json.opt("personas")),
                current = json.optString("current_persona")
                    .ifEmpty { json.optString("current") },
            )

            "persona_switched" -> HearthEvent.PersonaSwitched(personaField(json))

            "persona_config" -> HearthEvent.PersonaConfig(
                name = personaField(json),
                config = json.optJSONObject("config") ?: JSONObject(),
            )

            "state_update" -> HearthEvent.StateUpdate(
                state = json.optString("state"),
                stage = json.optString("stage").ifEmpty { null },
            )

            "ui_component" -> HearthEvent.UiComponent(json)

            "pipeline_stage" -> HearthEvent.PipelineStage(
                stage = json.optString("stage"),
                tools = stringList(json.optJSONArray("tools")),
            )

            "session_ended" -> HearthEvent.SessionEnded(
                reason = json.optString("reason"),
                summary = json.optString("summary").ifEmpty { null },
            )

            "session_resumed" -> HearthEvent.SessionResumed(
                slug = json.optString("slug"),
                turns = turns(json.optJSONArray("turns")),
            )

            "topic_session" -> HearthEvent.TopicSession(json.optString("name"))

            "engram_context" -> HearthEvent.EngramContext(
                json.optString("project"),
                json.optBoolean("context_loaded"),
            )

            "engram_saved" -> HearthEvent.EngramSaved(
                json.optString("thought_slug"),
                json.optBoolean("saved"),
            )

            else -> {
                // Forward compat, deliberately not an error.
                Log.i(TAG, "unhandled action '$action'")
                HearthEvent.Unknown(action)
            }
        }
    }

    /**
     * The house names a persona `persona_name`; some payloads and older
     * houses say `persona`. Both spellings arrive in the wild, so read both
     * rather than silently rendering a default persona's face.
     */
    private fun personaField(json: JSONObject): String =
        json.optString("persona_name").ifEmpty { json.optString("persona") }

    /** `personas_list` carries either [String] or [{name}], as on iOS. */
    private fun personaNames(raw: Any?): List<String> {
        val array = raw as? JSONArray ?: return emptyList()
        val out = mutableListOf<String>()
        for (i in 0 until array.length()) {
            when (val item = array.opt(i)) {
                is String -> out.add(item)
                is JSONObject -> item.optString("name").takeIf { it.isNotEmpty() }?.let(out::add)
            }
        }
        return out
    }

    private fun stringList(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { array.optString(it).ifEmpty { null } }
    }

    private fun turns(array: JSONArray?): List<Pair<String, String>> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            val turn = array.optJSONObject(i) ?: return@mapNotNull null
            turn.optString("user") to turn.optString("assistant")
        }
    }

    companion object {
        private const val TAG = "HearthSocket"
        const val DEFAULT_SAMPLE_RATE = 24000

        /**
         * No read timeout: a socket that is quiet between turns is healthy,
         * and OkHttp's default would close it mid-conversation. Liveness is
         * the keepalive ping instead, as on iOS.
         */
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .pingInterval(0, TimeUnit.MILLISECONDS)
            .build()
    }
}
