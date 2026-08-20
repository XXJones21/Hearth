package com.hearth.core.viewmodel

import android.util.Log
import com.hearth.core.config.ServerConfig
import com.hearth.core.models.ChatMessage
import com.hearth.core.models.HearthState
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

    init {
        // The handshake is the client's first word; without it the house
        // never sends client_info_ack and the turn machine never starts.
        socket.onOpen = { sendHandshake() }
        scope.launch {
            socket.events.collect { handle(it) }
        }
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
        socket.disconnect()
        _connected.value = false
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
        _state.value = HearthState.THINKING
        socket.sendTextQuery(trimmed)
    }

    fun switchPersona(name: String) = socket.switchPersona(name)

    fun newSession() = socket.newSession()

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
                if (event.persona.isNotEmpty()) _personaName.value = event.persona
                appendMessage(ChatMessage(role = ChatMessage.Role.AI, text = event.text))
                _thinkingStage.value = null
                // SPEAKING is owned by the audio path; with no player wired
                // yet a text turn closes here.
                if (_state.value == HearthState.THINKING) _state.value = HearthState.IDLE
            }

            is HearthEvent.ErrorMessage -> {
                appendMessage(ChatMessage(role = ChatMessage.Role.SYSTEM, text = event.text))
                _thinkingStage.value = null
                _state.value = HearthState.IDLE
            }

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
        const val DEFAULT_PERSONA = "Sulivan"
    }
}
