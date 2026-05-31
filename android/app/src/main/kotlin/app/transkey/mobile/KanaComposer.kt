package app.transkey.mobile

/**
 * Kana buffer for the Japanese 12-key flick layout.
 *
 * A flick yields a kana DIRECTLY (no romaji step), so this is just an editable
 * run of kana shown as composing text. The dakuten/handakuten/small key
 * ([modifyLast]) cycles the LAST kana through its variants (か->が, は->ば->ぱ,
 * つ->っ->づ, あ->ぁ), matching the keitai 小゛゜ key. Kept separate from
 * [RomajiKanaConverter] (the qwerty romaji path) - same role, different input.
 *
 * Kana->kanji conversion needs a dictionary and is out of scope here, so the
 * run stays kana until committed (space/enter) like the romaji path.
 */
class KanaComposer {

    private val buf = StringBuilder()

    val hasComposingText: Boolean get() = buf.isNotEmpty()
    val composingText: String get() = buf.toString()

    fun reset() { buf.setLength(0) }

    /** Replace the buffer (e.g. to resume editing after cancelling conversion). */
    fun load(s: String) { buf.setLength(0); buf.append(s) }

    fun add(s: String) { buf.append(s) }

    fun commit(): String { val s = buf.toString(); reset(); return s }

    /** Cycle the last kana through its dakuten/handakuten/small variants. */
    fun modifyLast() {
        if (buf.isEmpty()) return
        CYCLE[buf.last()]?.let { buf.setCharAt(buf.length - 1, it) }
    }

    /** Remove one kana. True if something changed. */
    fun backspace(): Boolean {
        if (buf.isNotEmpty()) { buf.deleteCharAt(buf.length - 1); return true }
        return false
    }

    companion object {
        // Each group lists a kana and its variants in cycle order; the last
        // wraps back to the first. Build a next-char map from them.
        private val GROUPS = arrayOf(
            "あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ",
            "かが", "きぎ", "くぐ", "けげ", "こご",
            "さざ", "しじ", "すず", "せぜ", "そぞ",
            "ただ", "ちぢ", "つっづ", "てで", "とど",
            "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ",
            "やゃ", "ゆゅ", "よょ", "わゎ",
        )
        private val CYCLE: Map<Char, Char> = buildMap {
            for (g in GROUPS) for (i in g.indices) put(g[i], g[(i + 1) % g.length])
        }
    }
}
