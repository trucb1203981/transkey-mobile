package app.transkey.mobile

/**
 * Hangul (Korean) syllable composer for the Dubeolsik (2-set) layout. Keys emit
 * compatibility jamo (ㄱ, ㅏ, ...); this combines leading consonant (초성) +
 * vowel (중성) + optional trailing consonant (종성) into a precomposed syllable
 * block (U+AC00 range), handling compound vowels (ㅗ+ㅏ=ㅘ), compound finals
 * (ㄱ+ㅅ=ㄳ), and the "trailing steals to next syllable" rule when a vowel
 * follows a final. Pure automaton - no dictionary.
 *
 * The whole in-progress run (already-formed syllables + the current one) is kept
 * as composing text; the IME finalizes it on space / word boundary / mode switch.
 */
class HangulComposer {

    private val lead = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
    private val vowel = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
    // jongseong (trailing): index 0 = none.
    private val tail = arrayOf(
        "", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ",
        "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    )

    private val committed = StringBuilder()
    private var cho = -1   // leading index, or -1
    private var jung = -1  // vowel index, or -1
    private var jong = 0   // trailing index, 0 = none

    val hasComposingText: Boolean get() = committed.isNotEmpty() || cho >= 0 || jung >= 0 || jong > 0
    val composingText: String get() = committed.toString() + current()

    fun reset() {
        committed.setLength(0); cho = -1; jung = -1; jong = 0
    }

    /** Finalize everything and return the full text. */
    fun commit(): String {
        val s = composingText; reset(); return s
    }

    private fun leadOf(c: Char) = lead.indexOf(c)
    private fun vowelOf(c: Char) = vowel.indexOf(c)
    private fun tailOf(c: Char): Int { val i = tail.indexOf(c.toString()); return if (i > 0) i else 0 }

    private fun current(): String = when {
        cho >= 0 && jung >= 0 -> (0xAC00 + (cho * 21 + jung) * 28 + jong).toChar().toString()
        cho >= 0 -> lead[cho].toString()
        jung >= 0 -> vowel[jung].toString()
        jong > 0 -> tail[jong]
        else -> ""
    }

    private fun flush() {
        committed.append(current()); cho = -1; jung = -1; jong = 0
    }

    /** Feed one compatibility jamo. */
    fun input(c: Char) {
        if (vowelOf(c) >= 0) inputVowel(c) else inputConsonant(c)
    }

    private fun inputConsonant(c: Char) {
        val l = leadOf(c)
        if (jung < 0) {
            // current has no vowel: empty, or a lone leading consonant.
            if (cho >= 0) flush()
            if (l >= 0) cho = l else committed.append(c)
            return
        }
        if (cho < 0) {
            // standalone vowel in progress -> consonant starts a new syllable.
            flush(); if (l >= 0) cho = l else committed.append(c)
            return
        }
        // cho + jung present (LV or LVT): try as trailing consonant.
        if (jong == 0) {
            val t = tailOf(c)
            if (t > 0) jong = t else { flush(); if (l >= 0) cho = l else committed.append(c) }
        } else {
            val comb = combineTail(jong, c)
            if (comb > 0) jong = comb else { flush(); if (l >= 0) cho = l else committed.append(c) }
        }
    }

    private fun inputVowel(c: Char) {
        val v = vowelOf(c)
        if (jung < 0) {
            // empty, or a lone leading consonant -> attach as the vowel.
            jung = v
            return
        }
        if (jong == 0) {
            // LV + vowel: try to form a compound vowel, else start a new syllable.
            val comb = combineVowel(jung, c)
            if (comb >= 0) jung = comb else { flush(); jung = v }
            return
        }
        // LVT + vowel: the trailing consonant detaches to lead the new syllable.
        val (remain, stolen) = splitTail(jong)
        jong = remain
        flush()
        cho = stolen; jung = v; jong = 0
    }

    /** Remove one jamo. Returns true if the composing text changed. */
    fun backspace(): Boolean {
        if (cho >= 0 || jung >= 0 || jong > 0) {
            when {
                jong > 0 -> jong = splitTail(jong).first
                jung >= 0 -> jung = decomposeVowel(jung)
                cho >= 0 -> cho = -1
            }
            return true
        }
        if (committed.isNotEmpty()) {
            val last = committed[committed.length - 1]
            committed.deleteCharAt(committed.length - 1)
            if (last.code in 0xAC00..0xD7A3) {
                val idx = last.code - 0xAC00
                cho = idx / (21 * 28); jung = (idx % (21 * 28)) / 28; jong = idx % 28
                return backspace() // drop the restored syllable's last jamo
            }
            return true // a standalone jamo was committed; just removed it
        }
        return false
    }

    // ㅗ+ㅏ=ㅘ etc. Returns combined vowel index, or -1.
    private fun combineVowel(base: Int, add: Char): Int = when ("${vowel[base]}$add") {
        "ㅗㅏ" -> vowelOf('ㅘ'); "ㅗㅐ" -> vowelOf('ㅙ'); "ㅗㅣ" -> vowelOf('ㅚ')
        "ㅜㅓ" -> vowelOf('ㅝ'); "ㅜㅔ" -> vowelOf('ㅞ'); "ㅜㅣ" -> vowelOf('ㅟ')
        "ㅡㅣ" -> vowelOf('ㅢ')
        else -> -1
    }

    // ㄱ+ㅅ=ㄳ etc. Returns combined tail index, or 0.
    private fun combineTail(base: Int, add: Char): Int = when ("${tail[base]}$add") {
        "ㄱㅅ" -> 3; "ㄴㅈ" -> 5; "ㄴㅎ" -> 6; "ㄹㄱ" -> 9; "ㄹㅁ" -> 10
        "ㄹㅂ" -> 11; "ㄹㅅ" -> 12; "ㄹㅌ" -> 13; "ㄹㅍ" -> 14; "ㄹㅎ" -> 15; "ㅂㅅ" -> 18
        else -> 0
    }

    // Split a trailing consonant for the "steal" rule: returns (remaining tail
    // index, leading index of the detached jamo). A single tail -> (0, its lead).
    private fun splitTail(t: Int): Pair<Int, Int> = when (t) {
        3 -> 1 to leadOf('ㅅ'); 5 -> 4 to leadOf('ㅈ'); 6 -> 4 to leadOf('ㅎ')
        9 -> 8 to leadOf('ㄱ'); 10 -> 8 to leadOf('ㅁ'); 11 -> 8 to leadOf('ㅂ')
        12 -> 8 to leadOf('ㅅ'); 13 -> 8 to leadOf('ㅌ'); 14 -> 8 to leadOf('ㅍ'); 15 -> 8 to leadOf('ㅎ')
        18 -> 17 to leadOf('ㅅ')
        else -> 0 to leadOf(tail[t][0])
    }

    // Compound vowel -> its base (one backspace step); else -1 (remove vowel).
    private fun decomposeVowel(v: Int): Int = when (vowel[v]) {
        'ㅘ', 'ㅙ', 'ㅚ' -> vowelOf('ㅗ')
        'ㅝ', 'ㅞ', 'ㅟ' -> vowelOf('ㅜ')
        'ㅢ' -> vowelOf('ㅡ')
        else -> -1
    }
}
