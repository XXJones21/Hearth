package com.hearth.core.viewmodel

import android.util.Log
import com.hearth.core.audio.SpeechRecognitionManager
import com.hearth.core.audio.TtsStreamPlayer
import com.hearth.core.config.ServerConfig
import com.hearth.core.models.ChatMessage
import com.hearth.core.models.HearthState
import com.hearth.core.persona.PersonaPalette
import com.hearth.core.persona.face.FaceGeometry
import com.hearth.core.transport.HearthEvent
import com.hearth.core.transport.HearthWebSocketClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.Locale
import java.util.TimeZone
import kotlin.math.min
import kotlin.math.pow

/**
 * The app's brain, ported from the iOS `ChatViewModel.swift`: connection
 * lifecycle, the turn state machine, keepalive, reconnect backoff, and the
 * transcript.
 *
 * Combine's `@Published` becomes [StateFlow]. The class is deliberately
 * framework-free below that so it can live in `core` and be driven by any
 * surface, including the cover screen.
 */
class ChatViewModel(
    private val config: ServerConfig,
    private val scope: CoroutineScope,
    private val socket: HearthWebSocketClient = HearthWebSocketClient(config),
    private val player: TtsStreamPlayer? = null,
    private val speech: SpeechRecognitionManager? = null,
) {

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _state = MutableStateFlow(HearthState.LOADING)
    val state: StateFlow<HearthState> = _state.asStateFlow()

    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected.asStateFlow()

    private val _personaName = MutableStateFlow(DEFAULT_PERSONA)
    val personaName: StateFlow<String> = _personaName.asStateFlow()

    private val _personas = MutableStateFlow<List<String>>(emptyList())
    val personas: StateFlow<List<String>> = _personas.asStateFlow()

    /** The house refused the token: re-pair, do not retry. */
    private val _needsPairing = MutableStateFlow(false)
    val needsPairing: StateFlow<Boolean> = _needsPairing.asStateFlow()

    /** thinking stage label: transcribing | deciding | acting. */
    private val _thinkingStage = MutableStateFlow<String?>(null)
    val thinkingStage: StateFlow<String?> = _thinkingStage.asStateFlow()

    private var keepaliveJob: Job? = null
    private var reconnectJob: Job? = null
    private var reconnectAttempt = 0
    private var inBackground = false

    /** Caption for the sentence being heard right now, in playback time. */
    private val _caption = MutableStateFlow<String?>(null)
    val caption: StateFlow<String?> = _caption.asStateFlow()

    /** Face cue for the sentence being heard, released by the karaoke clock. */
    private val _faceCue = MutableStateFlow<Pair<String, Long>?>(null)
    val faceCue: StateFlow<Pair<String, Long>?> = _faceCue.asStateFlow()

    /**
     * The amplitude of the sound THE HOUSE IS MAKING. Drives the face's mouth
     * and nothing else.
     *
     * Deliberately separate from [micLevel]: one shared level meant the
     * microphone drove the mouth, so the persona's mouth moved while the
     * operator was talking. iOS keeps these apart for the same reason, and
     * the face only ever reads the TTS side.
     */
    private val _ttsAmplitude = MutableStateFlow(0f)
    val ttsAmplitude: StateFlow<Float> = _ttsAmplitude.asStateFlow()

    /** What the MICROPHONE hears. Drives the composer's glow, never the face. */
    private val _micLevel = MutableStateFlow(0f)
    val micLevel: StateFlow<Float> = _micLevel.asStateFlow()

    /** What the mic has heard so far, for the composer. */
    private val _partialTranscript = MutableStateFlow<String?>(null)
    val partialTranscript: StateFlow<String?> = _partialTranscript.asStateFlow()

    /** The persona's colours per state; the face and the orb share them. */
    private val _palette = MutableStateFlow(PersonaPalette.fallback)
    val palette: StateFlow<PersonaPalette> = _palette.asStateFlow()

    /** Tools running this turn, from pipeline_stage. The status bar reads them. */
    private val _activeTools = MutableStateFlow<List<String>>(emptyList())
    val activeTools: StateFlow<List<String>> = _activeTools.asStateFlow()

    /** Non-null only for a procedural_face persona that sent its numbers. */
    private val _faceGeometry = MutableStateFlow<FaceGeometry?>(null)
    val faceGeometry: StateFlow<FaceGeometry?> = _faceGeometry.asStateFlow()

    /**
     * Captions and face cues parked by segment index, released when that
     * segment's audio is actually heard. The house pushes a whole reply in a
     * second or two while speaking it takes far longer, so these wait.
     */
    private val captionsBySegment = mutableMapOf<Int, String>()
    private val expressionsBySegment = mutableMapOf<Int, String>()

    /**
     * A reply the operator cut off. Late segments of a killed turn must not
     * reopen SPEAKING, which is what this flag prevents.
     */
    private var speechInterrupted = false

    private var listenJob: Job? = null

    init {
        // The handshake is the client's first word; without it the house
        // never sends client_info_ack and the turn machine never starts.
        socket.onOpen = { sendHandshake() }

        player?.onSegmentPlaying = { idx ->
            // removeValue: each cue is one-shot, as on iOS.
            captionsBySegment.remove(idx)?.let { _caption.value = it }
            expressionsBySegment.remove(idx)?.let {
                _faceCue.value = it to System.currentTimeMillis()
            }
        }
        player?.onAmplitude = { level ->
            _ttsAmplitude.value = if (_state.value == HearthState.SPEAKING) level else 0f
        }
        player?.onPlaybackComplete = {
            _caption.value = null
            if (_state.value == HearthState.SPEAKING) {
                _state.value = HearthState.IDLE
                // Post-speak listening window, unless the turn was cut off.
                if (!speechInterrupted) startListening(POST_SPEAK_WINDOW_MS)
            }
        }

        speech?.onPartialResult = { _partialTranscript.value = it }
        speech?.onSpeechStarted = {
            // The window was time to START talking. Someone did, so the
            // deadline is off and the silence timer owns the ending. Without
            // this the window was a hard cap on the whole utterance: a
            // question longer than five seconds was cut off mid-sentence and
            // the recognizer destroyed before it could return anything, which
            // read as the client ignoring the person.
            listenJob?.cancel()
            listenJob = null
        }
        speech?.onLevel = { level ->
            _micLevel.value = if (_state.value == HearthState.LISTENING) level else 0f
        }
        speech?.onFinalResult = { text ->
            _partialTranscript.value = null
            listenJob?.cancel()
            if (text.isBlank()) {
                // Heard nothing worth sending. Closing the window in silence
                // is correct after an automatic post-speak listen; the mic
                // simply stands down.
                _state.value = HearthState.IDLE
                _micLevel.value = 0f
            } else {
                appendMessage(ChatMessage(role = ChatMessage.Role.USER, text = text))
                Log.i(TAG, "sending transcript (${text.length} chars)")
                if (socket.sendClientTranscription(text)) {
                    _state.value = HearthState.THINKING
                } else {
                    reportUnsent()
                }
            }
        }
        speech?.onError = { message ->
            _partialTranscript.value = null
            listenJob?.cancel()
            _state.value = HearthState.IDLE
            appendMessage(ChatMessage(role = ChatMessage.Role.SYSTEM, text = message))
        }

        scope.launch {
            socket.events.collect { handle(it) }
        }
    }

    // ---- voice ------------------------------------------------------------

    /**
     * The mic button. During SPEAKING this is barge-in: the reply is cut off
     * and the turn becomes a listening one, exactly as on iOS.
     */
    fun toggleListening() {
        when (_state.value) {
            HearthState.SPEAKING -> {
                interruptSpeaking()
                startListening(INITIAL_WINDOW_MS)
            }

            HearthState.LISTENING -> {
                // A second tap commits what has been heard rather than
                // waiting out the silence timer.
                if (speech?.finishAndCommit() != true) {
                    listenJob?.cancel()
                    _state.value = HearthState.IDLE
                }
            }

            HearthState.IDLE -> startListening(INITIAL_WINDOW_MS)

            else -> Unit
        }
    }

    /**
     * Open the microphone. [windowMs] is how long to wait for someone to
     * START speaking, NOT a cap on how long they may speak: the first partial
     * or beginning-of-speech cancels it, and from then on the recognizer's
     * own silence timer ends the turn.
     */
    private fun startListening(windowMs: Long) {
        val stt = speech ?: return
        speechInterrupted = false
        _state.value = HearthState.LISTENING
        _partialTranscript.value = null
        Log.i(TAG, "window opens (${windowMs}ms to begin)")
        stt.start()
        listenJob?.cancel()
        listenJob = scope.launch {
            delay(windowMs)
            // Nobody started talking. Stand the mic down quietly rather than
            // holding it open forever.
            if (_state.value == HearthState.LISTENING && _partialTranscript.value == null) {
                Log.i(TAG, "window closed with nothing said")
                stt.stop()
                _state.value = HearthState.IDLE
                _micLevel.value = 0f
            }
        }
    }

    /**
     * Throw away what the mic has heard without sending it. The stage tap
     * does this while listening; the talk button SENDS, so the two gestures
     * are not the same and must not share a path.
     */
    fun discardListening() {
        if (_state.value != HearthState.LISTENING) return
        listenJob?.cancel()
        speech?.stop()
        _partialTranscript.value = null
        _micLevel.value = 0f
        _state.value = HearthState.IDLE
    }

    /** Cut off a reply in flight. */
    fun interruptSpeaking() {
        speechInterrupted = true
        player?.stop()
        captionsBySegment.clear()
        expressionsBySegment.clear()
        _caption.value = null
        _ttsAmplitude.value = 0f
        _micLevel.value = 0f
        _state.value = HearthState.IDLE
    }

    // ---- lifecycle --------------------------------------------------------

    /** Dial, unless there is no house yet: unconfigured must not retry-loop. */
    fun connect() {
        if (!config.isConfigured) {
            _state.value = HearthState.IDLE
            return
        }
        _state.value = HearthState.LOADING
        socket.connect()
    }

    fun enterBackground() {
        inBackground = true
        stopKeepalive()
        reconnectJob?.cancel()
        listenJob?.cancel()
        speech?.stop()
        player?.stop()
        socket.disconnect()
        _connected.value = false
        _ttsAmplitude.value = 0f
        _micLevel.value = 0f
    }

    fun enterForeground() {
        inBackground = false
        // Backoff resets on foreground: a person looking at the app is worth
        // dialing for immediately, whatever the last failure cost.
        reconnectAttempt = 0
        connect()
    }

    // ---- sending ----------------------------------------------------------

    fun sendText(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        appendMessage(ChatMessage(role = ChatMessage.Role.USER, text = trimmed))
        if (socket.sendTextQuery(trimmed)) {
            _state.value = HearthState.THINKING
        } else {
            // The socket was gone. Saying so beats sitting in THINKING
            // forever, and beats the silence that made a dropped follow-up
            // look like the client had ignored it.
            reportUnsent()
        }
    }

    /**
     * A turn that never reached the house. The socket drops for ordinary
     * reasons (the screen slept, the network moved) and the reconnect is
     * automatic, so this says what happened and invites the retry rather
     * than pretending to be thinking.
     */
    private fun reportUnsent() {
        _state.value = HearthState.IDLE
        _thinkingStage.value = null
        appendMessage(
            ChatMessage(
                role = ChatMessage.Role.SYSTEM,
                text = "That did not reach the house. Reconnecting; say it again.",
            )
        )
        if (!inBackground) scheduleReconnect()
    }

    fun switchPersona(name: String) = socket.switchPersona(name)

    fun newSession() = socket.newSession()

    /**
     * Reopen a past conversation. The house answers with session_ended (the
     * wipe) then session_resumed (the turns), so the transcript repaints
     * rather than appending to whatever was on screen.
     */
    fun resumeSession(sessionId: String) = socket.resumeSession(sessionId = sessionId)

    // ---- events -----------------------------------------------------------

    private fun handle(event: HearthEvent) {
        when (event) {
            is HearthEvent.ClientInfoAck -> {
                _connected.value = true
                _needsPairing.value = false
                reconnectAttempt = 0
                reconnectJob?.cancel()
                startKeepalive()
                _state.value = HearthState.IDLE
                socket.listPersonas()
            }

            is HearthEvent.AiResponse -> {
                _activeTools.value = emptyList()
                if (event.persona.isNotEmpty()) _personaName.value = event.persona
                appendMessage(ChatMessage(role = ChatMessage.Role.AI, text = event.text))
                _thinkingStage.value = null
                // SPEAKING is owned by the audio path, so a reply that will be
                // spoken leaves the state alone: tts_chunk_start moves it, and
                // playback completion moves it back.
                if (_state.value == HearthState.THINKING && player == null) {
                    _state.value = HearthState.IDLE
                }
            }

            is HearthEvent.ErrorMessage -> {
                appendMessage(ChatMessage(role = ChatMessage.Role.SYSTEM, text = event.text))
                _thinkingStage.value = null
                _state.value = HearthState.IDLE
            }

            is HearthEvent.TtsChunkStart -> {
                if (speechInterrupted) return
                _state.value = HearthState.SPEAKING
                _thinkingStage.value = null
                player?.startStream(event.sampleRate)
                player?.segmentStarted(event.segIdx)
                // Parked, not shown: both wait for this segment's audio.
                event.text?.let { captionsBySegment[event.segIdx] = it }
                event.expression?.let { expressionsBySegment[event.segIdx] = it }
            }

            is HearthEvent.PcmChunk -> {
                if (!speechInterrupted) player?.receivePcmChunk(event.bytes)
            }

            is HearthEvent.SpeakingComplete -> {
                if (!speechInterrupted) player?.markSpeakingComplete()
            }

            is HearthEvent.TtsError -> {
                appendMessage(ChatMessage(role = ChatMessage.Role.SYSTEM, text = event.text))
                player?.stop()
                _state.value = HearthState.IDLE
            }

            is HearthEvent.PipelineStage ->
                // Only the tools stage carries names worth showing; the rest
                // of the pipeline is the house's business.
                _activeTools.value = if (event.stage == "tools") event.tools else emptyList()

            is HearthEvent.StateUpdate -> handleStateUpdate(event.state, event.stage)

            is HearthEvent.PersonasList -> {
                _personas.value = event.names
                if (event.current.isNotEmpty()) {
                    _personaName.value = event.current
                    socket.getPersonaConfig(event.current)
                }
            }

            is HearthEvent.PersonaSwitched -> {
                _personaName.value = event.name
                socket.getPersonaConfig(event.name)
            }

            is HearthEvent.PersonaConfig -> {
                val visualization = event.config.optJSONObject("visualization")
                _palette.value = PersonaPalette.from(visualization)
                // A face config that arrived without its geometry falls back
                // to the orb, the same contract iOS uses: the two halves of "a
                // face" travel together or the stage draws what it knows.
                val type = visualization?.optString("type")
                _faceGeometry.value =
                    if (type == "procedural_face" && visualization.has("geometry")) {
                        FaceGeometry.from(visualization.optJSONObject("geometry"))
                    } else {
                        null
                    }
            }

            is HearthEvent.SessionEnded -> {
                _messages.value = emptyList()
                _state.value = HearthState.IDLE
            }

            is HearthEvent.SessionResumed -> {
                _messages.value = event.turns.flatMap { (user, assistant) ->
                    listOf(
                        ChatMessage(role = ChatMessage.Role.USER, text = user),
                        ChatMessage(role = ChatMessage.Role.AI, text = assistant),
                    )
                }
                _state.value = HearthState.IDLE
            }

            is HearthEvent.Closed -> {
                _connected.value = false
                stopKeepalive()
                if (event.authRejected) {
                    // Re-pair, do not retry: a refused token will be refused
                    // again, and a loop hides the real fix.
                    _needsPairing.value = true
                } else {
                    scheduleReconnect()
                }
            }

            is HearthEvent.Failure -> {
                _connected.value = false
                stopKeepalive()
                scheduleReconnect()
            }

            is HearthEvent.Unknown -> Log.i(TAG, "unhandled action '${event.action}'")

            // Audio, cards and the rest arrive in later phases; ignoring them
            // is correct today and the when stays exhaustive.
            else -> Unit
        }
    }

    /**
     * `thinking` from LISTENING stops the mic and enters THINKING; from
     * THINKING it only refreshes the label. It never moves out of IDLE or
     * SPEAKING, which is what keeps a late state_update from reopening a
     * finished turn.
     */
    private fun handleStateUpdate(state: String, stage: String?) {
        when (state) {
            "thinking" -> {
                _thinkingStage.value = stage
                if (_state.value == HearthState.LISTENING || _state.value == HearthState.IDLE) {
                    _state.value = HearthState.THINKING
                }
            }

            "idle" -> {
                _thinkingStage.value = null
                if (_state.value == HearthState.THINKING) _state.value = HearthState.IDLE
            }

            else -> Log.i(TAG, "unknown state '$state'")
        }
    }

    private fun appendMessage(message: ChatMessage) {
        _messages.value = _messages.value + message
    }

    // ---- keepalive and reconnect -----------------------------------------

    private fun startKeepalive() {
        stopKeepalive()
        keepaliveJob = scope.launch {
            while (isActive) {
                delay(KEEPALIVE_MS)
                if (!inBackground) socket.sendPing()
            }
        }
    }

    private fun stopKeepalive() {
        keepaliveJob?.cancel()
        keepaliveJob = null
    }

    /** Exponential backoff, capped. Suppressed in background or unpaired. */
    private fun scheduleReconnect() {
        if (inBackground || _needsPairing.value || !config.isConfigured) return
        reconnectJob?.cancel()
        val delayMs = min(MAX_BACKOFF_MS, 2.0.pow(reconnectAttempt) * 1000).toLong()
        reconnectAttempt++
        reconnectJob = scope.launch {
            delay(delayMs)
            if (!inBackground) socket.connect()
        }
    }

    /** Sent on connect: who this client is and what it can do. */
    fun deviceContext(): JSONObject = JSONObject()
        .put("timezone", TimeZone.getDefault().id)
        .put("locale", Locale.getDefault().toLanguageTag())
        .put("units", if (Locale.getDefault().country == "US") "imperial" else "metric")

    /** Called by the surface once the socket opens. */
    fun sendHandshake() = socket.sendClientInfo(deviceContext())

    companion object {
        private const val TAG = "ChatViewModel"
        private const val KEEPALIVE_MS = 20_000L
        private const val MAX_BACKOFF_MS = 30_000.0

        /** How long the mic stays open when a turn is started deliberately. */
        private const val INITIAL_WINDOW_MS = 15_000L

        /** The shorter window offered after the house finishes speaking. */
        private const val POST_SPEAK_WINDOW_MS = 5_000L
        const val DEFAULT_PERSONA = "Sulivan"
    }
}
