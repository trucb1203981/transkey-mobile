package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WordSuggesterTest {
    // Most common first, like the bundled lists.
    private val suggester = WordSuggester(
        listOf("the", "to", "this", "that", "help", "hello", "helmet", "there", "their", "where", "x"),
    )
    private val french = WordSuggester(listOf("de", "école", "écoute", "été", "est", "être", "ça"))
    private val german = WordSuggester(listOf("die", "Haus", "hat", "Häuser", "heute", "Straße"))

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
    }

    @Test fun singleLettersAreNotInTheList() =
        assertTrue(suggester.suggest("x").isEmpty())

    @Test fun maxIsRespected() =
        assertEquals(1, suggester.suggest("t", 1).size)

    // ---- accents and case (DE/FR/ES/IT/PT lists) ----

    @Test fun restoresAccentsOfAWordTypedWithout() =
        assertEquals("école", french.suggest("ecole").first())

    @Test fun completesThroughAccents() =
        assertEquals(listOf("école", "écoute"), french.suggest("eco"))

    @Test fun accentedTypingCompletesToo() =
        assertEquals(listOf("école", "écoute"), french.suggest("éco"))

    @Test fun capitalisedTypingCapitalisesAccentedWord() =
        assertEquals("École", french.suggest("Ecole").first())

    @Test fun correctlyAccentedWordGetsNoRestoration() =
        assertTrue(french.suggest("été").isEmpty())

    @Test fun germanNounKeepsItsCapital() {
        assertEquals(listOf("Haus", "Häuser"), german.suggest("hau"))
        assertEquals("Haus", german.suggest("haus").first())
    }

    @Test fun germanUmlautAndEszettWork() {
        assertEquals("Häuser", german.suggest("hauser").first())
        assertEquals("Straße", german.suggest("stras").first())
    }

    @Test fun trailingWordReadsLettersBeforeTheCaret() {
        assertEquals("hel", WordSuggester.trailingWord("say hel"))
        assertEquals("", WordSuggester.trailingWord("say hello "))
        assertEquals("Hi", WordSuggester.trailingWord("Hi"))
        assertEquals("école", WordSuggester.trailingWord("l'école"))
        assertEquals("", WordSuggester.trailingWord(""))
    }
}
