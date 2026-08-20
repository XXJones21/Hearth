//
//  ChatViewModel.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import AVFoundation
import Foundation
import Combine
import simd
import UIKit
import WidgetKit

public enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
}

/// One tap's worth of touch feedback, for a voice-first surface used without
/// looking at the screen: listening began, words went out, something failed.
@MainActor
enum Haptics {
    static func listenStart() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func commit() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

@MainActor
public class ChatViewModel: ObservableObject {
    /// Write-through: every change to the feed re-persists the active
    /// persona's transcript (debounced, system rows excluded). Restores
    /// happen in init and on persona swap, and go through the same variable,
    /// which keeps the store's copy and the screen's copy one thing.
    @Published public var messages: [ChatMessage] = [] {
        didSet { transcripts.scheduleSave(messages, persona: currentPersonaName) }
    }
    private let transcripts = TranscriptStore()
    @Published public var connectionStatus: ConnectionStatus = .disconnected {
        didSet { publishWidgetSnapshot(); tryStartPendingQuickTalk() }
    }
    /// Whether the server link is live. Starts optimistic (true) so the orb shows
    /// the normal LOADING look at launch; flips false only after an actual drop or
    /// a failed connect, which blacks the orb out until auto-reconnect revives it.
    @Published public var connectionAlive: Bool = true
    @Published public var isWaitingForResponse = false
    @Published public var currentPersonaName = "Sulivan"
    @Published public var thinkingText = ""
    @Published public var availablePersonas: [String] = []
    @Published public var selectedPersona: String = "Sulivan"
    /// The active persona's orb palette, data-driven from its server config.
    /// Warm HearthPalette fallback until the `persona_config` reply arrives.
    @Published public var personaPalette: PersonaPalette = .fallback
    /// Which renderer the active persona asks for. Sulivan stays on the 2D
    /// canvas; Selene and Sage mount RealityKit.
    @Published public var personaVisualization: PersonaVisualization = .fallback

    // Audio and state machine
    @Published public var hearthState: HearthState = .LOADING {
        didSet { publishWidgetSnapshot(); tryStartPendingQuickTalk() }
    }
    @Published public var isListening: Bool = false
    @Published public var liveTranscription: String = ""

    // Server state machine (Valar Phase B): THINKING sub-stage label
    // (transcribing / deciding / acting). Nil outside THINKING.
    @Published public var thinkingStage: String?
    /// Tools executing this turn, from `pipeline_stage`. Drives the house status
    /// bar ("Ringing the trading desk…"); empty when nothing is running.
    @Published public var activeTools: [String] = []
    /// The FULL response so far, as it ARRIVES — what the visionOS transcript
    /// card reads.
    @Published public var liveTranscript: String = ""
    /// The reply so far, in one growing block — the same shape the visionOS
    /// transcript card uses, so the two clients read alike. Sentences are
    /// appended when their audio is HEARD, not when it arrives, so the caption
    /// fills in step with the voice rather than racing ahead of it.
    @Published public var spokenSentence: String = ""
    /// Highest TTS segment already appended, so a repeated callback cannot
    /// append the same sentence twice.
    private var captionSegment = -1
    // Smoothed TTS playback amplitude 0..1 (drives Sulivan's speaking waveform).
    @Published public var ttsAmplitude: Float = 0
    /// Smoothed MICROPHONE level 0..1 while listening, so the listening pulse
    /// reads the actual mic instead of a timer. Quantized before publishing
    /// to keep the redraw rate civil.
    @Published public var micLevel: Float = 0
    /// A voice problem the user must SEE: permission denied, recognizer gone.
    /// The transcript rows still happen, but the transcript is collapsed by
    /// default -- this drives an alert with a Settings deep link.
    @Published public var voiceAlert: String?
    // Summary from the server's idle watchdog (session_ended).
    @Published public var sessionSummary: String?
    /// The house refused this phone's token (socket closed 1008). Reconnect is
    /// stopped -- retrying a revoked key is a loop that cannot win -- and the
    /// main view offers the way back: pair again with a fresh code.
    @Published public var needsPairing = false

    // Generative UI cards driven by the Valar gateway's ui_component messages.
    // Owned here; HearthMainView observes it via viewModel.cardStore.
    public let cardStore = CardStore()
    private var cardStoreObserver: AnyCancellable?

    // MARK: - visionOS immersive mode (caustics)
    // Whether the orb has switched from the volumetric window into the immersive
    // caustics space. Drives scene open/dismiss in SulivanVolumeView /
    // CausticsImmersiveView. Harmless on iOS.
    @Published public var isImmersiveActive = false
    /// 0..1 flourish progress while the pinch-and-hold builds toward the switch;
    /// mirrored onto RealityKitSceneManager.transitionProgress by the host.
    @Published public var transitionProgress: Float = 0
    /// The orb's transform captured in the `.immersiveSpace` coordinate frame at
    /// switch time, so the immersive scene can re-place it at the same physical
    /// spot. Set by the volume scene, consumed (and cleared) by the immersive scene.
    public var pendingOrbTransform: simd_float4x4?

