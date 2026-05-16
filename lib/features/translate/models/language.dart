class Language {
  const Language({
    required this.code,
    required this.nativeName,
    this.name,
    this.isLowResource = false,
  });

  final String code;
  final String nativeName;
  final String? name;
  final bool isLowResource;

  String get displayName => name != null ? '$name ($nativeName)' : nativeName;
}

/// Embedded fallback list. Used when the dynamic catalog hasn't been
/// fetched yet (first cold start before /features returns) or when the
/// backend is unreachable. Kept small — 16 popular languages — so the
/// picker is usable instantly while the live catalog loads in the
/// background.
const kSupportedLanguages = <Language>[
  Language(code: 'auto', nativeName: 'Auto Detect', name: 'Auto'),
  Language(code: 'vi', nativeName: 'Tiếng Việt', name: 'Vietnamese'),
  Language(code: 'en', nativeName: 'English', name: 'English'),
  Language(code: 'ja', nativeName: '日本語', name: 'Japanese'),
  Language(code: 'zh', nativeName: '中文', name: 'Chinese'),
  Language(code: 'ko', nativeName: '한국어', name: 'Korean'),
  Language(code: 'fr', nativeName: 'Français', name: 'French'),
  Language(code: 'es', nativeName: 'Español', name: 'Spanish'),
  Language(code: 'de', nativeName: 'Deutsch', name: 'German'),
  Language(code: 'ru', nativeName: 'Русский', name: 'Russian'),
  Language(code: 'th', nativeName: 'ไทย', name: 'Thai'),
  Language(code: 'id', nativeName: 'Bahasa Indonesia', name: 'Indonesian'),
  Language(code: 'pt', nativeName: 'Português', name: 'Portuguese'),
  Language(code: 'it', nativeName: 'Italiano', name: 'Italian'),
  Language(code: 'ar', nativeName: 'العربية', name: 'Arabic'),
  Language(code: 'hi', nativeName: 'हिन्दी', name: 'Hindi'),
];

// Live catalog populated from /features. Defaults to empty so the picker
// falls back to kSupportedLanguages until the first fetch succeeds.
List<Language> _dynamicCatalog = const <Language>[];

final Map<String, Language> _languageIndex = {
  for (final l in kSupportedLanguages) l.code: l,
};

const _fallbackLanguage = Language(code: 'en', nativeName: 'English', name: 'English');

/// Replace the dynamic catalog with `langs`. Called by features_provider
/// after a successful /features fetch. Rebuilds the lookup index so any
/// `languageByCode(...)` call (used across home/settings/result screens)
/// reflects fresh names/flags immediately. Fallback codes from the
/// embedded list are preserved if the dynamic catalog omits them — keeps
/// existing user prefs (e.g. saved targetLang='th') resolving to a label.
void setDynamicLanguageCatalog(List<Language> langs) {
  _dynamicCatalog = List<Language>.unmodifiable(langs);
  _languageIndex.clear();
  for (final l in langs) {
    _languageIndex[l.code] = l;
  }
  for (final l in kSupportedLanguages) {
    _languageIndex.putIfAbsent(l.code, () => l);
  }
}

/// All supported languages — dynamic catalog when available, embedded
/// fallback otherwise. Always includes 'auto' at the head for source-lang
/// pickers; consumers that don't want it filter by code.
List<Language> get supportedLanguages {
  if (_dynamicCatalog.isEmpty) return kSupportedLanguages;
  // Backend never sends 'auto' (it's a client-side virtual code), so prepend.
  if (_dynamicCatalog.first.code == 'auto') return _dynamicCatalog;
  return <Language>[
    const Language(code: 'auto', nativeName: 'Auto Detect', name: 'Auto'),
    ..._dynamicCatalog,
  ];
}

Language languageByCode(String code) => _languageIndex[code] ?? _fallbackLanguage;
