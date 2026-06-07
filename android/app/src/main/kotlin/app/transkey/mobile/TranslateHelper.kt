package app.transkey.mobile

import android.util.Log
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions

/**
 * On-device translation wrapper used by the live video-subtitle mode.
 *
 * Why on-device and not the server LLM: the subtitle hot path (capture →
 * OCR → translate → overlay) must finish in well under the ~2 s a subtitle
 * line stays on screen. A server round-trip is 0.5-2 s PER LINE, so the
 * translation would land after the line is already gone. ML Kit translate
 * runs locally in tens of ms. Quality is below the server LLM, but for live
 * subtitles "readable now" beats "polished late".
 *
 * Model lifecycle: ML Kit pivots every pair through English, so a vi→ja
 * translation needs the vi↔en and en↔ja models (~30 MB each), downloaded
 * once on first use via [prepare]. We keep ONE [Translator] resident for
 * the active source→target pair and swap it only when the pair changes, so
 * the hot path never pays model-load cost mid-session.
 *
 * Threading: ML Kit Tasks resolve on the main thread; [translate] is safe
 * to call repeatedly from the capture loop — calls queue inside ML Kit.
 */
object TranslateHelper {

    private const val TAG = "TranslateHelper"

    /** Active translator + the pair it serves, so we can detect a swap. */
    private var translator: Translator? = null
    private var activeSource: String? = null
    private var activeTarget: String? = null

    /** True once the active pair's models are confirmed downloaded. */
    @Volatile private var modelReady = false

    /**
     * Map an app language code (ISO-639-1, possibly region-tagged like
     * "pt-BR") to the ML Kit [TranslateLanguage] code, or null if ML Kit
     * cannot translate it. ML Kit covers ~59 languages; some scripts the
     * OCR can READ (e.g. certain Indic variants) have no translate model,
     * so callers must handle null by leaving the line untranslated.
     */
    fun toMlKitLang(code: String?): String? {
        if (code.isNullOrBlank()) return null
        // fromLanguageTag handles "en", "zh", "pt-BR" → supported code or null.
        return TranslateLanguage.fromLanguageTag(code)
            ?: TranslateLanguage.fromLanguageTag(code.substringBefore('-'))
    }

    /** Whether ML Kit can translate the given app language code. */
    fun isSupported(code: String?): Boolean = toMlKitLang(code) != null

    /**
     * Ensure a translator exists for [source]→[target] and its models are
     * downloaded. Safe to call repeatedly; rebuilds only when the pair
     * changes. [callback] fires with true once translation is usable.
     *
     * [requireWifi] gates the (large) first-time model download. The
     * subtitle mode passes the user's preference; default false because the
     * user explicitly opted into the feature and expects it to work now.
     */
    fun prepare(
        source: String,
        target: String,
        requireWifi: Boolean = false,
        callback: (Boolean) -> Unit = {},
    ) {
        val src = toMlKitLang(source)
        val tgt = toMlKitLang(target)
        if (src == null || tgt == null) {
            Log.w(TAG, "unsupported pair source=$source target=$target")
            callback(false)
            return
        }
        if (src == tgt) {
            // Same language: nothing to translate, treat as a no-op pass-through.
            swapTo(null, src, tgt)
            modelReady = true
            callback(true)
            return
        }
        // Already prepared for this exact pair → reuse.
        if (translator != null && activeSource == src && activeTarget == tgt && modelReady) {
            callback(true)
            return
        }

        val options = TranslatorOptions.Builder()
            .setSourceLanguage(src)
            .setTargetLanguage(tgt)
            .build()
        val client = Translation.getClient(options)
        swapTo(client, src, tgt)
        modelReady = false

        val conditions = DownloadConditions.Builder().apply {
            if (requireWifi) requireWifi()
        }.build()
        client.downloadModelIfNeeded(conditions)
            .addOnSuccessListener {
                // Guard against a pair swap that happened while downloading.
                if (translator === client) {
                    modelReady = true
                    Log.d(TAG, "model ready $src→$tgt")
                    callback(true)
                } else {
                    callback(false)
                }
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "model download failed $src→$tgt: ${e.message}")
                if (translator === client) modelReady = false
                callback(false)
            }
    }

    /**
     * Translate [text] for the active pair. Returns null via [callback] when
     * the model isn't ready yet (the caller should keep showing the original
     * line) or on failure. When source == target the input is passed through
     * unchanged. Does NOT trigger a download — call [prepare] first.
     */
    fun translate(text: String, callback: (String?) -> Unit) {
        val t = translator
        if (!modelReady) {
            callback(null)
            return
        }
        if (t == null) {
            // Same-language pass-through path (no client created).
            callback(text)
            return
        }
        t.translate(text)
            .addOnSuccessListener { callback(it) }
            .addOnFailureListener { e ->
                Log.w(TAG, "translate failed: ${e.message}")
                callback(null)
            }
    }

    /** Whether the active pair's models are downloaded and usable. */
    fun isReady(): Boolean = modelReady

    /** Close the active translator and forget the pair. Called on mode stop. */
    fun close() {
        translator?.close()
        translator = null
        activeSource = null
        activeTarget = null
        modelReady = false
    }

    /** Replace the resident translator, closing the previous one. */
    private fun swapTo(client: Translator?, src: String, tgt: String) {
        if (translator !== client) translator?.close()
        translator = client
        activeSource = src
        activeTarget = tgt
    }
}
