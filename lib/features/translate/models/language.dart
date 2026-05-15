class Language {
  const Language({
    required this.code,
    required this.nativeName,
    this.name,
  });

  final String code;
  final String nativeName;
  final String? name;

  String get displayName => name != null ? '$name ($nativeName)' : nativeName;
}

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

// O(1) lookup — kSupportedLanguages is iterated on many widget builds
// (chip labels, history cards, language picker, settings list).
final Map<String, Language> _languageIndex = {
  for (final l in kSupportedLanguages) l.code: l,
};

const _fallbackLanguage =
    Language(code: 'en', nativeName: 'English', name: 'English');

Language languageByCode(String code) => _languageIndex[code] ?? _fallbackLanguage;
