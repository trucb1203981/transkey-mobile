import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Speech-bubble bounding-box detector for manga pages.
///
/// Manga speech bubbles are visually distinctive: a closed dark-line
/// border surrounding a near-white interior with text inside. We can
/// pick them out without any ML model using classical connected-
/// component analysis.
///
/// Algorithm (all on-device, ~300-800 ms per page):
///   1. Decode + downscale to [_kProcWidth] for speed (results are
///      scaled back to the original image coordinates).
///   2. Compute a binary mask: pixels with luminance ≥ [_kWhiteThreshold]
///      = "interior", else = "border/background".
///   3. 4-connected flood fill on the mask to enumerate components.
///   4. Filter components by:
///      - Area within [_kMinAreaRatio, _kMaxAreaRatio] of page
///      - Aspect ratio within [_kMinAspect, _kMaxAspect]
///      - Doesn't touch the page edge (page edge = the paper background,
///        which is the dominant white region; speech bubbles are
///        ALWAYS interior to the panel).
///   5. Return remaining components' axis-aligned bounding rects in
///      ORIGINAL image coordinates.
class BubbleDetector {
  // ── BASELINE: original BubbleDetector v1. Plain flood-fill on a
  // strict white-pixel mask, no morphology, no padding, strict
  // touches-edge reject, no post-merge. The simplest version that
  // gave ~10-30 bubble bboxes per manga page.
  static const int _kProcWidth = 600;
  static const int _kWhiteThreshold = 220;

  /// Lowered 0.005 → 0.003. Small dialogue bubbles ("YES, SIR!!", short
  /// reaction lines) at the original 0.5% floor were rejected — at proc
  /// width 600 a 35x25 bubble is ~0.24% of the page. Pattern cap stays
  /// loose enough that adjacent small-bubble clusters still group as
  /// individual components, not one giant leak (leak guard is fill
  /// ratio, not the min-area floor).
  static const double _kMinAreaRatio = 0.003;

  /// Tightened further 0.12 → 0.08. Speech bubbles + narration boxes
  /// in manga rarely exceed ~8% of the page; the 12% cap still let
  /// through a flood-fill leak that spanned two adjacent bubbles
  /// (~10-11% total) and OCR'd the concatenated text as one
  /// duplicate overlay.
  static const double _kMaxAreaRatio = 0.08;
  static const double _kMinAspect = 0.2;

  /// Raised from 4.0 → 6.0. Long horizontal narration ribbons in
  /// manga (often spanning the top of a panel) are typically 5:1 or
  /// 6:1 wide-to-tall; the previous 4.0 cap rejected them, leaving
  /// 3-4 untranslated boxes at the top of every page. 0.2 / 6.0
  /// also lets thin vertical text columns (CJK column dialogue) pass.
  static const double _kMaxAspect = 6.0;

  /// Minimum fraction of the bounding box that must actually be
  /// "interior" pixels. A real speech bubble fills ~70-85% of its
  /// rect (oval inscribed in rectangle). A flood-fill leak that
  /// crawls from one bubble to a neighbour through a narrow corridor
  /// has its area scattered at the two ends of the bbox, leaving a
  /// fill ratio well below 50%. The threshold catches the leak
  /// without rejecting real bubble shapes.
  static const double _kMinFillRatio = 0.55;
  static const double _kBboxPaddingPx = 0;
  static const int _kCloseRadius = 0;

  /// Tiered touches-edge override. Strict reject (the documented
  /// pattern default) drops every component that hits the image
  /// border, including legitimate bubbles drawn at the top / bottom
  /// of the page (e.g. the entire top row of an action page). Empirical
  /// data: page scaled_1000012669 caught only 6 of 19 visible bubbles
  /// because the top 5 and several middle ones touched the image edge
  /// through panel-border gaps.
  ///
  /// Safety vs the giant-leak symptom is preserved by combining TWO
  /// gates rather than relaxing area alone (pattern said area-only at
  /// 35% brought the leak back):
  ///   - area < [_kEdgeMaxAreaRatio] of page (tight — leaks tend to
  ///     swallow ≥ 10% of the page once they propagate)
  ///   - fill ratio ≥ [_kEdgeMinFillRatio] (strict — a leak corridor
  ///     has its mass at two ends with empty bbox in between, ratio
  ///     drops well below 0.65; legit edge bubbles still satisfy this
  ///     because they're inscribed ovals).
  /// Both thresholds intentionally stricter than the non-edge filters.
  static const double _kEdgeMaxAreaRatio = 0.04;
  static const double _kEdgeMinFillRatio = 0.65;

