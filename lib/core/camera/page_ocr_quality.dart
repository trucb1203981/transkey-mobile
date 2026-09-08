import 'dart:math' as math;
import 'dart:ui';

int _latinLetters(String text) =>
    RegExp(r'[A-Za-z\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u024f\u1e00-\u1eff]')
        .allMatches(text)
        .length;

/// Retry automatic language selection only with clear, exclusively Latin text.
/// CJK labels and mixed-script pages retain the established broad recognizer.
bool shouldCheckLatinVision(String text) {
  final latin = _latinLetters(text);
  return latin >= 24 &&
      latin == RegExp(r'\p{L}', unicode: true).allMatches(text).length;
}

/// Accept punctuation repair without changing names or numerical content.
bool acceptsLatinVisionAlternative(String original, String alternative) {
  String words(String text) {
    // A closing bracket can become a trailing l/I after a quantity unit.
    // This is an acceptance comparison; the replacement still comes from OCR.
    final cleaned = text.replaceAllMapped(
        RegExp(r'(\d+\s*(?:pcs?|pieces?))[lI]\b', caseSensitive: false),
        (m) => m.group(1)!);
    return RegExp(r'\p{L}', unicode: true)
        .allMatches(cleaned)
        .map((m) => m.group(0)!)
        .join()
        .toLowerCase();
  }

  List<String> numbers(String text) => RegExp(r'\d+(?:[.,]\d+)*')
      .allMatches(text)
      .map((m) => m.group(0)!)
      .toList();
  final oldNumbers = numbers(original);
  final newNumbers = numbers(alternative);
  return shouldCheckLatinVision(original) &&
      shouldCheckLatinVision(alternative) &&
      words(original) == words(alternative) &&
      oldNumbers.length == newNumbers.length &&
      List.generate(oldNumbers.length, (i) => oldNumbers[i] == newNumbers[i])
          .every((same) => same);
}

/// Require substantial Latin evidence and little competing CJK evidence.
/// A few spurious CJK glyphs must not select a different script for every crop.
bool prefersLatinPage(String latinText, String alternateText) {
  int latinCount(String text) => text.runes
      .where((r) =>
          (r >= 0x41 && r <= 0x5a) ||
          (r >= 0x61 && r <= 0x7a) ||
          (r >= 0xc0 && r <= 0x24f && r != 0xd7 && r != 0xf7) ||
          (r >= 0x1e00 && r <= 0x1eff))
      .length;
  final latin = latinCount(latinText);
  final competingLatin = latinCount(alternateText);
  final cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]')
      .allMatches(alternateText)
      .length;
  return latin >= 80 &&
      latin >= competingLatin * 0.85 &&
      cjk <= 0.03 * math.max(1, competingLatin + cjk);
}

/// Recover substantial paragraphs outside the union of accepted source boxes.
/// Union coverage prevents overlapping existing reads from double-counting.
List<int> uncoveredParagraphs({
  required List<Rect> existing,
  required List<({String text, Rect box, double? confidence})> candidates,
  required Size imageSize,
}) {
  final accepted = [...existing];
  final result = <int>[];
  final page = Offset.zero & imageSize;
  for (var i = 0; i < candidates.length; i++) {
    final item = candidates[i];
    final box = item.box.intersect(page);
    final area = box.width * box.height;
    if (box.isEmpty ||
        area > page.width * page.height * 0.12 ||
        (item.confidence != null && item.confidence! < 0.35) ||
        RegExp(r'\p{L}', unicode: true).allMatches(item.text).length < 8) {
      continue;
    }
    final overlaps =
        accepted.map((r) => r.intersect(box)).where((r) => !r.isEmpty).toList();
    if (_unionArea(overlaps) >= area * 0.5) continue;
    result.add(i);
    accepted.add(box);
  }
  return result;
}

double _unionArea(List<Rect> boxes) {
  final xs = boxes.expand((r) => [r.left, r.right]).toSet().toList()..sort();
  var area = 0.0;
  for (var i = 1; i < xs.length; i++) {
    final slices = boxes
        .where((r) => r.left < xs[i] && r.right > xs[i - 1])
        .toList()
      ..sort((a, b) => a.top.compareTo(b.top));
    double? end;
    var height = 0.0;
    for (final r in slices) {
      final start = end == null ? r.top : math.max(end, r.top);
      height += math.max(0, r.bottom - start);
      end = end == null ? r.bottom : math.max(end, r.bottom);
    }
    area += (xs[i] - xs[i - 1]) * height;
  }
  return area;
}
