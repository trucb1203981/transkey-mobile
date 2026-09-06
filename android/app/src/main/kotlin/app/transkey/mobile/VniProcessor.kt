package app.transkey.mobile

/**
 * Vietnamese VNI composer, raw-derived (Unikey-style), sibling of
 * [TelexProcessor].
 *
 * The buffer of record is the LITERAL keystroke sequence ([raw]); the displayed
 * Vietnamese ([composingText]) is recomputed from scratch on every key, so fast
 * typing, backspace and mid-word edits can never leave a corrupt half-applied
 * state.
 *
 * VNI rules (the modifier is a DIGIT typed after the syllable):
 *   1 2 3 4 5 = sac huyen hoi nga nang, placed by Vietnamese orthography,
 *   6 = circumflex (a e o -> a^ e^ o^), 7 = horn (o u -> o+ u+, "uo" horns
 *   both), 8 = breve (a -> a(), 9 = d stroke, 0 = clear the tone.
 *
 * Repeating a modifier UNDOES it and emits the literal digit ("a1" -> a with
 * sac, "a11" -> "a1"; "d9" -> d stroked, "d99" -> "d9"), and from that point
 * the REST of the word is literal. That escape is what makes "covid19" and
 * other digit-carrying words typable at all, and it sets [literalIntent], the
 * signal to skip Vietnamese auto-correction on commit. Same shape as the
 * doubled-key escape in Telex.
 */
class VniProcessor {

    private val raw = StringBuilder()
    private var composed = ""
    private var literal = false

    val hasComposingText: Boolean get() = raw.isNotEmpty()
    val composingText: String get() = composed
    val literalIntent: Boolean get() = literal

    /**
     * The literal LETTER keystrokes typed so far, with the VNI digit modifiers
     * dropped. The keyboard compares this with the composed word to keep an
     * English word the user actually typed ("cursor") verbatim, so it must
     * survive a backspace - hence deriving it from [raw] rather than having the
     * caller track it.
     */
    val rawLetters: String get() = raw.filter { it.isLetter() }.toString()

    fun reset() {
        raw.setLength(0)
        composed = ""
        literal = false
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
        for (key in raw) {
            // Once the user escaped VNI by repeating a modifier ("covid19"),
            // the REST of the word is literal: no more tones or shapes.
            if (lit) {
                out.append(key)
                continue
            }
            if (!key.isDigit()) {
                out.append(key)
                relocateTone(out)
                continue
            }
            val applied = when (key) {
                in '1'..'5' -> applyTone(out, key - '1')
                '6' -> applyCircumflex(out)
                '7' -> applyHorn(out)
                '8' -> applyBreve(out)
                '9' -> applyDStroke(out)
                else -> clearTone(out) // '0'
            }
            if (applied) {
                relocateTone(out)
            } else {
                // Undone (a repeat) or nothing to modify: the digit is literal,
                // and the modifier helpers above have already reverted their
                // diacritic, so the word reads exactly as it was typed.
                out.append(key)
                lit = true
            }
        }
        composed = out.toString()
        literal = lit
    }

    /**
     * Returns true when the tone was applied, false when it was undone or is
     * not applicable - in both of those cases the caller emits the literal
     * digit and stops composing the word.
     */
    private fun applyTone(out: StringBuilder, tone: Int): Boolean {
        val end = lastVowelIndex(out)
        if (end < 0) return false
        val target = pickToneTarget(out, end)
        val current = out[target]
        if (toneOf(current) == tone) { // repeat: drop the tone, emit the digit
            out.setCharAt(target, stripTone(current))
            return false
        }
        val toned = toneChar(stripTone(current), tone) ?: return false
        out.setCharAt(target, preserveCase(current, toned))
        return true
    }

    private fun applyCircumflex(out: StringBuilder): Boolean =
        applyShape(out, setOf('a', 'e', 'o'), mapOf('a' to 'â', 'e' to 'ê', 'o' to 'ô'))

    private fun applyBreve(out: StringBuilder): Boolean =
        applyShape(out, setOf('a'), mapOf('a' to 'ă'))

    /**
     * Circumflex/breve on the nearest eligible vowel. A vowel that already
     * carries exactly this shape is reverted instead (the repeat escape).
     */
    private fun applyShape(
        out: StringBuilder,
        accepted: Set<Char>,
        replacements: Map<Char, Char>,
    ): Boolean {
        for (index in out.indices.reversed()) {
            val current = out[index]
            val base = plainBase(current)
            if (base !in accepted) continue
            val shaped = replacements.getValue(base)
            if (stripTone(current).lowercaseChar() == shaped) {
                out.setCharAt(index, replaceShapeKeepingTone(current, base))
                return false
            }
            out.setCharAt(index, replaceShapeKeepingTone(current, shaped))
            return true
        }
        return false
    }

