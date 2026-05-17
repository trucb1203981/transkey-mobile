package app.transkey.mobile

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/**
 * Thin wrapper around [SpeechRecognizer] so [BubbleService] doesn't have to
 * deal with the platform's verbose listener API. Drives a single-shot
 * recognition session: start() → onPartialResult* → onFinalResult → done.
 *
 * Single-instance per session; call [destroy] when the voice picker is
 * dismissed to release the underlying engine and the audio focus it grabs.
 */
class VoiceRecognitionHelper(
    private val context: Context,
    /** BCP-47 language tag, e.g. "vi-VN", "en-US". Null = let engine pick. */
    private val languageTag: String?,
    private val callbacks: Callbacks,
) {

    interface Callbacks {
        /** Listener attached, mic active. Use to start UI pulse. */
        fun onReady()
        /** Partial hypothesis as user speaks. May fire many times. */
        fun onPartialResult(text: String)
        /** Final hypothesis when user pauses / stops. Always fires (or onError). */
        fun onFinalResult(text: String)
        /** Recognition aborted — message is human-readable. */
        fun onError(message: String)
    }

    private var recognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var disposed = false
    @Volatile private var finalDelivered = false

    fun start() {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            callbacks.onError(context.getString(R.string.bubble_voice_unsupported))
            return
        }
        val sr = SpeechRecognizer.createSpeechRecognizer(context)
        recognizer = sr
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                if (!disposed) callbacks.onReady()
            }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {
                val text = pickBest(partialResults)
                if (!disposed && !text.isNullOrBlank()) {
                    callbacks.onPartialResult(text)
                }
            }
            override fun onResults(results: Bundle?) {
                val text = pickBest(results)
                deliverFinal(text)
            }
            override fun onError(error: Int) {
                // ERROR_NO_MATCH and ERROR_SPEECH_TIMEOUT often fire AFTER a
                // valid onPartialResults — engine just didn't see a clean
                // sentence boundary. Treat them as a final-result hand-off
                // using the last partial text we showed.
                val msg = errorMessage(error)
                if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                    if (!finalDelivered && lastPartial.isNotBlank()) {
                        deliverFinal(lastPartial)
                        return
                    }
                }
                if (!disposed) callbacks.onError(msg)
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            if (!languageTag.isNullOrBlank()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
                // PREFERENCE is honoured by some engines on top of LANGUAGE.
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, languageTag)
            }
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // Some OEMs require the calling package extra to surface partials.
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        }
        try {
            sr.startListening(intent)
        } catch (error: Exception) {
            Log.w(TAG, "startListening failed: ${error.message}")
            callbacks.onError(context.getString(R.string.bubble_voice_unsupported))
        }
    }

    private var lastPartial: String = ""

    /** Stop listening; commits whatever partial the engine has so far via onResults. */
    fun stop() {
        try { recognizer?.stopListening() } catch (_: Exception) {}
        // Safety net: some engines never call onResults after stopListening
        // (Samsung). Wait briefly, then fall back to lastPartial.
        mainHandler.postDelayed({
            if (!finalDelivered && !disposed) {
                deliverFinal(lastPartial.takeIf { it.isNotBlank() })
            }
        }, 600)
    }

    /** Discard current session — no callback fires. */
    fun cancel() {
        try { recognizer?.cancel() } catch (_: Exception) {}
        destroy()
    }

    fun destroy() {
        disposed = true
        try { recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null
    }

    private fun deliverFinal(text: String?) {
        if (finalDelivered || disposed) return
        finalDelivered = true
        if (text.isNullOrBlank()) {
            callbacks.onError(context.getString(R.string.bubble_voice_no_match))
        } else {
            callbacks.onFinalResult(text)
        }
    }

    private fun pickBest(bundle: Bundle?): String? {
        val list = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = list?.firstOrNull()?.trim()
        if (!text.isNullOrEmpty()) lastPartial = text
        return text
    }

    private fun errorMessage(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> context.getString(R.string.bubble_voice_no_match)
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
            context.getString(R.string.bubble_voice_network)
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
            context.getString(R.string.bubble_voice_perm_denied)
        SpeechRecognizer.ERROR_NO_MATCH,
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
            context.getString(R.string.bubble_voice_no_match)
        // ERROR_LANGUAGE_NOT_SUPPORTED (12) + ERROR_LANGUAGE_UNAVAILABLE (13)
        // are API 31+ constants — refer to them by numeric literal so we
        // compile on older platform targets too. These fire when the user's
        // Google Speech Services doesn't have an offline pack for the
        // requested locale (extremely common for ja/ko/zh on devices that
        // shipped with English-only). Surface a specific message pointing
        // the user at the system download flow.
        12, 13 -> context.getString(R.string.bubble_voice_lang_missing)
        else -> context.getString(R.string.bubble_voice_no_match)
    }

    companion object {
        private const val TAG = "VoiceHelper"

        /** Resolve an ISO-639-1 lang code to a BCP-47 tag the recognizer accepts. */
        fun resolveLanguageTag(lang: String?): String? = when (lang) {
            null, "", "auto" -> null
            "en" -> "en-US"
            "vi" -> "vi-VN"
            "ja" -> "ja-JP"
            "ko" -> "ko-KR"
            "zh" -> "zh-CN"
            "zh-TW" -> "zh-TW"
            "fr" -> "fr-FR"
            "de" -> "de-DE"
            "es" -> "es-ES"
            "pt" -> "pt-BR"
            "it" -> "it-IT"
            "ru" -> "ru-RU"
            "th" -> "th-TH"
            "id" -> "id-ID"
            else -> lang
        }
    }
}
