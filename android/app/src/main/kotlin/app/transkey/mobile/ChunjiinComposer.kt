package app.transkey.mobile

/**
 * Korean Chunjiin (천지인 / Cheonjiin) 10-key composer.
 *
 * Vowels are drawn from three strokes - · (cheon/dot, 'D'), ㅡ (ji/earth, 'H'),
 * ㅣ (in/human, 'V') - e.g. ㅣ+· = ㅏ, ·+ㅡ = ㅗ. Consonants multi-tap through a
 * group (ㄱ -> ㅋ -> ㄲ). The resulting jamo stream is fed to [HangulComposer]
 * to build syllable blocks, so block logic (batchim, steal-to-next) is reused.
 *
 * Strategy: keep a finalized jamo sequence + one in-progress jamo (the consonant
 * mid-multitap or the vowel mid-stroke); render by replaying the whole stream
 * through a fresh HangulComposer each keystroke (runs are short, so cheap). This
 * sidesteps any "replace the last jamo" surgery.
 */
class ChunjiinComposer {

    private val seq = StringBuilder()   // finalized jamo of the current run
    private var inProgress: Char? = null
    private var isVowel = false
    private var consKey = -1            // which consonant group is mid-multitap
    private var consIdx = 0
    private var stroke = ""             // current vowel stroke buffer (D/H/V)

    private val consGroups = arrayOf(
        "ㄱㅋㄲ", "ㄴㄹ", "ㄷㅌㄸ", "ㅂㅍㅃ", "ㅅㅎㅆ", "ㅈㅊㅉ", "ㅇㅁ",
    )

    private val vowelMap = mapOf(
        "V" to 'ㅣ', "H" to 'ㅡ', "HV" to 'ㅢ',
        "VD" to 'ㅏ', "VDV" to 'ㅐ', "VDD" to 'ㅑ', "VDDV" to 'ㅒ',
        "DV" to 'ㅓ', "DVV" to 'ㅔ', "DDV" to 'ㅕ', "DDVV" to 'ㅖ',
        "DH" to 'ㅗ', "DHV" to 'ㅚ', "DHVD" to 'ㅘ', "DHVDV" to 'ㅙ', "DDH" to 'ㅛ',
        "HD" to 'ㅜ', "HDV" to 'ㅟ', "HDD" to 'ㅠ', "HDDV" to 'ㅝ', "HDDVV" to 'ㅞ',
    )
    private val vowelPrefixes: Set<String> = buildSet {
        for (k in vowelMap.keys) for (i in 1 until k.length) add(k.substring(0, i))
    }

    val hasComposingText: Boolean get() = seq.isNotEmpty() || inProgress != null

    val composingText: String get() {
        val h = HangulComposer()
        for (c in seq) h.input(c)
        inProgress?.let { h.input(it) }
        return h.composingText
    }

    fun reset() {
        seq.setLength(0); inProgress = null; isVowel = false; consKey = -1; consIdx = 0; stroke = ""
    }

    fun commit(): String { finalize(); val s = composingText; reset(); return s }

    private fun finalize() {
        inProgress?.let { seq.append(it) }
        inProgress = null; isVowel = false; consKey = -1; consIdx = 0; stroke = ""
    }

    /** Tap a consonant group (0..6). Repeated taps of the same group cycle it. */
    fun consonant(group: Int) {
        if (group !in consGroups.indices) return
        val g = consGroups[group]
        if (!isVowel && consKey == group && inProgress != null) {
            consIdx = (consIdx + 1) % g.length
            inProgress = g[consIdx]
        } else {
            finalize()
            consKey = group; consIdx = 0; isVowel = false
            inProgress = g[0]
        }
    }

    /** Add a vowel stroke: 'D' (·), 'H' (ㅡ), 'V' (ㅣ). */
    fun vowel(s: Char) {
        if (isVowel) {
            val cand = stroke + s
            if (vowelMap.containsKey(cand) || cand in vowelPrefixes) {
                stroke = cand
                inProgress = vowelMap[cand] // null while only a prefix (e.g. "D")
                return
            }
            finalize()
        } else {
            finalize()
        }
        // start a new vowel
        isVowel = true; consKey = -1; consIdx = 0
        stroke = s.toString()
        inProgress = vowelMap[stroke]
    }

    /** Remove one step. True if something changed. */
    fun backspace(): Boolean {
        if (inProgress != null || stroke.isNotEmpty()) {
            if (isVowel && stroke.length > 1) {
                stroke = stroke.dropLast(1)
                inProgress = vowelMap[stroke]
                return true
            }
            inProgress = null; isVowel = false; consKey = -1; consIdx = 0; stroke = ""
            return true
        }
        if (seq.isNotEmpty()) { seq.deleteCharAt(seq.length - 1); return true }
        return false
    }
}
