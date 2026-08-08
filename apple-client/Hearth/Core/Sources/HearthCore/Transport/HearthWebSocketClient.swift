//
//  HearthWebSocketClient.swift
//  Hearth
//
//  Created by Joshua Jones on 11/6/25.
//

import Foundation

class HearthWebSocketClient: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    
    private var connectionContinuation: CheckedContinuation<Bool, Never>?
    private var isConnected = false
    private var isWaitingForResponse = false
    /// Who an unnamed reply is attributed to.
    ///
    /// Valinor initialised this to "Valinor" and the blanket rename made it
    /// "Hearth", which is worse rather than better: the product's name is not a
    /// speaker, and a transcript row reading "Hearth said" is a bug the rename
    /// would have shipped quietly. The bundled persona is the honest default --
    /// it is who the client draws before any persona_config arrives.
    private var currentPersonaName = BundledPersona.sulivan?.name ?? "Sulivan"
    
    // Chunked audio reassembly state (for iOS legacy WAV path)
    private var pendingWavChunks: [Data] = []
    private var expectedWavChunks: Int = 0
    private var currentWavInfo: WavFileInfo?

    // PCM streaming state — active when server sends tts_chunk_start/tts_chunk_end
    private(set) var isInPCMStreamMode = false

    // Callbacks for UI integration (matching Desktop Client pattern)
    var onAIResponseReceived: ((String, String) -> Void)? // (text, personaName)
    var onClientInfoAckReceived: ((ClientInfoAck) -> Void)?
    var onErrorReceived: ((String) -> Void)?
    var onConnectionClosed: (() -> Void)?
    var onPongReceived: ((PongResponse) -> Void)?
    var onPlayWavFileReceived: ((WavFileInfo) -> Void)?
    var onEnvironmentModificationReceived: (([Any]) -> Void)?
    var onThinkingMessageReceived: ((String) -> Void)?
    var onFastResponseReceived: ((String, Double, Bool) -> Void)? // (text, qualityScore, escalationTriggered)
    var onWebSocketConnected: (() -> Void)?

    // Audio callbacks (matching Quest 3 pattern)
    var onTranscriptionReceived: ((String) -> Void)?
    var onAudioResponseReceived: ((Data) -> Void)?
    var onSpeakingComplete: (() -> Void)?
    var onPartialTranscriptionReceived: ((String, Bool) -> Void)?

    // PCM streaming callbacks (iOS streaming path)
    var onTTSChunkStart: ((Int, Double) -> Void)?
    var onPCMChunkReceived: ((Data) -> Void)?
    var onTTSChunkEnd: ((Int) -> Void)?

    // Persona callbacks
    var onPersonasListReceived: (([String], String) -> Void)?
    var onPersonaSwitched: ((String) -> Void)?
    /// (persona name, decoded orb palette) from a `persona_config` reply.
    var onPersonaConfigReceived: ((String, PersonaPalette) -> Void)?
    /// How the persona wants to be drawn (sphere_particle vs glb_animated).
    var onPersonaVisualizationReceived: ((String, PersonaVisualization) -> Void)?

    // Engram brain-sync callbacks
    var onEngramContextReceived: ((String, Bool) -> Void)?
    var onEngramSaved: ((String, Bool) -> Void)?

    // Generative UI + server state machine callbacks (Valar gateway)
    var onUiComponent: (([String: Any]) -> Void)? // raw ui_component payload
    var onStateUpdate: ((String, String?) -> Void)? // (state, stage)
    var onSessionEnded: ((String, String?) -> Void)? // (reason, summary)
    var onPipelineStage: ((String, [String]) -> Void)? // (stage, tool names)
    var onTtsSentence: ((String, Int) -> Void)? // (sentenceText, segIdx)
    
    private let serverURL: String
    
    init(serverURL: String) {
        self.serverURL = serverURL
        super.init()
    }
    
    func connect() async -> Bool {
        guard let url = URL(string: serverURL) else {
            onErrorReceived?("Invalid server URL: \(serverURL)")
            return false
        }
        
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages BEFORE sending client_info (critical for catching ack)
        receiveTask = Task {
            await receiveMessages()
        }
        
        // Send client capability information (audio-enabled for Phase 2)
        let clientInfo = ClientInfo.iosAudioEnabled()
        do {
            let jsonData = try JSONEncoder().encode(clientInfo)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            try await webSocketTask?.send(message)
            
            // Wait for client_info_ack with timeout (5 seconds)
            let connected = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    connectionContinuation = continuation
                    
                    // Set timeout
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        if !self.isConnected, let cont = self.connectionContinuation {
                            self.connectionContinuation = nil
                            cont.resume(returning: false)
                        }
                    }
                }
            } onCancel: {
                if let cont = connectionContinuation {
                    connectionContinuation = nil
                    cont.resume(returning: false)
                }
            }
            
            if connected && isConnected {
                return true
            } else {
                if !isConnected {
                    onErrorReceived?("Connection acknowledgment timeout after 5 seconds")
                }
                return false
            }
        } catch {
            onErrorReceived?("Failed to send client_info: \(error.localizedDescription)")
            return false
        }
    }
    
    private func receiveMessages() async {
        while let task = webSocketTask {
            do {
                let message = try await task.receive()
                
                switch message {
                case .string(let text):
                    await handleTextMessage(text)
                case .data(let data):
                    // Binary audio data (WAV files from server)
                    // Note: iOS WebSocket has 1MB message size limit
                    // Server should chunk large audio files into smaller messages
                    if data.count > 1_048_576 {
                        let errorMsg = "Received audio message too large (\(data.count) bytes). Server should chunk audio into smaller messages (max 1MB per message)."
                        print("ERROR: \(errorMsg)")
                        onErrorReceived?(errorMsg)
                        // Don't close connection - let server handle retry with smaller chunks
                    } else {
                        await handleBinaryMessage(data)
                    }
                @unknown default:
                    break
                }
            } catch {
                // Connection closed or error
                let errorDescription = error.localizedDescription
                print("WebSocket receive error: \(errorDescription)")
                
                // Check if it's a "Message too long" error
                if errorDescription.contains("Message too long") || errorDescription.contains("exceeds maximum") {
                    let errorMsg = "Server sent message exceeding iOS WebSocket limit (1MB). Server needs to chunk audio into smaller messages."
                    onErrorReceived?(errorMsg)
                }
                
                isConnected = false
                if let cont = connectionContinuation {
                    connectionContinuation = nil
                    cont.resume(returning: false)
                }
                onConnectionClosed?()
                break
            }
        }
    }
    
    private func handleTextMessage(_ text: String) async {
        // Try to parse as JSON first
        if let data = text.data(using: .utf8),
           let json = try? JSONDecoder().decode(ServerMessage.self, from: data) {
            
            let action = json.action
            
            switch action {
            case "ai_response":
                let responseText = json.text ?? ""
                let personaName = json.personaName ?? currentPersonaName
                currentPersonaName = personaName
                
                // Signal response received
                isWaitingForResponse = false
                
                onAIResponseReceived?(responseText, personaName)
                
            case "client_info_ack":
                isConnected = true
                if let cont = connectionContinuation {
                    connectionContinuation = nil
                    cont.resume(returning: true)
                }
                
                if let ackData = text.data(using: .utf8),
                   let ack = try? JSONDecoder().decode(ClientInfoAck.self, from: ackData) {
                    onClientInfoAckReceived?(ack)
                }
                
            case "error":
                let errorMsg = json.message ?? "Unknown error"
                isWaitingForResponse = false
                onErrorReceived?(errorMsg)
                
            case "pong":
                if let pongData = text.data(using: .utf8),
                   let pong = try? JSONDecoder().decode(PongResponse.self, from: pongData) {
                    onPongReceived?(pong)
                }
                
            case "play_wav_file":
                // Audio file metadata - binary data will follow
                if let wavData = text.data(using: .utf8),
                   let wav = try? JSONDecoder().decode(WavFileInfo.self, from: wavData) {
                    onPlayWavFileReceived?(wav)
                    
                    // Check if audio is chunked (iOS)
                    if let chunkCount = wav.wavChunks, chunkCount > 1 {
                        // Initialize chunk reassembly state
                        currentWavInfo = wav
                        expectedWavChunks = chunkCount
                        pendingWavChunks = []
                        print("Expecting \(chunkCount) audio chunks for reassembly")
                    } else {
                        // Single chunk or Quest 3 - clear any pending state
                        currentWavInfo = nil
                        expectedWavChunks = 0
                        pendingWavChunks = []
                    }
                    // Binary WAV data will arrive as separate binary message(s)
                }
                
            case "tts_chunk_start":
                // PCM streaming: server is about to stream float32 PCM chunks for a sentence
                isInPCMStreamMode = true
                let chunkInfo = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
                let segIdx = chunkInfo["seg_idx"] as? Int ?? 0
                let sampleRate = chunkInfo["sample_rate"] as? Double ?? 48000.0
                onTTSChunkStart?(segIdx, sampleRate)
                // Per-sentence transcript: the server sends each sentence's text on
                // its tts_chunk_start so the chat keeps pace with the voice.
                if let sentence = chunkInfo["text"] as? String, !sentence.isEmpty {
                    onTtsSentence?(sentence, segIdx)
                }

            case "tts_chunk_end":
                // PCM streaming: sentence stream closed (player continues seamlessly)
                let segIdx = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                    .flatMap { $0["seg_idx"] as? Int } ?? 0
                onTTSChunkEnd?(segIdx)

            case "speaking_complete":
                // Server signals all audio has been sent
                isInPCMStreamMode = false
                onSpeakingComplete?()
                
            case "partial_transcription":
                if let partialText = json.text {
                    let isFinal = json.isFinal ?? false
                    onPartialTranscriptionReceived?(partialText, isFinal)
                }

            case "transcription":
                if let transcriptionText = json.text {
                    onTranscriptionReceived?(transcriptionText)
                }
                
            case "personas_list":
                if let rawData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                   let rawPersonas = jsonObj["personas"] as? [Any],
                   let currentPersona = jsonObj["current_persona"] as? String {
                    // Valar sends a plain [String] (PersonaEngine.list_personas).
                    // This previously cast to [[String: Any]], which always
                    // failed, so the whole handler never fired and every client
                    // persona picker stayed empty. Accept objects too in case
                    // the payload ever grows richer.
                    let names: [String] = rawPersonas.compactMap { entry in
                        if let name = entry as? String { return name }
                        return (entry as? [String: Any])?["name"] as? String
                    }
                    onPersonasListReceived?(names, currentPersona)
                    // Pull the current persona's orb palette (server owns it).
                    sendGetPersonaConfig(currentPersona)
                }

            case "persona_switched":
                if let rawData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                   let personaName = jsonObj["persona_name"] as? String {
                    onPersonaSwitched?(personaName)
                    // Recolor the orb to the newly active persona.
                    sendGetPersonaConfig(personaName)
                }

            case "persona_config":
                if let rawData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                    let name = jsonObj["persona_name"] as? String ?? currentPersonaName
                    let config = jsonObj["config"] as? [String: Any]
                    let visualization = config?["visualization"] as? [String: Any]
                    let palette = PersonaPalette.from(visualization: visualization)
                    onPersonaVisualizationReceived?(name, PersonaVisualization.from(visualization: visualization, personaName: name))
                    onPersonaConfigReceived?(name, palette)
                }

            case "environment_modification":
                // Environment modifications - for future spatial phase
                if let envData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: envData) as? [String: Any],
                   let modifications = jsonObj["modifications"] as? [Any] {
                    onEnvironmentModificationReceived?(modifications)
                }
                
            case "fast_response":
                // Fast response from HRM evaluation (intermediate message)
                let responseText = json.text ?? ""
                let qualityScore = json.qualityScore ?? 0.0
                let escalationTriggered = json.escalationTriggered ?? false
                // Note: Do NOT clear isWaitingForResponse - this is an intermediate message
                onFastResponseReceived?(responseText, qualityScore, escalationTriggered)
                
            case "thinking_message":
                // Thinking message - for future thinking messages
                if let thinkingText = json.text {
                    onThinkingMessageReceived?(thinkingText)
                }
                
            case "tts_error":
                // TTS generation error - server signals that some audio failed to generate
                let errorMsg = json.message ?? "TTS generation incomplete"
                print("[TTS] Server reported TTS error: \(errorMsg)")
                onErrorReceived?("TTS Error: \(errorMsg)")

            case "engram_context":
                if let rawData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                    let project = jsonObj["project"] as? String ?? ""
                    let loaded = jsonObj["context_loaded"] as? Bool ?? false
                    onEngramContextReceived?(project, loaded)
                }

            case "engram_saved":
                if let rawData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                    let slug = jsonObj["thought_slug"] as? String ?? ""
                    let saved = jsonObj["saved"] as? Bool ?? false
                    onEngramSaved?(slug, saved)
                }

            case "ui_component":
                // Generative UI card (Valar): forward the raw payload; the card
                // store owns op (upsert/clear/clear_all), ttl, and type parsing.
                if let rawData = text.data(using: .utf8),
                   let jsonObj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                    onUiComponent?(jsonObj)
                }

            case "state_update":
                // Server-announced state machine transition (Valar Phase B).
                if let state = json.state {
                    onStateUpdate?(state, json.stage)
                }

            case "session_ended":
                // Server idle watchdog persisted + cleared the session.
                onSessionEnded?(json.reason ?? "unknown", json.summary)

            case "pipeline_stage":
                // Tool-activity breadcrumb (Valar 2026-07-31): stage/event plus
                // the tool names now running. Cosmetic on the wire — the house
                // status bar consumes it; until that lands, absorb it silently.
                if let jsonObj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                    let tools = (jsonObj["tools"] as? [String]) ?? []
                    onPipelineStage?(jsonObj["stage"] as? String ?? "", tools)
                }

            default:
                // Forward compatibility: an action this build does not know is
                // NOT a user-facing error (the server ships new ones ahead of
                // the clients). Log it and move on.
                print("[WS] unhandled server action: \(action)")
            }
        } else {
            // Plain text response - could be transcription or legacy AI response
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                // Check if this looks like a transcription (no JSON structure)
                // Transcriptions come as plain text from server
                if !trimmedText.hasPrefix("{") && !trimmedText.hasPrefix("[") {
                    // Likely a transcription - invoke transcription callback
                    onTranscriptionReceived?(trimmedText)
                } else {
                    // Legacy AI response
                    isWaitingForResponse = false
                    onAIResponseReceived?(trimmedText, currentPersonaName)
                }
            }
        }
    }
    
    private func handleBinaryMessage(_ data: Data) async {
        // In PCM streaming mode, binary messages are raw float32 audio chunks
        if isInPCMStreamMode {
            onPCMChunkReceived?(data)
            return
        }

        // Legacy WAV path (non-iOS clients or fallback)
        // Check if we're expecting chunked audio (iOS)
        if expectedWavChunks > 0 {
            // Add chunk to pending list
            pendingWavChunks.append(data)
            print("Received audio chunk \(pendingWavChunks.count)/\(expectedWavChunks) (\(data.count) bytes)")
            
            // Check if we've received all chunks
            if pendingWavChunks.count >= expectedWavChunks {
                // Reassemble chunks into complete WAV file
                var completeWavData = Data()
                for chunk in pendingWavChunks {
                    completeWavData.append(chunk)
                }
                
                print("Reassembled \(pendingWavChunks.count) chunks into \(completeWavData.count) bytes")
                
                // Clear chunking state. `currentWavInfo` was bound to a local
                // here and never read -- a leftover from when the reassembled
                // header was passed on.
                currentWavInfo = nil
                expectedWavChunks = 0
                pendingWavChunks = []
                
                // Send complete WAV file to callback
                onAudioResponseReceived?(completeWavData)
            }
            // Otherwise, wait for more chunks
        } else {
            // Single chunk (Quest 3 or small file) - send directly
            onAudioResponseReceived?(data)
        }
    }
    
    func sendAudioChunk(_ data: Data) -> Bool {
        guard let task = webSocketTask else {
            return false
        }
        
        guard isConnected else {
            return false
        }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        
        Task {
            do {
                try await task.send(message)
            } catch {
                onErrorReceived?("Error sending audio chunk: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    func sendTextQuery(_ text: String) -> Bool {
        guard let task = webSocketTask else {
            onErrorReceived?("Not connected to server")
            return false
        }
        
        guard isConnected else {
            onErrorReceived?("Connection not ready yet")
            return false
        }
        
        guard !isWaitingForResponse else {
            onErrorReceived?("Still waiting for previous response")
            return false
        }
        
        let command: [String: Any] = [
            "action": "text_query",
            "text": text
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            onErrorReceived?("Failed to encode text query")
            return false
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        
        Task {
            do {
                try await task.send(message)
                isWaitingForResponse = true
            } catch {
                isConnected = false
                isWaitingForResponse = false
                onErrorReceived?("Error sending message: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    func sendPing() -> Bool {
        guard let task = webSocketTask else {
            onErrorReceived?("Not connected to server")
            return false
        }
        
        let command: [String: Any] = [
            "action": "ping"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return false
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        
        Task {
            do {
                try await task.send(message)
            } catch {
                onErrorReceived?("Error sending ping: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    func sendListPersonas() {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = ["action": "list_personas"]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    func sendSwitchPersona(_ name: String) {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = ["action": "switch_persona", "persona_name": name]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    /// Ask the server for a persona's full public config (name, classification,
    /// visualization palette, voice). Reply arrives as `persona_config`.
    func sendGetPersonaConfig(_ name: String) {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = ["action": "get_persona_config", "persona_name": name]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    /// Phase 5: the user picked a past conversation in the generative session
    /// gallery. The server reads the Engram Thought for `slug` and resumes it per
    /// `mode` (continue | restore | add_context). Resume execution is server-side
    /// (deferred) — see tasks/visionos-phase5-sessions-handoff.md.
    func sendSessionResume(slug: String, mode: String) {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = [
            "action": "session_resume",
            "slug": slug,
            "mode": mode,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    /// Ask the server to have the active persona speak `text` verbatim in its
    /// real voice (used for short UI cues like the immersive-mode switch). The
    /// server runs TTS on the text and streams it back over the normal tts path.
    func sendSay(_ text: String) {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = ["action": "say", "text": text]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    /// TTS-player breadcrumbs. Valar has no `client_debug` action — sending it
    /// earned an `error` reply per event, which the timeline then rendered as a
    /// user-facing row. Keep these local.
    func sendDebug(_ message: String) {
        print("[TTS] \(message)")
    }

    func sendResetVAD() {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = ["action": "reset_vad"]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    func sendClientTranscription(_ text: String) {
        guard let task = webSocketTask, isConnected else { return }
        let command: [String: Any] = [
            "action": "client_transcription",
            "text": text,
            "source": "apple_speech"
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        isWaitingForResponse = true
        Task {
            try? await task.send(.string(jsonString))
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        isWaitingForResponse = false
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onWebSocketConnected?()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        isWaitingForResponse = false
        onConnectionClosed?()
    }
}
