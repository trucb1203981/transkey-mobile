import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// Pins the "overlay double" collapse (CameraService._dedupSameTextOverlapping
/// via dedupOverlappingForTest).
///
/// On the manga / comic path _groupDbnetByBubbles can emit TWO boxes for one
/// speech bubble: a tight text-line union box (the lines DBNet assigned) plus
/// the leftover lines as an orphan cluster, or the full-bubble shape box from
/// the empty-bubble recall fill. The two boxes overlap heavily but their IoU
/// is LOW because their areas differ a lot, so the old `IoU > 0.4 || contains`
/// rule missed them - the user saw two stacked cards (one translated, the
/// other echoing raw source). Reproduced on device 2026-06-15 on a French
/// Tintin page: VI card [10,102 111x49] over FR source card [11,116 114x86],
/// IoU 0.34 -> NOT merged.
///
/// The collapse must: merge a same-bubble pair whose overlap covers a majority
/// of the SMALLER box, keep the SMALLEST bbox for position and the text with
/// the most meaningful chars; and must NOT merge genuinely distinct sibling
/// bubbles that only graze each other.
void main() {
  final service = CameraService();

  OcrBlock blk(String text, double l, double t, double w, double h) =>
      OcrBlock(text: text, boundingBox: Rect.fromLTWH(l, t, w, h));

  group('overlay double collapse', () {
    test('partial text-line box + full bubble box (low IoU) merge to one', () {
      // Mirrors the device repro: small top-line union vs full bubble.
      final small = blk('Hi', 100, 100, 100, 50); // area 5000 (top line)
      final full = blk('Hi there my old friend', 100, 110, 100, 120); // 12000
      // Intersection 100x40 = 4000. IoU = 4000/13000 = 0.31 (< 0.4, old miss).
      // inter/smaller = 4000/5000 = 0.80 (> 0.6, new rule catches).
      final out = service.dedupOverlappingForTest([small, full]);
      expect(out.length, 1);
      // Keeper: smallest bbox for position, richest text.
      expect(out.first.text, 'Hi there my old friend');
      expect(out.first.boundingBox, const Rect.fromLTWH(100, 100, 100, 50));
    });

    test('distinct side-by-side bubbles that only graze stay separate', () {
      final left = blk('Bonjour', 100, 100, 100, 80); // area 8000
      final right = blk('Madame', 170, 100, 100, 80); // overlap x30 -> 2400
      // IoU 0.18, inter/smaller 0.30 (< 0.6) -> keep both.
      final out = service.dedupOverlappingForTest([left, right]);
      expect(out.length, 2);
    });

    test('fully-contained box still merges (existing rectContains rule)', () {
      final big = blk('full sentence here', 0, 0, 200, 200);
      final inner = blk('frag', 50, 50, 40, 40);
      final out = service.dedupOverlappingForTest([big, inner]);
      expect(out.length, 1);
      // Smallest bbox kept, richest text kept.
      expect(out.first.boundingBox, const Rect.fromLTWH(50, 50, 40, 40));
      expect(out.first.text, 'full sentence here');
    });

    test('high-IoU near-duplicate boxes still merge (existing rule)', () {
      final a = blk('hello world', 0, 0, 100, 100);
      final b = blk('hello vorld', 5, 5, 100, 100); // IoU ~0.82
      final out = service.dedupOverlappingForTest([a, b]);
      expect(out.length, 1);
    });

    test('disjoint boxes are left untouched', () {
      final a = blk('aaaa', 0, 0, 50, 50);
      final b = blk('bbbb', 100, 100, 50, 50);
      final out = service.dedupOverlappingForTest([a, b]);
      expect(out.length, 2);
    });

    test('cluster of dup pair + one distinct bubble -> two blocks', () {
      final small = blk('Top', 100, 100, 100, 50);
      final full = blk('Top line then the rest of the bubble', 100, 110, 100, 120);
      final other = blk('Elsewhere', 400, 400, 90, 60); // disjoint
      final out = service.dedupOverlappingForTest([small, full, other]);
      expect(out.length, 2);
      // The distinct bubble survives unchanged.
      expect(out.any((b) => b.text == 'Elsewhere'), isTrue);
    });

    test('overlap just under 60% of the smaller box does NOT merge', () {
      // Smaller area 5000; need inter <= 3000 to stay under 0.6 AND IoU < 0.4.
      final small = blk('x', 100, 100, 100, 50); // area 5000
      final big = blk('y', 100, 130, 100, 120); // overlap 100x20 = 2000
      // inter/smaller = 2000/5000 = 0.40 (< 0.6); IoU = 2000/15000 = 0.13.
      final out = service.dedupOverlappingForTest([small, big]);
      expect(out.length, 2);
    });
  });
}
