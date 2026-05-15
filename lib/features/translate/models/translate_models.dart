class SuggestionEntry {
  const SuggestionEntry({required this.source, required this.target});

  final String source;
  final String target;

  factory SuggestionEntry.fromMap(Map<String, dynamic> map) => SuggestionEntry(
        source: map['source'] as String? ?? '',
        target: map['target'] as String? ?? '',
      );
}

class TranslateResult {
  const TranslateResult({
    required this.translation,
    this.romanization,
    this.detectedLang,
    this.model,
    this.suggestions = const [],
    this.used = 0,
    this.limit = 0,
    this.remaining = 0,
  });

  final String translation;
  final String? romanization;
  final String? detectedLang;
  final String? model;
  final List<SuggestionEntry> suggestions;
  final int used;
  final int limit;
  final int remaining;

  factory TranslateResult.fromMap(Map<String, dynamic> map) => TranslateResult(
        translation: map['translation'] as String? ??
            map['result'] as String? ??
            map['summary'] as String? ??
            map['explanation'] as String? ??
            map['refined'] as String? ??
            '',
        romanization: map['romanization'] as String?,
        detectedLang: map['detectedLang'] as String?,
        model: map['model'] as String?,
        suggestions: (map['suggestions'] as List<dynamic>?)
                ?.map((e) => SuggestionEntry.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
        used: map['used'] as int? ?? 0,
        limit: map['limit'] as int? ?? 0,
        remaining: map['remaining'] as int? ?? 0,
      );
}

enum TranslateMode {
  translate('translate'),
  reply('reply'),
  summarize('summarize'),
  explain('explain'),
  refine('refine');

  const TranslateMode(this.value);
  final String value;

  String get label {
    switch (this) {
      case TranslateMode.translate:
        return 'Translate';
      case TranslateMode.reply:
        return 'Reply';
      case TranslateMode.summarize:
        return 'Summarize';
      case TranslateMode.explain:
        return 'Explain';
      case TranslateMode.refine:
        return 'Refine';
    }
  }

  bool get requiresPro =>
      this != TranslateMode.translate && this != TranslateMode.reply;
}
