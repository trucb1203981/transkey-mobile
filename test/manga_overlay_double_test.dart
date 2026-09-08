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
/// Collapse matching OCR content only, preserving the selected read's text
/// and geometry together. Unrelated overlapping bubbles remain independent.
void main() {
  final service = CameraService();

  OcrBlock blk(String text, double l, double t, double w, double h) =>
      OcrBlock(text: text, boundingBox: Rect.fromLTWH(l, t, w, h));

  group('overlay double collapse', () {
    test('French paragraph cannot borrow a contained fragment position', () {
      final paragraph =
          blk('MES TRAVAUX SCIENTIFIQUES MONT FATIGUE', 525, 425, 510, 140);
      final fragment = blk('VOUS AUSSI', 787, 490, 230, 50);
      final out = service.dedupOverlappingForTest([paragraph, fragment]);
      expect(out, [paragraph, fragment]);
      for (final block in out) {
        expect(
            identical(block, paragraph) || identical(block, fragment), isTrue);
      }
    });

    test('overlap chain cannot join distinct panels through a bridge', () {
      final first = blk('First dialogue about the journey', 0, 0, 100, 50);
      final bridge = blk('First dialogue about the journey and the next panel',
          0, 0, 100, 170);
      final last = blk('A separate answer in the next panel', 0, 120, 100, 50);
      final out = service.dedupOverlappingForTest([first, bridge, last]);
      expect(out, contains(same(last)));
      expect(
          out.every((b) =>
              identical(b, first) ||
              identical(b, bridge) ||
              identical(b, last)),
          isTrue);
    });

    test('different numbers and short dialogue remain distinct', () {
      final values = [
        blk('Ticket 15 please', 0, 0, 100, 50),
        blk('Ticket 19 please', 0, 0, 100, 50),
        blk('No', 0, 0, 100, 50),
        blk('Go', 0, 0, 100, 50),
      ];
      expect(service.dedupOverlappingForTest(values), values);
    });

    test('partial text-line box + full bubble box (low IoU) merge to one', () {
      // Mirrors the device repro: small top-line union vs full bubble.
      final small =
          blk('Hi there my old', 100, 100, 100, 50); // area 5000 (top line)
      final full = blk('Hi there my old friend', 100, 110, 100, 120); // 12000
      // Intersection 100x40 = 4000. IoU = 4000/13000 = 0.31 (< 0.4, old miss).
      // inter/smaller = 4000/5000 = 0.80 (> 0.6, new rule catches).
      final out = service.dedupOverlappingForTest([small, full]);
      expect(out.length, 1);
      // The complete read keeps its own source geometry.
      expect(out.first.text, 'Hi there my old friend');
      expect(out.first, same(full));
    });

    test('distinct side-by-side bubbles that only graze stay separate', () {
      final left = blk('Bonjour', 100, 100, 100, 80); // area 8000
      final right = blk('Madame', 170, 100, 100, 80); // overlap x30 -> 2400
      // IoU 0.18, inter/smaller 0.30 (< 0.6) -> keep both.
      final out = service.dedupOverlappingForTest([left, right]);
      expect(out.length, 2);
    });

    test('unrelated contained text is not a duplicate', () {
      final big = blk('full sentence here', 0, 0, 200, 200);
      final inner = blk('frag', 50, 50, 40, 40);
      final out = service.dedupOverlappingForTest([big, inner]);
      expect(out, [big, inner]);
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
      final small = blk('Top line then the rest', 100, 100, 100, 50);
      final full =
          blk('Top line then the rest of the bubble', 100, 110, 100, 120);
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
