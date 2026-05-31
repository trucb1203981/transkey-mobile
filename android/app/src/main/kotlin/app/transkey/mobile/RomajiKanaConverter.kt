package app.transkey.mobile

/**
 * Romaji -> Hiragana converter for Japanese input on the Latin qwerty layout.
 * Pure table + small automaton: handles the gojuon, yoon (きゃ), sokuon (double
 * consonant -> っ), and syllabic ん. Output is kana only (no kana->kanji
 * conversion, which needs a dictionary). The pending romaji is shown as latin
 * until it forms a kana, so the user sees the in-progress reading.
 */
class RomajiKanaConverter {

    private val committed = StringBuilder()
    private var pending = ""

    val hasComposingText: Boolean get() = committed.isNotEmpty() || pending.isNotEmpty()
    val composingText: String get() = committed.toString() + pending

    fun reset() { committed.setLength(0); pending = "" }

    /** Replace the kana with [s] (resume editing after cancelling conversion). */
    fun load(s: String) { committed.setLength(0); committed.append(s); pending = "" }

    fun commit(): String {
        // A trailing "n"/"nn" finalizes as ん; any other leftover stays literal.
        if (pending == "n" || pending == "nn") { committed.append("ん"); pending = "" }
        val s = composingText; reset(); return s
    }

    private fun isVowel(c: Char) = c in "aiueo"
    private fun isConsonant(c: Char) = c in 'a'..'z' && !isVowel(c)

    fun input(c: Char) {
        pending += c.lowercaseChar()
        resolve()
    }

    private fun resolve() {
        while (pending.isNotEmpty()) {
            // Sokuon: a doubled consonant (kk, tt, ...) -> っ + keep one.
            if (pending.length >= 2 && pending[0] == pending[1] &&
                isConsonant(pending[0]) && pending[0] != 'n'
            ) {
                committed.append("っ"); pending = pending.substring(1); continue
            }
            // Syllabic ん.
            if (pending.length >= 2 && pending[0] == 'n') {
                val second = pending[1]
                if (second == 'n') {
                    // "nn" is ambiguous: alone it is ん, but "nn" + vowel/y is
                    // ん + a な-row syllable (こんにちは = ko-n-nichi-ha), so wait
                    // for the next char before deciding how many n's to consume.
                    if (pending.length == 2) return
                    val third = pending[2]
                    committed.append("ん")
                    // vowel/y after "nn" -> drop one n so "n"+rest forms な-row;
                    // otherwise the doubled n is a lone ん (consume both).
                    pending = if (isVowel(third) || third == 'y') pending.substring(1)
                              else pending.substring(2)
                    continue
                }
                if (isConsonant(second) && second != 'y') {
                    // n + consonant (not y) -> ん + that consonant.
                    committed.append("ん"); pending = pending.substring(1); continue
                }
            }
            // Exact kana match.
            TABLE[pending]?.let { committed.append(it); pending = ""; return }
            // Still a prefix of some kana -> wait for more input.
            if (PREFIXES.contains(pending)) return
            // Dead end: emit the first char as literal latin, retry the rest.
            committed.append(pending[0]); pending = pending.substring(1)
        }
    }

    /** Remove one unit (pending romaji char, else last kana). True if changed. */
    fun backspace(): Boolean {
        if (pending.isNotEmpty()) { pending = pending.dropLast(1); return true }
        if (committed.isNotEmpty()) { committed.deleteCharAt(committed.length - 1); return true }
        return false
    }

    companion object {
        private val TABLE: Map<String, String> = buildMap {
            put("a", "あ"); put("i", "い"); put("u", "う"); put("e", "え"); put("o", "お")
            put("ka", "か"); put("ki", "き"); put("ku", "く"); put("ke", "け"); put("ko", "こ")
            put("ga", "が"); put("gi", "ぎ"); put("gu", "ぐ"); put("ge", "げ"); put("go", "ご")
            put("sa", "さ"); put("shi", "し"); put("si", "し"); put("su", "す"); put("se", "せ"); put("so", "そ")
            put("za", "ざ"); put("ji", "じ"); put("zi", "じ"); put("zu", "ず"); put("ze", "ぜ"); put("zo", "ぞ")
            put("ta", "た"); put("chi", "ち"); put("ti", "ち"); put("tsu", "つ"); put("tu", "つ"); put("te", "て"); put("to", "と")
            put("da", "だ"); put("di", "ぢ"); put("du", "づ"); put("de", "で"); put("do", "ど")
            put("na", "な"); put("ni", "に"); put("nu", "ぬ"); put("ne", "ね"); put("no", "の")
            put("ha", "は"); put("hi", "ひ"); put("fu", "ふ"); put("hu", "ふ"); put("he", "へ"); put("ho", "ほ")
            put("ba", "ば"); put("bi", "び"); put("bu", "ぶ"); put("be", "べ"); put("bo", "ぼ")
            put("pa", "ぱ"); put("pi", "ぴ"); put("pu", "ぷ"); put("pe", "ぺ"); put("po", "ぽ")
            put("ma", "ま"); put("mi", "み"); put("mu", "む"); put("me", "め"); put("mo", "も")
            put("ya", "や"); put("yu", "ゆ"); put("yo", "よ")
            put("ra", "ら"); put("ri", "り"); put("ru", "る"); put("re", "れ"); put("ro", "ろ")
            put("wa", "わ"); put("wo", "を"); put("nn", "ん")
            // yoon (contracted)
            put("kya", "きゃ"); put("kyu", "きゅ"); put("kyo", "きょ")
            put("gya", "ぎゃ"); put("gyu", "ぎゅ"); put("gyo", "ぎょ")
            put("sha", "しゃ"); put("shu", "しゅ"); put("sho", "しょ")
            put("sya", "しゃ"); put("syu", "しゅ"); put("syo", "しょ")
            put("ja", "じゃ"); put("ju", "じゅ"); put("jo", "じょ")
            put("cha", "ちゃ"); put("chu", "ちゅ"); put("cho", "ちょ")
            put("nya", "にゃ"); put("nyu", "にゅ"); put("nyo", "にょ")
            put("hya", "ひゃ"); put("hyu", "ひゅ"); put("hyo", "ひょ")
            put("bya", "びゃ"); put("byu", "びゅ"); put("byo", "びょ")
            put("pya", "ぴゃ"); put("pyu", "ぴゅ"); put("pyo", "ぴょ")
            put("mya", "みゃ"); put("myu", "みゅ"); put("myo", "みょ")
            put("rya", "りゃ"); put("ryu", "りゅ"); put("ryo", "りょ")
            put("-", "ー")
        }

        // Every proper prefix of a table key, so we know when to keep waiting.
        private val PREFIXES: Set<String> = buildSet {
            for (k in TABLE.keys) for (i in 1 until k.length) add(k.substring(0, i))
            add("n") // 'n' alone may still become な-row, ん, or にゃ
        }
    }
}
