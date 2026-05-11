class GlossaryEntry {
  const GlossaryEntry({
    required this.source,
    required this.target,
  });

  final String source;
  final String target;

  Map<String, dynamic> toMap() => {
        'source': source,
        'target': target,
      };

  factory GlossaryEntry.fromMap(Map<String, dynamic> map) => GlossaryEntry(
        source: map['source'] as String? ?? '',
        target: map['target'] as String? ?? '',
      );

  GlossaryEntry copyWith({
    String? source,
    String? target,
  }) =>
      GlossaryEntry(
        source: source ?? this.source,
        target: target ?? this.target,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlossaryEntry && source == other.source && target == other.target;

  @override
  int get hashCode => Object.hash(source, target);
}
