package app.transkey.mobile

/**
 * Vietnamese Telex composer, raw-derived (Unikey/OpenKey-style).
 *
 * The buffer of record is the LITERAL keystroke sequence ([raw]); the displayed
 * Vietnamese ([composingText]) is recomputed from scratch on every key. This is
 * far more robust than mutating the display in place: fast typing, backspace and
 * mid-word edits can never leave a corrupt half-applied state.
 *
 * Telex rules:
 *   aa ee oo -> â ê ô,  dd -> đ,  aw ow uw -> ă ơ ư
 *   tones on the right vowel cluster: s f r x j = sắc huyền hỏi ngã nặng,
 *   placed by Vietnamese orthography (chào not chaò; giá not gía).
 *   Repeating a modifier UNDOES it and emits the literal key
 *   ("as"->á, "ass"->as; "oo"->ô, but "telexx"->telex). A repeat also sets
 *   [literalIntent], the signal to skip Vietnamese auto-correction so English
 *   words typed in VI mode ("telexx", "ass") survive verbatim.
 */
class TelexProcessor {

    private val raw = StringBuilder()
    private var composed = ""
    private var literal = false

    val hasComposingText: Boolean get() = raw.isNotEmpty()
    val composingText: String get() = composed
    val literalIntent: Boolean get() = literal

    fun reset() {
        raw.setLength(0); composed = ""; literal = false
    }

    fun input(ch: Char): Boolean {
        raw.append(ch)
        recompute()
        return true
    }

    fun backspace(): Boolean {
        if (raw.isEmpty()) return false
        raw.deleteCharAt(raw.length - 1)
        recompute()
        return true
    }

    fun commitWord(): String {
        val out = composed
        reset()
        return out
    }

    private fun recompute() {
        val out = StringBuilder()
        var lit = false
        for (c in raw) {
            val lc = c.lowercaseChar()
            var handled = false

            // Once the user escaped Telex by doubling a modifier (e.g. "currsor",
            // "telexx"), the REST of the word is literal English: no more tone /
            // circumflex / horn. This makes typing English words in VI mode easy
            // ("currsor" -> "cursor") instead of fighting diacritics mid-word.
            if (lit) {
                out.append(c)
                continue
            }

            // ---- tone keys s f r x j ----
            if (TONE_KEY.containsKey(lc) && out.isNotEmpty()) {
                val tone = TONE_KEY.getValue(lc)
                var vi = out.length - 1
                while (vi >= 0 && !isVowel(out[vi])) vi--
                if (vi >= 0) {
                    val ti = pickToneTarget(out, vi)
                    val cur = out[ti]
                    if (toneOf(cur) == tone) {
                        out.setCharAt(ti, stripTone(cur))
                        out.append(c); lit = true; handled = true
                    } else {
                        val res = applyTone(stripTone(cur), tone)
                        if (res != null) {
                            out.setCharAt(ti, if (cur.isUpperCase()) res.uppercaseChar() else res)
                            handled = true
                        }
                    }
                }
                if (!handled) { out.append(c); handled = true }
            } else if (lc in "aeo" && out.isNotEmpty() &&
                stripTone(out.last()).lowercaseChar() == lc &&
                stripTone(out.last()) !in CIRCUMFLEX.values
            ) {
                // circumflex: aa ee oo (preserve any tone already on the vowel)
                val prev = out.last()
                val t = toneOf(prev)
                val nb = CIRCUMFLEX.getValue(lc)
                val ch = if (t >= 0) applyTone(nb, t)!! else nb
                out.setCharAt(out.length - 1, if (prev.isUpperCase()) ch.uppercaseChar() else ch)
                handled = true
            } else if (lc in "aeo" && out.isNotEmpty() && stripTone(out.last()) == CIRCUMFLEX[lc]) {
                // undo circumflex: â + a -> aa (literal)
                val prev = out.last()
                out.setCharAt(out.length - 1, if (prev.isUpperCase()) lc.uppercaseChar() else lc)
                out.append(c); lit = true; handled = true
            } else if (lc == 'd' && out.isNotEmpty() && out.last().lowercaseChar() == 'd') {
                out.setCharAt(out.length - 1, if (out.last().isUpperCase()) 'Đ' else 'đ')
                handled = true
            } else if (lc == 'd' && out.isNotEmpty() && (out.last() == 'đ' || out.last() == 'Đ')) {
                out.setCharAt(out.length - 1, if (out.last() == 'Đ') 'D' else 'd')
                out.append(c); lit = true; handled = true
            } else if (lc == 'w' && out.isNotEmpty()) {
                when (applyHorn(out)) {
                    1 -> handled = true
                    2 -> { out.append(c); lit = true; handled = true } // undo -> literal
                }
            }

            if (!handled) out.append(c)
            normalizeIeYeUe(out)
        }
        composed = out.toString()
        literal = lit
    }

