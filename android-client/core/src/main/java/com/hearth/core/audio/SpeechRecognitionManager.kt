package com.hearth.core.audio

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import kotlin.math.min

/**
 * On-device speech to text, ported from the iOS `SpeechRecognitionManager`.
 *
 * The audio NEVER leaves the phone: only the final transcript ships, as
 * `client_transcription`. That is the same contract as iOS and the reason the
 * house's own Whisper path stays unused by this client.
 *
 * The timing rules carry across verbatim, because they are what makes a turn
 * feel like a conversation rather than a form:
 *   - partial results stream, so the composer can show the words forming
 *   - 1.5 s of silence after the last partial auto-submits
 *   - a manual commit ([finishAndCommit]) submits immediately
 *   - [hasFiredFinal] guards the double-send those two paths would otherwise
 *     race into
 *
 * Android's SpeechRecognizer must be driven from the main thread, which is
 * what the handler below is for.
 */
class SpeechRecognitionManager(private val context: Context) {

    var onPartialResult: ((String) -> Unit)? = null
    var onFinalResult: ((String) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    /** Microphone level 0..1, for the composer's glow. */
    var onLevel: ((Float) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null

    @Volatile
    private var isRunning = false

    private var lastPartialText = ""
    private var hasFiredFinal = false
    private var offlineRetried = false
    private val silenceRunnable = Runnable {
        if (isRunning && !hasFiredFinal && lastPartialText.isNotBlank()) {
            hasFiredFinal = true
            commit(lastPartialText)
        }
    }

    val isAvailable: Boolean
        get() = SpeechRecognizer.isRecognitionAvailable(context)

    fun start() = start(preferOffline = true)

    private fun start(preferOffline: Boolean) {
        if (isRunning) return
        if (!isAvailable) {
            onError?.invoke("Speech recognition is not available on this device.")
            return
        }
        main.post {
            lastPartialText = ""
            hasFiredFinal = false
            if (preferOffline) offlineRetried = false

            val r = SpeechRecognizer.createSpeechRecognizer(context)
            r.setRecognitionListener(Listener())
            recognizer = r

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                // On-device when the device can: the audio must not leave the
                // phone, which is the whole posture of this client. Dropped
                // only on the retry below, when the platform reports it has
                // no on-device pack at all.
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, preferOffline)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            }
            isRunning = true
            r.startListening(intent)
        }
    }

    /**
     * Submit what has been heard so far, now. The mic button's path; the
     * silence timer takes the same one, and [hasFiredFinal] keeps whichever
     * arrives second from sending twice.
     */
    fun finishAndCommit(): Boolean {
        if (!isRunning || hasFiredFinal) return false
        hasFiredFinal = true
        val text = lastPartialText
        main.post { recognizer?.stopListening() }
        if (text.isBlank()) {
            stop()
            return false
        }
        commit(text)
        return true
    }

    fun stop() {
        main.post {
            cancelSilenceTimer()
            isRunning = false
            try {
                recognizer?.stopListening()
                recognizer?.destroy()
            } catch (e: Exception) {
                Log.w(TAG, "stop failed: ${e.message}")
            }
            recognizer = null
            onLevel?.invoke(0f)
        }
    }

    private fun commit(text: String) {
        cancelSilenceTimer()
        isRunning = false
        onFinalResult?.invoke(text)
        stop()
    }

    private fun armSilenceTimer() {
        cancelSilenceTimer()
        main.postDelayed(silenceRunnable, SILENCE_TIMEOUT_MS)
    }

    private fun cancelSilenceTimer() = main.removeCallbacks(silenceRunnable)

    private inner class Listener : RecognitionListener {

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
            if (text.isNotBlank()) {
                lastPartialText = text
                onPartialResult?.invoke(text)
                // Re-armed on every partial, so the window is silence AFTER
                // the last word rather than a fixed ceiling on the whole turn.
                armSilenceTimer()
            }
        }

        override fun onResults(results: Bundle?) {
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                .orEmpty()
            if (hasFiredFinal) return
            hasFiredFinal = true
            commit(text.ifBlank { lastPartialText })
        }

        override fun onRmsChanged(rmsdB: Float) {
            // The platform reports roughly -2..10 dB. Map to 0..1 for a glow.
            onLevel?.invoke(min(1f, maxOf(0f, (rmsdB + 2f) / 12f)))
        }

        override fun onError(error: Int) {
            if (hasFiredFinal) return
            Log.i(TAG, "recognition error $error")
            val message = when (error) {
                // Nobody spoke. That is the normal end of a listening window
                // the house opened on its own after a reply, and it must pass
                // in silence: an error row here turns "you said nothing" into
                // "something broke". iOS swallows the same two cases (203 and
                // 216 in kAFAssistantErrorDomain).
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> null

                // 12/13: the platform could not check for, or does not have,
                // an on-device language pack. Seen on emulators and on a
                // fresh device before the pack downloads. Retried once
                // without EXTRA_PREFER_OFFLINE rather than surfaced, because
                // there is nothing the operator can do with the message.
                ERROR_CANNOT_CHECK_SUPPORT, ERROR_LANGUAGE_UNAVAILABLE -> {
                    if (!offlineRetried) {
                        offlineRetried = true
                        isRunning = false
                        main.post { start(preferOffline = false) }
                        return
                    }
                    null
                }

                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    "Hearth needs microphone permission to listen."

                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                    "Speech recognition could not reach its service."

                else -> "I could not catch that."
            }
            isRunning = false
            message?.let { onError?.invoke(it) }
            stop()
        }

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    companion object {
        private const val TAG = "HearthStt"

        /** Silence after the last partial that auto-submits the turn. */
        private const val SILENCE_TIMEOUT_MS = 1_500L

        // Not in SpeechRecognizer until API 33/34 respectively, and named
        // here so the when-branch reads as intent rather than as magic ints.
        private const val ERROR_LANGUAGE_UNAVAILABLE = 12
        private const val ERROR_CANNOT_CHECK_SUPPORT = 13
    }
}