  /// Run detection on the file at [imagePath]. Returns an empty list
  /// if decode fails or no bubble-like regions are found.
  ///
  /// [whiteThreshold] picks the luminance floor for "interior" pixels.
  /// Default 220 (the pattern baseline) catches solid-fill bubbles.
  /// A second pass with a lower threshold (e.g. 200) catches flashback
  /// / memory bubbles whose interior is a light screentone — the
  /// orchestrator unions the two passes with IoU+containment dedupe.
  static Future<List<Rect>> detect(String imagePath,
      {int whiteThreshold = _kWhiteThreshold}) {
    return compute(_detectIsolate,
        _DetectArgs(imagePath: imagePath, whiteThreshold: whiteThreshold));
  }

  // ── Internal: runs in a background isolate ──

  static List<Rect> _detectIsolate(_DetectArgs args) {
    final imagePath = args.imagePath;
    final whiteThreshold = args.whiteThreshold;
    try {
      final bytes = File(imagePath).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const [];

      final origW = decoded.width;
      final origH = decoded.height;
      // Downscale for speed; scale rects back at the end.
      final scale = _kProcWidth / origW;
      const procW = _kProcWidth;
      final procH = (origH * scale).toInt();
      final small = img.copyResize(
        decoded,
        width: procW,
        height: procH,
        interpolation: img.Interpolation.linear,
      );

      // Build the binary mask. 1 = "interior" (white-ish), 0 = border/dark.
      Uint8List mask = Uint8List(procW * procH);
      for (var y = 0; y < procH; y++) {
        for (var x = 0; x < procW; x++) {
          final p = small.getPixel(x, y);
          final lum = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b).toInt();
          mask[y * procW + x] = lum >= whiteThreshold ? 1 : 0;
        }
      }

      // Morphological close: dilate then erode. Closes small gaps in
      // bubble borders so a slightly broken outline doesn't bleed the
      // bubble's interior into the surrounding panel (which would
      // either swallow neighbour bubbles or get rejected by the
      // touches-edge filter).
      //
      // NOTE: dilation expands "interior" (white). Apply it to the
      // INVERSE so we expand "border" (dark) instead, closing border
      // gaps. Equivalent to morphological close on inverse, then
      // re-invert.
      mask = _closeInverse(mask, procW, procH, _kCloseRadius);

      final totalArea = procW * procH;
      final minArea = (totalArea * _kMinAreaRatio).toInt();
      final maxArea = (totalArea * _kMaxAreaRatio).toInt();

      // Flood-fill via DFS; the explicit `stack` list avoids the
      // recursion-depth limit on the long components.
      final visited = Uint8List(procW * procH);
      final rects = <Rect>[];
      final stack = <int>[];

      for (var seed = 0; seed < mask.length; seed++) {
        if (visited[seed] != 0 || mask[seed] == 0) continue;

        stack.clear();
        stack.add(seed);
        visited[seed] = 1;
        var minX = procW, minY = procH, maxX = 0, maxY = 0, area = 0;
        var touchesEdge = false;

        while (stack.isNotEmpty) {
          final cur = stack.removeLast();
          final cx = cur % procW;
          final cy = cur ~/ procW;
          area++;
          if (cx < minX) minX = cx;
          if (cy < minY) minY = cy;
          if (cx > maxX) maxX = cx;
          if (cy > maxY) maxY = cy;
          if (cx == 0 || cy == 0 || cx == procW - 1 || cy == procH - 1) {
            touchesEdge = true;
          }

          // 8-connectivity — original v1 baseline. Diagonal links
          // are tolerated here because the upstream pipeline produced
          // better results with this setting overall, per the user.
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = cx + dx;
              final ny = cy + dy;
              if (nx < 0 || ny < 0 || nx >= procW || ny >= procH) continue;
              final n = ny * procW + nx;
              if (visited[n] == 0 && mask[n] == 1) {
                visited[n] = 1;
                stack.add(n);
              }
            }
          }
        }

        // Area + aspect first so we can short-circuit before the
        // fill-ratio math.
        if (area < minArea || area > maxArea) continue;
        final compW = maxX - minX + 1;
        final compH = maxY - minY + 1;
        final aspect = compW / compH;
        if (aspect < _kMinAspect || aspect > _kMaxAspect) continue;
        // Fill ratio gate — leaked corridor components have area
        // clustered at the two bubble ends with empty bbox between,
        // dropping ratio well below the ~0.78 of a real oval-in-rect
        // speech bubble. Silver-bullet leak guard per pattern.
        final fillRatio = area / (compW * compH);
        if (fillRatio < _kMinFillRatio) continue;

