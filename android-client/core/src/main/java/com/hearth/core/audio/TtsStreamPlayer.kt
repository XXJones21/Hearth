package com.hearth.core.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Gapless streaming player for the float32 PCM the house sends. Ported from
 * the iOS `TTSStreamPlayer.swift`.
 *
 * AudioTrack in MODE_STREAM replaces AVAudioEngine plus AVAudioPlayerNode:
 * writes queue continuously and the track never stops between sentences.
 *
 * THE KARAOKE CLOCK, which is the whole reason this class is careful:
 * captions and face cues must fire when a sentence is HEARD, not when it
 * arrives. The house pushes every segment of a reply within a second or two
 * while speaking them takes far longer, so anything driven off arrival races
 * ahead of the voice. [segmentStarted] records the frame offset where a
 * segment's audio will begin, and the polling loop maps
 * [AudioTrack.getPlaybackHeadPosition] onto those marks. The head only
 * advances as audio actually renders, so a starved stream stalls the caption
 * instead of running ahead of it.
 *
 * Protocol, matching iOS:
 *   startStream(sampleRate)  on tts_chunk_start
 *   segmentStarted(idx)      on tts_chunk_start, after startStream
 *   receivePcmChunk(bytes)   for each binary frame
 *   markSpeakingComplete()   on speaking_complete
 *   stop()                   a hard stop, for barge-in
 */
class TtsStreamPlayer {

    /** Fires when a segment's audio actually STARTS BEING HEARD. */
    var onSegmentPlaying: ((Int) -> Unit)? = null

    /** Smoothed playback amplitude 0..1, for the face's mouth. */
    var onAmplitude: ((Float) -> Unit)? = null

    var onPlaybackComplete: (() -> Unit)? = null

    /**
     * 0..1. Zero keeps the whole turn intact -- the karaoke caption still
     * reveals in playback time -- with nothing audible and the amplitude
     * reading silence, which correctly keeps the face's mouth shut.
     */
    var playbackVolume: Float = 1f
        set(value) {
            field = value.coerceIn(0f, 1f)
            track?.setVolume(field)
        }

    private var track: AudioTrack? = null
    private var sampleRate = 0
    private var pollThread: Thread? = null

    @Volatile
    private var running = false

    /** Frames written so far: the timeline every segment mark is measured against. */
    private var scheduledFrames = 0L

    private val marks = mutableListOf<Pair<Int, Long>>()
    private var lastEmittedSegment = -1
    private val markLock = Any()

    private var smoothedAmplitude = 0f

    @Volatile
    private var completePending = false

    fun startStream(sampleRate: Int) {
        // A zero or negative rate came straight off the wire. Refuse the
        // stream rather than building a track that cannot render.
        if (sampleRate <= 0) {
            Log.w(TAG, "refusing stream with invalid sample rate $sampleRate")
            return
        }
        if (track != null && this.sampleRate == sampleRate && running) return

        stopInternal(clearFormat = false)

        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
        )
        if (minBuffer <= 0) {
            Log.w(TAG, "AudioTrack rejected ${sampleRate}Hz float32 mono")
            return
        }

        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            // Four times the minimum: a reply arrives faster than it plays,
            // and a tight buffer makes the writer block on every chunk.
            .setBufferSizeInBytes(minBuffer * 4)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        t.setVolume(playbackVolume)
        t.play()

