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

/// Ask for both voice permissions in one deliberate moment (first run, right
/// after pairing succeeds), instead of two system alerts stacking on the
/// first mic tap. Skips anything already answered. Public because first run
/// lives in the app target.
public enum VoicePermissions {
    public static func prime() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume(returning: true)
                }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
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
    /// Smoothed input level 0..1, ~per audio buffer while the mic is live.
    /// Drives the listening pulse so it reads the actual microphone rather
    /// than a timer -- a muted mic and a dead route now LOOK different.
    var onLevel: ((Float) -> Void)?
    private var smoothedLevel: Float = 0

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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            // The buffer is already in hand; metering it is one pass.
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sumSquares: Float = 0
            for i in 0..<n { let s = channel[i]; sumSquares += s * s }
            let rms = (sumSquares / Float(n)).squareRoot()
            let level = min(1, rms * 9)
            self.smoothedLevel = self.smoothedLevel * 0.7 + level * 0.3
            let out = self.smoothedLevel
            DispatchQueue.main.async { self.onLevel?(out) }
        }

        lastPartialText = ""
        hasFiredFinal = false

        // The whole handler hops to main. The recognition task's callback
        // queue is undocumented, and Timer.scheduledTimer installs on the
        // CALLING thread's run loop -- on a queue without one the silence
        // timer never fires and the only auto-submit path in the app is
        // dead. Main is also where lastPartialText / hasFiredFinal /
        // silenceTimer are read by stopRecognition and finishAndCommit, so
        // this ends the race across those too.
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
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

    /// Commit whatever has been said SO FAR, now -- the user's tap instead of
    /// the silence timeout. Same path the timer takes (`hasFiredFinal` keeps
    /// the recognizer's own late final from double-sending), so tap and
    /// timeout cannot drift apart. No partial yet means nothing to commit;
    /// the caller treats that as a plain stop.
    @discardableResult
    func finishAndCommit() -> Bool {
        guard isRunning, !hasFiredFinal else { return false }
        let text = lastPartialText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        hasFiredFinal = true
        cancelSilenceTimer()
        print("[SpeechRecognitionManager] Tap commit -- finalizing: '\(text)'")
        onFinalResult?(text)
        return true
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