    /**
     * i/y + e + (at least one more letter) -> iê/yê. The trailing letter
     * marks the rime "iê" (always ê: tiên, biết), and "yê" (yên, and the y in
     * chuyên/truyền). A word-final "e" (keo, beo, theo) is left plain and an
     * explicit "ee" is handled by the circumflex branch. Tone-preserving, so a
     * tone typed after the cluster lands on the ê. Runs after every key.
     *
     * NOT 'u': every "u + e + consonant" in Vietnamese is the "qu" digraph
     * (qu = /kw/), where the e is the nucleus and is lexically plain e OR ê -
     * "quen"/"quét" (plain e) vs "quên"/"quết" (ê) are distinct words. Forcing
     * uê here would make "quen" unreachable. Genuine "uê" rimes (thuê, tuệ,
     * Huế) are all open, so they never hit this branch anyway. Mirrors the
     * qu/gi exception already in [pickToneTarget].
     *
     * "gi" exception: "gi" is also a digraph (onset /z/). "gi + e + vowel" is
     * the "eo" rime, so "gieo" (sow) keeps plain e. But "gi + e + consonant"
     * IS "giê" (giết, giếng), so we only skip when a vowel follows the e -
     * a positional rule that needs no word list and can't regress giết/giếng.
     */
    private fun normalizeIeYeUe(out: StringBuilder) {
        if (out.length < 3) return
        for (i in 0..out.length - 3) {
            val a = stripTone(out[i]).lowercaseChar()
            val b = out[i + 1]
            if (a !in "iy" || stripTone(b).lowercaseChar() != 'e') continue
            // "gi" digraph + e + vowel = the "eo" rime (gieo) -> leave plain e.
            val isGiEo = a == 'i' && i > 0 &&
                stripTone(out[i - 1]).lowercaseChar() == 'g' &&
                isVowel(out[i + 2])
            if (isGiEo) continue
            val t = toneOf(b)
            val ch = if (t >= 0) applyTone('ê', t)!! else 'ê'
            out.setCharAt(i + 1, if (b.isUpperCase()) ch.uppercaseChar() else ch)
        }
    }

    /**
     * Apply the Telex horn/breve key 'w' to the current word, cluster-aware so
     * "uo" becomes "ươ" in one keystroke ("thuong"+w -> "thương", the way most
     * Vietnamese type). Returns 0 = not applicable, 1 = horn applied,
     * 2 = horn undone (caller appends the literal 'w' + sets literal-intent).
     *
     *  - Special: a "uo" pair in the cluster horns BOTH -> "ươ" (or undoes
     *    both if already "ươ").
     *  - Else horns the rightmost a/o/u in the cluster (or undoes if already
     *    horned). The cluster is the trailing run of vowels, skipping any
     *    trailing consonants ("thuong" -> horn the "uo", not the "ng").
     */
    private fun applyHorn(out: StringBuilder): Int {
        var ce = out.length - 1
        while (ce >= 0 && !isVowel(out[ce])) ce--
        if (ce < 0) return 0
        var cs = ce
        while (cs - 1 >= 0 && isVowel(out[cs - 1])) cs--

        // "uo" pair -> horn both (ươ), or undo both if already ươ.
        for (i in cs until ce) {
            if (hornBase(out[i]) == 'u' && hornBase(out[i + 1]) == 'o') {
                if (stripTone(out[i]) == 'ư' && stripTone(out[i + 1]) == 'ơ') {
                    unhorn(out, i); unhorn(out, i + 1)
                    return 2
                }
                horn(out, i); horn(out, i + 1)
                return 1
            }
        }
        // Single vowel: rightmost hornable in the cluster.
        var target = -1
        for (i in cs..ce) if (hornBase(out[i]) in "aou") target = i
        if (target < 0) return 0
        return if (stripTone(out[target]) in "ăơư") { unhorn(out, target); 2 }
        else { horn(out, target); 1 }
    }

    /** Plain base letter ignoring tone AND horn/circumflex (ư->u, ấ->a). */
    private fun hornBase(ch: Char): Char {
        val b = stripTone(ch).lowercaseChar()
        return HORN_REV[b] ?: CIRC_REV[b] ?: b
    }

