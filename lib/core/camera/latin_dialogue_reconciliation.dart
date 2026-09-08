import 'dart:math' as math;
import 'dart:ui';

import 'vision_dialogue_geometry.dart';

typedef DialogueRead = ({String text, Rect box, double? confidence});

String _key(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

double _coverage(Rect inner, Rect outer) {
  if (inner.isEmpty || outer.isEmpty) return 0;
  final overlap = inner.intersect(outer);
  return overlap.isEmpty
      ? 0
      : overlap.width * overlap.height / (inner.width * inner.height);
}

int _distance(String a, String b) {
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      row[j] = math.min(math.min(row[j - 1], previous[j]) + 1,
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    previous = row;
  }
  return previous.last;
}

/// Use independently recognized page paragraphs to confirm crop boundaries.
/// Keep crop wording except independently confirmed trailing drawing artifacts.
/// Tiny repeated glyphs are removed only inside a substantial accepted read.
List<DialogueRead> reconcileLatinDialogue(
  List<DialogueRead> reads,
  List<DialogueRead> page, {
  required Size imageSize,
  List<DialogueRead> firstEngine = const [],
  List<DialogueRead> secondEngine = const [],
  List<Rect> dialogueBoxes = const [],
}) {
  // Native engines can split even a two-line utterance into separate blocks.
  // Only single-row anchors can join here; multi-line captions stay separate.
  final singleRows = page.where((r) => !r.text.contains('\n')).toList();
  final rowGroups =
      groupHorizontalDialogueLines(singleRows.map((r) => r.box).toList());
  final anchors = <DialogueRead>[
    ...page.where((r) => r.text.contains('\n')),
    for (final group in rowGroups)
      (
        text: group.map((i) => singleRows[i].text).join('\n'),
        box: group
            .map((i) => singleRows[i].box)
            .reduce((a, b) => a.expandToInclude(b)),
        confidence: singleRows[group.first].confidence
      ),
  ];
  reads = reads.map((r) {
    // A drawing beside a sentence can become an invented trailing code.
    // Require a matching page row and a clean row from the other native
    // engine, plus geometric overflow. Missing evidence keeps identifiers.
    final token = RegExp(r'\s+([A-Za-z0-9]{2,3})[.!?]*$').firstMatch(r.text);
    if (token == null) return r;
    final tail = token[1]!;
    if (!RegExp(r'[A-Za-z]').hasMatch(tail) || !RegExp(r'\d').hasMatch(tail)) {
      return r;
    }
    final prefix = r.text.substring(0, token.start).trimRight();
    final base = _key(prefix);
    if (base.length < 5 || base.length > 100) return r;
    final fromFirst = firstEngine.any((e) =>
        _key(e.text) == _key(r.text) &&
        _coverage(r.box, e.box.inflate(2)) >= 0.8);
    final fromSecond = secondEngine.any((e) =>
        _key(e.text) == _key(r.text) &&
        _coverage(r.box, e.box.inflate(2)) >= 0.8);
    if (fromFirst == fromSecond) return r;
    final independent = fromFirst ? secondEngine : firstEngine;
    final confirmed = page.any((p) =>
        _key(p.text) == base &&
        _coverage(p.box, r.box.inflate(3)) >= 0.6 &&
        r.box.right - p.box.right >= p.box.height &&
        independent.any((e) =>
            _coverage(p.box, e.box.inflate(3)) >= 0.65 &&
            e.text.split('\n').where((line) => _key(line) == base).length ==
                1 &&
            !_key(e.text).contains(_key(tail))));
    return confirmed ? (text: prefix, box: r.box, confidence: r.confidence) : r;
  }).toList();
  // Recover a short missing row only when another row of the same small
  // utterance is independently recognized in a crop. Never recover isolated
  // short page specks or rewrite the crop's existing words.
  for (final group in rowGroups) {
    if (group.length < 2 || group.length > 3) continue;
    final rows = group.map((i) => singleRows[i]).toList();
    if (_key(rows.map((r) => r.text).join()).length > 40) continue;
    final supported = rows.any((row) =>
        _key(row.text).length >= 4 &&
        reads.any((r) =>
            _coverage(r.box, row.box.inflate(3)) >= 0.7 &&
            _distance(_key(r.text), _key(row.text)) <=
                _key(row.text).length * 0.25));
    if (!supported) continue;
    for (final row in rows) {
      final key = _key(row.text);
      if (key.length < 2 || key.length > 3 || RegExp(r'\d').hasMatch(key)) {
        continue;
      }
      if (!reads.any((r) => _coverage(row.box, r.box.inflate(2)) >= 0.5)) {
        reads.add(row);
      }
    }
  }
  // Short standalone utterances need a detected speech shape to compensate
  // for the conservative full-page recovery length floor.
  for (final row in page) {
    final key = _key(row.text);
    final words =
        RegExp(r'\p{L}+', unicode: true).allMatches(row.text).toList();
    if (key.length < 4 ||
        key.length >= 8 ||
        words.length < 2 ||
        RegExp(r'\d').hasMatch(row.text) ||
        (row.confidence ?? 1) < 0.5) {
      continue;
    }
    final inBalloon = dialogueBoxes.any((box) =>
        box.width * box.height <= imageSize.width * imageSize.height * 0.03 &&
        _coverage(row.box, box) >= 0.9);
    if (inBalloon &&
        !reads.any((r) => _coverage(row.box, r.box.inflate(2)) >= 0.5)) {
      reads.add(row);
    }
  }
  final active = List<bool>.filled(reads.length, true);
  for (var i = 0; i < reads.length; i++) {
    final small = reads[i];
    final key = _key(small.text);
    final fragments = RegExp(r'\p{L}+', unicode: true)
        .allMatches(small.text)
        .map((m) => m[0]!);
    if (key.isEmpty ||
        key.length > 8 ||
        RegExp(r'\d').hasMatch(key) ||
        fragments.any((word) => word.length > 3)) {
      continue;
    }
    active[i] = !reads.any((large) {
      final largeKey = _key(large.text);
      if ((key.length > 3 && small.box.width > large.box.width * 0.35) ||
          largeKey.length < 12 ||
          largeKey.length > 800 ||
          _coverage(
                  small.box,
                  large.box.inflate(
                      large.box.height / large.text.split('\n').length * 0.2)) <
              0.85) {
        return false;
      }
      return anchors.any((anchor) {
        final anchorKey = _key(anchor.text);
        return anchorKey.length >= 12 &&
            anchorKey.length <= 800 &&
            _coverage(large.box, anchor.box.inflate(4)) >= 0.8 &&
            _coverage(small.box, anchor.box.inflate(4)) >= 0.8 &&
            _distance(largeKey, anchorKey) <=
                math.max(largeKey.length, anchorKey.length) * 0.35;
      });
    });
  }
  // Reject only unresolved short reads where two native engines disagree at
  // the same position, with no full-page support. Missing evidence is not a
  // reason to delete short dialogue, numbers, names, or sound effects.
  for (var i = 0; i < reads.length; i++) {
    if (!active[i]) continue;
    final r = reads[i];
    final key = _key(r.text);
    if (key.length < 2 ||
        key.length > 4 ||
        RegExp(r'^\d+$').hasMatch(key) ||
        (r.confidence ?? 0) >= 0.8 ||
        page.any((p) =>
            _coverage(r.box, p.box.inflate(3)) >= 0.65 &&
            (_key(p.text).contains(key) ||
                (_key(p.text).length <= 4 &&
                    _distance(key, _key(p.text)) <= 1)))) {
      continue;
    }
    List<DialogueRead> nearby(List<DialogueRead> engine) => engine.where((e) {
          final other = _key(e.text);
          return other.length >= 2 &&
              other.length <= 4 &&
              math.max(_coverage(r.box, e.box), _coverage(e.box, r.box)) >= 0.5;
        }).toList();
    final first = nearby(firstEngine), second = nearby(secondEngine);
    if (first.isEmpty || second.isEmpty) continue;
    if ([...first, ...second].any((e) => (e.confidence ?? 0) >= 0.8)) continue;
    final agreement = first.any(
        (a) => second.any((b) => _distance(_key(a.text), _key(b.text)) <= 1));
    if (!agreement) active[i] = false;
  }
  final replacements = <int, DialogueRead>{};
  final pageArea = imageSize.width * imageSize.height;
  for (final anchor in anchors) {
    final key = _key(anchor.text);
    if (key.length < 4 ||
        key.length > 800 ||
        anchor.box.isEmpty ||
        anchor.box.width * anchor.box.height > pageArea * 0.12) {
      continue;
    }
    // Overlapping native paragraphs may cross panels. They cannot be anchors.
    if (anchors.any((other) =>
        other != anchor &&
        _coverage(anchor.box, other.box) > 0.25 &&
        _coverage(other.box, anchor.box) > 0.25)) {
      continue;
    }
    final indices = [
      for (var i = 0; i < reads.length; i++)
        if (active[i] && _coverage(reads[i].box, anchor.box.inflate(3)) >= 0.6)
          i
    ];
    if (indices.length < 2) continue;
    // Rank alternatives by page agreement, then compare each candidate only
    // with retained reads. This avoids transitive duplicate chains.
    final ranked = [...indices]..sort((i, j) {
        final distance = _distance(_key(reads[i].text), key)
            .compareTo(_distance(_key(reads[j].text), key));
        if (distance != 0) return distance;
        final area = (reads[i].box.width * reads[i].box.height)
            .compareTo(reads[j].box.width * reads[j].box.height);
        return area != 0 ? area : i.compareTo(j);
      });
    String numbers(String text) =>
        RegExp(r'\d+').allMatches(text).map((m) => m[0]).join('|');
    final retained = <int>[];
    for (final i in ranked) {
      final duplicate = retained.any((j) {
        final a = reads[i], b = reads[j];
        final ka = _key(a.text), kb = _key(b.text);
        return ka.length >= 10 &&
            kb.length >= 10 &&
            ka.length <= 800 &&
            kb.length <= 800 &&
            numbers(a.text) == numbers(b.text) &&
            math.max(_coverage(a.box, b.box), _coverage(b.box, a.box)) >=
                0.85 &&
            math.min(_coverage(a.box, b.box), _coverage(b.box, a.box)) >= 0.4 &&
            _distance(ka, kb) <= math.max(ka.length, kb.length) * 0.22;
      });
      if (!duplicate) retained.add(i);
    }
    final candidates = [...retained];
    retained.removeWhere((i) => candidates.any((j) {
          if (i == j) return false;
          final a = _key(reads[i].text), b = _key(reads[j].text);
          if (b.length < 12 ||
              b.length <= a.length ||
              _coverage(reads[i].box, reads[j].box.inflate(2)) < 0.85) {
            return false;
          }
          // Never discard numerical identifiers using the tiny-letter rule.
          if (a.length <= 3 && !RegExp(r'\d').hasMatch(a)) return true;
          return a.length >= 4 && b.contains(a);
        }));
    retained.sort((a, b) => reads[a].box.top.compareTo(reads[b].box.top));
    if (retained.isEmpty) continue;
    final text = retained.map((i) => reads[i].text).join('\n');
    final joinedKey = _key(text);
    if (joinedKey.length > 1000 ||
        _distance(key, joinedKey) >
            math.max(key.length, joinedKey.length) * 0.28) {
      continue;
    }
    // Confirm adjacent source rows, not just shared membership in a big box.
    final groups = groupHorizontalDialogueLines(
        retained.map((i) => reads[i].box).toList());
    if (groups.length != 1 && retained.length > 1) {
      // Multi-line crop paragraphs have larger heights. Compare the actual
      // gap to estimated row heights, preserving adjacent paragraph pieces.
      var connected = true;
      for (var k = 1; k < retained.length; k++) {
        final a = reads[retained[k - 1]], b = reads[retained[k]];
        final rowHeight = math.min(a.box.height / a.text.split('\n').length,
            b.box.height / b.text.split('\n').length);
        final overlap = math.min(a.box.right, b.box.right) -
            math.max(a.box.left, b.box.left);
        if (b.box.top - a.box.bottom < -rowHeight * 0.5 ||
            b.box.top - a.box.bottom > rowHeight * 0.9 ||
            overlap < math.min(a.box.width, b.box.width) * 0.5) {
          connected = false;
        }
      }
      if (!connected) continue;
    }
    final box = retained
        .map((i) => reads[i].box)
        .reduce((a, b) => a.expandToInclude(b));
    replacements[indices.first] =
        (text: text, box: box, confidence: reads[retained.first].confidence);
    for (final i in indices) {
      active[i] = false;
    }
  }
  return [
    for (var i = 0; i < reads.length; i++)
      if (replacements.containsKey(i))
        replacements[i]!
      else if (active[i])
        reads[i]
  ];
}
