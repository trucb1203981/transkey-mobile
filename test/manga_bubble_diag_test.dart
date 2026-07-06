@Tags(['diag'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:transkey_mobile/core/camera/bubble_detector.dart';

/// OFFLINE diagnostic (NOT a pinned test; skips when the local images are
/// absent). Runs the REAL BubbleDetector on specific manga pages and prints the
/// shape geometry that the manga empty-bubble fallback in
/// CameraService._groupDbnetByBubbles receives, so the per-column-fragmentation
/// fix is chosen from ground truth (does BubbleDetector split one bubble into
/// several shapes, or return it whole?).
///
/// Drop the ACTUAL fragmenting page (the "みーは今日も..." page) into the list
/// below, then: flutter test test/manga_bubble_diag_test.dart --tags diag
void main() {
  const mangaDir = '/Users/trucnguyen/Desktop/Record/Manga';
  final images = <String>[
    if (Directory(mangaDir).existsSync())
      for (final f in Directory(mangaDir).listSync().whereType<File>())
        if (f.path.toLowerCase().endsWith('.jpg') ||
            f.path.toLowerCase().endsWith('.png'))
          f.path,
  ]..sort();

  double iou(Rect a, Rect b) {
    final l = math.max(a.left, b.left), t = math.max(a.top, b.top);
    final r = math.min(a.right, b.right), bo = math.min(a.bottom, b.bottom);
    if (r <= l || bo <= t) return 0;
    final inter = (r - l) * (bo - t);
    final u = a.width * a.height + b.width * b.height - inter;
    return u <= 0 ? 0 : inter / u;
  }

  bool contains(Rect outer, Rect inner) =>
      inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;

  String fr(Rect r) =>
      '${r.left.round()},${r.top.round()} ${r.width.round()}x${r.height.round()}';

  for (final path in images) {
    test('BubbleDetector geometry: ${path.split('/').last}', () async {
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('SKIP (missing): $path');
        return;
      }
      final decoded = img.decodeImage(File(path).readAsBytesSync())!;
      final W = decoded.width.toDouble(), H = decoded.height.toDouble();
      final pageArea = W * H;

      final pass1 = await BubbleDetector.detect(path);
      final pass2 = await BubbleDetector.detect(path, whiteThreshold: 200);
      final shapes = <Rect>[...pass1];
      for (final b2 in pass2) {
        if (pass1.any((b1) => iou(b1, b2) > 0.5)) continue;
        if (pass1.where((b1) => contains(b2, b1)).length >= 2) continue;
        shapes.add(b2);
      }

      // ignore: avoid_print
      print('\n=== ${path.split('/').last}  image=${W.round()}x${H.round()} '
          'pass1=${pass1.length} pass2=${pass2.length} union=${shapes.length}');
      for (final b in shapes) {
        final ratio = (b.width * b.height) / pageArea;
        final asp = b.width >= b.height
            ? b.width / math.max(b.height, 1.0)
            : b.height / math.max(b.width, 1.0);
        final bucket = ratio < 0.005
            ? 'rej:small'
            : ratio > 0.06
                ? 'rej:big'
                : asp > 2.5
                    ? 'rej:aspect'
                    : 'emptyKeep';
        // ignore: avoid_print
        print('  shape ${fr(b)}  ratio=${ratio.toStringAsFixed(4)} '
            'asp=${asp.toStringAsFixed(2)} -> $bucket');
      }

      // Fragmentation signal: column-like shapes (thin + tall) and how many
      // pairs would be FUSED by _mergeColumnBubbles (side-by-side + vertically
      // overlapping). If this is 0 across every real page, BubbleDetector never
      // splits a vertical bubble into columns -> the merge targets a non-problem.
      final cols = shapes
          .where((b) => b.height / math.max(b.width, 1.0) >= 2.0)
          .toList();
      var mergeablePairs = 0;
      for (var i = 0; i < cols.length; i++) {
        for (var j = i + 1; j < cols.length; j++) {
          final a = cols[i], b = cols[j];
          final vOverlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
          if (vOverlap <= 0) continue;
          final horizGap =
              math.max(a.left, b.left) - math.min(a.right, b.right);
          if (horizGap <= 0.6 * math.min(a.width, b.width)) mergeablePairs++;
        }
      }
      // ignore: avoid_print
      print('  >> columnLike=${cols.length} mergeablePairs=$mergeablePairs');
    });
  }
}
