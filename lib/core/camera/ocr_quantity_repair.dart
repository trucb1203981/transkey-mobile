import 'dart:ui';

/// A suspect line and two nearby views to check against its original pixels.
class QuantityRepairRegion {
  const QuantityRepairRegion(this.index, this.views);
  final int index;
  final List<Rect> views;
}

String _normalize(String text) {
  const from = '０１２３４５６７８９［］（）【】「」';
  const to = '0123456789[]()[][]';
  for (var i = 0; i < from.length; i++) {
    text = text.replaceAll(from[i], to[i]);
  }
  return text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

final _number = RegExp(r'\d+');
final _quantity = RegExp(r'\d+(?:個|枚|本|匹|杯|皿|食|袋|串|pcs?|pieces?)');
final _letters = RegExp(r'[^a-z\u00c0-\u024f\u3040-\u30ff\u3400-\u9fff]');

bool _balanced(String text) {
  final stack = <String>[];
  for (final c in text.split('')) {
    if (c == '[' || c == '(') stack.add(c);
    if (c == ']' || c == ')') {
      if (stack.isEmpty || stack.removeLast() != (c == ']' ? '[' : '(')) {
        return false;
      }
    }
  }
  return stack.isEmpty;
}

/// Only malformed, short quantity labels qualify, never prices or whole rows.
bool needsQuantityRepair(String text) {
  final s = _normalize(text);
  return s.length <= 60 &&
      s.contains(RegExp(r'[\[\]()]')) &&
      !_balanced(s) &&
      _number.allMatches(s).length == 1 &&
      _quantity.hasMatch(s) &&
      !s.contains(RegExp(r'[円¥$€£%]')) &&
      s.replaceAll(_letters, '').length >= 2;
}

/// Cap work at four lines / eight native ROI reads; never add provider calls.
List<QuantityRepairRegion> quantityRepairRegions(
  List<({String text, Rect box})> lines,
  Size size,
) {
  final bounds = Offset.zero & size;
  final result = <QuantityRepairRegion>[];
  for (var i = 0; i < lines.length && result.length < 4; i++) {
    final line = lines[i];
    final b = line.box;
    if (!needsQuantityRepair(line.text) ||
        !b.isFinite ||
        b.isEmpty ||
        b.width < b.height ||
        b.height > size.height * 0.05 ||
        !bounds.contains(b.center)) {
      continue;
    }
    result.add(QuantityRepairRegion(i, [
      b.inflate(b.height * 0.2).intersect(bounds),
      Rect.fromLTRB(b.left - b.height * 0.5, b.top - b.height * 0.35,
              b.right + b.height * 0.5, b.bottom + b.height * 0.35)
          .intersect(bounds),
    ]));
  }
  return result;
}

bool _sameLabel(String oldText, String newText) {
  final a = _normalize(oldText).replaceAll(_letters, '');
  final b = _normalize(newText).replaceAll(_letters, '');
  if (a == b) return true;
  // A tight read may recover one missing kana, but must not change a name.
  if ((a.length - b.length).abs() != 1) return false;
  final longer = a.length > b.length ? a : b;
  final shorter = a.length > b.length ? b : a;
  for (var i = 0; i < longer.length; i++) {
    if (longer.replaceRange(i, i + 1, '') == shorter) return true;
  }
  return false;
}

/// Both views must agree on one complete, balanced label before replacing it.
/// Missing/extra lines, conflicting digits, or changed names retain the source.
String? agreedQuantityRepair(
    String original, List<String> first, List<String> second) {
  if (!needsQuantityRepair(original) ||
      first.length != 1 ||
      second.length != 1) {
    return null;
  }
  final a = _normalize(first.single);
  final b = _normalize(second.single);
  if (a != b || !_balanced(a) || _number.allMatches(a).length != 1) return null;
  final quantity = _quantity.firstMatch(a);
  if (quantity == null || !_sameLabel(original, a)) return null;
  // The complete quantity must be enclosed, not a number elsewhere in the crop.
  final before = a.substring(0, quantity.start);
  final after = a.substring(quantity.end);
  if (!(before.endsWith('[') && after.startsWith(']')) &&
      !(before.endsWith('(') && after.startsWith(')'))) {
    return null;
  }
  return first.single.trim();
}
