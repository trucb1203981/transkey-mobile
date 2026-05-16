package com.example.transkey_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/**
 * Thin wrapper over ML Kit Text Recognition v2. Picks the right script
 * recognizer based on the user's source-language hint — Latin works for
 * European/Vietnamese/etc, while CJK languages each need their own model
 * (Japanese kana/kanji, Korean hangul, Chinese hanzi).
 *
 * Each recognizer holds a ~3 MB on-device model and is closed after use
 * so we don't keep all four resident between scans.
 *
 * Two output modes:
 *  - [recognize] returns the filtered joined text (legacy "scan screen"
 *    flow that drops the user into the input picker).
 *  - [recognizeBlocks] returns the individual ML Kit text blocks with
 *    bounding boxes (Lens flow — needed to overlay translated text on
 *    top of the original positions).
 */
object OcrHelper {

    private const val TAG = "OcrHelper"

    /** Cap roughly matching the translate input limit (5000 chars). */
    private const val MAX_CHARS = 5000

    /** Per-block coordinates in the source bitmap, used by LensOverlayView. */
    data class Block(val text: String, val bounds: Rect)

    /**
     * Legacy single-string flow used by the "Scan screen → Input picker"
     * path. Joins all recognised blocks, applies the content heuristic,
     * caps to [MAX_CHARS], and hands back the result (or null on
     * empty/failure) via [callback].
     */
    fun recognize(
        @Suppress("UNUSED_PARAMETER") context: Context,
        bitmap: Bitmap,
        hintLang: String?,
        callback: (String?) -> Unit,
    ) {
        runRecognize(bitmap, hintLang) { blocks ->
            if (blocks == null) {
                callback(null)
                return@runRecognize
            }
            val merged = blocks
                .map { it.text.trim() }
                .filter(::looksLikeContent)
                .joinToString("\n")
                .trim()
                .take(MAX_CHARS)
            callback(merged.takeIf { it.isNotEmpty() })
        }
    }

    /**
     * Block-level flow used by the Lens overlay. Each [Block] keeps its
     * bounding box (pixel coords in the source bitmap) so the overlay can
     * paint the translation at the same on-screen position.
     *
     * Same content heuristic applies — buttons / "12:34" / icons survive
     * to OCR as 1-3 chars; without the filter the overlay would render
     * dozens of useless translated chips on top of UI chrome.
     */
    fun recognizeBlocks(
        bitmap: Bitmap,
        hintLang: String?,
        callback: (List<Block>?) -> Unit,
    ) {
        runRecognize(bitmap, hintLang) { blocks ->
            if (blocks == null) {
                callback(null)
                return@runRecognize
            }
            val filtered = blocks.filter { looksLikeContent(it.text) }
            callback(filtered)
        }
    }

    private fun runRecognize(
        bitmap: Bitmap,
        hintLang: String?,
        callback: (List<Block>?) -> Unit,
    ) {
        val recognizer = pickRecognizer(hintLang)
        val image = try {
            InputImage.fromBitmap(bitmap, 0)
        } catch (error: Exception) {
            Log.w(TAG, "InputImage.fromBitmap failed: ${error.message}")
            recognizer.close()
            callback(null)
            return
        }
        recognizer.process(image)
            .addOnSuccessListener { result ->
                val blocks = mutableListOf<Block>()
                for (block in result.textBlocks) {
                    val text = block.text.trim()
                    if (text.isEmpty()) continue
                    val box = block.boundingBox ?: continue
                    blocks.add(Block(text, Rect(box)))
                }
                callback(blocks)
                recognizer.close()
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "recognizer.process failed: ${error.message}")
                callback(null)
                recognizer.close()
            }
    }

    /**
     * Drop blocks that look like UI chrome — short labels (e.g. "Back",
     * "12:34", icons that survived to OCR as 1-2 chars). A block stays if
     * it's long enough, contains whitespace, or ends in sentence
     * punctuation.
     */
    private fun looksLikeContent(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return false
        if (trimmed.length >= 8) return true
        if (trimmed.any { it.isWhitespace() }) return true
        if (trimmed.any { it in PUNCT_CHARS }) return true
        // CJK scripts pack meaning much more densely than Latin — a 3-char
        // Japanese / Chinese / Korean sentence carries as much information
        // as 8-10 chars of English. The 8-char threshold was silently
        // dropping every short CJK utterance ("こんにちは", "你好", "안녕").
        if (trimmed.any { isCjk(it) }) return true
        return false
    }

    private fun isCjk(ch: Char): Boolean {
        val code = ch.code
        return (code in 0x4E00..0x9FFF) ||   // CJK Unified Ideographs
            (code in 0x3040..0x309F) ||      // Hiragana
            (code in 0x30A0..0x30FF) ||      // Katakana
            (code in 0xAC00..0xD7AF) ||      // Hangul Syllables
            (code in 0x3400..0x4DBF) ||      // CJK Ext A
            (code in 0xFF66..0xFF9F)         // Halfwidth Katakana
    }

    private val PUNCT_CHARS = setOf(
        '.', '!', '?', '…', '。', '！', '？', '،', ';', '；', ':', '：',
    )

    private fun pickRecognizer(hintLang: String?): TextRecognizer = when (hintLang) {
        "ja" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        "ko" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        "zh", "zh-TW", "zh-CN" ->
            TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        // Default Latin recognizer covers EN/VI/FR/DE/ES/PT/IT/RU/etc and
        // basic numbers — handles roughly 80% of mobile UI in our user base.
        else -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }
}