    private fun applyHorn(out: StringBuilder): Boolean {
        val end = lastVowelIndex(out)
        if (end < 0) return false
        var start = end
        while (start > 0 && isVowel(out[start - 1])) start--
        for (index in start until end) {
            if (plainBase(out[index]) == 'u' && plainBase(out[index + 1]) == 'o') {
                // "uo" horns as a pair (thuong -> thuong with horns); a second
                // 7 unhorns both.
                val horned = stripTone(out[index]).lowercaseChar() == 'ư' &&
                    stripTone(out[index + 1]).lowercaseChar() == 'ơ'
                out.setCharAt(index, replaceShapeKeepingTone(out[index], if (horned) 'u' else 'ư'))
                out.setCharAt(index + 1, replaceShapeKeepingTone(out[index + 1], if (horned) 'o' else 'ơ'))
                return !horned
            }
        }
        for (index in end downTo start) {
            val base = plainBase(out[index])
            val shaped = when (base) {
                'u' -> 'ư'
                'o' -> 'ơ'
                else -> null
            } ?: continue
            if (stripTone(out[index]).lowercaseChar() == shaped) {
                out.setCharAt(index, replaceShapeKeepingTone(out[index], base))
                return false
            }
            out.setCharAt(index, replaceShapeKeepingTone(out[index], shaped))
            return true
        }
        return false
    }

    private fun applyDStroke(out: StringBuilder): Boolean {
        for (index in out.indices.reversed()) {
            when (out[index]) {
                'd' -> { out.setCharAt(index, 'đ'); return true }
                'D' -> { out.setCharAt(index, 'Đ'); return true }
                // Already stroked: a second 9 restores the plain d and the
                // digit is emitted literally.
                'đ' -> { out.setCharAt(index, 'd'); return false }
                'Đ' -> { out.setCharAt(index, 'D'); return false }
            }
        }
        return false
    }

    private fun clearTone(out: StringBuilder): Boolean {
        var changed = false
        for (index in out.indices) {
            val current = out[index]
            val plain = stripTone(current)
            if (plain != current) {
                out.setCharAt(index, plain)
                changed = true
            }
        }
        return changed
    }

    private fun relocateTone(out: StringBuilder) {
        val end = lastVowelIndex(out)
        if (end < 0) return
        var start = end
        while (start > 0 && isVowel(out[start - 1])) start--
        val tonedIndices = (start..end).filter { toneOf(out[it]) >= 0 }
        if (tonedIndices.size != 1) return
        val currentIndex = tonedIndices.first()
        val target = pickToneTarget(out, end)
        if (currentIndex == target) return
        val tone = toneOf(out[currentIndex])
        val moved = toneChar(stripTone(out[target]), tone) ?: return
        out.setCharAt(currentIndex, stripTone(out[currentIndex]))
        out.setCharAt(target, preserveCase(out[target], moved))
    }

    private fun pickToneTarget(out: StringBuilder, end: Int): Int {
        var start = end
        while (start > 0 && isVowel(out[start - 1])) start--
        val closed = end + 1 < out.length && !isVowel(out[end + 1])
        if (end > start) {
            val first = stripTone(out[start]).lowercaseChar()
            val before = if (start > 0) out[start - 1].lowercaseChar() else ' '
            if ((before == 'g' && first == 'i') || (before == 'q' && first == 'u')) start++
        }
        val count = end - start + 1
        var priority = -1
        for (index in start..end) {
            if (stripTone(out[index]).lowercaseChar() in PRIORITY) priority = index
        }
        if (priority >= 0) return priority
        if (count == 1) return start
        if (count >= 3) return start + 1
        if (closed) return end
        return start
    }

    private fun lastVowelIndex(out: StringBuilder): Int {
        for (index in out.indices.reversed()) if (isVowel(out[index])) return index
        return -1
    }

    private fun replaceShapeKeepingTone(current: Char, shaped: Char): Char {
        val tone = toneOf(current)
        val replacement = if (tone >= 0) toneChar(shaped, tone) ?: shaped else shaped
        return preserveCase(current, replacement)
    }

    private fun plainBase(ch: Char): Char = SHAPE_TO_BASE[stripTone(ch).lowercaseChar()]
        ?: stripTone(ch).lowercaseChar()

    private fun isVowel(ch: Char): Boolean = stripTone(ch).lowercaseChar() in VOWELS

    private fun stripTone(ch: Char): Char {
        val base = TONE_OF[ch.lowercaseChar()]?.first ?: ch.lowercaseChar()
        return preserveCase(ch, base)
    }

    private fun toneOf(ch: Char): Int = TONE_OF[ch.lowercaseChar()]?.second ?: -1

    private fun toneChar(base: Char, tone: Int): Char? = VOWELS[base.lowercaseChar()]?.get(tone)

    private fun preserveCase(source: Char, replacement: Char): Char =
        if (source.isUpperCase()) replacement.uppercaseChar() else replacement

    companion object {
        private val PRIORITY = setOf('â', 'ă', 'ê', 'ô', 'ơ', 'ư')
        private val SHAPE_TO_BASE = mapOf('â' to 'a', 'ă' to 'a', 'ê' to 'e', 'ô' to 'o', 'ơ' to 'o', 'ư' to 'u')
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
        private val TONE_OF: Map<Char, Pair<Char, Int>> = buildMap {
            for ((base, variants) in VOWELS) {
                for ((tone, char) in variants.withIndex()) put(char, base to tone)
            }
        }
    }
}
