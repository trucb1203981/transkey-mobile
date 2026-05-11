import 'package:uuid/uuid.dart';

import '../../translate/models/translate_models.dart';

class HistoryEntry {
  HistoryEntry({
    String? id,
    DateTime? createdAt,
    required this.sourceText,
    required this.translation,
    this.sourceLang = '',
    this.targetLang = '',
    this.romanization,
    this.mode = TranslateMode.translate,
    this.isFavorite = false,
    this.isLocked = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  final DateTime createdAt;
  final String sourceText;
  final String translation;
  final String sourceLang;
  final String targetLang;
  final String? romanization;
  final TranslateMode mode;
  final bool isFavorite;
  final bool isLocked;

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'sourceText': sourceText,
        'translation': translation,
        'sourceLang': sourceLang,
        'targetLang': targetLang,
        'romanization': romanization,
        'mode': mode.value,
        'isFavorite': isFavorite,
        'isLocked': isLocked,
      };

  factory HistoryEntry.fromMap(Map<String, dynamic> map) => HistoryEntry(
        id: map['id'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        sourceText: map['sourceText'] as String,
        translation: map['translation'] as String,
        sourceLang: map['sourceLang'] as String? ?? '',
        targetLang: map['targetLang'] as String? ?? '',
        romanization: map['romanization'] as String?,
        mode: TranslateMode.values.firstWhere(
          (m) => m.value == map['mode'],
          orElse: () => TranslateMode.translate,
        ),
        isFavorite: map['isFavorite'] as bool? ?? false,
        isLocked: map['isLocked'] as bool? ?? false,
      );

  HistoryEntry copyWith({
    bool? isFavorite,
    bool? isLocked,
  }) =>
      HistoryEntry(
        id: id,
        createdAt: createdAt,
        sourceText: sourceText,
        translation: translation,
        sourceLang: sourceLang,
        targetLang: targetLang,
        romanization: romanization,
        mode: mode,
        isFavorite: isFavorite ?? this.isFavorite,
        isLocked: isLocked ?? this.isLocked,
      );
}
