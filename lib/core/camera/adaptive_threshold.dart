import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Bradley local-mean threshold for an 8-bit grayscale image, written in place.
/// A short-axis window gives the same result when the photo rotates 90 degrees.
void adaptiveThreshold(
  img.Image image, {
  double windowFraction = 0.125,
  double t = 0.15,
  bool bright = false,
}) {
  final w = image.width;
  final h = image.height;
  if (w < 3 || h < 3) return;

  final stride = w + 1;
  // The OCR pipeline caps these images at 2000px per side. Four-byte sums
  // give the integral buffer predictable storage without boxed integers.
  // Keep a wide fallback for callers with more than 16.8 million pixels.
  final List<int> integral = w * h <= 0xffffffff ~/ 255
      ? Uint32List(stride * (h + 1))
      : Uint64List(stride * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    final above = y * stride;
    final row = above + stride;
    for (var x = 0; x < w; x++) {
      rowSum += image.getPixel(x, y).r.toInt();
      integral[row + x + 1] = integral[above + x + 1] + rowSum;
    }
  }

  final half = math.max(1, (math.min(w, h) * windowFraction / 2).round());
  final factor = bright ? 1.0 + t : 1.0 - t;
  for (var y = 0; y < h; y++) {
    final y1 = math.max(0, y - half) * stride;
    final y2 = (math.min(h - 1, y + half) + 1) * stride;
    final rows = (y2 - y1) ~/ stride;
    for (var x = 0; x < w; x++) {
      final x1 = math.max(0, x - half);
      final x2 = math.min(w - 1, x + half) + 1;
      final count = (x2 - x1) * rows;
      final sum = integral[y2 + x2] -
          integral[y1 + x2] -
          integral[y2 + x1] +
          integral[y1 + x1];
      final pixel = image.getPixel(x, y);
      final weighted = pixel.r.toInt() * count;
      final isText = bright ? weighted > sum * factor : weighted < sum * factor;
      final value = isText ? 0 : 255;
      pixel.setRgb(value, value, value);
    }
  }
}
