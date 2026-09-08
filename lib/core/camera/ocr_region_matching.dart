import 'dart:math' as math;
import 'dart:ui';

/// Duplicate OCR needs matching content and overlapping source geometry.
/// Rendered translation cards may overlap even when their sources are distinct.
bool duplicateOcrRegions(Rect a, String textA, Rect b, String textB) {
  final intersection = a.intersect(b);
  if (intersection.isEmpty) return false;
  final smaller = math.min(a.width * a.height, b.width * b.height);
  if (smaller <= 0 ||
      intersection.width * intersection.height / smaller <= 0.6) {
    return false;
  }
  return sameOcrContent(textA, textB);
}

bool sameOcrContent(String a, String b) {
  String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  String numbers(String text) =>
      RegExp(r'\d+').allMatches(text).map((m) => m[0]).join('|');
  // Repeated amounts and identifiers are distinct content, even in one area.
  if (numbers(a) != numbers(b)) return false;
  var x = normalize(a);
  var y = normalize(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  if (x.length > y.length) {
    final swap = x;
    x = y;
    y = swap;
  }
  // A substantial partial read may duplicate a full paragraph. A lone word
  // inside a long paragraph is insufficient evidence to remove another box.
  if (x.length >= 6 && x.length / y.length >= 0.5 && y.contains(x)) {
    return true;
  }
  if (x.length < 10 || y.length > 800) return false;
  final budget = (x.length * 0.12).floor();
  if (y.length - x.length > budget) return false;
  var previous = List<int>.generate(y.length + 1, (i) => i);
  for (var i = 1; i <= x.length; i++) {
    final current = List<int>.filled(y.length + 1, 0)..[0] = i;
    var rowMin = i;
    for (var j = 1; j <= y.length; j++) {
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + (x.codeUnitAt(i - 1) == y.codeUnitAt(j - 1) ? 0 : 1),
      );
      rowMin = math.min(rowMin, current[j]);
    }
    if (rowMin > budget) return false;
    previous = current;
  }
  return previous.last <= budget;
}
