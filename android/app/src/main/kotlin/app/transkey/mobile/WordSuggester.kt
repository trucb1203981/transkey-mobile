package app.transkey.mobile

import android.content.Context
import java.text.Normalizer

/**
 * Word suggestions for the Latin keyboard strips (EN, DE, FR, ES, IT, PT), in
 * the iOS QuickType layout.
 *
 * Each language has a frequency-ranked list, most common first: EN reuses
 * assets/en_words.txt (also the Vietnamese corrector's English passthrough),
 * the others are assets/words_<lang>.txt built by tools/keyboard-words. Entries
 * keep their natural case (German nouns are capitalised). Matching ignores
 * case and accents, so a user who types without accents still gets them.
 * For the word being typed it offers, best first:
 * 1. by frequency, the same word with its accents or capital restored
 *    ("ecole" -> "école", German "haus" -> "Haus") and completions
 *    ("hel" -> "help", "hello");
 * 2. when nothing matches and it is not a word itself, corrections within a
 *    small edit distance ("teh" -> "the"), by distance then frequency.
 *
 * Mirrored in ios/TransKeyKeyboard/WordSuggester.swift: keep the two in sync.
 */
class WordSuggester internal constructor(words: Iterable<String>) {

    private val forms = ArrayList<String>()   // display form, most common first
    private val keys = ArrayList<String>()    // accent-free lowercase, same index
    private val known = HashSet<String>()     // lowercase forms

    init {
        for (line in words) {
            val s = line.trim()
            if (s.length < 2 || !s.all { it.isLetter() }) continue
            val lower = s.lowercase()
            if (!known.add(lower)) continue
            forms.add(s)
            keys.add(fold(lower))
        }
    }

    /** Up to [max] suggestions for [typed], never [typed] itself; empty when [typed] is not a word. */
    fun suggest(typed: String, max: Int = 2): List<String> {
        if (max <= 0 || !isWordToken(typed)) return emptyList()
        val lower = typed.lowercase()
        val key = fold(lower)
        val out = ArrayList<String>(max)
        fun add(i: Int): Boolean {
            val s = matchCase(typed, forms[i])
            if (s !in out) out.add(s)
            return out.size >= max
        }
        // One pass in frequency order over two kinds of match: the typed word
        // itself with its accents or capital restored, and completions. Ranking
        // them together keeps a rare exact form ("Hau") behind a common
        // completion ("Haus").
        for (i in keys.indices) {
            val k = keys[i]
            val match = if (k.length == key.length) {
                k == key && matchCase(typed, forms[i]) != typed
            } else {
                k.length > key.length && k.startsWith(key)
            }
            if (match && add(i)) return out
        }
        if (out.isNotEmpty() || key.length < 2 || known.contains(lower)) return out
        val cap = if (key.length <= 4) 1 else 2
        val scored = ArrayList<Pair<Int, Int>>()
        for (i in keys.indices) {
            if (kotlin.math.abs(keys[i].length - key.length) > cap) continue
            val d = distance(key, keys[i], cap)
            if (d <= cap) scored.add(i to d)
        }
        // sortedBy is stable, so equal distances keep frequency order.
        for ((i, _) in scored.sortedBy { it.second }) {
            if (add(i)) break
        }
        return out
    }

    companion object {
        const val MAX_TOKEN = 24

        /** Languages that ship a word list. */
        val LANGS = setOf("en", "de", "fr", "es", "it", "pt")

        fun load(context: Context, lang: String): WordSuggester =
            WordSuggester(loadAsset(context, if (lang == "en") "en_words.txt" else "words_$lang.txt"))

        /** Letters only, the only shape these lists can complete. */
        fun isWordToken(s: String): Boolean = s.length in 1..MAX_TOKEN && s.all { it.isLetter() }

        /** The trailing word of [before] (the text left of the caret), or "" when the caret is not right after one. */
        fun trailingWord(before: CharSequence): String {
            var i = before.length
            while (i > 0 && before[i - 1].isLetter()) i--
            return before.subSequence(i, before.length).toString()
        }

        /** Lowercase with accents stripped ("École" -> "ecole"); ß and other base letters stay. */
        internal fun fold(s: String): String =
            Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).filter { Character.getType(it) != Character.NON_SPACING_MARK.toInt() }

        /**
         * The suggestion in the case the user is typing: ALL CAPS stays all
         * caps, a capitalised word gets a capital, otherwise the list's own
         * form (so German nouns keep their capital).
         */
        private fun matchCase(typed: String, form: String): String = when {
            typed.length >= 2 && typed.all { it.isUpperCase() } -> form.uppercase()
            typed[0].isUpperCase() -> form.replaceFirstChar { it.uppercaseChar() }
            else -> form
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
