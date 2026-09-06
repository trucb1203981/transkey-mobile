package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VniProcessorTest {

    private fun type(keys: String): String {
        val processor = VniProcessor()
        keys.forEach(processor::input)
        return processor.composingText
    }

    @Test fun toneKeys() {
        assertEquals("á", type("a1"))
        assertEquals("à", type("a2"))
        assertEquals("ả", type("a3"))
        assertEquals("ã", type("a4"))
        assertEquals("ạ", type("a5"))
    }

    @Test fun shapeKeys() {
        assertEquals("â", type("a6"))
        assertEquals("ê", type("e6"))
        assertEquals("ô", type("o6"))
        assertEquals("ơ", type("o7"))
        assertEquals("ư", type("u7"))
        assertEquals("ă", type("a8"))
        assertEquals("đ", type("d9"))
    }

    @Test fun shapeAndToneWorkInEitherOrder() {
        assertEquals("ấ", type("a61"))
        assertEquals("ấ", type("a16"))
        assertEquals("ớ", type("o71"))
        assertEquals("ớ", type("o17"))
    }

    @Test fun commonWords() {
        assertEquals("đường", type("d9u7o7ng2"))
        assertEquals("tiếng", type("tie6ng1"))
        assertEquals("Việt", type("Vie65t"))
        assertEquals("hòa", type("hoa2"))
    }

    @Test fun zeroClearsToneButKeepsLetterShape() {
        assertEquals("â", type("a610"))
        assertEquals("đương", type("d9u7o7ng20"))
    }

    @Test fun modifierWithoutTargetIsLiteral() {
        val processor = VniProcessor()
        processor.input('1')
        assertEquals("1", processor.composingText)
        assertTrue(processor.literalIntent)
    }

    @Test fun backspaceRecomputesRawSequence() {
        val processor = VniProcessor()
        "a61".forEach(processor::input)
        assertEquals("ấ", processor.composingText)
        assertTrue(processor.backspace())
        assertEquals("â", processor.composingText)
        assertTrue(processor.backspace())
        assertEquals("a", processor.composingText)
        assertFalse(processor.literalIntent)
    }

    @Test fun uppercaseIsPreserved() {
        assertEquals("Ấ", type("A61"))
        assertEquals("Đ", type("D9"))
    }

    // ---- repeat-a-modifier escape (Unikey parity, mirrors Telex "ass"/"telexx")

    @Test fun repeatedToneUndoesItAndEmitsTheDigit() {
        assertEquals("a1", type("a11"))
        assertEquals("ban2", type("ban22"))
    }

    @Test fun repeatedShapeKeyUndoesIt() {
        assertEquals("a6", type("a66"))
        assertEquals("o7", type("o77"))
        assertEquals("a8", type("a88"))
        assertEquals("d9", type("d99"))
        assertEquals("duong7", type("du7o7ng7"))
    }

    @Test fun escapeMakesTheRestOfTheWordLiteral() {
        assertEquals("covid19", type("covid119"))
        val processor = VniProcessor()
        "covid119".forEach(processor::input)
        assertTrue(processor.literalIntent)
    }

    @Test fun digitsWithNothingToModifyStayLiteral() {
        assertEquals("25", type("25"))
        assertEquals("a0", type("a0"))
    }

    @Test fun toneMovesWhenTheSyllableCloses() {
        assertEquals("hoán", type("hoa1n"))
        assertEquals("tiếng", type("ti1e6ng"))
    }

    @Test fun rawLettersDropTheModifiersAndSurviveBackspace() {
        val processor = VniProcessor()
        "d9u7o7ng2".forEach(processor::input)
        assertEquals("duong", processor.rawLetters)
        assertTrue(processor.backspace())
        assertEquals("duong", processor.rawLetters)
        assertEquals("đương", processor.composingText)
    }
}
