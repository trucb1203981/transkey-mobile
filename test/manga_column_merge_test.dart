import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// Pins the manga vertical-CJK column merge (CameraService._mergeColumnBubbles
/// via mergeColumnBubblesForTest). When DBNet has weak recall on a vertical
/// Japanese bubble, its columns fall to the empty-bubble OCR fallback as
/// SEPARATE BubbleDetector shapes (one per column) and used to render one card
/// per column. The merge fuses side-by-side columns of the same bubble into
/// one region while leaving separate bubbles, vertically-stacked shapes and
/// horizontal bubbles untouched.
///
/// Geometry convention: a "column" is a thin tall rect (w=30, h=200) on a
/// 1000x1500 page. Columns of ONE vertical bubble sit side-by-side with a
/// tight intra-column gap (~5px); separate bubbles have a wider gutter.
void main() {
  final service = CameraService();

  // A vertical text column: thin + tall.
  Rect col(double left, double top, {double w = 30, double h = 200}) =>
      Rect.fromLTWH(left, top, w, h);

  // Right-to-left run of [n] columns starting at [rightLeft] (the left edge of
  // the rightmost column), stepping left by width+gap. Models one bubble.
  List<Rect> columns(int n, double rightLeft, double top,
      {double w = 30, double gap = 5, double h = 200}) {
    return [
      for (var i = 0; i < n; i++) col(rightLeft - i * (w + gap), top, w: w, h: h),
    ];
  }

  group('vertical bubble columns merge', () {
    test('5 columns of one bubble -> 1 region covering them all', () {
      final cols = columns(5, 700, 300); // x 560..730, y 300..500
      final out = service.mergeColumnBubblesForTest(cols);

      expect(out, hasLength(1));
      final u = out.single;
      expect(u.left, 560);
      expect(u.top, 300);
      expect(u.right, 730);
      expect(u.bottom, 500);
    });

    test('flow-log shape: 10 columns across 3 bubbles -> 3 regions', () {
      // emptyBubbleFill=10 in the syslog were really 3 vertical bubbles
      // (5 + 3 + 2 columns) stacked down the page. Expect merged=3.
      final shapes = <Rect>[
        ...columns(5, 700, 200), // bubble A  y 200..400
        ...columns(3, 700, 600), // bubble B  y 600..800
        ...columns(2, 700, 1000), // bubble C y 1000..1200
      ];
      final out = service.mergeColumnBubblesForTest(shapes);
      expect(out, hasLength(3));
    });
  });

  group('no over-merge (regression guards)', () {
    test('two side-by-side bubbles with a real gutter stay separate', () {
      // Left bubble x 560..730; right bubble x 800..865. Nearest gutter is
      // 70px (>> 0.6 x column width = 18), so they must NOT fuse.
      final shapes = <Rect>[
        ...columns(5, 700, 300), // left bubble
        ...columns(2, 835, 300), // right bubble, x 800..865
      ];
      final out = service.mergeColumnBubblesForTest(shapes);
      expect(out, hasLength(2));
    });

    test('vertically-stacked narrow shapes (no vertical overlap) stay separate',
        () {
      // Same x, one above the other with a 20px vertical gap. Stacked dialogue
      // bubbles, not columns of one bubble -> must not merge.
      final shapes = <Rect>[
        col(500, 300, h: 150), // y 300..450
        col(500, 470, h: 150), // y 470..620
      ];
      final out = service.mergeColumnBubblesForTest(shapes);
      expect(out, hasLength(2));
    });

    test('near-stacked shapes with only slight vertical overlap stay separate',
        () {
      // Real page Screenshot_2026-06-02-19-19-20-193: two column-like shapes
      // that overlap vertically by ~9px (~4% of height) and overlap
      // horizontally are two SEPARATE stacked bubbles, not columns of one.
      // The >=50% vertical-overlap guard must keep them apart.
      final shapes = <Rect>[
        const Rect.fromLTWH(657, 945, 126, 261), // y 945..1206
        const Rect.fromLTWH(594, 1197, 101, 229), // y 1197..1426 (9px overlap)
      ];
      final out = service.mergeColumnBubblesForTest(shapes);
      expect(out, hasLength(2));
    });

    test('a lone horizontal bubble is left untouched', () {
      const wide = Rect.fromLTWH(300, 800, 250, 60);
      final out = service.mergeColumnBubblesForTest([wide]);
      expect(out, hasLength(1));
      expect(out.single, wide);
    });

    test('panel-cap guard: an over-large merged union is kept as members', () {
      // Tight cap so the 5-column union (170x200 = 34000) exceeds it; the
      // members are returned individually rather than painting one big card.
      final cols = columns(5, 700, 300);
      final out = service.mergeColumnBubblesForTest(cols, maxAreaRatio: 0.001);
      expect(out, hasLength(5));
    });
  });

  group('trivial inputs', () {
    test('single shape returned unchanged', () {
      final c = col(500, 300);
      expect(service.mergeColumnBubblesForTest([c]), [c]);
    });

    test('empty input -> empty', () {
      expect(service.mergeColumnBubblesForTest(const []), isEmpty);
    });
  });
}
