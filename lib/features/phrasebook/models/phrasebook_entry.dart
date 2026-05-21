/// Stable category slugs the server accepts. UI maps these to localised
/// labels via the `l.phrasebookCategory*` keys.
class PhrasebookCategory {
  static const menu = 'menu';
  static const place = 'place';
  static const document = 'document';
  static const other = 'other';

  /// Ordering used in filter chip rows + dropdowns.
  static const all = <String>[menu, place, document, other];

  /// Pick a default bucket from the capture scene at save time. Scenes
  /// that don't map cleanly (auto / screenshot / word) fall to 'other'.
  static String fromScene(String scene) {
    switch (scene) {
      case 'menu':
        return menu;
      case 'sign':
        return place;
      case 'document':
        return document;
      default:
        return other;
    }
  }
}

/// Local-only model for a server-stored phrasebook entry. Maps 1:1 with
/// the /phrasebook API response shape. Kept immutable so list rebuilds
/// don't bug out when the user adds / removes entries concurrently.
class PhrasebookEntry {
  const PhrasebookEntry({
    required this.id,
    required this.recognizedText,
    required this.explanation,
    required this.scene,
    required this.targetLang,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.originalText,
    this.sourceLang,
    this.note,
  });

  final int id;
  final String recognizedText;
  final String? originalText;
  final String explanation;
  final String scene;
  final String targetLang;
  /// ISO 639-1 of the original text (the recognizedText language) — used by
  /// the saved-list speaker to TTS in the correct pronunciation. Nullable
  /// for rows saved before the column existed; UI disables the speaker when
  /// null.
  final String? sourceLang;
  /// Bucket slug ('menu' | 'place' | 'document' | 'other'). Defaults to
  /// 'other' for rows saved before the column existed.
  final String category;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PhrasebookEntry.fromMap(Map<String, dynamic> map) => PhrasebookEntry(
        id: (map['id'] as num).toInt(),
        recognizedText: map['recognizedText'] as String,
        originalText: map['originalText'] as String?,
        explanation: map['explanation'] as String,
        scene: map['scene'] as String? ?? 'menu',
        targetLang: map['targetLang'] as String? ?? 'en',
        sourceLang: map['sourceLang'] as String?,
        category: (map['category'] as String?) ?? PhrasebookCategory.other,
        note: map['note'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  PhrasebookEntry copyWith({String? note, String? category}) => PhrasebookEntry(
        id: id,
        recognizedText: recognizedText,
        originalText: originalText,
        explanation: explanation,
        scene: scene,
        targetLang: targetLang,
        sourceLang: sourceLang,
        category: category ?? this.category,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
