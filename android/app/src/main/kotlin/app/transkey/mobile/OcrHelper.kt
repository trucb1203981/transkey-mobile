package app.transkey.mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.atomic.AtomicInteger

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
        recognizeFiltered(bitmap, hintLang) { blocks ->
            if (blocks == null) {
                callback(null)
                return@recognizeFiltered
            }
            val merged = blocks
                .map { it.text.trim() }
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
        recognizeFiltered(bitmap, hintLang, callback)
    }

    /**
     * Run OCR with [hintLang], apply the content heuristic, and hand back
     * a filtered block list. When [hintLang] is null we DON'T know which
     * script the user is pointing the lens at, so the Latin-only fallback
     * would mangle Japanese / Korean / Chinese pages into Latin garbage
     * ("返信が遅く" → "Xyt-6ɔ2t"). Run all four recognizers in parallel
     * and keep the result with the most meaningful captured characters
     * — Google Lens uses the same heuristic.
     */
    private fun recognizeFiltered(
        bitmap: Bitmap,
        hintLang: String?,
        callback: (List<Block>?) -> Unit,
    ) {
        if (hintLang != null) {
            // User picked a specific source lang — trust the hint, use a
            // single recognizer to keep memory + latency low.
            runRecognize(bitmap, hintLang) { blocks ->
                callback(blocks?.filter { looksLikeContent(it.text) })
            }
            return
        }
        recognizeAuto(bitmap, callback)
    }

    /**
     * Auto-detect script by running Latin + Japanese + Korean + Chinese
     * recognizers in parallel and picking whichever returned the most
     * "meaningful" text (post content-heuristic, char count). ML Kit
     * recognizers are async + thread-safe so this fans out without any
     * scheduling — slowest-of-four wallclock is roughly 200-500 ms.
     *
     * Tradeoff: ~12 MB peak memory across the four loaded models.
     * Acceptable for one-shot scans; recognizers close after each run.
     */
    private fun recognizeAuto(
        bitmap: Bitmap,
        callback: (List<Block>?) -> Unit,
    ) {
        val scripts = listOf<String?>(null, "ja", "ko", "zh")
        val results = arrayOfNulls<List<Block>>(scripts.size)
        val remaining = AtomicInteger(scripts.size)
        val lock = Any()

        fun finishIfDone() {
            if (remaining.decrementAndGet() != 0) return
            val best = synchronized(lock) {
                results
                    .filterNotNull()
                    .maxByOrNull { list -> list.sumOf { b -> b.text.length } }
                    ?: emptyList()
            }
            Log.d(
                TAG,
                "auto-OCR picked: ${scripts.zip(results.toList())
                    .map { (s, r) -> "${s ?: "latin"}=${r?.sumOf { it.text.length } ?: 0}" }
                    .joinToString(",")
                }",
            )
            callback(best)
        }

        scripts.forEachIndexed { idx, hint ->
            runRecognize(bitmap, hint) { blocks ->
                val filtered = blocks?.filter { looksLikeContent(it.text) } ?: emptyList()
                synchronized(lock) { results[idx] = filtered }
                finishIfDone()
            }
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
                callback(mergeAdjacentBlocks(blocks))
                recognizer.close()
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "recognizer.process failed: ${error.message}")
                callback(null)
                recognizer.close()
            }
    }

    /**
     * Glue back together OCR blocks that ML Kit returned as separate
     * paragraphs but really belong to one sentence wrapped across visual
     * lines. ML Kit's TextBlock segmentation is conservative — chat
     * bubble backgrounds, inline emojis, or just narrow text containers
     * can split a single sentence into two adjacent blocks. Translating
     * those independently changes the meaning ("I think it will rain" +
     * "tomorrow." → loses the time-of-event link); the existing CONTEXT
     * block helps the LLM, but it still has to commit one translation
     * per OCR block.
     *
     * Heuristic — merge B into A when ALL hold:
     *  - Same column: their horizontal extents overlap by at least 60%
     *    of the narrower block (avoids merging side-by-side columns).
     *  - Same vertical neighbourhood: B.top - A.bottom < min line
     *    height (gap smaller than one line of text means B is the next
     *    wrapped line, not a new paragraph).
     *  - A doesn't end with a strong sentence terminator. "。" / "!" /
     *    "?" / ".\n" suggest A is a complete thought, so we leave B as
     *    a fresh block even when geometrically close.
     */
    private fun mergeAdjacentBlocks(blocks: List<Block>): List<Block> {
        if (blocks.size < 2) return blocks
        // Sort by top first (and left as tiebreaker so multi-column
        // pages still produce a stable reading order).
        val sorted = blocks.sortedWith(compareBy({ it.bounds.top }, { it.bounds.left }))
        val merged = ArrayList<Block>(sorted.size)
        merged.add(sorted[0])
        for (i in 1 until sorted.size) {
            val next = sorted[i]
            val current = merged.last()
            if (shouldMerge(current, next)) {
                merged[merged.lastIndex] = Block(
                    text = current.text + "\n" + next.text,
                    bounds = Rect(
                        minOf(current.bounds.left, next.bounds.left),
                        minOf(current.bounds.top, next.bounds.top),
                        maxOf(current.bounds.right, next.bounds.right),
                        maxOf(current.bounds.bottom, next.bounds.bottom),
                    ),
                )
            } else {
                merged.add(next)
            }
        }
        return merged
    }

    private fun shouldMerge(a: Block, b: Block): Boolean {
        // Only consider merging when B is below A (or just barely
        // overlapping its baseline).
        val verticalGap = b.bounds.top - a.bounds.bottom
        val lineH = minOf(a.bounds.height(), b.bounds.height())
        if (verticalGap > lineH) return false
        if (verticalGap < -(lineH / 2)) return false  // B starts well above A → different paragraphs

        val overlap = minOf(a.bounds.right, b.bounds.right) - maxOf(a.bounds.left, b.bounds.left)
        if (overlap <= 0) return false
        val narrower = minOf(a.bounds.width(), b.bounds.width())
        if (narrower <= 0) return false
        val overlapRatio = overlap.toFloat() / narrower
        if (overlapRatio < 0.6f) return false  // side-by-side columns

        val lastChar = a.text.trimEnd().lastOrNull() ?: return true
        if (lastChar in PARAGRAPH_TERMINATORS) return false

        // Don't glue a new bullet onto a previous one — bulleted/numbered
        // lists are semantically distinct items and merging them produces
        // a giant single "paragraph" that the batch translator may truncate
        // (LinkedIn job posts with 8-12 bullet requirements were getting
        // cut off mid-list with an "…" ellipsis). Detect by checking the
        // first non-whitespace character of B against common bullet markers.
        val bFirst = b.text.trimStart().firstOrNull()
        if (bFirst != null && bFirst in BULLET_STARTERS) return false
        // Also catch numbered lists: "1. ", "(1)", "1)".
        if (b.text.trimStart().take(4).matches(NUMBERED_LIST_REGEX)) return false

        // Cap merged size so even when individual blocks look like wrapped
        // continuation, we don't accumulate them into a multi-paragraph
        // monster. ~400 chars is the empirically-safe ceiling: Haiku 3.5
        // reliably translates strings up to this length without invented
        // "…" truncation markers.
        if (a.text.length + b.text.length > MERGE_CHAR_CAP) return false
        return true
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

    /**
     * Characters that indicate the end of a complete thought — when a
     * block ends with one of these, [mergeAdjacentBlocks] leaves the
     * next block as its own paragraph even if geometry says they're
     * close. ":" / "：" intentionally excluded — a line ending with
     * "Tanaka-san:" usually continues with the message body below.
     */
    private val PARAGRAPH_TERMINATORS = setOf(
        '.', '!', '?', '…', '。', '！', '？',
    )

    /** First characters that mark the start of a bullet item — used to
     *  stop [mergeAdjacentBlocks] from gluing successive bullets together. */
    private val BULLET_STARTERS = setOf(
        '•', '·', '◦', '▪', '▫', '►', '▶', '■', '★', '☆',
        '-', '–', '—', '*', '+',
    )

    /** Matches "1.", "12)", "(3)" etc at the start of a string. */
    private val NUMBERED_LIST_REGEX = Regex("""^\(?\d{1,3}[.)]\s?.*""")

    /** Hard cap on merged-block size in chars. Above this the LLM batch
     *  translator becomes unreliable (truncates the tail with "…" even
     *  with explicit "no truncation" rules in the prompt). Picked from
     *  the LinkedIn-job-post regression where ~600-char merged bullets
     *  reliably truncated; 400 leaves headroom for the merge that adds
     *  one final wrapped line. */
    private const val MERGE_CHAR_CAP = 400

    private fun pickRecognizer(hintLang: String?): TextRecognizer = when (hintLang) {
        "ja" -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        "ko" -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        "zh", "zh-TW", "zh-CN" ->
            TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        // Devanagari covers Hindi / Marathi / Nepali. Without this case
        // the lookup fell through to the Latin recognizer, which CAN'T
        // read Devanagari — Hindi screens silently returned garbage
        // glyphs instead of either real OCR or the vision fallback.
        "hi", "mr", "ne" ->
            TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
        // Default Latin recognizer covers Latin-script languages (en, vi,
        // fr, de, es, pt, it, id, ms, tr, pl, nl, sv, da, fi, no, cs, sk,
        // hu, ro, hr, sr-Latn, …) plus basic digits. NOTE: it CANNOT read
        // Cyrillic, Thai, Arabic, Hebrew, Greek, Khmer, Lao, Myanmar,
        // Georgian, etc. — those are handled by the vision LLM fallback,
        // see [needsVisionForSource].
        else -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    /**
     * Script-class set ML Kit cannot read with any of its on-device
     * recognizers. When the user pins source to one of these, Lens must
     * skip ML Kit entirely and route the bitmap through the vision LLM
     * (Gemini-first via `/translate-image?withBoxes=true`) — running ML
     * Kit's Latin recognizer on Cyrillic / Thai / Arabic either returns
     * nothing or hallucinates lookalike Latin chars (garbage out).
     *
     * Kept as a hard-coded set rather than a probe because the user's
     * source pick is the authoritative signal — the cost of being wrong
     * (vision call on a Latin screen) is far higher than the cost of
     * being right (ML Kit free path on a supported script).
     */
    fun needsVisionForSource(hintLang: String?): Boolean {
        val lang = hintLang?.lowercase()?.split('-', '_')?.firstOrNull() ?: return false
        return lang in VISION_ONLY_LANGS
    }

    private val VISION_ONLY_LANGS = setOf(
        // Cyrillic
        "ru", "uk", "bg", "sr", "mk", "be", "kk", "ky", "mn",
        // Thai / Lao / Khmer / Myanmar
        "th", "lo", "km", "my",
        // Arabic-script (Arabic, Persian, Urdu, Pashto)
        "ar", "fa", "ur", "ps",
        // Hebrew / Yiddish, Greek, Georgian, Armenian, Sinhala, Amharic
        "he", "yi", "el", "ka", "hy", "si", "am",
        // Non-Devanagari Indic ML Kit doesn't ship a recognizer for
        "ta", "te", "kn", "ml", "or", "gu", "pa", "bn",
    )
}
