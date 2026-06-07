package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pure-JVM unit tests for the Vietnamese Telex composer. These lock in the
 * "qu"/"gi" digraph behavior that regressed (typing "quen" used to yield
 * "quên"), plus a regression set of common diacritic transforms so a future
 * tweak to the rules can't silently break everyday words.
 *
 * Each case feeds the literal keystrokes one char at a time and reads back the
 * displayed composing text (what the user sees before committing).
 */
class TelexProcessorTest {

    private fun type(keys: String): String {
        val t = TelexProcessor()
        for (c in keys) t.input(c)
        return t.composingText
    }

    // ---- qu digraph: e stays plain e, must be typeable (the shipped bug) ----

    @Test fun quen_staysPlainE() = assertEquals("quen", type("quen"))
    @Test fun quet_staysPlainE() = assertEquals("quet", type("quet"))
    @Test fun quet_withTone() = assertEquals("quét", type("quets"))
    @Test fun quen_circumflexViaDoubleE() = assertEquals("quên", type("queen"))

    // ---- gi digraph: "gi + e + vowel" is the eo rime (gieo), keep plain e;
    //      "gi + e + consonant" is giê (giết) and must still convert ----

    @Test fun gieo_staysPlainE() = assertEquals("gieo", type("gieo"))
    @Test fun giet_convertsToGie() = assertEquals("giết", type("giets"))

    // ---- regression: i/y + e + ... must still become iê/yê ----

    @Test fun tien() = assertEquals("tiên", type("tien"))
    @Test fun biet() = assertEquals("biết", type("biets"))
    @Test fun yen() = assertEquals("yên", type("yen"))
    @Test fun chuyen() = assertEquals("chuyên", type("chuyen"))
    @Test fun tieu() = assertEquals("tiêu", type("tieu"))
    @Test fun kieu() = assertEquals("kiêu", type("kieu"))

    // ---- regression: tones, circumflex, horn, đ, escape-to-literal ----

    @Test fun chao() = assertEquals("chào", type("chaof"))
    @Test fun thuong() = assertEquals("thương", type("thuongw"))
    @Test fun circumflexAA() = assertEquals("â", type("aa"))
    @Test fun circumflexOO() = assertEquals("ô", type("oo"))
    @Test fun dd() = assertEquals("đ", type("dd"))
    @Test fun toneSac() = assertEquals("á", type("as"))
    @Test fun toneUndoEmitsLiteral() = assertEquals("as", type("ass"))

    // ---- strict Telex (autoRime = false, the keyboard's autocorrect-OFF
    //      default): the ie/yê rime is NOT auto-filled, so plain letters stay
    //      plain ("viet" -> "viet") and ê needs the explicit "ee" key. Every
    //      key-driven transform (tones, doubled vowels, horn, đ) still works. ----

    private fun typeStrict(keys: String): String {
        val t = TelexProcessor()
        t.autoRime = false
        for (c in keys) t.input(c)
        return t.composingText
    }

    @Test fun strict_viet_staysPlain() = assertEquals("viet", typeStrict("viet"))
    @Test fun strict_tien_staysPlain() = assertEquals("tien", typeStrict("tien"))
    @Test fun strict_eViaDoubleE() = assertEquals("viêt", typeStrict("vieet"))
    @Test fun strict_tone_stillWorks() = assertEquals("á", typeStrict("as"))
    @Test fun strict_circumflex_stillWorks() = assertEquals("â", typeStrict("aa"))
    @Test fun strict_horn_stillWorks() = assertEquals("thương", typeStrict("thuongw"))
    @Test fun strict_dd_stillWorks() = assertEquals("đ", typeStrict("dd"))
}