    private fun horn(out: StringBuilder, i: Int) {
        val p = out[i]; val t = toneOf(p)
        val nb = HORN[stripTone(p).lowercaseChar()] ?: return
        val ch = if (t >= 0) applyTone(nb, t)!! else nb
        out.setCharAt(i, if (p.isUpperCase()) ch.uppercaseChar() else ch)
    }

    private fun unhorn(out: StringBuilder, i: Int) {
        val p = out[i]; val t = toneOf(p)
        val orig = HORN_REV[stripTone(p).lowercaseChar()] ?: return
        val ch = if (t >= 0) applyTone(orig, t)!! else orig
        out.setCharAt(i, if (p.isUpperCase()) ch.uppercaseChar() else ch)
    }

    private fun pickToneTarget(out: StringBuilder, end: Int): Int {
        var start = end
        while (start - 1 >= 0 && isVowel(out[start - 1])) start--
        val closed = end + 1 < out.length && !isVowel(out[end + 1])
        if (end > start) {
            val first = stripTone(out[start]).lowercaseChar()
            val before = if (start > 0) out[start - 1].lowercaseChar() else ' '
            if ((before == 'g' && first == 'i') || (before == 'q' && first == 'u')) start++
        }
        val n = end - start + 1
        var pr = -1
        for (i in start..end) if (stripTone(out[i]).lowercaseChar() in PRIORITY) pr = i
        if (pr >= 0) return pr
        if (n == 1) return start
        if (n >= 3) return start + 1
        if (closed) return end
        val pair = "" + stripTone(out[start]).lowercaseChar() + stripTone(out[end]).lowercaseChar()
        return if (pair == "oa" || pair == "oe" || pair == "uy") end else start
    }

    private fun isVowel(ch: Char): Boolean {
        val c = ch.lowercaseChar()
        return BASE.contains(c) || TONE_OF.containsKey(c)
    }

    private fun stripTone(ch: Char): Char {
        val c = ch.lowercaseChar()
        val base = TONE_OF[c]?.first ?: c
        return if (ch.isUpperCase()) base.uppercaseChar() else base
    }

    private fun toneOf(ch: Char): Int = TONE_OF[ch.lowercaseChar()]?.second ?: -1

    private fun applyTone(base: Char, tone: Int): Char? {
        val variants = VOWELS[base.lowercaseChar()] ?: return null
        return variants[tone]
    }

    companion object {
        private val TONE_KEY = mapOf('s' to 0, 'f' to 1, 'r' to 2, 'x' to 3, 'j' to 4)
        private val PRIORITY = setOf('â', 'ă', 'ê', 'ô', 'ơ', 'ư')
        private val CIRCUMFLEX = mapOf('a' to 'â', 'e' to 'ê', 'o' to 'ô')
        private val HORN = mapOf('a' to 'ă', 'o' to 'ơ', 'u' to 'ư')
        private val HORN_REV = mapOf('ă' to 'a', 'ơ' to 'o', 'ư' to 'u')
        private val CIRC_REV = mapOf('â' to 'a', 'ê' to 'e', 'ô' to 'o')

        // base vowel -> [sắc, huyền, hỏi, ngã, nặng]
        private val VOWELS: Map<Char, CharArray> = mapOf(
            'a' to charArrayOf('á', 'à', 'ả', 'ã', 'ạ'),
            'â' to charArrayOf('ấ', 'ầ', 'ẩ', 'ẫ', 'ậ'),
            'ă' to charArrayOf('ắ', 'ằ', 'ẳ', 'ẵ', 'ặ'),
            'e' to charArrayOf('é', 'è', 'ẻ', 'ẽ', 'ẹ'),
            'ê' to charArrayOf('ế', 'ề', 'ể', 'ễ', 'ệ'),
            'i' to charArrayOf('í', 'ì', 'ỉ', 'ĩ', 'ị'),
            'o' to charArrayOf('ó', 'ò', 'ỏ', 'õ', 'ọ'),
            'ô' to charArrayOf('ố', 'ồ', 'ổ', 'ỗ', 'ộ'),
            'ơ' to charArrayOf('ớ', 'ờ', 'ở', 'ỡ', 'ợ'),
            'u' to charArrayOf('ú', 'ù', 'ủ', 'ũ', 'ụ'),
            'ư' to charArrayOf('ứ', 'ừ', 'ử', 'ữ', 'ự'),
            'y' to charArrayOf('ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ'),
        )
        private val BASE: Set<Char> = VOWELS.keys
        private val TONE_OF: Map<Char, Pair<Char, Int>> = buildMap {
            for ((base, variants) in VOWELS) for ((i, ch) in variants.withIndex()) put(ch, base to i)
        }
    }
}
