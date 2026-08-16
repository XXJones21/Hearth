//
//  SpeechRecognitionManager.swift
//  Hearth
//
//  On-device speech-to-text using Apple's SFSpeechRecognizer.
//  Replaces server-side Whisper STT for the iOS client, eliminating
//  the audio streaming round-trip.
//

import AVFoundation
import Foundation
import Speech

enum SpeechRecognitionError: Error {
    case recognizerUnavailable
    case notAuthorized
    case microphonePermissionDenied
    case audioEngineError(Error)
}

class SpeechRecognitionManager: NSObject, SFSpeechRecognizerDelegate {
    /// Optional, not force-unwrapped: `SFSpeechRecognizer(locale:)` returns nil
    /// on a device whose locale set does not include en-US, and this manager
    /// is built during ChatViewModel construction -- a crash here is a crash
    /// on launch. A nil recognizer surfaces as recognizerUnavailable instead.
    private let speechRecognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRunning = false

    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.5
    private var lastPartialText: String = ""
    private var hasFiredFinal = false

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechRecognizer?.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Recognition

    func startRecognition() async throws {
        guard !isRunning else { return }

        guard let speechRecognizer else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // Authorization FIRST. `isAvailable` is commonly false until the
        // recognizer is authorized, so checking it first threw
        // recognizerUnavailable ("not available on this device") on a genuine
        // first run, before the permission dialog ever appeared.
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            let granted = await requestAuthorization()
            guard granted else { throw SpeechRecognitionError.notAuthorized }
        } else if authStatus != .authorized {
            throw SpeechRecognitionError.notAuthorized
        }

        guard speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        let audioApp = AVAudioApplication.shared
        if audioApp.recordPermission == .undetermined {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { throw SpeechRecognitionError.microphonePermissionDenied }
        } else if audioApp.recordPermission == .denied {
            throw SpeechRecognitionError.microphonePermissionDenied
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        self.recognitionRequest = request

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // A zero-rate format happens mid Bluetooth handoff or after a failed
        // session activation, and installTap with it throws the uncatchable
        // ObjC "format.sampleRate == hwFormat.sampleRate" exception -- the
        // do/catch below only guards engine.start(). Refuse it as an error
        // the caller can present.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            cleanup()
            throw SpeechRecognitionError.audioEngineError(NSError(
                domain: "SpeechRecognitionManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "the microphone route reported no usable format"]
            ))
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        lastPartialText = ""
        hasFiredFinal = false

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString

                if result.isFinal {
                    self.cancelSilenceTimer()
                    if !self.hasFiredFinal {
                        self.hasFiredFinal = true
                        self.onFinalResult?(text)
                    }
                } else {
                    self.lastPartialText = text
                    self.onPartialResult?(text)
                    self.resetSilenceTimer()
                }
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203 {
                    return
                }
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    return
                }
                self.cancelSilenceTimer()
                self.onError?(error)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            print("[SpeechRecognitionManager] Recognition started (on-device)")
        } catch {
            cleanup()
            throw SpeechRecognitionError.audioEngineError(error)
        }
    }

    func stopRecognition() {
        guard isRunning else { return }
        cancelSilenceTimer()
        recognitionRequest?.endAudio()
        cleanup()
        print("[SpeechRecognitionManager] Recognition stopped")
    }

    private func cleanup() {
        cancelSilenceTimer()
        if let inputNode = audioEngine?.inputNode {
            inputNode.removeTap(onBus: 0)
        }
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRunning = false
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        cancelSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self, self.isRunning, !self.hasFiredFinal else { return }
            let text = self.lastPartialText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.hasFiredFinal = true
            print("[SpeechRecognitionManager] Silence timeout — finalizing: '\(text)'")
            self.onFinalResult?(text)
        }
    }

    private func cancelSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available && isRunning {
            stopRecognition()
            onError?(SpeechRecognitionError.recognizerUnavailable)
        }
        print("[SpeechRecognitionManager] Availability changed: \(available)")
    }
}
