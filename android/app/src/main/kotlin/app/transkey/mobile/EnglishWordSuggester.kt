package app.transkey.mobile

import android.content.Context

/**
 * English word suggestions for the EN keyboard strip (iOS QuickType parity).
 *
 * Built on the same frequency-ranked list the Vietnamese corrector uses for
 * English passthrough (assets/en_words.txt, most common first), so it adds no
 * asset. For the word being typed it offers, best first:
 * 1. completions: words that start with it, by frequency ("hel" -> "help", "hello");
 * 2. when nothing completes and it is not a word itself, corrections within a
 *    small edit distance ("teh" -> "the"), by distance then frequency.
 *
 * Mirrored in ios/TransKeyKeyboard/EnglishWordSuggester.swift: keep the two in sync.
 */
class EnglishWordSuggester internal constructor(words: Iterable<String>) {

    private val ranked = ArrayList<String>()   // most common first
    private val known = HashSet<String>()

    constructor(context: Context) : this(loadAsset(context, "en_words.txt"))

    init {
        for (line in words) {
            val s = line.trim().lowercase()
            if (s.length >= 2 && s.all { it in 'a'..'z' } && known.add(s)) ranked.add(s)
        }
    }

    /** Up to [max] suggestions for [typed], never [typed] itself; empty when [typed] is not a word. */
    fun suggest(typed: String, max: Int = 2): List<String> {
        if (max <= 0 || !isWordToken(typed)) return emptyList()
        val w = typed.lowercase()
        val out = ArrayList<String>(max)
        for (cand in ranked) {
            if (cand.length > w.length && cand.startsWith(w)) {
                out.add(matchCase(typed, cand))
                if (out.size >= max) return out
            }
        }
        if (out.isNotEmpty() || w.length < 2 || known.contains(w)) return out
        val cap = if (w.length <= 4) 1 else 2
        val scored = ArrayList<Pair<String, Int>>()
        for (cand in ranked) {
            if (kotlin.math.abs(cand.length - w.length) > cap) continue
            val d = distance(w, cand, cap)
            if (d <= cap) scored.add(cand to d)
        }
        // sortedBy is stable, so equal distances keep frequency order.
        for ((cand, _) in scored.sortedBy { it.second }) {
            out.add(matchCase(typed, cand))
            if (out.size >= max) break
        }
        return out
    }

    companion object {
        const val MAX_TOKEN = 24

        /** Letters only (ASCII), the only shape this list can complete. */
        fun isWordToken(s: String): Boolean =
            s.length in 1..MAX_TOKEN && s.all { it in 'a'..'z' || it in 'A'..'Z' }

        /** The trailing word of [before] (the text left of the caret), or "" when the caret is not right after one. */
        fun trailingWord(before: CharSequence): String {
            var i = before.length
            while (i > 0 && before[i - 1].isLetter()) i--
            return before.subSequence(i, before.length).toString()
        }

        private fun matchCase(typed: String, word: String): String = when {
            typed.length >= 2 && typed.all { it.isUpperCase() } -> word.uppercase()
            typed[0].isUpperCase() -> word.replaceFirstChar { it.uppercaseChar() }
            else -> word
        }

        /** Optimal-string-alignment distance (adjacent swaps cost 1), early exit above [cap]. */
        private fun distance(a: String, b: String, cap: Int): Int {
            val n = a.length
            val m = b.length
            var prev2 = IntArray(m + 1)
            var prev = IntArray(m + 1) { it }
            var cur = IntArray(m + 1)
            for (i in 1..n) {
                cur[0] = i
                var rowMin = cur[0]
                for (j in 1..m) {
                    val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                    var v = minOf(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                    if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
                        v = minOf(v, prev2[j - 2] + 1)
                    }
                    cur[j] = v
                    if (v < rowMin) rowMin = v
                }
                if (rowMin > cap) return cap + 1
                val t = prev2; prev2 = prev; prev = cur; cur = t
            }
            return prev[m]
        }

        private fun loadAsset(context: Context, name: String): List<String> =
            context.assets.open(name).bufferedReader().useLines { it.toList() }
    }
}