        this.sampleRate = sampleRate
        track = t
        resetSegmentTracking()
        running = true
        completePending = false
        startPolling()
        Log.i(TAG, "stream started @ ${sampleRate}Hz")
    }

    /**
     * The house has begun SENDING this segment. Its audio will be heard once
     * everything already queued has drained, so mark that frame offset rather
     * than announcing the segment now.
     */
    fun segmentStarted(segIdx: Int) {
        synchronized(markLock) { marks.add(segIdx to scheduledFrames) }
    }

    fun receivePcmChunk(bytes: ByteArray) {
        val t = track ?: run {
            Log.w(TAG, "PCM chunk before startStream; ignoring")
            return
        }
        val frameCount = bytes.size / 4
        if (frameCount <= 0) return

        val floats = FloatArray(frameCount)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floats)

        // Amplitude is computed on the write buffer: Android has no mixer tap,
        // and the value only feeds the mouth, so measuring what was handed to
        // the track is close enough and costs nothing extra.
        var sumSquares = 0.0
        for (s in floats) sumSquares += (s * s).toDouble()
        val rms = sqrt(sumSquares / frameCount).toFloat()
        val level = min(1f, rms * 7)
        smoothedAmplitude = smoothedAmplitude * 0.6f + level * 0.4f
        onAmplitude?.invoke(smoothedAmplitude)

        t.write(floats, 0, frameCount, AudioTrack.WRITE_BLOCKING)
        synchronized(markLock) { scheduledFrames += frameCount }
    }

    /**
     * After the last chunk, queue a short silence so the head has something to
     * reach: when it drains past everything written, the reply is fully heard.
     */
    fun markSpeakingComplete() {
        if (track == null) {
            onPlaybackComplete?.invoke()
            return
        }
        val silence = FloatArray(sampleRate / 20) // 50 ms, as on iOS
        track?.write(silence, 0, silence.size, AudioTrack.WRITE_BLOCKING)
        synchronized(markLock) { scheduledFrames += silence.size }
        completePending = true
    }

    /** A hard stop: barge-in, or a turn abandoned. */
    fun stop() {
        stopInternal(clearFormat = true)
        smoothedAmplitude = 0f
        onAmplitude?.invoke(0f)
    }

    // ---- the karaoke clock ------------------------------------------------

    private fun startPolling() {
        pollThread?.interrupt()
        pollThread = thread(name = "hearth-tts-clock", isDaemon = true) {
            while (running) {
                try {
                    emitSegmentIfAdvanced()
                    checkComplete()
                    Thread.sleep(POLL_MS)
                } catch (e: InterruptedException) {
                    return@thread
                } catch (e: Exception) {
                    Log.w(TAG, "clock tick failed: ${e.message}")
                }
            }
        }
    }

    /**
     * Maps the track's rendered position onto the segment marks and announces
     * a segment the first time its audio is reached.
     *
     * EVERY newly reached segment, in order, never just the latest: a
     * last-wins collapse silently drops any segment passed over inside one
     * tick, and with it that sentence's caption and parked face cue. Two marks
     * sharing a start frame after a server-side TTS error is the guaranteed
     * case.
     */
    private fun emitSegmentIfAdvanced() {
        val t = track ?: return
        val played = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL

        val newlyReached = synchronized(markLock) {
            val reached = marks
                .filter { (idx, startFrame) -> startFrame <= played && idx > lastEmittedSegment }
                .map { it.first }
                .sorted()
            reached.lastOrNull()?.let { lastEmittedSegment = it }
            reached
        }
        for (idx in newlyReached) onSegmentPlaying?.invoke(idx)
    }

    private fun checkComplete() {
        if (!completePending) return
        val t = track ?: return
        val played = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
        val total = synchronized(markLock) { scheduledFrames }
        if (played >= total) {
            completePending = false
            onPlaybackComplete?.invoke()
            // The reply is drained: idle the path. startStream rebuilds it.
            quiesce()
        }
    }

    private fun quiesce() {
        running = false
        smoothedAmplitude = 0f
        onAmplitude?.invoke(0f)
        try {
            track?.pause()
            track?.flush()
        } catch (e: Exception) {
            Log.w(TAG, "quiesce failed: ${e.message}")
        }
    }

    private fun stopInternal(clearFormat: Boolean) {
        running = false
        completePending = false
        pollThread?.interrupt()
        pollThread = null
        try {
            track?.pause()
            track?.flush()
            track?.release()
        } catch (e: Exception) {
            Log.w(TAG, "stop failed: ${e.message}")
        }
        track = null
        if (clearFormat) sampleRate = 0
        resetSegmentTracking()
    }

    private fun resetSegmentTracking() {
        synchronized(markLock) {
            scheduledFrames = 0
            marks.clear()
            lastEmittedSegment = -1
        }
    }

    companion object {
        private const val TAG = "HearthTts"

        /**
         * The clock's resolution. iOS gets this for free per audio buffer from
         * the mixer tap; Android polls, and 20 ms is well under the shortest
         * sentence while costing nothing measurable.
         */
        private const val POLL_MS = 20L
    }
}
