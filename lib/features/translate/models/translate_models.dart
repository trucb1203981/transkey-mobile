class SuggestionEntry {
  const SuggestionEntry({required this.source, required this.target});

  final String source;
  final String target;

  factory SuggestionEntry.fromMap(Map<String, dynamic> map) => SuggestionEntry(
        source: map['source'] as String? ?? '',
        target: map['target'] as String? ?? '',
      );
}

/// Fraud warning folded into the translate response. Present only when the
/// server judged the message warning-worthy (it drops level "none").
/// [reason] is a target-language explanation, only returned on paid plans.
class ScamRisk {
  const ScamRisk({required this.level, this.type, this.reason});

  /// "low" | "high" — the server never sends "none" (it omits scamRisk then).
  final String level;
  final String? type;
  final String? reason;

  bool get isHigh => level == 'high';

  static ScamRisk? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final level = map['level'] as String?;
    if (level != 'low' && level != 'high') return null;
    final type = (map['type'] as String?)?.trim();
    final reason = (map['reason'] as String?)?.trim();
    return ScamRisk(
      level: level!,
      type: (type != null && type.isNotEmpty) ? type : null,
      reason: (reason != null && reason.isNotEmpty) ? reason : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'level': level,
        if (type != null) 'type': type,
        if (reason != null) 'reason': reason,
      };
}

class TranslateResult {
  const TranslateResult({
    required this.translation,
    this.romanization,
    this.detectedLang,
    this.model,
    this.suggestions = const [],
    this.scamRisk,
    this.used = 0,
    this.limit = 0,
    this.remaining = 0,
  });

  final String translation;
  final String? romanization;
  final String? detectedLang;
  final String? model;
  final List<SuggestionEntry> suggestions;
  final ScamRisk? scamRisk;
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
        scamRisk: ScamRisk.fromMap(map['scamRisk'] as Map<String, dynamic>?),
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