        // Tiered touches-edge filter. The page background is the
        // largest white region and always touches the edge — if its
        // border has any 1-pixel gap, flood-fill leaks INTO every
        // bubble through it, returning the whole page as one giant
        // component ("dính 1 block lớn"). BUT strict reject also
        // drops every legitimate bubble drawn at the top / bottom
        // of an action page. Two-gate compromise: reject ONLY if
        // (area ≥ tight cap) OR (fill ratio < strict floor). The
        // page-background-leak case fails BOTH thresholds together
        // (large + corridor-shaped); a legit edge bubble passes
        // both (small + oval).
        if (touchesEdge) {
          final edgeMaxArea = (totalArea * _kEdgeMaxAreaRatio).toInt();
          if (area >= edgeMaxArea) continue;
          if (fillRatio < _kEdgeMinFillRatio) continue;
        }

        // Scale back to original image coordinates AND inflate by
        // [_kBboxPaddingPx] so the rect encloses the bubble's black
        // border, not just the interior. Clamp to image bounds.
        final inv = 1.0 / scale;
        final left = (minX * inv - _kBboxPaddingPx).clamp(0.0, origW.toDouble());
        final top = (minY * inv - _kBboxPaddingPx).clamp(0.0, origH.toDouble());
        final right =
            ((maxX + 1) * inv + _kBboxPaddingPx).clamp(0.0, origW.toDouble());
        final bottom =
            ((maxY + 1) * inv + _kBboxPaddingPx).clamp(0.0, origH.toDouble());
        rects.add(Rect.fromLTRB(left, top, right, bottom));
      }
      // Geometric container drop was unreliable — adjacent narration
      // ribbons can geometrically contain a smaller bubble bbox even
      // though they're separate real text. The leak-detection moves
      // post-OCR (text content dedup) in CameraService, which knows
      // what each region actually says.
      return rects;
    } catch (_) {
      return const [];
    }
  }

  /// Morphological close on the INVERSE of [mask] (treating 0 as
  /// foreground), returning a new mask with bubble-border gaps sealed.
  /// Implemented as dilation-then-erosion using two-pass separable
  /// box filters over a 2*r+1 window. Cheap: O(w*h*r).
  static Uint8List _closeInverse(Uint8List mask, int w, int h, int r) {
    if (r <= 0) return mask;
    // Inverse: 1 where original was 0 (border / dark).
    final inv = Uint8List(w * h);
    for (var i = 0; i < mask.length; i++) {
      inv[i] = mask[i] == 0 ? 1 : 0;
    }
    final dilated = _dilate(inv, w, h, r);
    final eroded = _erode(dilated, w, h, r);
    // Re-invert back to original convention.
    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = eroded[i] == 0 ? 1 : 0;
    }
    return out;
  }

  /// Binary dilation with a (2r+1)x(2r+1) square structuring element.
  /// A pixel is set if ANY pixel within the window is set in [src].
  static Uint8List _dilate(Uint8List src, int w, int h, int r) {
    // Two separable passes: horizontal, then vertical. Equivalent to
    // a full 2D dilation but O(w*h*r) instead of O(w*h*r²).
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 0;
        for (var d = -r; d <= r; d++) {
          final xx = x + d;
          if (xx < 0 || xx >= w) continue;
          if (src[y * w + xx] == 1) {
            on = 1;
            break;
          }
        }
        tmp[y * w + x] = on;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 0;
        for (var d = -r; d <= r; d++) {
          final yy = y + d;
          if (yy < 0 || yy >= h) continue;
          if (tmp[yy * w + x] == 1) {
            on = 1;
            break;
          }
        }
        out[y * w + x] = on;
      }
    }
    return out;
  }

  /// Binary erosion (mirror of dilation): pixel set only if ALL
  /// pixels in the window are set.
  static Uint8List _erode(Uint8List src, int w, int h, int r) {
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 1;
        for (var d = -r; d <= r; d++) {
          final xx = x + d;
          if (xx < 0 || xx >= w || src[y * w + xx] == 0) {
            on = 0;
            break;
          }
        }
        tmp[y * w + x] = on;
      }
    }
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var on = 1;
        for (var d = -r; d <= r; d++) {
          final yy = y + d;
          if (yy < 0 || yy >= h || tmp[yy * w + x] == 0) {
            on = 0;
            break;
          }
        }
        out[y * w + x] = on;
      }
    }
    return out;
  }
}

/// Isolate transport for [BubbleDetector._detectIsolate]. `compute()`
/// only accepts a single positional argument, so wrap the image path
/// + tunable threshold in one immutable record.
class _DetectArgs {
  const _DetectArgs({
    required this.imagePath,
    required this.whiteThreshold,
  });
  final String imagePath;
  final int whiteThreshold;
}
