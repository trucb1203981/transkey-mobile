import 'package:uuid/uuid.dart';

class GlossaryEntry {
  GlossaryEntry({
    String? id,
    required this.source,
    required this.target,
    this.isName = false,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String source;
  final String target;
  final bool isName;

  Map<String, dynamic> toMap() => {
        'id': id,
        'source': source,
        'target': target,
        'is_name': isName,
      };

  factory GlossaryEntry.fromMap(Map<String, dynamic> map) => GlossaryEntry(
        id: (map['id'] as String?) ??
            'legacy_${map['source']}_${map['target']}',
        source: map['source'] as String? ?? '',
        target: map['target'] as String? ?? '',
        isName: (map['is_name'] as bool?) ?? false,
      );

  GlossaryEntry copyWith({
    String? source,
    String? target,
    bool? isName,
  }) =>
      GlossaryEntry(
        id: id,
        source: source ?? this.source,
        target: target ?? this.target,
        isName: isName ?? this.isName,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlossaryEntry &&
          source == other.source &&
          target == other.target &&
          isName == other.isName;

  @override
  int get hashCode => Object.hash(source, target, isName);
}
