import 'dart:math' as math;
import 'dart:ui';

/// Reserve a cell around each source center before fitting translated cards.
/// Pairwise cuts are symmetric, so growing text cannot cover a neighboring
/// card. Full content remains available through the card's action sheet.
Rect boundOverlayCard({
  required Rect desired,
  required Rect source,
  required Iterable<Rect> neighbors,
  required Rect imageBounds,
}) {
  var left = imageBounds.left;
  var top = imageBounds.top;
  var right = imageBounds.right;
  var bottom = imageBounds.bottom;
  final center = source.center;
  for (final neighbor in neighbors) {
    final other = neighbor.center;
    final dx = other.dx - center.dx;
    final dy = other.dy - center.dy;
    if (dx.abs() < 0.01 && dy.abs() < 0.01) continue;
    if (dx.abs() >= dy.abs()) {
      final middle = (center.dx + other.dx) / 2;
      final gap = math.min(1.5, dx.abs() / 8);
      if (dx > 0) {
        right = math.min(right, middle - gap);
      } else {
        left = math.max(left, middle + gap);
      }
    } else {
      final middle = (center.dy + other.dy) / 2;
      final gap = math.min(1.5, dy.abs() / 8);
      if (dy > 0) {
        bottom = math.min(bottom, middle - gap);
      } else {
        top = math.max(top, middle + gap);
      }
    }
  }
  left = left.clamp(imageBounds.left, imageBounds.right);
  right = right.clamp(left, imageBounds.right);
  top = top.clamp(imageBounds.top, imageBounds.bottom);
  bottom = bottom.clamp(top, imageBounds.bottom);
  final width = math.min(desired.width, right - left);
  final height = math.min(desired.height, bottom - top);
  return Rect.fromLTWH(
    desired.left.clamp(left, right - width),
    desired.top.clamp(top, bottom - height),
    width,
    height,
  );
}
