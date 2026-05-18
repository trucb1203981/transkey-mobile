/// Maps the app's 2-letter source-language codes to BCP-47 locale IDs
/// that Android's SpeechRecognizer (and iOS Speech framework) require.
///
/// Why this exists: the platform speech recognizers refuse to find a
/// voice model when given a bare 2-letter code like "th" — they need
/// "th_TH". For the languages in [_explicitMap] the country code is
/// either non-obvious (zh → CN, pt → BR, no → NO) or there are several
/// valid regions and we pick the most-supported one. For everything else
/// the heuristic `<code>_<UPPER>` fallback works because the language
/// code and majority country code align (vi → vi_VN, th → th_TH, etc.).
///
/// Used by the home-screen voice input today; if/when we add voice input
/// to other surfaces (lens audio capture, future widgets) they should
/// import from here instead of redefining the map.
library;

/// Returns the BCP-47 locale string for the given source-language code,
/// or `null` for the special "auto" code (caller should treat null as
/// "use the device-default locale").
String? bcp47ForLang(String code) {
  if (code == 'auto') return null;
  return _explicitMap[code] ?? '${code}_${code.toUpperCase()}';
}

/// Curated overrides where the country code differs from the language
/// code, or where multiple regional dialects exist and we picked the
/// one with the widest ASR coverage. Anything not in this map gets the
/// `<code>_<UPPER>` heuristic in [bcp47ForLang].
const Map<String, String> _explicitMap = {
  // East Asian
  'zh': 'zh_CN',  // zh_TW also valid but CN has wider ASR support
  'ja': 'ja_JP',
  'ko': 'ko_KR',
  // Southeast Asian
  'vi': 'vi_VN',
  'th': 'th_TH',
  'id': 'id_ID',
  'ms': 'ms_MY',
  'tl': 'fil_PH',
  'fil': 'fil_PH',
  'my': 'my_MM',
  'km': 'km_KH',
  'lo': 'lo_LA',
  // South Asian
  'hi': 'hi_IN',
  'bn': 'bn_IN',
  'ta': 'ta_IN',
  'te': 'te_IN',
  'ml': 'ml_IN',
  'kn': 'kn_IN',
  'mr': 'mr_IN',
  'gu': 'gu_IN',
  'pa': 'pa_IN',
  'ur': 'ur_PK',
  'ne': 'ne_NP',
  'si': 'si_LK',
  // European (most-used dialects)
  'en': 'en_US',
  'fr': 'fr_FR',
  'de': 'de_DE',
  'es': 'es_ES',
  'pt': 'pt_BR',  // pt_PT also valid; BR has wider ASR coverage
  'it': 'it_IT',
  'ru': 'ru_RU',
  'pl': 'pl_PL',
  'nl': 'nl_NL',
  'sv': 'sv_SE',
  'da': 'da_DK',
  'no': 'no_NO',
  'fi': 'fi_FI',
  'cs': 'cs_CZ',
  'sk': 'sk_SK',
  'hu': 'hu_HU',
  'ro': 'ro_RO',
  'bg': 'bg_BG',
  'el': 'el_GR',
  'uk': 'uk_UA',
  'sr': 'sr_RS',
  'hr': 'hr_HR',
  'sl': 'sl_SI',
  'lt': 'lt_LT',
  'lv': 'lv_LV',
  'et': 'et_EE',
  // Middle East / Africa
  'ar': 'ar_SA',
  'he': 'he_IL',
  'fa': 'fa_IR',
  'tr': 'tr_TR',
  'sw': 'sw_KE',
  'am': 'am_ET',
  'af': 'af_ZA',
  'zu': 'zu_ZA',
};
