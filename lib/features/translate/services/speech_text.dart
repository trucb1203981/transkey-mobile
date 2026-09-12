const speechChunkLimit = 500;

String cleanSpeechText(String text) {
  return text
      .replaceAll('\r', '')
      .replaceAll(
          RegExp(r'^.*\[ROM\].*$', multiLine: true, caseSensitive: false), '')
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAllMapped(RegExp(r'!?\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'`([^`\n]+)`'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1]!)
      .replaceAll(
          RegExp(r'^\s*(?:#{1,6}\s+|[-*+]\s+|\d+\.\s+|>\s*)', multiLine: true),
          '')
      .replaceAll(RegExp('[\u2028\u2029]'), '\n')
      .replaceAll(
          RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u200B\uFEFF]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Group whole neighboring sentences, including paragraph pauses and decimals.
List<String> speechChunks(String text) {
  var remaining = text.trim();
  final chunks = <String>[];
  while (remaining.length > speechChunkLimit) {
    var boundary = 0;
    for (var i = 1; i <= speechChunkLimit; i++) {
      final previous = remaining[i - 1];
      final next = remaining[i];
      if ('。！？؟।\n'.contains(previous) ||
          ('.!?'.contains(previous) && RegExp(r'\s').hasMatch(next))) {
        boundary = i;
      }
    }
    if (boundary < speechChunkLimit ~/ 2) {
      boundary = remaining.lastIndexOf(' ', speechChunkLimit);
    }
    if (boundary < speechChunkLimit ~/ 2) {
      boundary = speechChunkLimit;
      final code = remaining.codeUnitAt(boundary - 1);
      if (code >= 0xd800 && code <= 0xdbff) boundary--;
    }
    chunks.add(remaining.substring(0, boundary).trim());
    remaining = remaining.substring(boundary).trimLeft();
  }
  if (remaining.isNotEmpty) chunks.add(remaining);
  return chunks;
}