    /// Ask Sulivan to speak a short cue line (e.g. when switching modes) in her
    /// real persona voice via the server `say` intent. No-op off the WebSocket path.
    /// A cue does NOT open a listening turn when it finishes (unlike a normal reply).
    public func speakCue(_ text: String) {
        cueInFlight = true
        webSocketClient?.sendSay(text)
    }
    private var cueInFlight = false

    // Settings
    @Published public var showSettings: Bool = false

    // WebSocket and audio
    private var webSocketClient: HearthWebSocketClient?
    private var thinkingTask: Task<Void, Never>?
    /// Held for its CONSTRUCTION: AudioSessionManager's init configures the
    /// process-wide AVAudioSession (.playAndRecord, the loudness mode fix)
    /// that every other audio path depends on. Nothing calls it afterward
    /// and that is fine -- the property looking unused is not a bug.
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
    /// Face expressions keyed the same way, and revealed the same way. A cue
    /// fired on arrival would play the sixth sentence's laugh over the first
    /// sentence's audio, which is the caption bug wearing a different face.
    private var expressionsBySegment: [Int: String] = [:]
    // Safety net for THINKING: the server said it is working, so the listen
    // timeout no longer applies — but if nothing arrives (server died
    // mid-pipeline), don't wedge the app in THINKING forever.
    // Raised from 90s on 2026-08-16. Every state_update refreshes this, but a
    // file sweep can spend minutes inside one tool phase and the harness only
    // emitted a stage on the FIRST round of each batch, so a 240s ingest
    // tripped the watchdog on a perfectly healthy turn: closeTurn() dropped to
    // IDLE, the composer was up, and the face sat in `listening` indefinitely.
    // The harness now sends a `working` heartbeat at every batch and every
    // fold; this is only the backstop for when it genuinely goes quiet.
    private var thinkingWatchdogTask: Task<Void, Never>?
    private let thinkingWatchdogTimeout: TimeInterval = 300.0

    // Safety net for SPEAKING. The state is normally closed by the sentinel
    // buffer draining (markSpeakingComplete -> onPlaybackComplete), but a
    // phone call, Siri, or a failed engine start kills the audio path with
    // the sentinel unplayed and NOTHING else can leave SPEAKING -- the mic,
    // the stage tap and the text field were all disabled by it. The tap
    // callback fires constantly while playback is alive (silence included),
    // so "the tap went quiet" is the stall signal.
    private var speakingWatchdogTask: Task<Void, Never>?
    private var lastSpeechActivity = Date()
    private let speakingStallTimeout: TimeInterval = 12.0
    /// The user (or a stall) cut this reply off. Later segments of the SAME
    /// reply keep arriving for a while; this mutes them so a chunk_start
    /// cannot flip the state back to SPEAKING after the interrupt.
    private var speechInterrupted = false

    // Audio-session interruptions (calls, Siri) and route losses (Bluetooth
    // walking away). Registered once; without these, an interruption
    // mid-reply wedges SPEAKING permanently -- see the watchdog above, which
    // stays as the net for whatever these do not catch.
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    /// choice_card answers (see ActionCards.swift).
    private var choiceObserver: NSObjectProtocol?
    /// Journal resume/topic requests (see SessionModels.swift).
    private var journalObservers: [NSObjectProtocol] = []

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

    public init() {
        // CardStore is a nested ObservableObject, so its changes do NOT reach
        // views observing this view model. Cards only ever appeared because a
        // turn also churns ttsAmplitude/hearthState and forced a redraw — a
        // card arriving while idle (a timer firing, an ambient clock) would sit
        // invisible until something else moved. Forward the signal.
        cardStoreObserver = cardStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // Yesterday's conversation is still here today. Restored before the
        // dial so the feed is not empty-then-flashing; the boot sequence's
        // personas_list re-answers the persona and the adopt guard below
        // keeps it from wiping what this just restored.
        messages = transcripts.load(persona: LastPersona.name)

        // One path, not two. Valinor chose here between an on-device MLX engine
        // and the socket; the on-device set did not come across, and the
        // product's thesis already answers the question it was asking -- the
        // inference runs on the user's own machine, which for a phone is the
        // house rather than the phone.
        setupWebSocket()
        dial()
        startKeepalive()
    }

