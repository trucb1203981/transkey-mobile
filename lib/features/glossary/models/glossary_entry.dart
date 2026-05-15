import 'package:uuid/uuid.dart';

class GlossaryEntry {
  GlossaryEntry({
    String? id,
    required this.source,
    required this.target,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String source;
  final String target;

  Map<String, dynamic> toMap() => {
        'id': id,
        'source': source,
        'target': target,
      };

  factory GlossaryEntry.fromMap(Map<String, dynamic> map) => GlossaryEntry(
        // Older payloads (and the server, which keys on source/target) don't
        // include an id. Fall back to a deterministic synthesis so the same
        // entry retains the same id across reloads.
        id: (map['id'] as String?) ??
            'legacy_${map['source']}_${map['target']}',
        source: map['source'] as String? ?? '',
        target: map['target'] as String? ?? '',
      );

  GlossaryEntry copyWith({
    String? source,
    String? target,
  }) =>
      GlossaryEntry(
        id: id,
        source: source ?? this.source,
        target: target ?? this.target,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlossaryEntry &&
          source == other.source &&
          target == other.target;

  @override
  int get hashCode => Object.hash(source, target);
}
