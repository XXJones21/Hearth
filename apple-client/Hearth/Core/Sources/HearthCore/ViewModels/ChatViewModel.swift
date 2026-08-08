//
//  ChatViewModel.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation
import Combine
import simd
import UIKit
import WidgetKit

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected {
        didSet { publishWidgetSnapshot(); tryStartPendingQuickTalk() }
    }
    /// Whether the server link is live. Starts optimistic (true) so the orb shows
    /// the normal LOADING look at launch; flips false only after an actual drop or
    /// a failed connect, which blacks the orb out until auto-reconnect revives it.
    @Published var connectionAlive: Bool = true
    @Published var isWaitingForResponse = false
    @Published var currentPersonaName = "Sulivan"
    @Published var thinkingText = ""
    @Published var availablePersonas: [String] = []
    @Published var selectedPersona: String = "Sulivan"
    /// The active persona's orb palette, data-driven from its server config.
    /// Warm HearthPalette fallback until the `persona_config` reply arrives.
    @Published var personaPalette: PersonaPalette = .fallback
    /// Which renderer the active persona asks for. Sulivan stays on the 2D
    /// canvas; Selene and Sage mount RealityKit.
    @Published var personaVisualization: PersonaVisualization = .fallback

    // Audio and state machine
    @Published var hearthState: HearthState = .LOADING {
        didSet { publishWidgetSnapshot(); tryStartPendingQuickTalk() }
    }
    @Published var isListening: Bool = false
    @Published var liveTranscription: String = ""

    // Server state machine (Valar Phase B): THINKING sub-stage label
    // (transcribing / deciding / acting). Nil outside THINKING.
    @Published var thinkingStage: String?
    /// Tools executing this turn, from `pipeline_stage`. Drives the house status
    /// bar ("Ringing the trading desk…"); empty when nothing is running.
    @Published var activeTools: [String] = []
    /// The FULL response so far, as it ARRIVES — what the visionOS transcript
    /// card reads.
    @Published var liveTranscript: String = ""
    /// The reply so far, in one growing block — the same shape the visionOS
    /// transcript card uses, so the two clients read alike. Sentences are
    /// appended when their audio is HEARD, not when it arrives, so the caption
    /// fills in step with the voice rather than racing ahead of it.
    @Published var spokenSentence: String = ""
    /// Highest TTS segment already appended, so a repeated callback cannot
    /// append the same sentence twice.
    private var captionSegment = -1
    // Smoothed TTS playback amplitude 0..1 (drives Sulivan's speaking waveform).
    @Published var ttsAmplitude: Float = 0
    // Summary from the server's idle watchdog (session_ended).
    @Published var sessionSummary: String?

    // Generative UI cards driven by the Valar gateway's ui_component messages.
    // Owned here; HearthMainView observes it via viewModel.cardStore.
    let cardStore = CardStore()
    private var cardStoreObserver: AnyCancellable?

    // MARK: - visionOS immersive mode (caustics)
    // Whether the orb has switched from the volumetric window into the immersive
    // caustics space. Drives scene open/dismiss in SulivanVolumeView /
    // CausticsImmersiveView. Harmless on iOS.
    @Published var isImmersiveActive = false
    /// 0..1 flourish progress while the pinch-and-hold builds toward the switch;
    /// mirrored onto RealityKitSceneManager.transitionProgress by the host.
    @Published var transitionProgress: Float = 0
    /// The orb's transform captured in the `.immersiveSpace` coordinate frame at
    /// switch time, so the immersive scene can re-place it at the same physical
    /// spot. Set by the volume scene, consumed (and cleared) by the immersive scene.
    var pendingOrbTransform: simd_float4x4?

    /// Ask Sulivan to speak a short cue line (e.g. when switching modes) in her
    /// real persona voice via the server `say` intent. No-op off the WebSocket path.
    /// A cue does NOT open a listening turn when it finishes (unlike a normal reply).
    func speakCue(_ text: String) {
        cueInFlight = true
        webSocketClient?.sendSay(text)
    }
    private var cueInFlight = false

    // Settings and debug
    @Published var showSettings: Bool = false
    @Published var isDebugMode: Bool = false

    // WebSocket and audio
    private var webSocketClient: HearthWebSocketClient?
    private var thinkingTask: Task<Void, Never>?
    private var audioInputManager: AudioSessionManager?
    private var speechRecognitionManager: SpeechRecognitionManager?
    private var ttsStreamPlayer: TTSStreamPlayer?
    private var responseWaitTimer: Timer?
    private let initialListenTimeout: TimeInterval = 15.0
    private let postSpeakListenTimeout: TimeInterval = 5.0
    private var isPostSpeakListen = false

    // Per-sentence streaming reply accumulator (nil = no streaming line open).
    private var streamingBotText: String?
    /// Sentence text keyed by TTS segment index, so the karaoke caption can be
    /// revealed when that segment is actually heard rather than when it arrives.
    private var sentencesBySegment: [Int: String] = [:]
    // Safety net for THINKING: the server said it is working, so the listen
    // timeout no longer applies — but if nothing arrives (server died
    // mid-pipeline), don't wedge the app in THINKING forever.
    private var thinkingWatchdogTask: Task<Void, Never>?
    private let thinkingWatchdogTimeout: TimeInterval = 90.0

    /// The persona the house was last speaking as, so the name in the rail is
    /// right before the server confirms it rather than flashing the default.
    ///
    /// Valinor kept this in `PersonaStore`, which also cached persona configs
    /// and system prompts for the on-device engine. That engine did not come
    /// across, and one preference does not need a store: this is the whole of
    /// what the socket path ever used.
    private enum LastPersona {
        private static let key = "hearth.lastUsedPersona"
        static var name: String? {
            get { UserDefaults.standard.string(forKey: key) }
            set {
                guard let value = newValue, !value.isEmpty else {
                    UserDefaults.standard.removeObject(forKey: key)
                    return
                }
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    // MARK: - Init

    init() {
        // CardStore is a nested ObservableObject, so its changes do NOT reach
        // views observing this view model. Cards only ever appeared because a
        // turn also churns ttsAmplitude/hearthState and forced a redraw — a
        // card arriving while idle (a timer firing, an ambient clock) would sit
        // invisible until something else moved. Forward the signal.
        cardStoreObserver = cardStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // One path, not two. Valinor chose here between an on-device MLX engine
        // and the socket; the on-device set did not come across, and the
        // product's thesis already answers the question it was asking -- the
        // inference runs on the user's own machine, which for a phone is the
        // house rather than the phone.
        setupWebSocket()
    }

    // MARK: - Audio / Speech Setup

    private func setupAudioComponents() {
        audioInputManager = AudioSessionManager()

        speechRecognitionManager = SpeechRecognitionManager()
        speechRecognitionManager?.onPartialResult = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.liveTranscription = text
                self?.stopResponseWaitTimer()
            }
        }
        speechRecognitionManager?.onFinalResult = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.handleClientTranscription(text)
            }
        }
        speechRecognitionManager?.onError = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.hearthState == .LISTENING {
                    self.stopListening()
                }
            }
        }

        ttsStreamPlayer = TTSStreamPlayer()
        ttsStreamPlayer?.onPlaybackComplete = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleSpeakingComplete()
            }
        }
        ttsStreamPlayer?.onDebugEvent = { [weak self] msg in
            self?.webSocketClient?.sendDebug(msg)
        }
        ttsStreamPlayer?.onSegmentPlaying = { [weak self] segIdx in
            // Already on the main queue.
            guard let self,
                  segIdx > self.captionSegment,
                  let sentence = self.sentencesBySegment[segIdx] else { return }
            self.captionSegment = segIdx
            self.spokenSentence = self.spokenSentence.isEmpty
                ? sentence
                : self.spokenSentence + " " + sentence
        }
        ttsStreamPlayer?.onAmplitude = { [weak self] amp in
            // Already on the main queue; drives Sulivan's speaking waveform.
            self?.ttsAmplitude = amp
        }
    }

    // MARK: - WebSocket Setup

    private func setupWebSocket() {
        // No house configured yet: first run owns the screen until an address
        // is saved, so there is nothing to dial and nothing to report. Building
        // a client against a placeholder origin would spend the reconnect
        // backoff failing to reach a house the person has not named.
        guard let serverURL = ServerConfig.shared.serverURL else {
            connectionStatus = .disconnected
            hearthState = .IDLE
            return
        }
        webSocketClient = HearthWebSocketClient(serverURL: serverURL)

        // Seed the persona from the last one used so the UI shows the right name
        // before the server confirms (instead of falling back to a default).
        if let last = LastPersona.name {
            selectedPersona = last
            currentPersonaName = last
        }

        setupAudioComponents()

        // PCM streaming callbacks. The only audio path: Hearth serves one TTS
        // engine in one format, so there is no WAV-blob branch to choose against.
        webSocketClient?.onTTSChunkStart = { [weak self] segIdx, sampleRate in
            Task { @MainActor [weak self] in
                if segIdx == 0 {
                    self?.ttsStreamPlayer?.startStream(sampleRate: sampleRate)
                }
                self?.ttsStreamPlayer?.segmentStarted(segIdx)
                // Any non-speaking state -> SPEAKING when audio arrives, so a slow
                // server whose reply lands after the watchdog closed the turn still
                // shows Sulivan speaking (not stuck idle).
                if self?.hearthState != .SPEAKING {
                    self?.hearthState = .SPEAKING
                    self?.stopThinkingAnimation()
                    self?.thinkingStage = nil
                    self?.cancelThinkingWatchdog()
                }
            }
        }

        webSocketClient?.onPCMChunkReceived = { [weak self] data in
            self?.ttsStreamPlayer?.receivePCMChunk(data)
        }

        webSocketClient?.onTTSChunkEnd = { [weak self] segIdx in
            self?.ttsStreamPlayer?.segmentEnded(segIdx)
        }

        webSocketClient?.onAIResponseReceived = { [weak self] text, personaName in
            Task { @MainActor [weak self] in
                self?.handleAIResponse(text: text, personaName: personaName)
            }
        }

        webSocketClient?.onClientInfoAckReceived = { [weak self] ack in
            Task { @MainActor [weak self] in
                self?.connectionStatus = .connected
                self?.connectionAlive = true
                self?.cancelReconnect()
                self?.hearthState = .IDLE
                self?.addSystemMessage("Connected to Hearth Server")
                self?.webSocketClient?.sendListPersonas()
            }
        }

        webSocketClient?.onPersonasListReceived = { [weak self] names, currentPersona in
            Task { @MainActor [weak self] in
                print("[Persona] server list: \(names.joined(separator: ", "))")
                self?.availablePersonas = names
                self?.selectedPersona = currentPersona
                self?.currentPersonaName = currentPersona
                LastPersona.name = currentPersona
            }
        }

        webSocketClient?.onPersonaSwitched = { [weak self] personaName in
            Task { @MainActor [weak self] in
                self?.selectedPersona = personaName
                self?.currentPersonaName = personaName
                LastPersona.name = personaName
                self?.addSystemMessage("Switched to \(personaName)")
            }
        }

        webSocketClient?.onPersonaConfigReceived = { [weak self] personaName, palette in
            Task { @MainActor [weak self] in
                self?.personaPalette = palette
            }
        }

        // Both are log-only: the memory layer lives on the server and the client
        // has nothing to show for either event yet. No capture, so no warning
        // about a `self` that is written and never read.
        webSocketClient?.onEngramContextReceived = { project, loaded in
            if loaded {
                print("[Engram] Project context loaded: \(project)")
            }
        }

        webSocketClient?.onEngramSaved = { slug, saved in
            if saved {
                print("[Engram] Session saved: \(slug)")
            }
        }

        // Generative UI + server state machine (Valar gateway)
        webSocketClient?.onStateUpdate = { [weak self] state, stage in
            Task { @MainActor [weak self] in
                self?.handleStateUpdate(state: state, stage: stage)
            }
        }

        webSocketClient?.onPersonaVisualizationReceived = { [weak self] _, visualization in
            Task { @MainActor [weak self] in
                self?.personaVisualization = visualization
            }
        }

        webSocketClient?.onPipelineStage = { [weak self] stage, tools in
            Task { @MainActor [weak self] in
                guard stage == "tools" else { return }
                self?.activeTools = tools
            }
        }

        webSocketClient?.onTtsSentence = { [weak self] sentence, segIdx in
            Task { @MainActor [weak self] in
                self?.handleTtsSentence(sentence, segIdx: segIdx)
            }
        }

        webSocketClient?.onSessionEnded = { [weak self] reason, summary in
            Task { @MainActor [weak self] in
                self?.handleSessionEnded(reason: reason, summary: summary)
            }
        }

        webSocketClient?.onUiComponent = { [weak self] payload in
            // Route the raw payload into the card store (owns op/ttl/type parsing).
            Task { @MainActor [weak self] in
                self?.cardStore.apply(payload)
                self?.publishWidgetSnapshot()
            }
        }

        webSocketClient?.onErrorReceived = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, !self.isDebugMode else { return }
                self.addSystemMessage("Error: \(error)")
                self.isWaitingForResponse = false
                self.activeTools = []
            }
        }

        webSocketClient?.onConnectionClosed = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isDebugMode else { return }
                self.connectionStatus = .disconnected
                self.connectionAlive = false
                self.addSystemMessage("Connection closed")
                self.isWaitingForResponse = false
                self.stopListening()
                self.scheduleReconnect()
            }
        }

        webSocketClient?.onPongReceived = { [weak self] pong in
            Task { @MainActor [weak self] in
                self?.addSystemMessage("Server ping successful")
            }
        }

        // Server-side partial_transcription and transcription callbacks are unused
        // with client-side STT. SpeechRecognitionManager handles partials locally.

        webSocketClient?.onSpeakingComplete = { [weak self] in
            self?.ttsStreamPlayer?.markSpeakingComplete()
        }

        webSocketClient?.onFastResponseReceived = { _, qualityScore, escalationTriggered in
            print("Fast response received: quality=\(qualityScore), escalation=\(escalationTriggered)")
        }

        Task { @MainActor in
            connectionStatus = .connecting
            hearthState = .LOADING
            addSystemMessage("Connecting to Hearth Server...")

            let connected = await webSocketClient?.connect() ?? false
            if !connected && !isDebugMode {
                connectionStatus = .disconnected
                connectionAlive = false
                hearthState = .IDLE
                addSystemMessage("Failed to connect to server")
                scheduleReconnect()
            }
        }
    }

    // MARK: - Server address

    /// Apply a new server address and redial. The socket only reads the
    /// address when it DIALS, so saving alone changes nothing -- the old
    /// client has to be torn down and rebuilt against the new origin. Called
    /// by the Connection section after the user edits the field.
    func redial() async {
        cancelReconnect()
        webSocketClient?.disconnect()
        webSocketClient = nil
        connectionStatus = .connecting
        connectionAlive = true
        addSystemMessage("Connecting to \(ServerConfig.shared.address)...")

        setupWebSocket()
        let ok = await webSocketClient?.connect() ?? false
        if !ok {
            connectionStatus = .disconnected
            scheduleReconnect()
        }
    }

    /// Probe `GET /health` without touching the live socket, for the Test
    /// button. Returns the round trip and what the server said about itself.
    struct HealthProbe {
        let latencyMs: Int
        let brainReady: Bool
        let brainBackend: String
        let persona: String
    }

    static func probeHealth() async -> HealthProbe? {
        guard let url = ServerConfig.shared.url("/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return HealthProbe(
                latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                brainReady: json["brain_ready"] as? Bool ?? false,
                brainBackend: json["brain_backend"] as? String ?? "unknown",
                persona: json["current_persona"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    // MARK: - Auto-reconnect

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    /// Reconnect with exponential backoff after an unexpected drop or a failed
    /// connect. The orb stays "dead" (connectionAlive == false) until a fresh
    /// client_info_ack revives it. One loop at a time; no-op in debug mode.
    private func scheduleReconnect() {
        guard !isDebugMode else { return }
        guard reconnectTask == nil else { return }
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let delaySec = min(30.0, pow(2.0, Double(self.reconnectAttempt)))  // 1,2,4,...,30
                self.reconnectAttempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
                if Task.isCancelled { return }
                self.connectionStatus = .connecting
                let ok = await self.webSocketClient?.connect() ?? false
                if ok {
                    // onClientInfoAck flips connectionAlive/status and cancels us.
                    return
                }
                self.connectionStatus = .disconnected
            }
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
    }

    // MARK: - Audio / Listening

    func toggleListening() {
        if hearthState == .LISTENING {
            stopListening()
            return
        }

        guard connectionStatus == .connected else {
            addSystemMessage("Connection not ready yet")
            return
        }

        guard hearthState == .IDLE else { return }

        isPostSpeakListen = false
        Task {
            do {
                try await speechRecognitionManager?.startRecognition()
                hearthState = .LISTENING
                isListening = true
                startResponseWaitTimer()
            } catch {
                if let sttError = error as? SpeechRecognitionError {
                    switch sttError {
                    case .notAuthorized:
                        addSystemMessage("Speech recognition permission denied. Please enable in Settings.")
                    case .microphonePermissionDenied:
                        addSystemMessage("Microphone permission denied. Please enable in Settings.")
                    case .recognizerUnavailable:
                        addSystemMessage("Speech recognition is not available on this device.")
                    case .audioEngineError(let underlying):
                        addSystemMessage("Audio error: \(underlying.localizedDescription)")
                    }
                } else {
                    addSystemMessage("Failed to start speech recognition: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopListening() {
        speechRecognitionManager?.stopRecognition()
        hearthState = .IDLE
        isListening = false
        isPostSpeakListen = false
        stopResponseWaitTimer()
        liveTranscription = ""
    }

    private func handleClientTranscription(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stopListening()
            return
        }

        liveTranscription = ""
        let userMessage = ChatMessage(text: text, type: .user)
        messages.append(userMessage)

        speechRecognitionManager?.stopRecognition()
        isListening = false
        stopResponseWaitTimer()

        // Fresh turn: next reply starts a new streaming bot line.
        streamingBotText = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        captionSegment = -1

        if isDebugMode {
            hearthState = .IDLE
            addSystemMessage("[Debug] Transcription received -- no server to forward to")
        } else {
            hearthState = .THINKING
            startThinkingAnimation()
            armThinkingWatchdog()
            webSocketClient?.sendClientTranscription(text)
        }
    }

    private func handleSpeakingComplete() {
        liveTranscript = ""
        // The caption deliberately SURVIVES the turn: what Sulivan just said
        // stays readable on the stage until the next turn replaces it. The
        // fresh-turn paths clear it. Leaving captionSegment alone also means a
        // late playback callback cannot append onto a finished reply.
        // A spoken UI cue (say intent) just finished — return to IDLE instead of
        // opening a listening window the way a normal reply does.
        if cueInFlight {
            cueInFlight = false
            isListening = false
            hearthState = .IDLE
            return
        }
        isPostSpeakListen = true
        hearthState = .LISTENING
        isListening = true
        startResponseWaitTimer()

        Task {
            do {
                try await speechRecognitionManager?.startRecognition()
            } catch {
                addSystemMessage("Failed to restart speech recognition: \(error.localizedDescription)")
            }
        }
    }

    private func startResponseWaitTimer() {
        stopResponseWaitTimer()
        let timeout = isPostSpeakListen ? postSpeakListenTimeout : initialListenTimeout
        responseWaitTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hearthState == .LISTENING {
                    self.stopListening()
                }
            }
        }
    }

    private func stopResponseWaitTimer() {
        responseWaitTimer?.invalidate()
        responseWaitTimer = nil
    }

    // MARK: - Text Messaging

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard connectionStatus == .connected else {
            addSystemMessage("Connection not ready yet")
            return
        }
        guard !isWaitingForResponse else {
            addSystemMessage("Still waiting for previous response...")
            return
        }

        let userMessage = ChatMessage(text: text, type: .user)
        messages.append(userMessage)

        // Fresh turn: next reply starts a new streaming bot line.
        streamingBotText = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        captionSegment = -1

        if isDebugMode {
            addSystemMessage("[Debug] Message received -- no server to forward to")
            return
        }

        let sent = webSocketClient?.sendTextQuery(text) ?? false
        if sent {
            isWaitingForResponse = true
            startThinkingAnimation()
        }
    }

    func sendPing() {
        _ = webSocketClient?.sendPing()
    }

    func switchPersona(_ name: String) {
        guard name != selectedPersona else { return }
        webSocketClient?.sendSwitchPersona(name)
    }

    func setDebugMode(_ enabled: Bool) {
        isDebugMode = enabled
        if enabled {
            cancelReconnect()
            webSocketClient?.disconnect()
            webSocketClient = nil
            connectionStatus = .connected
            connectionAlive = true
            hearthState = .IDLE
            messages.removeAll()
            addSystemMessage("Debug mode enabled -- server connection simulated")
        } else {
            connectionStatus = .disconnected
            connectionAlive = true   // optimistic; setupWebSocket reconnects
            hearthState = .LOADING
            messages.removeAll()
            addSystemMessage("Debug mode disabled -- reconnecting...")
            setupWebSocket()
        }
    }

    private func handleAIResponse(text: String, personaName: String) {
        stopThinkingAnimation()
        cancelThinkingWatchdog()
        thinkingStage = nil
        activeTools = []
        currentPersonaName = personaName
        // Finalize: if the reply streamed in sentence-by-sentence, replace that
        // line with the canonical full text; otherwise append it fresh.
        if streamingBotText != nil {
            replaceLastAiMessage(with: text, personaName: personaName)
            streamingBotText = nil
        } else {
            let aiMessage = ChatMessage(text: text, type: .ai, personaName: personaName)
            messages.append(aiMessage)
        }
        isWaitingForResponse = false
    }

    // MARK: - Server State Machine + Generative UI (Valar)

    /// The server announced its own transition (Phase B vocabulary): "thinking"
    /// with stages transcribing -> deciding -> acting, or "idle" when a turn
    /// died server-side without output. Clients follow instead of free-running
    /// timers; unknown states are ignored (additive vocabulary).
    private func handleStateUpdate(state: String, stage: String?) {
        switch state {
        case "thinking":
            switch hearthState {
            case .LISTENING:
                // Leave LISTENING immediately instead of the listen timeout
                // firing into IDLE mid-pipeline.
                speechRecognitionManager?.stopRecognition()
                isListening = false
                stopResponseWaitTimer()
                hearthState = .THINKING
                thinkingStage = stage
                startThinkingAnimation()
                armThinkingWatchdog()
            case .THINKING:
                // Later stage events refresh the label + watchdog.
                thinkingStage = stage
                armThinkingWatchdog()
            default:
                break // never moves us out of IDLE/SPEAKING on its own
            }
        case "idle":
            // A turn died server-side without output (no_speech / cancelled /
            // error): close the turn now instead of waiting out the watchdog.
            if hearthState == .THINKING {
                closeTurn()
            } else if isWaitingForResponse {
                // Text turn that never left IDLE: stop the waiting indicator.
                stopThinkingAnimation()
                isWaitingForResponse = false
            }
        default:
            break
        }
    }

    /// Stream the assistant text in step with speech: the server sends each
    /// sentence on its tts_chunk_start, so the chat keeps pace with the voice.
    /// Seg 0 starts a fresh bot line; the rest extend it.
    private func handleTtsSentence(_ sentence: String, segIdx: Int) {
        if segIdx == 0 || streamingBotText == nil {
            streamingBotText = sentence
            messages.append(ChatMessage(text: sentence, type: .ai, personaName: currentPersonaName))
        } else {
            let joined = (streamingBotText ?? "") + " " + sentence
            streamingBotText = joined
            replaceLastAiMessage(with: joined, personaName: currentPersonaName)
        }
        // The visionOS card shows the FULL response so far.
        liveTranscript = streamingBotText ?? sentence

        // The iPhone karaoke caption is driven by PLAYBACK, not arrival: the
        // server pushes every segment within a second or two while speaking
        // them takes far longer, so setting the caption here rapid-fired the
        // whole reply before the first sentence was audible. Park the text
        // against its segment and let onSegmentPlaying reveal it in time.
        sentencesBySegment[segIdx] = sentence
        // Segment 0 is the exception: its audio begins essentially now, and
        // waiting for the first tap would leave the stage blank at the open.
        if segIdx == 0 {
            spokenSentence = sentence
            captionSegment = 0
        }
    }

    /// The card this turn produced, surfaced on the persona stage while the turn
    /// is live. It is the same instance the feed holds — the stage is a spotlight
    /// on the newest card, not a second copy, and it releases when the turn ends.
    var stageCard: UiComponentDescriptor? {
        switch hearthState {
        case .THINKING, .SPEAKING: return cardStore.cards.last
        default: return nil
        }
    }

    /// The server's idle watchdog persisted + cleared the session. The next
    /// turn starts fresh; the transcript is retained as history.
    private func handleSessionEnded(reason: String, summary: String?) {
        print("[Session] ended (reason=\(reason)); summary=\(summary ?? "<none>")")
        sessionSummary = summary
        if summary?.isEmpty == false { sessionSummaryDate = Date() }
        streamingBotText = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        captionSegment = -1
        activeTools = []
        publishWidgetSnapshot()
    }

    // MARK: - Sessions gallery (Phase 5, generative UI)

    /// The user tapped a past-conversation card in the `session_gallery`. Send the
    /// pick to the server (which resumes it per `mode`) and dismiss the gallery.
    /// Resume execution is server-side and deferred — see the Phase 5 handoff doc.
    func selectSession(slug: String, mode: String) {
        print("[Session] select slug=\(slug) mode=\(mode)")
        webSocketClient?.sendSessionResume(slug: slug, mode: mode)
        cardStore.dismissType(UiComponentDescriptor.typeSessionGallery)
        addSystemMessage("\(mode.capitalized): \(slug)")
    }

    #if DEBUG
    /// Inject a sample `session_gallery` through the live ui_component path so the
    /// gallery can be verified on device before the server `recall_sessions` tool
    /// exists. No live trigger is wired; call this from a temporary affordance
    /// when re-testing the gallery layout.
    ///
    /// The fixtures are deliberately invented. Valinor seeded this with six real
    /// sessions carrying real dates and real summaries, which meant every build
    /// shipped a stranger a week of somebody's actual work. Two obvious
    /// placeholders exercise the same layout -- one long summary, one short --
    /// without carrying anyone's history into the binary.
    func debugShowSampleGallery() {
        let payload: [String: Any] = [
            "type": UiComponentDescriptor.typeSessionGallery,
            "op": "upsert",
            "props": [
                "mode": "continue",
                "prompt": "Recent conversations",
                "sessions": [
                    ["slug": "sample-session-one", "title": "Sample session one",
                     "date": "2026-01-02", "persona": "Sulivan", "project": "sample",
                     "summary": "A placeholder summary, long enough to wrap onto a second line so the card's text layout is exercised at something like a realistic width."],
                    ["slug": "sample-session-two", "title": "Sample session two",
                     "date": "2026-01-01", "persona": "Sulivan", "project": "sample",
                     "summary": "A short placeholder summary."],
                ],
            ],
        ]
        cardStore.apply(payload)
    }
    #endif

    // MARK: - Widget snapshot (App Group)

    /// Timestamp of the latest session summary (for the SessionSummary widget).
    private var sessionSummaryDate: Date?

    /// Publish the glanceable state to the App Group and refresh the widgets.
    /// No-op at runtime if the App Group isn't configured.
    func publishWidgetSnapshot() {
        let snapshot = HearthSnapshot(
            personaName: currentPersonaName,
            connected: connectionStatus == .connected,
            state: Self.stateString(hearthState),
            sessionSummary: sessionSummary,
            sessionSummaryDate: sessionSummaryDate,
            cards: widgetCardSummaries(),
            updatedAt: Date()
        )
        SharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Flatten the live generative-UI cards into compact, widget-renderable
    /// summaries for the persona widget's carousel.
    private func widgetCardSummaries() -> [HearthSnapshot.CardSummary] {
        var out: [HearthSnapshot.CardSummary] = []
        // The store is transcript history (up to 40); the widget carousel only
        // wants what just happened, so summarise the newest handful.
        for card in cardStore.cards.suffix(6) {
            switch card.type {
            case UiComponentDescriptor.typeWeatherCard:
                let isTomorrow = card.str("day").hasPrefix("tomorrow")
                let lead = isTomorrow ? card.str("high") : card.str("temp")
                out.append(.init(type: card.type, symbol: "cloud.sun.fill",
                                 title: lead.isEmpty ? card.str("condition") : lead,
                                 subtitle: card.str("condition"),
                                 detail: card.str("location"), fireAt: nil))
            case UiComponentDescriptor.typeTimerCard:
                for obj in card.objList("timers") {
                    let epoch = obj.optInt("fire_at", fallback: 0)
                    guard epoch > 0 else { continue }
                    out.append(.init(type: card.type, symbol: "timer",
                                     title: obj.optString("label", fallback: "Timer"),
                                     subtitle: "", detail: "",
                                     fireAt: Date(timeIntervalSince1970: TimeInterval(epoch))))
                }
            case UiComponentDescriptor.typeBriefText:
                out.append(.init(type: card.type, symbol: "text.alignleft",
                                 title: card.str("title", fallback: "Brief"),
                                 subtitle: "", detail: card.str("body"), fireAt: nil))
            case UiComponentDescriptor.typeCaptions:
                let text = card.str("text")
                if !text.isEmpty {
                    out.append(.init(type: card.type, symbol: "captions.bubble.fill",
                                     title: "Now", subtitle: text, detail: "", fireAt: nil))
                }
            case UiComponentDescriptor.typeGeneratedView:
                let firstText = card.objList("sections")
                    .first { $0.optString("kind") == "text" }?
                    .optString("body") ?? ""
                out.append(.init(type: card.type, symbol: "rectangle.3.group.fill",
                                 title: card.str("title", fallback: "Info"),
                                 subtitle: "", detail: firstText, fireAt: nil))
            default:
                continue // clock / slideshow not surfaced in the widget
            }
        }
        return out
    }

    // MARK: - QuickTalk widget deep link (hearth://talk)

    private var pendingQuickTalk = false

    /// Called from the QuickTalk widget deep link. Starts a listening turn now
    /// if possible, else once we're connected and idle.
    func handleQuickTalkDeepLink() {
        pendingQuickTalk = true
        tryStartPendingQuickTalk()
    }

    private func tryStartPendingQuickTalk() {
        guard pendingQuickTalk,
              connectionStatus == .connected,
              hearthState == .IDLE else { return }
        pendingQuickTalk = false
        toggleListening()
    }

    private static func stateString(_ state: HearthState) -> String {
        switch state {
        case .LOADING:   return "loading"
        case .IDLE:      return "idle"
        case .LISTENING: return "listening"
        case .THINKING:  return "thinking"
        case .SPEAKING:  return "speaking"
        }
    }

    private func replaceLastAiMessage(with text: String, personaName: String) {
        if let idx = messages.lastIndex(where: { $0.type == .ai }) {
            messages[idx] = ChatMessage(text: text, type: .ai, personaName: personaName)
        } else {
            messages.append(ChatMessage(text: text, type: .ai, personaName: personaName))
        }
    }

    /// Return to IDLE, clearing all turn state.
    private func closeTurn() {
        cancelThinkingWatchdog()
        stopThinkingAnimation()
        thinkingStage = nil
        isWaitingForResponse = false
        streamingBotText = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        captionSegment = -1
        isListening = false
        hearthState = .IDLE
    }

    private func armThinkingWatchdog() {
        thinkingWatchdogTask?.cancel()
        thinkingWatchdogTask = Task { @MainActor [weak self] in
            guard let timeout = self?.thinkingWatchdogTimeout else { return }
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.hearthState == .THINKING {
                print("[State] THINKING watchdog fired -- no response from server")
                self.addSystemMessage("Server stopped responding mid-turn")
                self.closeTurn()
            }
        }
    }

    private func cancelThinkingWatchdog() {
        thinkingWatchdogTask?.cancel()
        thinkingWatchdogTask = nil
    }

    private func addSystemMessage(_ text: String) {
        let systemMessage = ChatMessage(text: text, type: .system)
        messages.append(systemMessage)
    }

    // MARK: - Thinking Animation

    private func startThinkingAnimation() {
        stopThinkingAnimation()
        let dots = ["", ".", "..", "..."]
        thinkingTask = Task { @MainActor [weak self] in
            var dotIndex = 0
            while !Task.isCancelled {
                self?.thinkingText = "\(self?.currentPersonaName ?? "Hearth") is thinking\(dots[dotIndex])"
                dotIndex = (dotIndex + 1) % dots.count
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopThinkingAnimation() {
        thinkingTask?.cancel()
        thinkingTask = nil
        thinkingText = ""
    }

    // MARK: - Cleanup

    deinit {
        thinkingTask?.cancel()
        thinkingWatchdogTask?.cancel()
        responseWaitTimer?.invalidate()
        speechRecognitionManager?.stopRecognition()
        webSocketClient?.disconnect()
    }
}
