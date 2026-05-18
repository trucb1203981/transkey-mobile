package app.transkey.mobile

import android.content.Context
import android.content.Intent
import android.os.Build
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
        // Reset disposal flags so the same helper instance can be
        // re-`start()`ed in place (used by the picker's tap-mic-to-retry
        // path after an error). Each start() spawns a fresh
        // SpeechRecognizer so prior state from a failed attempt doesn't
        // bleed into the new one.
        disposed = false
        finalDelivered = false
        lastPartial = ""
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            callbacks.onError(context.getString(R.string.bubble_voice_unsupported))
            return
        }
        val sr = SpeechRecognizer.createSpeechRecognizer(context)
        recognizer = sr
        Log.w(TAG, "start() lang=$languageTag available=true")
        sr.setRecognitionListener(object : RecognitionListener {
            private var maxRms = Float.NEGATIVE_INFINITY
            private var rmsSamples = 0
            private var rmsSum = 0f
            override fun onReadyForSpeech(params: Bundle?) {
                Log.w(TAG, "onReadyForSpeech")
                if (!disposed) callbacks.onReady()
            }
            override fun onBeginningOfSpeech() {
                Log.w(TAG, "onBeginningOfSpeech")
            }
            override fun onRmsChanged(rmsdB: Float) {
                if (rmsdB > maxRms) maxRms = rmsdB
                rmsSamples++; rmsSum += rmsdB
                // Log periodically — every ~25 samples (RMS fires ~10/s
                // so this is ~2.5s) so logcat doesn't drown in noise.
                if (rmsSamples % 25 == 0) {
                    Log.w(TAG, "rms samples=$rmsSamples max=$maxRms avg=${rmsSum / rmsSamples}")
                }
            }
            override fun onBufferReceived(buffer: ByteArray?) {
                Log.w(TAG, "onBufferReceived size=${buffer?.size}")
            }
            override fun onEndOfSpeech() {
                Log.w(TAG, "onEndOfSpeech (samples=$rmsSamples max=$maxRms)")
            }
            override fun onPartialResults(partialResults: Bundle?) {
                val text = pickBest(partialResults)
                Log.w(TAG, "onPartialResults='${text ?: "(null)"}'")
                if (!disposed && !text.isNullOrBlank()) {
                    callbacks.onPartialResult(text)
                }
            }
            override fun onResults(results: Bundle?) {
                val text = pickBest(results)
                Log.w(TAG, "onResults='${text ?: "(null)"}'")
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
                // Surface every other failure explicitly — silent retry
                // hides the failure from the user, who then sees "Listening…"
                // forever and has no idea recognition died. The picker UI
                // turns the mic icon tappable when error fires so a single
                // tap restarts a fresh session in place.
                Log.w(TAG, "onError code=$error msg='$msg' (samples=$rmsSamples max=$maxRms lastPartial='$lastPartial')")
                if (!disposed) callbacks.onError(msg)
            }
            override fun onEvent(eventType: Int, params: Bundle?) {
                Log.w(TAG, "onEvent type=$eventType")
            }
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
            // Generous silence thresholds — Android default (~500-1500ms)
            // ends recognition the moment the user pauses to think mid-
            // sentence, triggering premature ERROR_NO_MATCH that forces
            // the user to re-tap and re-speak. The values below give a
            // natural "speak a full sentence" feel: up to 2.5s of complete
            // silence before commit, with a 1.5s warning window before
            // that. Min length 1s so a single short utterance still ends
            // promptly when the user genuinely stops talking.
            // NB: do NOT set EXTRA_SPEECH_INPUT_*_LENGTH_MILLIS here. Two
            // failure modes were observed:
            //  1. As `1000L` (Long): Bundle.getInt() rejects the Long, falls
            //     back to 0, recognizer hangs.
            //  2. As `1000` (Int): honoured — but Google's Soda recognizer
            //     interprets a non-zero MINIMUM_LENGTH_MILLIS as a hint that
            //     the caller wants AMBIENT_CONTINUOUS mode, which never
            //     finalises (the log shows
            //     "applicationDomain: AMBIENT_CONTINUOUS"). Either way the
            //     user sees "đang nghe" with no result.
            // Letting Google use its built-in defaults (≈1500 ms silence)
            // keeps Soda in AMBIENT_ONESHOT and returns finals reliably.
            // Force online recognition when available — the online model is
            // an order of magnitude larger than the offline pack and has a
            // much broader proper-noun vocabulary (foreign names like
            // "Shinzato", brand names, place names). Offline-only is fine
            // for common Vietnamese words but turns proper nouns into
            // phonetic approximations ("Shinzato" → "xin cho tôi").
            // Falls back to offline automatically if no network.
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            // Android 13+ (API 33): enable on-device formatting +
            // glossary-based name biasing. Compiled by numeric literal so
            // we still build on platform targets below 33.
            if (Build.VERSION.SDK_INT >= 33) {
                putExtra("android.speech.extra.ENABLE_FORMATTING", "quality")
                // EXTRA_BIASING_STRINGS: hint specific phrases to the
                // recognizer so proper nouns the user typed into their
                // glossary (foreign names like "Shinzato", brand names,
                // place names) actually get recognized instead of being
                // phonetically mangled into common Vietnamese words. The
                // glossary the in-app translate flow uses already
                // contains exactly the vocabulary the user cares about
                // for THIS conversation — reuse it for ASR with zero
                // extra UI.
                val biasing = readGlossaryBiasingStrings()
                if (biasing.isNotEmpty()) {
                    putExtra("android.speech.extra.BIASING_STRINGS", biasing.toTypedArray())
                    Log.w(TAG, "biasing strings (${biasing.size}): ${biasing.take(5)}…")
                }
            }
        }
        try {
            sr.startListening(intent)
            Log.w(TAG, "startListening dispatched (lang=$languageTag)")
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

    /**
     * Pull the user's glossary `source` terms from the shared Flutter
     * SharedPreferences (the same JSON-encoded list the Dart side reads
     * via the glossary tab) and use them as recognizer biasing strings.
     * Falls back to empty list silently if the prefs are missing,
     * malformed, or the glossary is empty — none of those are user-
     * visible failures, just means no name boosting that session.
     */
    private fun readGlossaryBiasingStrings(): List<String> {
        return try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE,
            )
            val raw = prefs.getString("flutter.tk_glossary", null) ?: return emptyList()
            val arr = org.json.JSONArray(raw)
            // Bias only entries flagged as proper names. Sending the whole
            // glossary (up to 50 entries on free, 500 on pro) crowds the
            // recognizer's hint list — Google's ASR weights drop off fast
            // past ~10 strings, so non-name terminology was diluting the
            // signal for the names that actually need it.
            val out = mutableListOf<String>()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                if (!obj.optBoolean("is_name", false)) continue
                val source = obj.optString("source", "").trim()
                if (source.isNotEmpty() && source.length <= 100) {
                    out.add(source)
                }
            }
            out
        } catch (e: Exception) {
            Log.w(TAG, "readGlossaryBiasingStrings failed: ${e.message}")
            emptyList()
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
        // ERROR_SERVER_DISCONNECTED (11) commonly fires when the user
        // changes language pills mid-session — the online recognizer
        // session for the previous lang is dropped before the new one
        // is ready. Same surface as a transient network glitch from
        // the user's perspective.
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED ->
            context.getString(R.string.bubble_voice_network)
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
        /** How many silent-listen cycles to retry before giving up. */
        private const val MAX_RESTART = 2

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
