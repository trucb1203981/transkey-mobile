package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VietWordCorrectorTest {
    private val corrector = VietWordCorrector(
        vietnameseWords = listOf("và", "của", "bạn", "bàn", "khỏe", "chào", "trúc"),
        englishWords = listOf("email", "code", "class", "example"),
    )

    @Test fun validVietnameseHasNoSuggestion() =
        assertTrue(corrector.suggest("bạn").isEmpty())

    @Test fun nearbyExtraLetterSuggestsVietnamese() =
        assertEquals("bạn", corrector.suggest("bạnm").first())

    @Test fun missingToneCanSuggestRankedVietnamese() =
        assertEquals("bạn", corrector.suggest("ban").first())

    @Test fun commonEnglishPassesThrough() {
        assertTrue(corrector.isEnglish("email"))
        assertTrue(corrector.suggest("email").isEmpty())
        assertNull(corrector.fix("email"))
    }

    @Test fun capitalizedProperNameIsNeverCorrected() {
        assertTrue(corrector.suggest("Truc").isEmpty())
        assertNull(corrector.fix("Truc"))
    }

    @Test fun urlAndEmailLikeTokensAreNeverCorrected() {
        assertTrue(corrector.suggest("example.com").isEmpty())
        assertTrue(corrector.suggest("me@example.com").isEmpty())
        assertNull(corrector.fix("example.com"))
    }

    @Test fun lowercaseTypoCanBeFixedWhenAutocorrectIsOptedIn() =
        assertEquals("bạn", corrector.fix("bạnm"))

    @Test fun mergedVietnameseSyllablesCanBeSplit() =
        assertEquals("bạn khỏe", corrector.fix("bạnkhỏe"))

    @Test fun maxSuggestionCountIsRespected() =
        assertTrue(corrector.suggest("ban", max = 1).size <= 1)

    // ---- includeKnown: the live strip (iOS QuickType parity) ----

    @Test fun knownWordGetsNeighboursForTheStrip() {
        val out = corrector.suggest("bạn", includeKnown = true)
        assertTrue(out.contains("bàn"))
        assertTrue(!out.contains("bạn"))
    }

    @Test fun capitalisedWordGetsCapitalisedNeighbours() =
        assertTrue(corrector.suggest("Bạn", includeKnown = true).contains("Bàn"))

    @Test fun includeKnownStillRejectsUrlsAndDigits() {
        assertTrue(corrector.suggest("example.com", includeKnown = true).isEmpty())
        assertTrue(corrector.suggest("ban2", includeKnown = true).isEmpty())
    }
}
