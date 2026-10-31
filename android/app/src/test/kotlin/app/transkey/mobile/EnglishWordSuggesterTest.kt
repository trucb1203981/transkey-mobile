package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EnglishWordSuggesterTest {
    // Most common first, like assets/en_words.txt.
    private val suggester = EnglishWordSuggester(
        listOf("the", "to", "this", "that", "help", "hello", "helmet", "there", "their", "where", "x"),
    )

    @Test fun completesByFrequency() =
        assertEquals(listOf("help", "hello"), suggester.suggest("hel"))

    @Test fun neverReturnsTheTypedWord() =
        assertEquals(listOf("this"), suggester.suggest("thi"))

    @Test fun knownWordStillGetsLongerCompletions() =
        assertEquals(listOf("there", "their"), suggester.suggest("the"))

    @Test fun correctsTypoWhenNothingCompletes() =
        assertEquals("the", suggester.suggest("teh").first())

    @Test fun correctsAdjacentSwapInLongerWord() =
        assertEquals("where", suggester.suggest("wheer").first())

    @Test fun knownWordWithoutCompletionsGetsNothing() =
        assertTrue(suggester.suggest("helmet").isEmpty())

    @Test fun keepsCapitalisation() {
        assertEquals(listOf("Help", "Hello"), suggester.suggest("Hel"))
        assertEquals(listOf("HELP", "HELLO"), suggester.suggest("HEL"))
    }

    @Test fun rejectsNonWords() {
        assertTrue(suggester.suggest("").isEmpty())
        assertTrue(suggester.suggest("he1").isEmpty())
        assertTrue(suggester.suggest("café").isEmpty())
    }

    @Test fun singleLettersAreNotInTheList() =
        assertTrue(suggester.suggest("x").isEmpty())

    @Test fun maxIsRespected() =
        assertEquals(1, suggester.suggest("t", 1).size)

    @Test fun trailingWordReadsLettersBeforeTheCaret() {
        assertEquals("hel", EnglishWordSuggester.trailingWord("say hel"))
        assertEquals("", EnglishWordSuggester.trailingWord("say hello "))
        assertEquals("Hi", EnglishWordSuggester.trailingWord("Hi"))
        assertEquals("", EnglishWordSuggester.trailingWord(""))
    }
}