    /// Application-level ping. Desktop pings every 5 seconds; without one the
    /// phone only discovers a half-open socket when the next turn fails.
    /// One loop for the process -- it reads whatever client is current, so a
    /// redial does not need to restart it.
    private var keepaliveTask: Task<Void, Never>?

    private func startKeepalive() {
        guard keepaliveTask == nil else { return }
        keepaliveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.connectionStatus == .connected, !self.inBackground {
                    _ = self.webSocketClient?.sendPing()
                }
            }
        }
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
        speechRecognitionManager?.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // The error used to be bound to `_`: a dropped recognizer or
                // revoked mic presented as "the button flicked back for no
                // reason". Say what happened.
                if self.hearthState == .LISTENING {
                    self.stopListening()
                    self.presentVoiceProblem(error)
                }
            }
        }
        speechRecognitionManager?.onLevel = { [weak self] level in
            // Already on the main queue. Quantized so the pulse follows the
            // mic without publishing 47 view updates a second.
            guard let self, self.hearthState == .LISTENING else { return }
            let stepped = (level * 10).rounded() / 10
            if abs(stepped - self.micLevel) >= 0.1 {
                self.micLevel = stepped
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
            guard let self else { return }
            // The face reacts on the sentence being HEARD -- segment 0
            // included. The server emits tts_chunk_start BEFORE synthesizing
            // the sentence and OmniVoice yields nothing until the whole
            // sentence is done, so arrival time ran seconds early: a reply
            // opening with [laughter] laughed at a silent face, then spoke
            // with a flat one. removeValue also makes each cue one-shot.
            // This runs BEFORE the caption guard on purpose: captionSegment
            // is seeded to 0 at arrival (the caption's own approximation),
            // which would otherwise swallow segment 0's cue here.
            if let expression = self.expressionsBySegment.removeValue(forKey: segIdx) {
                self.fireFaceCue(expression)
            }
            guard segIdx > self.captionSegment else { return }
            guard let sentence = self.sentencesBySegment[segIdx] else { return }
            self.captionSegment = segIdx
            self.spokenSentence = self.spokenSentence.isEmpty
                ? sentence
                : self.spokenSentence + " " + sentence
        }
        ttsStreamPlayer?.onAmplitude = { [weak self] amp in
            // Already on the main queue; drives Sulivan's speaking waveform.
            // The face reads the same number off FaceFeed instead of a second
            // @Published, so a 60fps mouth costs no view updates.
            FaceFeed.shared.speechLevel = Double(amp)
            self?.ttsAmplitude = amp
            // The tap firing at all is proof the audio path is alive; the
            // SPEAKING watchdog measures silence in these.
            self?.lastSpeechActivity = Date()
        }

        // Registered once for the process; setupAudioComponents runs again on
        // every redial and a second observer would double-handle each event.
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                MainActor.assumeIsolated {
                    self?.handleAudioPathLost(reason: "interrupted")
                }
            }
        }
        if routeChangeObserver == nil {
            routeChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
                else { return }
                MainActor.assumeIsolated {
                    self?.handleAudioPathLost(reason: "audio route lost")
                }
            }
        }
        if journalObservers.isEmpty {
            // The Journal's way back into a conversation (resume by diary
            // slug) and into a topic (a shelf book's name). The Journal tree
            // takes no view model by design; these are its two verbs.
            journalObservers.append(NotificationCenter.default.addObserver(
                forName: .hearthResumeSession, object: nil, queue: .main
            ) { [weak self] note in
                guard let slug = note.userInfo?["slug"] as? String, !slug.isEmpty else { return }
                MainActor.assumeIsolated { self?.resumeSession(slug: slug) }
            })
            journalObservers.append(NotificationCenter.default.addObserver(
                forName: .hearthTopicSession, object: nil, queue: .main
            ) { [weak self] note in
                guard let name = note.userInfo?["name"] as? String, !name.isEmpty else { return }
                MainActor.assumeIsolated { self?.startTopicSession(name: name) }
            })
        }
        if choiceObserver == nil {
            // A tapped choice_card chip is an answer: it goes out as the
            // user's turn, exactly as if they had typed the label (the
            // desktop feed's contract).
            choiceObserver = NotificationCenter.default.addObserver(
                forName: .hearthChoicePicked,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let label = note.userInfo?["label"] as? String, !label.isEmpty else { return }
                MainActor.assumeIsolated {
                    self?.sendMessage(label)
                }
            }
        }
    }

    /// A call, Siri, or a departed Bluetooth device took the audio path out
    /// from under whichever engine held it. Close the affected state cleanly
    /// now instead of leaving the watchdogs to discover the wedge later.
    private func handleAudioPathLost(reason: String) {
        switch hearthState {
        case .SPEAKING:
            print("[Audio] \(reason) mid-reply -- closing the speaking turn")
            interruptSpeaking()
        case .LISTENING:
            print("[Audio] \(reason) while listening -- stopping the mic")
            stopListening()
        default:
            break
        }
    }

    /// Hand the face a transient.
    ///
    /// `at` must be on the same clock the renderer ticks with
    /// (timeIntervalSinceReferenceDate in milliseconds) or the envelope is
    /// measured against a time that never arrives and the cue is silently
    /// inert -- which looks exactly like a harness that never sent one.
    private func fireFaceCue(_ name: String) {
        FaceFeed.shared.cue = FaceCue(
            name: name, at: Date.timeIntervalSinceReferenceDate * 1000)
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
                guard let self else { return }
                if segIdx == 0 {
                    // A new reply clears any interrupt from the previous one,
                    // and picks up the phone's voice prefs (Settings > Voice).
                    self.speechInterrupted = false
                    self.ttsStreamPlayer?.playbackVolume = ClientPrefs.effectiveVolume
                    self.ttsStreamPlayer?.startStream(sampleRate: sampleRate)
                }
                // An interrupted reply's later segments keep arriving for a
                // while; they must not restart audio or flip the state back.
                guard !self.speechInterrupted else { return }
                self.ttsStreamPlayer?.segmentStarted(segIdx)
                // Any non-speaking state -> SPEAKING when audio arrives, so a slow
                // server whose reply lands after the watchdog closed the turn still
                // shows Sulivan speaking (not stuck idle).
                if self.hearthState != .SPEAKING {
                    self.hearthState = .SPEAKING
                    self.stopThinkingAnimation()
                    self.thinkingStage = nil
                    self.cancelThinkingWatchdog()
                }
                self.armSpeakingWatchdog()
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
                guard let self else { return }
                print("[Persona] server list: \(names.joined(separator: ", "))")
                self.availablePersonas = names
                self.adoptPersona(currentPersona)
                // Settings > Personas > start with: ask the house for the
                // pinned persona once per connect. Desktop's rule verbatim --
                // only when it differs AND exists in the served list, so a
                // stale pin cannot strand the client on a persona the house
                // no longer serves.
                if let pin = ClientPrefs.startPersona,
                   pin.caseInsensitiveCompare(currentPersona) != .orderedSame,
                   names.contains(where: { $0.caseInsensitiveCompare(pin) == .orderedSame }) {
                    self.webSocketClient?.sendSwitchPersona(pin)
                }
            }
        }

        webSocketClient?.onPersonaSwitched = { [weak self] personaName in
            Task { @MainActor [weak self] in
                self?.adoptPersona(personaName)
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

        // The face's transient for this sentence, parked against its segment
        // and played when that segment is actually heard. Segment 0 is no
        // longer the exception: its tts_chunk_start arrives before synthesis
        // even starts, so firing on arrival played the opening reaction over
        // seconds of silence. The playback tap announces segment 0 the moment
        // its first audio renders, which is the honest "now".
        webSocketClient?.onFaceCue = { [weak self] name, segIdx in
            Task { @MainActor [weak self] in
                self?.expressionsBySegment[segIdx] = name
            }
        }

        webSocketClient?.onSessionEnded = { [weak self] reason, summary in
            Task { @MainActor [weak self] in
                self?.handleSessionEnded(reason: reason, summary: summary)
            }
        }

        webSocketClient?.onSessionResumed = { [weak self] slug, turns in
            Task { @MainActor [weak self] in
                self?.handleSessionResumed(slug: slug, turns: turns)
            }
        }

        webSocketClient?.onTopicSession = { [weak self] name in
            Task { @MainActor [weak self] in
                self?.addSystemMessage(name.isEmpty ? "New session" : "Session for \(name)")
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
                guard let self else { return }
                self.addSystemMessage("Error: \(error)")
                self.isWaitingForResponse = false
                self.activeTools = []
            }
        }

        webSocketClient?.onAuthRejected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.needsPairing = true
                self.cancelReconnect()
                self.addSystemMessage("The house refused this phone's key. Pair again with a fresh code.")
            }
        }

        webSocketClient?.onConnectionClosed = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectionStatus = .disconnected
                self.connectionAlive = false
                // A background teardown is deliberate; narrating it would
                // stamp "Connection closed" into the feed on every app
                // switch.
                if !self.inBackground {
                    self.addSystemMessage("Connection closed")
                }
                self.isWaitingForResponse = false
                // The tap dies with the socket; whatever level it last wrote
                // would otherwise hold the face's mouth open at idle.
                FaceFeed.shared.speechLevel = 0
                self.ttsAmplitude = 0
                self.stopListening()
                self.scheduleReconnect()
            }
        }

        // Log-only. This used to write "Server ping successful" into the
        // transcript, which with a real keepalive would narrate the feed
        // into noise every twenty seconds.
        webSocketClient?.onPongReceived = { _ in
            print("[WS] pong")
        }

        // Server-side partial_transcription and transcription callbacks are unused
        // with client-side STT. SpeechRecognitionManager handles partials locally.

        webSocketClient?.onSpeakingComplete = { [weak self] in
            self?.ttsStreamPlayer?.markSpeakingComplete()
        }

        webSocketClient?.onFastResponseReceived = { _, qualityScore, escalationTriggered in
            print("Fast response received: quality=\(qualityScore), escalation=\(escalationTriggered)")
        }

    }

    /// Dial the client `setupWebSocket` just built.
    ///
    /// Separate from the building, and that separation is the fix for a real
    /// defect: `setupWebSocket` used to end by dialling, and `redial()` calls
    /// `setupWebSocket()` and then dials again. Two overlapping `connect()`
    /// calls on one client means the second overwrites the first's
    /// `connectionContinuation`, so the first is never resumed -- the
    /// "SWIFT TASK CONTINUATION MISUSE: connect() leaked its continuation"
    /// in the first device log -- and both handshakes ack, so the house is
    /// asked for its persona list twice.
    ///
    /// It only showed on a real first run because that is the path that goes
    /// through `redial()`: launching with an address already saved dials once.
    private func dial() {
        // No client means no house was configured, so there is nothing to dial
        // and nothing to report failing.
        guard webSocketClient != nil else { return }
        Task { @MainActor in
            connectionStatus = .connecting
            hearthState = .LOADING
            addSystemMessage("Connecting to Hearth Server...")

            let connected = await webSocketClient?.connect() ?? false
            if !connected {
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
    public func redial() async {
        cancelReconnect()
        // A redial is how a re-pair or a new address takes effect; whatever
        // refusal came before it is history.
        needsPairing = false
        webSocketClient?.disconnect()
        webSocketClient = nil
        connectionStatus = .connecting
        connectionAlive = true
        addSystemMessage("Connecting to \(ServerConfig.shared.address)...")

        setupWebSocket()
        // Dialled here and NOT via dial(), because this caller wants the
        // result. Exactly one of the two paths connects; see dial().
        guard let client = webSocketClient else {
            // The address was cleared rather than changed. Forgetting a house
            // is not a failed connection, and must not start a reconnect loop
            // against nothing.
            connectionStatus = .disconnected
            hearthState = .IDLE
            return
        }
        if !(await client.connect()) {
            connectionStatus = .disconnected
            scheduleReconnect()
        }
    }

    /// Probe `GET /health` without touching the live socket, for the Test
    /// button. Returns the round trip and what the server said about itself.
    public struct HealthProbe {
        public let latencyMs: Int
        public let brainReady: Bool
        public let brainBackend: String
        public let persona: String
    }

    public static func probeHealth() async -> HealthProbe? {
        guard let url = ServerConfig.shared.url("/health") else { return nil }
        var request = URLRequest(url: url)
        ServerConfig.shared.authorize(&request)
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

    // MARK: - Scene lifecycle

    /// True between scenePhase background and the next foreground. Gates the
    /// reconnect loop and the keepalive: a suspended app cannot service
    /// either, and iOS kills the socket anyway -- better to close it on our
    /// own terms.
    private var inBackground = false

    /// scenePhase went to background: stop the engines deliberately instead
    /// of letting suspension kill them mid-frame, and close the socket so
    /// its death is not discovered as an "error" later.
    public func enterBackground() {
        inBackground = true
        if hearthState == .LISTENING { stopListening() }
        if hearthState == .SPEAKING { interruptSpeaking() }
        cancelReconnect()
        webSocketClient?.disconnect()
        connectionStatus = .disconnected
        connectionAlive = false
    }

    /// Back on screen: reset the backoff and dial NOW. Without this the
    /// person returned to a loop already at the 30 second cap and a dead
    /// talk button for the rest of it.
    public func enterForeground() {
        guard inBackground else { return }
        inBackground = false
        guard !needsPairing, ServerConfig.shared.isConfigured else { return }
        Task { await redial() }
    }

    // MARK: - History

    /// Settings > Conversation history. Clearing the active persona also
    /// empties the live feed; clearing all leaves other personas' feeds to
    /// be discovered empty on their next swap.
    public func clearHistory(allPersonas: Bool) {
        if allPersonas {
            transcripts.clearAll()
        } else {
            transcripts.clear(persona: currentPersonaName)
        }
        messages = []
    }

    // MARK: - Auto-reconnect

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    /// Reconnect with exponential backoff after an unexpected drop or a failed
    /// connect. The orb stays "dead" (connectionAlive == false) until a fresh
    /// client_info_ack revives it. One loop at a time; no-op in debug mode.
    private func scheduleReconnect() {
        // A refused token cannot be retried into working; the way back is the
        // pairing screen, and looping behind it would just keep earning 1008s.
        guard !needsPairing else { return }
        // Settings > Connection: someone debugging a server can stop the
        // client from dialing back. And a backgrounded phone does not dial;
        // the foreground kick does.
        guard ClientPrefs.autoReconnect, !inBackground else { return }
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

    public func toggleListening() {
        if hearthState == .LISTENING {
            // The button reads "tap to send", so a tap SENDS what has been
            // said so far -- the silence timeout's path exactly, just now.
            // (It used to discard, which surprised everyone who trusted the
            // label.) With nothing said yet it is a plain stop.
            if speechRecognitionManager?.finishAndCommit() != true {
                stopListening()
            }
            return
        }

        guard connectionStatus == .connected else {
            addSystemMessage("Connection not ready yet")
            return
        }

        // Barge-in: the mic during SPEAKING means "stop talking, listen to
        // me" -- cut the voice and fall through into a listening turn.
        if hearthState == .SPEAKING {
            interruptSpeaking()
        }

        guard hearthState == .IDLE else { return }

        isPostSpeakListen = false
        Task {
            do {
                try await speechRecognitionManager?.startRecognition()
                hearthState = .LISTENING
                isListening = true
                Haptics.listenStart()
                startResponseWaitTimer()
            } catch {
                presentVoiceProblem(error)
            }
        }
    }

    /// Throw the partial transcription away without sending it. The stage
    /// tap's meaning during LISTENING, now that the mic button commits.
    public func discardListening() {
        guard hearthState == .LISTENING else { return }
        stopListening()
    }

    /// A voice failure the user must SEE. The transcript row still happens
    /// (the record), but the transcript is collapsed by default -- denying
    /// the mic used to make the button look silently dead, with the
    /// explanation written to a pane nobody had open. `voiceAlert` drives an
    /// alert with a Settings deep link for the permission cases.
    private func presentVoiceProblem(_ error: Error) {
        Haptics.error()
        let message: String
        if let sttError = error as? SpeechRecognitionError {
            switch sttError {
            case .notAuthorized:
                message = "Hearth needs Speech Recognition permission to hear you. Turn it on in Settings."
            case .microphonePermissionDenied:
                message = "Hearth needs the microphone to hear you. Turn it on in Settings."
            case .recognizerUnavailable:
                message = "Speech recognition is not available on this device right now."
            case .audioEngineError(let underlying):
                message = "The microphone could not start: \(underlying.localizedDescription)"
            }
        } else {
            message = "Listening could not start: \(error.localizedDescription)"
        }
        addSystemMessage(message)
        voiceAlert = message
    }

    private func stopListening() {
        speechRecognitionManager?.stopRecognition()
        hearthState = .IDLE
        isListening = false
        isPostSpeakListen = false
        stopResponseWaitTimer()
        liveTranscription = ""
        micLevel = 0
    }

    private func handleClientTranscription(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stopListening()
            return
        }

        liveTranscription = ""
        micLevel = 0
        Haptics.commit()
        let userMessage = ChatMessage(text: text, type: .user)
        messages.append(userMessage)

        speechRecognitionManager?.stopRecognition()
        isListening = false
        stopResponseWaitTimer()

        // Fresh turn: next reply starts a new streaming bot line.
        streamingBotText = nil
        streamingMessageId = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        expressionsBySegment.removeAll()
        captionSegment = -1

        hearthState = .THINKING
        startThinkingAnimation()
        armThinkingWatchdog()
        webSocketClient?.sendClientTranscription(text)
    }

    /// Stop the voice mid-reply -- the user's interrupt, or the audio path
    /// dying. The stopped player emits amplitude 0 (closing the face's
    /// mouth), and later segments of this reply are muted so a still-arriving
    /// chunk_start cannot reopen the state.
    public func interruptSpeaking() {
        guard hearthState == .SPEAKING else { return }
        speechInterrupted = true
        cancelSpeakingWatchdog()
        ttsStreamPlayer?.stop()
        cueInFlight = false
        isListening = false
        hearthState = .IDLE
    }

    private func armSpeakingWatchdog() {
        guard speakingWatchdogTask == nil else { return }
        lastSpeechActivity = Date()
        speakingWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.hearthState == .SPEAKING else { continue }
                if Date().timeIntervalSince(self.lastSpeechActivity) > self.speakingStallTimeout {
                    print("[State] SPEAKING watchdog fired -- audio path went quiet")
                    self.addSystemMessage("Audio stalled mid-reply")
                    self.interruptSpeaking()
                    return
                }
            }
        }
    }

    private func cancelSpeakingWatchdog() {
        speakingWatchdogTask?.cancel()
        speakingWatchdogTask = nil
    }

    private func handleSpeakingComplete() {
        cancelSpeakingWatchdog()
        // An interrupted reply must not open the post-speak listening window:
        // the sentinel (or the stop itself) firing completion is the tail of
        // a turn the user already ended.
        if speechInterrupted {
            speechInterrupted = false
            isListening = false
            if hearthState == .SPEAKING { hearthState = .IDLE }
            return
        }
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

    public func sendMessage(_ text: String) {
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
        streamingMessageId = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        expressionsBySegment.removeAll()
        captionSegment = -1

        let sent = webSocketClient?.sendTextQuery(text) ?? false
        if sent {
            isWaitingForResponse = true
            startThinkingAnimation()
        }
    }

    public func sendPing() {
        _ = webSocketClient?.sendPing()
    }

    public func switchPersona(_ name: String) {
        guard name != selectedPersona else { return }
        webSocketClient?.sendSwitchPersona(name)
    }

    /// Adopt the persona the server says is active. The equality guard is
    /// desktop's boot-sequence fix carried over: personas_list and
    /// persona_config both name the current persona on every connect, and
    /// without the check the second arrival swaps the transcript it just
    /// restored. An actual change swaps the in-memory feed to the new
    /// persona's stored one -- it does NOT delete the old persona's file;
    /// that is what makes per-persona history real.
    private func adoptPersona(_ name: String) {
        guard !name.isEmpty else { return }
        let changed = currentPersonaName.caseInsensitiveCompare(name) != .orderedSame
        selectedPersona = name
        currentPersonaName = name
        LastPersona.name = name
        guard changed else { return }
        messages = transcripts.load(persona: name)
    }

    // setDebugMode is gone. It was public, had zero callers and no UI, wiped
    // the feed, and tore down the socket -- a loaded gun with no trigger. A
    // future dev pane can rebuild the simulation honestly if one is wanted.

    private func handleAIResponse(text: String, personaName: String) {
        stopThinkingAnimation()
        cancelThinkingWatchdog()
        thinkingStage = nil
        activeTools = []
        currentPersonaName = personaName
        // Finalize: if the reply streamed in sentence-by-sentence, replace that
        // line with the canonical full text; otherwise append it fresh.
        if streamingBotText != nil {
            replaceStreamingMessage(with: text, personaName: personaName)
            streamingBotText = nil
        } else {
            let aiMessage = ChatMessage(text: text, type: .ai, personaName: personaName)
            messages.append(aiMessage)
        }
        streamingMessageId = nil
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
    /// Seg 0 starts a fresh bot line; the rest extend it. A RE-emitted
    /// segment 0 (a restarted stream) restarts the line rather than opening a
    /// duplicate bubble.
    private func handleTtsSentence(_ sentence: String, segIdx: Int) {
        if streamingBotText == nil {
            streamingBotText = sentence
            let message = ChatMessage(text: sentence, type: .ai, personaName: currentPersonaName)
            streamingMessageId = message.id
            messages.append(message)
        } else if segIdx == 0 {
            streamingBotText = sentence
            replaceStreamingMessage(with: sentence, personaName: currentPersonaName)
        } else {
            let joined = (streamingBotText ?? "") + " " + sentence
            streamingBotText = joined
            replaceStreamingMessage(with: joined, personaName: currentPersonaName)
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
    public var stageCard: UiComponentDescriptor? {
        switch hearthState {
        case .THINKING, .SPEAKING: return cardStore.cards.last
        default: return nil
        }
    }

    /// The server persisted and cleared the session (idle watchdog, or an
    /// explicit new_session / resume_session). The feed is WIPED to match:
    /// the house has filed this conversation and no longer remembers it, and
    /// a screen that keeps showing it invites a follow-up with no context and
    /// nothing to explain why. Desktop wipes here for the same reason.
    /// resume_session emits this first, then session_resumed repaints.
    private func handleSessionEnded(reason: String, summary: String?) {
        print("[Session] ended (reason=\(reason)); summary=\(summary ?? "<none>")")
        sessionSummary = summary
        if summary?.isEmpty == false { sessionSummaryDate = Date() }
        streamingBotText = nil
        streamingMessageId = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        expressionsBySegment.removeAll()
        captionSegment = -1
        activeTools = []
        isWaitingForResponse = false
        FaceFeed.shared.speechLevel = 0
        ttsAmplitude = 0
        messages.removeAll()
        cardStore.clearAll()
        if hearthState == .THINKING {
            closeTurn()
        }
        // The house wrote a summary of what was just filed; this is where it
        // surfaces in-app (the widget already showed it).
        if let summary, !summary.isEmpty {
            addSystemMessage("Session filed: \(summary)")
        } else {
            addSystemMessage("New session")
        }
        publishWidgetSnapshot()
    }

    // MARK: - Session control (new / resume / topic)

    /// Every session verb shares one gate: a live socket, and no turn in
    /// flight. Desktop hard-blocks all three the same way -- ending or
    /// swapping the session under a reply that is still streaming would
    /// wipe a feed the server is actively writing to.
    private func canControlSession() -> Bool {
        guard connectionStatus == .connected else {
            addSystemMessage("Connection not ready yet")
            return false
        }
        guard !isWaitingForResponse, hearthState != .THINKING, hearthState != .SPEAKING else {
            addSystemMessage("Wait for the current turn to finish")
            return false
        }
        return true
    }

    /// Start fresh without closing the app. The house keeps what it wrote
    /// down; the live chat clears when `session_ended` comes back.
    public func startNewSession() {
        guard canControlSession() else { return }
        webSocketClient?.sendNewSession()
    }

    /// Resume a session record by id, or a journal entry by its diary slug.
    /// The server validates before ending the live chat, replies
    /// `session_ended` (wipe) then `session_resumed` (repaint), or an
    /// `error` when there is no transcript -- which surfaces through the
    /// normal error path without having wiped anything.
    public func resumeSession(recordId: String) {
        guard canControlSession() else { return }
        webSocketClient?.sendResumeSession(sessionId: recordId)
    }

    public func resumeSession(slug: String) {
        guard canControlSession() else { return }
        webSocketClient?.sendResumeSession(slug: slug)
    }

    /// A fresh chat that already knows what it is about: opened with an
    /// Engram topic hint so recall reads that project or life root first.
    public func startTopicSession(name: String) {
        guard canControlSession() else { return }
        webSocketClient?.sendStartTopicSession(name: name)
    }

    /// The resumed conversation, flattened in order. `session_ended` already
    /// wiped the feed; this repaints it.
    private func handleSessionResumed(slug: String, turns: [(user: String, assistant: String)]) {
        var rebuilt: [ChatMessage] = []
        for turn in turns {
            let user = turn.user.trimmingCharacters(in: .whitespacesAndNewlines)
            let assistant = turn.assistant.trimmingCharacters(in: .whitespacesAndNewlines)
            if !user.isEmpty { rebuilt.append(ChatMessage(text: user, type: .user)) }
            if !assistant.isEmpty {
                rebuilt.append(ChatMessage(text: assistant, type: .ai, personaName: currentPersonaName))
            }
        }
        messages = rebuilt
        addSystemMessage("Resumed session")
        publishWidgetSnapshot()
    }

    // MARK: - Widget snapshot (App Group)

    /// Timestamp of the latest session summary (for the SessionSummary widget).
    private var sessionSummaryDate: Date?

    /// Publish the glanceable state to the App Group and refresh the widgets.
    /// No-op at runtime if the App Group isn't configured.
    public func publishWidgetSnapshot() {
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
    public func handleQuickTalkDeepLink() {
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

    /// The streaming line, held by ID. Matching "the last .ai message"
    /// overwrote the wrong row whenever anything else appended after the
    /// streaming line mid-turn.
    private var streamingMessageId: UUID?

    private func replaceStreamingMessage(with text: String, personaName: String) {
        let replacement = ChatMessage(text: text, type: .ai, personaName: personaName)
        if let id = streamingMessageId,
           let idx = messages.lastIndex(where: { $0.id == id }) {
            messages[idx] = replacement
        } else {
            messages.append(replacement)
        }
        streamingMessageId = replacement.id
    }

    /// Return to IDLE, clearing all turn state. The speech level is zeroed
    /// explicitly: the amplitude tap is the only writer, and if it died with
    /// a non-zero value latched (socket drop mid-reply, watchdog close) the
    /// face kept a round open mouth at idle until the next reply's audio.
    private func closeTurn() {
        cancelThinkingWatchdog()
        cancelSpeakingWatchdog()
        stopThinkingAnimation()
        FaceFeed.shared.speechLevel = 0
        ttsAmplitude = 0
        thinkingStage = nil
        isWaitingForResponse = false
        streamingBotText = nil
        streamingMessageId = nil
        liveTranscript = ""
        spokenSentence = ""
        sentencesBySegment.removeAll()
        expressionsBySegment.removeAll()
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
        speakingWatchdogTask?.cancel()
        keepaliveTask?.cancel()
        responseWaitTimer?.invalidate()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let choiceObserver {
            NotificationCenter.default.removeObserver(choiceObserver)
        }
        for observer in journalObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        speechRecognitionManager?.stopRecognition()
        webSocketClient?.disconnect()
    }
}
