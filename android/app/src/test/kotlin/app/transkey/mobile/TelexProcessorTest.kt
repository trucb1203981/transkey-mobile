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

    // ---- bare 'w' = ư (device-reported: "được" could not be typed at all) ----

    @Test fun bareW_givesUHorn() = assertEquals("ư", type("w"))
    @Test fun bareW_afterDd() = assertEquals("đư", type("ddw"))
    @Test fun duoc_viaBareW() = assertEquals("được", type("ddwowcj"))
    @Test fun duoc_viaBareW_progressesPerKey() {
        val t = TelexProcessor()
        val expected = listOf("d", "đ", "đư", "đưo", "đươ", "đươc", "được")
        "ddwowcj".forEachIndexed { index, key ->
            t.input(key)
            assertEquals("step $index for key $key", expected[index], t.composingText)
        }
    }
    @Test fun duoc_viaUw_stillWorks() = assertEquals("được", type("dduwowcj"))
    @Test fun duoc_strictMode() = assertEquals("được", typeStrict("ddwowcj"))
    @Test fun bareW_afterConsonant() = assertEquals("hư", type("hw"))
    @Test fun doubleW_escapesToLiteral() = assertEquals("w", type("ww"))
    /** The escape keeps the case of the FIRST w, not of the escape keystroke. */
    @Test fun doubleW_keepsUppercase() = assertEquals("W", type("Ww"))
    /** A vowel that exists but cannot take a horn stays literal (not "ư"). */
    @Test fun w_afterNonHornableVowel_staysLiteral() = assertEquals("new", type("new"))

    // ---- modern tone placement on open oa / oe / uy clusters ----

    @Test fun hoa_modern() = assertEquals("hòa", type("hoaf"))
    @Test fun loa_modern() = assertEquals("lòa", type("loaf"))
    @Test fun khoe_modern() = assertEquals("khỏe", type("khoer"))
    @Test fun loe_modern() = assertEquals("lóe", type("loes"))
    @Test fun thuy_modern() = assertEquals("thúy", type("thuys"))
    @Test fun thuy_hoi_modern() = assertEquals("thủy", type("thuyr"))

    @Test fun legacyToneStyle_stillAvailable() {
        val t = TelexProcessor()
        t.modernToneStyle = false
        for (c in "hoaf") t.input(c)
        assertEquals("hoà", t.composingText)
    }

    // ---- a tone typed EARLY must follow the vowel as the cluster changes ----

    @Test fun toneBeforeCircumflex_migrates() = assertEquals("tiếng", type("tiseeng"))
    @Test fun toneAfterCircumflex_unchanged() = assertEquals("tiếng", type("tieesng"))
    @Test fun toneAtEnd_unchanged() = assertEquals("tiếng", type("tieengs"))
    @Test fun toneEarly_thuy() = assertEquals("thủy", type("thury"))
    @Test fun closedCluster_hoan() = assertEquals("hoàn", type("hoafn"))

    // ---- cases most at risk from the tone-relocation pass ----

    @Test fun toan_toneBeforeFinal() = assertEquals("toán", type("toasn"))
    @Test fun toan_toneAfterFinal() = assertEquals("toán", type("toans"))
    @Test fun muon_uoCluster() = assertEquals("muốn", type("muoosn"))
    @Test fun tuyet_uyeCluster() = assertEquals("tuyệt", type("tuyeejt"))
    @Test fun nghieng_toneBeforeNg() = assertEquals("nghiếng", type("nghieesng"))
    @Test fun ngoai_huyen() = assertEquals("ngoài", type("ngoaif"))
    @Test fun ngoai_sac() = assertEquals("ngoái", type("ngoais"))
    @Test fun cua_uPriorityWins() = assertEquals("cửa", type("cuwar"))
    @Test fun thua_uPriorityWins() = assertEquals("thừa", type("thuwaf"))
    @Test fun quy_quDigraphSkip() = assertEquals("quỷ", type("quyr"))
    @Test fun gia_giDigraphSkip() = assertEquals("già", type("giaf"))
    @Test fun viet_toneAfterWholeSyllable() = assertEquals("việt", type("vieetj"))
    @Test fun khuyen_uyeSac() = assertEquals("khuyến", type("khuyeens"))
    @Test fun mua_singleTarget() = assertEquals("mùa", type("muaf"))
    /** Repeating the tone key still escapes to literal text. */
    @Test fun repeatTone_stillEscapes() = assertEquals("as", type("ass"))
    // ---- swapping a vowel's shape: circumflex <-> breve/horn (Unikey parity) ----

    @Test fun circumflexThenW_becomesBreve() = assertEquals("ă", type("aaw"))
    @Test fun breveThenA_becomesCircumflex() = assertEquals("â", type("awa"))
    @Test fun circumflexThenW_becomesHorn() = assertEquals("ơ", type("oow"))
    @Test fun hornThenO_becomesCircumflex() = assertEquals("ô", type("owo"))
    @Test fun swapInsideWord() = assertEquals("năm", type("naawm"))
    @Test fun swapBackInsideWord() = assertEquals("nâm", type("nawam"))
    @Test fun swapKeepsTone() = assertEquals("ắ", type("aasw"))
    @Test fun swapBackKeepsTone() = assertEquals("tố", type("towso"))
    @Test fun uoPairWithCircumflex_hornsBoth() = assertEquals("thương", type("thuoongw"))
    @Test fun swapKeepsUppercase() = assertEquals("Ă", type("AAW"))
}
