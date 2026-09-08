import 'dart:math' as math;
import 'dart:ui';

class DialogueGeometryGroup {
  const DialogueGeometryGroup(this.indices, this.box);
  final List<int> indices;
  final Rect box;
}

/// Correct a model-estimated position only when one native read identifies
/// the same substantial text. Repeated or short expressions stay unchanged.
List<Rect> alignDialogueAnchors(
  List<({String text, Rect box})> vision,
  List<({String text, Rect box})> native,
) {
  String key(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final counts = <String, int>{};
  for (final item in vision) {
    counts.update(key(item.text), (count) => count + 1, ifAbsent: () => 1);
  }
  return vision.map((item) {
    final text = key(item.text);
    if (text.runes.length < 4 || counts[text] != 1) return item.box;
    final matches = native.where((n) => key(n.text) == text).toList();
    return matches.length == 1 ? matches.single.box : item.box;
  }).toList();
}

/// Join fragments supported by one detected balloon, then join nearby
/// vertically stacked orphan fragments. Separate detected balloons never join.
List<DialogueGeometryGroup> groupDialogueBoxes(
  List<Rect> boxes,
  List<Rect> bubbles, {
  required Size imageSize,
  bool joinVerticalFragments = false,
}) {
  final pageArea = imageSize.width * imageSize.height;
  final labels = List<int>.filled(boxes.length, -1);
  final groups = <int, List<int>>{};
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i];
    var bestArea = double.infinity;
    for (var j = 0; j < bubbles.length; j++) {
      final bubble = bubbles[j];
      final area = bubble.width * bubble.height;
      if (area > pageArea * 0.15 || !bubble.contains(box.center)) continue;
      final overlap = bubble.intersect(box);
      if (overlap.isEmpty ||
          box.isEmpty ||
          overlap.width * overlap.height < box.width * box.height * 0.6) {
        continue;
      }
      if (area < bestArea) {
        bestArea = area;
        labels[i] = j;
      }
    }
    final group = labels[i] < 0 ? bubbles.length + i : labels[i];
    (groups[group] ??= []).add(i);
  }
  final members = groups.values.toList();
  if (joinVerticalFragments) {
    final maxGap = math.min(imageSize.width, imageSize.height) * 0.025;
    for (var i = 0; i < members.length; i++) {
      if (members[i].isEmpty || labels[members[i].first] >= 0) continue;
      for (var j = i + 1; j < members.length; j++) {
        if (members[j].isEmpty || labels[members[j].first] >= 0) continue;
        final a = _union(members[i].map((k) => boxes[k]));
        final b = _union(members[j].map((k) => boxes[k]));
        final horizontal =
            math.min(a.right, b.right) - math.max(a.left, b.left);
        final gap = math.max(a.top, b.top) - math.min(a.bottom, b.bottom);
        final union = a.expandToInclude(b);
        if (gap < 0 ||
            gap > maxGap ||
            horizontal < math.min(a.width, b.width) * 0.5 ||
            union.height > imageSize.height * 0.15) {
          continue;
        }
        members[i].addAll(members[j]);
        members[j].clear();
      }
    }
  }
  final result = [
    for (final indices in members)
      if (indices.isNotEmpty)
        DialogueGeometryGroup(
            indices..sort(), _union(indices.map((i) => boxes[i]))),
  ];
  result.sort((a, b) => a.indices.first.compareTo(b.indices.first));
  return result;
}

Rect _union(Iterable<Rect> rects) =>
    rects.reduce((a, b) => a.expandToInclude(b));

/// Group horizontal native lines by adjacent rows rather than by the detector
/// crop. A crop may contain several panels or a caption above a speech balloon.
/// Font and gap checks use individual rows, never an accumulated paragraph box.
List<List<int>> groupHorizontalDialogueLines(List<Rect> boxes) {
  if (boxes.isEmpty) return const [];
  final order = List.generate(boxes.length, (i) => i)
    ..sort((a, b) => boxes[a].top.compareTo(boxes[b].top));
  final rows = <List<int>>[];
  for (final index in order) {
    final b = boxes[index];
    List<int>? match;
    for (final row in rows) {
      final a = _union(row.map((i) => boxes[i]));
      final short = math.min(a.height, b.height);
      final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
      final gap = math.max(a.left, b.left) - math.min(a.right, b.right);
      if (short > 0 &&
          overlap >= short * 0.65 &&
          gap >= -short * 0.8 &&
          gap <= short * 0.8 &&
          math.max(a.height, b.height) <= short * 1.8) {
        match = row;
        break;
      }
    }
    if (match == null) {
      rows.add([index]);
    } else {
      match.add(index);
    }
  }
  for (final row in rows) {
    row.sort((a, b) => boxes[a].left.compareTo(boxes[b].left));
  }
  rows.sort((a, b) => _union(a.map((i) => boxes[i]))
      .top
      .compareTo(_union(b.map((i) => boxes[i])).top));
  final groups = <List<List<int>>>[];
  for (final row in rows) {
    final b = _union(row.map((i) => boxes[i]));
    List<List<int>>? best;
    var bestGap = double.infinity;
    for (final group in groups) {
      final a = _union(group.last.map((i) => boxes[i]));
      final short = math.min(a.height, b.height);
      final gap = b.top - a.bottom;
      final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
      if (short <= 0 ||
          gap < -short * 0.5 ||
          gap > short * 0.8 ||
          math.max(a.height, b.height) > short * 2 ||
          overlap < math.min(a.width, b.width) * 0.5) {
        continue;
      }
      if (gap < bestGap) {
        bestGap = gap;
        best = group;
      }
    }
    if (best == null) {
      groups.add([row]);
    } else {
      best.add(row);
    }
  }
  return groups.map((g) => g.expand((row) => row).toList()).toList();
}
