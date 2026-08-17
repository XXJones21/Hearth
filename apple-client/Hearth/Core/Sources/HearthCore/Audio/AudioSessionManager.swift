//
//  AudioSessionManager.swift
//  Hearth
//
//  Who owns the AVAudioSession category and mode, and nothing else.
//
//  Valinor's AudioInputManager was two things in one file. The load-bearing
//  half is below: the session configuration, which every other audio path in
//  the client depends on being right. The other half was a 48kHz-to-16kHz
//  capture and upload path whose entry point, startStreaming(), had no caller
//  anywhere in the tree -- server-side Whisper is not the phone's path, because
//  STT is on-device and that is a product claim rather than a convenience.
//
//  Renamed with the subtraction, because after it the file no longer manages
//  audio input.
//

import AVFoundation
import Foundation

public final class AudioSessionManager {
    // `.shared` is gone: it had zero references, and a second instance beside
    // ChatViewModel's would just re-run configure() against the same
    // process-wide AVAudioSession.

    public init() {
        configure()
    }

    /// Configure the session for a persona that both listens and speaks.
    ///
    /// The mode is the whole story for playback loudness. `.voiceChat` engages
    /// iOS voice processing -- acoustic echo cancellation and automatic gain
    /// control tuned for telephony -- which holds output well below what the
    /// same signal reaches on `.playback`, so TTS came out quiet with the
    /// hardware volume already at maximum. `.default` leaves the signal alone,
    /// and speech is what this app is for.
    ///
    /// `.playAndRecord` stays in both cases because dictation has to be
    /// available without tearing the session down and rebuilding it, which
    /// costs a route change every time the operator taps to talk.
    ///
    /// - Parameter echoCancellation: engage `.videoChat` processing. This is
    ///   the branch Valinor took for Ray-Bans, where HFP puts the microphone
    ///   centimetres from the speaker and without cancellation the persona
    ///   hears itself; there the processing is worth the level it costs.
    ///   Nothing passes true today -- MWDAT is out of the pre-alpha -- and the
    ///   branch survives because the reasoning is expensive to rediscover and
    ///   the parameter is what a wearable turns back on.
    public func configure(echoCancellation: Bool = false) {
        do {
            let session = AVAudioSession.sharedInstance()

            #if os(visionOS)
            // Every routing option above is a phone's concern, and none of them
            // mean anything to a headset: there is no speaker route to prefer,
            // and the microphone is a fixed array rather than something that
            // might be a paired earpiece. `.mixWithOthers` is the one that
            // still says something -- the house should not silence the room.
            //
            // This matters more than a tidy-up. `setCategory` throwing here
            // would be swallowed by the catch below, `setActive` would never
            // run, and the microphone would be silently dead while everything
            // else looked healthy -- a pinch on the orb that does nothing, with
            // no error anywhere. Valinor cleared this as a crash cause but kept
            // the visionOS-safe session as a deliberate improvement; this is
            // that same change.
            //
            // The mode split carries: `.default` leaves the signal alone, and
            // speech is what this app is for.
            try session.setCategory(.playAndRecord,
                                    mode: echoCancellation ? .videoChat : .default,
                                    options: [.mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            // No overrideOutputAudioPort: there is no speaker port to take.
            #else
            if echoCancellation {
                try session.setCategory(.playAndRecord, mode: .videoChat,
                    options: [.allowBluetoothHFP, .mixWithOthers, .defaultToSpeaker])
            } else {
                // A2DP as well as HFP: a bluetooth speaker should get the
                // stereo profile rather than the headset one, which is
                // narrowband and sounds worse than the phone's own speaker.
                try session.setCategory(.playAndRecord, mode: .default,
                    options: [.defaultToSpeaker, .allowBluetoothHFP,
                              .allowBluetoothA2DP, .mixWithOthers])
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // `.defaultToSpeaker` is the category's preference, not a
            // guarantee: a session that has already routed to the receiver
            // stays there until told otherwise. Only override when nothing
            // better is attached, so this cannot steal audio back from
            // headphones or a car.
            if !echoCancellation, !Self.isExternalRoute(session) {
                try? session.overrideOutputAudioPort(.speaker)
            }
            #endif
        } catch {
            print("[AudioSessionManager] Failed to setup audio session: \(error)")
        }
    }

    /// True when the operator has something plugged in or paired that should
    /// keep the audio.
    private static func isExternalRoute(_ session: AVAudioSession) -> Bool {
        let external: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
            .carAudio, .airPlay, .usbAudio, .HDMI,
        ]
        return session.currentRoute.outputs.contains { external.contains($0.portType) }
    }

    // requestMicrophonePermission() is gone: zero call sites, and the real
    // permission flow lives in VoicePermissions.prime() (first run) and
    // SpeechRecognitionManager.startRecognition() (lazy fallback).
}
