//
//  TTSStreamPlayer.swift
//  Hearth
//
//  Gapless streaming audio player for PCM chunks delivered over WebSocket.
//  Uses AVAudioEngine + AVAudioPlayerNode, which allows buffers to be
//  scheduled continuously — the player node never stops between sentences.
//
//  Protocol:
//    startStream(sampleRate:)    — called on tts_chunk_start
//    receivePCMChunk(_:)         — called for each binary float32 PCM message
//    markSpeakingComplete()      — called on speaking_complete; fires onPlaybackComplete
//                                  after the last queued buffer drains
//    stop()                      — hard stop (e.g. user interrupts)
//

import AVFoundation
import Foundation

class TTSStreamPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat?
    private var currentSegIdx = 0
    private let chunkLock = NSLock()
    private var _chunksReceived = 0

    var onPlaybackComplete: (() -> Void)?
    var onDebugEvent: ((String) -> Void)?
    /// Smoothed playback amplitude 0..1, emitted ~per audio buffer while TTS
    /// plays. Drives Sulivan's speaking waveform. Always called on the main queue.
    var onAmplitude: ((Float) -> Void)?
    private var smoothedAmplitude: Float = 0
    private var amplitudeTapInstalled = false

    /// Fires when a segment's audio actually STARTS BEING HEARD, on the main
    /// queue. Not the same as `segmentStarted`, which fires when the server
    /// begins *sending* that segment — the server pushes every segment within a
    /// second or two while playback takes far longer, so anything driven off
    /// arrival races ahead of the voice. The karaoke caption reads this.
    var onSegmentPlaying: ((Int) -> Void)?

    /// 0..1 on the playback mixer. Zero (Settings > Voice off) keeps the
    /// whole turn intact -- rendering continues, so the karaoke caption still
    /// reveals in playback time -- with nothing audible and the amplitude tap
    /// reading silence, which correctly keeps the face's mouth shut.
    var playbackVolume: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = max(0, min(1, playbackVolume)) }
    }

    /// Frames of audio scheduled so far — the playback timeline every segment
    /// mark is measured against.
    private var scheduledFrames: AVAudioFramePosition = 0
    /// (segment index, frame offset where its audio begins), in order.
    private var segmentMarks: [(idx: Int, startFrame: AVAudioFramePosition)] = []
    private var lastEmittedSegment = -1
    private let markLock = NSLock()

    init() {
        engine.attach(playerNode)
    }

    // MARK: - Public API

    func startStream(sampleRate: Double) {
        if let fmt = audioFormat, fmt.sampleRate == sampleRate, engine.isRunning {
            return
        }

        if engine.isRunning {
            playerNode.stop()
            engine.stop()
        }

        // `sampleRate` came straight off the wire (tts_chunk_start). A zero or
        // negative value used to hit a force-unwrapped AVAudioFormat and crash
        // the app on a server's bad day; refuse the stream instead.
        guard sampleRate > 0,
              let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
              )
        else {
            print("[TTSStreamPlayer] Refusing stream with invalid sample rate \(sampleRate)")
            audioFormat = nil
            return
        }
        audioFormat = fmt
        chunkLock.lock()
        _chunksReceived = 0
        chunkLock.unlock()
        resetSegmentTracking()

        removeAmplitudeTap()
        engine.connect(playerNode, to: engine.mainMixerNode, format: fmt)

        do {
            try engine.start()
        } catch {
            print("[TTSStreamPlayer] Failed to start engine: \(error)")
            // Without this, every later guard passes against a dead engine:
            // buffers get scheduled onto a node that never renders and the
            // app sits in SPEAKING forever. A nil format makes the failure
            // visible to every path that checks it.
            audioFormat = nil
            return
        }

        engine.mainMixerNode.outputVolume = max(0, min(1, playbackVolume))
        playerNode.play()
        installAmplitudeTap()
        print("[TTSStreamPlayer] Stream started @ \(sampleRate)Hz")
    }

    /// The server has begun SENDING this segment. Its audio will be heard once
    /// everything already queued has drained, so mark that frame offset rather
    /// than announcing the segment now.
    func segmentStarted(_ segIdx: Int) {
        currentSegIdx = segIdx
        chunkLock.lock()
        _chunksReceived = 0
        chunkLock.unlock()
        markLock.lock()
        segmentMarks.append((idx: segIdx, startFrame: scheduledFrames))
        markLock.unlock()
        let msg = "[Client] Queued PCM segment \(segIdx)"
        print(msg)
        onDebugEvent?(msg)
    }

    func segmentEnded(_ segIdx: Int) {
        chunkLock.lock()
        let count = _chunksReceived
        chunkLock.unlock()
        let msg = "[Client] Stop playing PCM segment \(segIdx) (\(count) chunks received)"
        print(msg)
        onDebugEvent?(msg)
    }

    func receivePCMChunk(_ data: Data) {
        guard let fmt = audioFormat else {
            print("[TTSStreamPlayer] Received PCM chunk before startStream -- ignoring")
            return
        }

        chunkLock.lock()
        _chunksReceived += 1
        chunkLock.unlock()

        let frameCount = data.count / MemoryLayout<Float>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: fmt,
                frameCapacity: AVAudioFrameCount(frameCount)
              )
        else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { rawPtr in
            guard let src = rawPtr.bindMemory(to: Float.self).baseAddress,
                  let dst = buffer.floatChannelData?[0]
            else { return }
            // `update(from:count:)` is the current spelling of what used to be
            // `assign(from:count:)`. Same operation, same semantics for the
            // AVAudioPCMBuffer's already-allocated channel storage; the old
            // name is deprecated, and the comment it carried claimed a
            // distinction between the two that never existed.
            dst.update(from: src, count: frameCount)
        }

        playerNode.scheduleBuffer(buffer)
        markLock.lock()
        scheduledFrames += AVAudioFramePosition(frameCount)
        markLock.unlock()
    }

    // MARK: - Segment playback tracking

    private func resetSegmentTracking() {
        markLock.lock()
        scheduledFrames = 0
        segmentMarks.removeAll()
        lastEmittedSegment = -1

        markLock.unlock()
    }

    /// Called from the amplitude tap (which already runs per audio buffer).
    /// Maps the node's rendered-sample position onto the segment marks and
    /// announces a segment the first time its audio is reached. The node's
    /// sample time only advances as buffers actually render, so a starved
    /// stream stalls the caption instead of running ahead of it.
    private func emitSegmentIfAdvanced() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        let played = playerTime.sampleTime

        // EVERY newly reached segment, in order -- not just the last. The
        // last-wins collapse silently dropped any segment passed over within
        // one amplitude buffer (two marks sharing a startFrame after a
        // server-side TTS error is the guaranteed case), and with it that
        // sentence's caption and parked face cue.
        markLock.lock()
        var newlyReached: [Int] = []
        for mark in segmentMarks
        where mark.startFrame <= played && mark.idx > lastEmittedSegment {
            newlyReached.append(mark.idx)
        }
        newlyReached.sort()
        if let latest = newlyReached.last { lastEmittedSegment = latest }
        markLock.unlock()

        guard !newlyReached.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for idx in newlyReached { self?.onSegmentPlaying?(idx) }
        }
    }

    /// After all PCM chunks have been queued, schedule a silent sentinel buffer.
    /// When it finishes playing, we know all audio has drained — fires onPlaybackComplete.
    func markSpeakingComplete() {
        guard let fmt = audioFormat else {
            onPlaybackComplete?()
            return
        }

        // 50ms of silence at target sample rate
        let silentFrames = AVAudioFrameCount(fmt.sampleRate * 0.05)
        guard let sentinel = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: silentFrames) else {
            onPlaybackComplete?()
            return
        }
        sentinel.frameLength = silentFrames
        // Zero out the audio buffer memory safely using memset
        if let ptr = sentinel.floatChannelData?[0] {
            memset(ptr, 0, Int(silentFrames) * MemoryLayout<Float>.stride)
        }

        playerNode.scheduleBuffer(sentinel, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                let msg = "[Client] Finished playing (PCM streaming)"
                print(msg)
                self?.onDebugEvent?(msg)
                self?.onPlaybackComplete?()
                // The reply is fully drained: put the engine down. Without
                // this the amplitude tap ran an RMS loop over silence ~43
                // times a second for the rest of the process after the first
                // reply. startStream restarts everything for the next one.
                self?.quiesce()
            }
        }
    }

    /// Idle the audio path between replies. Keeps `audioFormat` so a
    /// same-rate startStream is still recognised as a fresh start (the
    /// engine-running check fails and it rebuilds).
    private func quiesce() {
        removeAmplitudeTap()
        playerNode.stop()
        engine.stop()
        smoothedAmplitude = 0
        onAmplitude?(0)
    }

    func stop() {
        removeAmplitudeTap()
        playerNode.stop()
        engine.stop()
        audioFormat = nil
        resetSegmentTracking()
        smoothedAmplitude = 0
        DispatchQueue.main.async { [weak self] in self?.onAmplitude?(0) }
        print("[TTSStreamPlayer] Stopped")
    }

    // MARK: - Amplitude tap (drives the speaking waveform)

    private func installAmplitudeTap() {
        guard !amplitudeTapInstalled else { return }
        let mixer = engine.mainMixerNode
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sumSquares: Float = 0
            for i in 0..<n { let s = channel[i]; sumSquares += s * s }
            let rms = (sumSquares / Float(n)).squareRoot()
            // Map RMS to a lively 0..1 range and smooth (attack/decay).
            let level = min(1, rms * 7)
            self.smoothedAmplitude = self.smoothedAmplitude * 0.6 + level * 0.4
            let amp = self.smoothedAmplitude
            DispatchQueue.main.async { self.onAmplitude?(amp) }
            self.emitSegmentIfAdvanced()
        }
        amplitudeTapInstalled = true
    }

    private func removeAmplitudeTap() {
        guard amplitudeTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        amplitudeTapInstalled = false
    }
}
