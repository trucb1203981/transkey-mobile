package app.transkey.mobile

import android.content.Context
import kotlin.math.abs

/**
 * Vietnamese auto-corrector + English passthrough.
 *
 * Vietnamese writes each space-separated token as one syllable from a finite
 * set (~7k). We load a frequency-ranked syllable list (assets/vn_syllables.txt)
 * and, for a possibly mistyped/merged token, return the closest valid
 * syllable(s) by a keyboard-proximity-weighted edit distance (g↔h cheap,
 * tone/diacritic-only cheaper, far letters expensive), tie-broken by frequency.
 * A DP segmentation also splits words merged by a missed space
 * ("bạnnkhoẻ" -> "bạn khoẻ").
 *
 * A common English word list (assets/en_words.txt) lets English mixed into
 * Vietnamese pass through untouched ("email", "code", "class").
 */
class VietWordCorrector internal constructor(
    vietnameseWords: Iterable<String>,
    englishWords: Iterable<String>,
) {

    private val rank = HashMap<String, Int>()               // syllable -> freq rank (0 = top)
    private val byLen = HashMap<Int, MutableList<String>>()  // length -> syllables
    private val english = HashSet<String>()                  // common English words

    constructor(context: Context) : this(
        loadAsset(context, "vn_syllables.txt"),
        loadAsset(context, "en_words.txt"),
    )

    init {
        var i = 0
        for (line in vietnameseWords) {
            val s = line.trim()
            if (s.isNotEmpty() && rank.putIfAbsent(s, i) == null) {
                byLen.getOrPut(s.length) { ArrayList() }.add(s)
            }
            i++
        }
        for (line in englishWords) {
            val s = line.trim()
            if (s.length >= 2) english.add(s)
        }
    }

    fun isValid(word: String): Boolean = rank.containsKey(word.lowercase())

    /** A known common English word - typed as-is, never Vietnamese-corrected. */
    fun isEnglish(word: String): Boolean = word.length >= 2 && english.contains(word.lowercase())

    /** Best-first suggestions for a (possibly mistyped) syllable. */
    fun suggest(typed: String, max: Int = 3): List<String> {
        if (!isCorrectionCandidate(typed) || max <= 0) return emptyList()
        val w = typed.lowercase()
        if (rank.containsKey(w) || english.contains(w)) return emptyList()
        val rows = DistanceRows()
        val scored = ArrayList<Pair<String, Double>>()
        for (len in (w.length - 1)..(w.length + 1)) {
            val pool = byLen[len] ?: continue
            for (cand in pool) {
                val cost = distance(w, cand, MAX_COST, rows)
                if (cost <= MAX_COST) {
                    scored.add(cand to cost + (rank[cand] ?: 0) * RANK_WEIGHT)
                }
            }
        }
        scored.sortBy { it.second }
        val res = ArrayList<String>(max)
        for ((s, _) in scored) {
            if (s != w && s !in res) {
                res.add(matchCase(typed, s))
                if (res.size >= max) break
            }
        }
        return res
    }

    /**
     * Auto-fix a committed word: returns a replacement (possibly several
     * syllables separated by spaces) or null to keep what was typed. Runs a DP
     * segmentation; each piece must be (or correct within [SEG_MAX_COST] to) a
     * valid syllable, with a per-syllable [JOIN_PENALTY] to avoid over-splitting.
     */
    fun fix(typed: String): String? {
        if (!isCorrectionCandidate(typed)) return null
        val w = typed.lowercase()
        if (rank.containsKey(w) || english.contains(w)) return null
        val n = w.length
        if (n > MAX_TOKEN) return null
        val rows = DistanceRows()
        val nearest = HashMap<String, Pair<String?, Double>>()
        val dp = DoubleArray(n + 1) { Double.MAX_VALUE }
        val back = arrayOfNulls<Pair<Int, String>>(n + 1)
        dp[0] = 0.0
        for (i in 1..n) {
            val lo = maxOf(0, i - MAX_SYL)
            for (j in lo until i) {
                if (dp[j] == Double.MAX_VALUE) continue
                val seg = w.substring(j, i)
                val word: String
                val c: Double
                if (rank.containsKey(seg)) {
                    word = seg
                    c = 0.0
                } else {
                    val (bw, bc) = nearest.getOrPut(seg) { bestSingle(seg, SEG_MAX_COST, rows) }
                    if (bw == null) continue
                    word = bw
                    c = bc
                }
                val total = dp[j] + c + JOIN_PENALTY
                if (total < dp[i]) {
                    dp[i] = total
                    back[i] = j to word
                }
            }
        }
        if (dp[n] == Double.MAX_VALUE) return null
        val parts = ArrayList<String>()
        var i = n
        while (i > 0) {
            val b = back[i] ?: return null
            parts.add(b.second)
            i = b.first
        }
        parts.reverse()
        val result = parts.joinToString(" ")
        if (result == w) return null
        return matchCase(typed, result)
    }

    /** Nearest valid syllable to [w] within [cap]; (null, MAX) if none. */
    private fun bestSingle(w: String, cap: Double, rows: DistanceRows): Pair<String?, Double> {
        if (w.length < 2) return null to Double.MAX_VALUE
        var best: String? = null
        var bestCost = cap + 0.001
        for (len in (w.length - 1)..(w.length + 1)) {
            val pool = byLen[len] ?: continue
            for (cand in pool) {
                val cost = distance(w, cand, cap, rows)
                if (cost < bestCost ||
                    (cost == bestCost && best != null && (rank[cand] ?: 0) < (rank[best] ?: 0))
                ) {
                    bestCost = cost
                    best = cand
                }
            }
        }
        return best to (if (best == null) Double.MAX_VALUE else bestCost)
    }

    private fun matchCase(src: String, out: String): String =
        if (src.isNotEmpty() && src[0].isUpperCase()) out.replaceFirstChar { it.uppercaseChar() } else out

    /**
     * Conservative by design: capitalized tokens may be names, while URL,
     * email and code punctuation must never enter Vietnamese correction.
     */
    private fun isCorrectionCandidate(word: String): Boolean =
        word.length in 2..MAX_TOKEN && word.all { it.isLetter() && !it.isUpperCase() }

    /** Keyboard-proximity-weighted edit distance, with early exit above [cap]. */
    // Scratch rows belong to one request: suggestion and commit can run on
    // different threads without sharing mutable edit-distance state.
    private class DistanceRows {
        val first = DoubleArray(MAX_TOKEN + 2)
        val second = DoubleArray(MAX_TOKEN + 2)
    }

    private fun distance(a: String, b: String, cap: Double, rows: DistanceRows): Double {
        val n = a.length
        val m = b.length
        if (abs(n - m) > 1) return cap + 1
        var prev = rows.first
        var cur = rows.second
        for (j in 0..m) prev[j] = j * INDEL
        val band = (cap / INDEL).toInt()
        for (i in 1..n) {
            cur[0] = i * INDEL
            var rowMin = cur[0]
            val ca = a[i - 1]
            // Outside this diagonal band, insertions/deletions alone exceed
            // the cap. Reset its edges because the scratch rows are reused.
            val first = maxOf(1, i - band)
            val last = minOf(m, i + band)
            if (first > 1) cur[first - 1] = cap + INDEL
            if (last < m) cur[last + 1] = cap + INDEL
            for (j in first..last) {
                val sub = prev[j - 1] + subCost(ca, b[j - 1])
                val del = prev[j] + INDEL
                val ins = cur[j - 1] + INDEL
                var v = sub
                if (del < v) v = del
                if (ins < v) v = ins
                cur[j] = v
                if (v < rowMin) rowMin = v
            }
            if (rowMin > cap) return cap + 1
            val t = prev; prev = cur; cur = t
        }
        return prev[m]
    }

    private fun subCost(a: Char, b: Char): Double {
        if (a == b) return 0.0
        val ai = CHAR_IDS[a.code]
        val bi = CHAR_IDS[b.code]
        if (ai >= 0 && bi >= 0) return SUBSTITUTIONS[ai][bi]
        val ba = base(a)
        val bb = base(b)
        if (ba == bb) return SAME_BASE
        if (adjacent(ba, bb)) return ADJ
        return FAR
    }

    companion object {
        private fun loadAsset(context: Context, name: String): List<String> =
            runCatching {
                context.assets.open(name).bufferedReader().use { it.readLines() }
            }.getOrDefault(emptyList())

        private const val INDEL = 1.0
        private const val SAME_BASE = 0.3
        private const val ADJ = 0.7
        private const val FAR = 2.0
        private const val MAX_COST = 2.2
        private const val RANK_WEIGHT = 0.00014

        private const val MAX_TOKEN = 16
        private const val MAX_SYL = 7
        private const val SEG_MAX_COST = 1.3
        private const val JOIN_PENALTY = 0.8

        private val ROWS = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        private val POS: Map<Char, Pair<Int, Int>> = buildMap {
            for ((r, row) in ROWS.withIndex()) for ((c, ch) in row.withIndex()) put(ch, r to c)
        }

        private fun adjacent(a: Char, b: Char): Boolean {
            val pa = POS[a] ?: return false
            val pb = POS[b] ?: return false
            return abs(pa.first - pb.first) <= 1 && abs(pa.second - pb.second) <= 1
        }

        private val BASE_MAP: Map<Char, Char> = buildMap {
            val groups = mapOf(
                'a' to "àáảãạăằắẳẵặâầấẩẫậ",
                'e' to "èéẻẽẹêềếểễệ",
                'i' to "ìíỉĩị",
                'o' to "òóỏõọôồốổỗộơờớởỡợ",
                'u' to "ùúủũụưừứửữự",
                'y' to "ỳýỷỹỵ",
                'd' to "đ",
            )
            for ((b, variants) in groups) for (ch in variants) put(ch, b)
        }

        private fun base(ch: Char): Char {
            val c = ch.lowercaseChar()
            return BASE_MAP[c] ?: c
        }

        // Resolve diacritics and keyboard proximity once, outside the hot DP
        // loop. Keep the existing calculation for letters outside this alphabet.
        private val ALPHABET = ('a'..'z').toList() + BASE_MAP.keys
        private val CHAR_IDS = IntArray(Char.MAX_VALUE.code + 1) { -1 }.apply {
            ALPHABET.forEachIndexed { index, ch -> this[ch.code] = index }
        }
        private val SUBSTITUTIONS = Array(ALPHABET.size) { i ->
            DoubleArray(ALPHABET.size) { j ->
                val a = ALPHABET[i]
                val b = ALPHABET[j]
                when {
                    a == b -> 0.0
                    base(a) == base(b) -> SAME_BASE
                    adjacent(base(a), base(b)) -> ADJ
                    else -> FAR
                }
            }
        }
    }
}
