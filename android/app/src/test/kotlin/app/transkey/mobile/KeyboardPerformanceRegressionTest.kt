package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardPerformanceRegressionTest {
    @Test fun telexBackspaceRestoresEveryPrefixAcrossCheckpoints() {
        for (autoRime in listOf(false, true)) {
            val t = TelexProcessor().apply { this.autoRime = autoRime }
            val states = mutableListOf("" to false)
            // Cross multiple checkpoints before and after an escaped modifier.
            val keys = "nghieng".repeat(18) + "thuongwss" + "example".repeat(16)
            for (ch in keys) {
                t.input(ch)
                states.add(t.composingText to t.literalIntent)
            }
            for (expected in states.dropLast(1).asReversed()) {
                t.backspace()
                assertEquals(expected, t.composingText to t.literalIntent)
            }
            for (ch in "chaof") t.input(ch)
            assertEquals("chào", t.commitWord())
        }
    }

    @Test fun telexOptionsInvalidateCachedPrefixes() {
        val t = TelexProcessor().apply { autoRime = false }
        "nghieng".repeat(12).forEach(t::input)
        t.autoRime = true
        t.input('s')
        val fresh = TelexProcessor()
        ("nghieng".repeat(12) + "s").forEach(fresh::input)
        assertEquals(fresh.composingText, t.composingText)
        t.modernToneStyle = false
        t.backspace()
        val legacy = TelexProcessor().apply { modernToneStyle = false }
        "nghieng".repeat(12).forEach(legacy::input)
        assertEquals(legacy.composingText, t.composingText)
    }

    @Test fun correctionScratchRowsStayIndependentAcrossThreads() {
        val c = VietWordCorrector(listOf("bạn", "bàn", "khỏe", "chào", "trúc"), emptyList())
        val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
        try {
            val tasks = (1..100).map {
                pool.submit<Boolean> {
                    c.suggest("banm", 3).first() == "bạn" && c.fix("bạnkhỏe") == "bạn khỏe"
                }
            }
            tasks.forEach { assertEquals(true, it.get()) }
        } finally {
            pool.shutdownNow()
        }
    }

    @Test fun cjkComposersPreserveTypingAndDeletion() {
        val hangul = HangulComposer()
        "ㅎㅏㄴㄱㅡㄹ".forEach(hangul::input)
        assertEquals("한글", hangul.composingText)
        hangul.backspace()
        assertEquals("한그", hangul.composingText)
        val romaji = RomajiKanaConverter()
        "konnichiha".forEach(romaji::input)
        assertEquals("こんにちは", romaji.commit())
        val kana = KanaComposer()
        kana.add("は")
        kana.modifyLast()
        assertEquals("ば", kana.composingText)
        kana.modifyLast()
        assertEquals("ぱ", kana.commit())
        val chun = ChunjiinComposer()
        chun.consonant(0)
        chun.vowel('V')
        chun.vowel('D')
        assertEquals("가", chun.commit())
    }
}
