import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// Pins CameraService.joinVisionRegionText / collapseCjkNewlines. Apple Vision
/// returns a vertical Japanese bubble as one observation per column - OFTEN per
/// GLYPH (a near-square box). An aspect-ratio "is it tall?" test misses the
/// per-glyph case, so the source stacked ONE CHARACTER PER LINE in the manga
/// list view ("source isn't reassembled left-to-right"). The fix is
/// content-based: CJK-dominant text collapses its newlines into one continuous
/// horizontal string; genuine Latin multi-line text keeps its line breaks.

// A vertical-CJK COLUMN observation: taller than wide.
OcrBlock _col(String t, double x) =>
    OcrBlock(text: t, boundingBox: Rect.fromLTWH(x, 0, 20, 60));

// A per-GLYPH observation: near-square (the case the aspect-ratio test missed).
OcrBlock _glyph(String t, double y) =>
    OcrBlock(text: t, boundingBox: Rect.fromLTWH(40, y, 22, 24));

// A horizontal Latin LINE observation: wider than tall.
OcrBlock _line(String t, double y) =>
    OcrBlock(text: t, boundingBox: Rect.fromLTWH(0, y, 200, 24));

void main() {
  group('joinVisionRegionText', () {
    test('vertical-CJK COLUMNS join into one continuous horizontal string', () {
      final ordered = [_col('行', 80), _col('す', 60), _col('く', 40), _col('ぐ', 20)];
      expect(CameraService.joinVisionRegionText(ordered), '行すくぐ');
    });

    test('per-GLYPH vertical CJK (square boxes) is NOT stacked - the user bug',
        () {
      // Each glyph is its own near-square observation, stacked down a column.
      final ordered = [
        _glyph('行', 0),
        _glyph('す', 24),
        _glyph('く', 48),
        _glyph('ぐ', 72),
        _glyph('か', 96),
      ];
      final out = CameraService.joinVisionRegionText(ordered);
      expect(out, '行すくぐか');
      expect(out.contains('\n'), isFalse);
    });

    test('horizontal Latin multi-line text KEEPS newline separators', () {
      final ordered = [_line('First line', 0), _line('Second line', 30)];
      expect(
        CameraService.joinVisionRegionText(ordered),
        'First line\nSecond line',
      );
    });

    test('empty region yields empty string', () {
      expect(CameraService.joinVisionRegionText(const []), '');
    });
  });

  group('collapseCjkNewlines', () {
    test('collapses newlines between CJK glyphs', () {
      expect(CameraService.collapseCjkNewlines('行\nす\nく\nぐ'), '行すくぐ');
      expect(CameraService.collapseCjkNewlines('あっ\nごあ\n一っ'), 'あっごあ一っ');
    });

    test('leaves Latin multi-line untouched', () {
      expect(
        CameraService.collapseCjkNewlines('Hello\nWorld'),
        'Hello\nWorld',
      );
    });

    test('no-op when there is no newline', () {
      expect(CameraService.collapseCjkNewlines('行すくぐ'), '行すくぐ');
    });

    test('mixed but CJK-dominant collapses; Latin-dominant does not', () {
      expect(CameraService.collapseCjkNewlines('日本\n語'), '日本語');
      expect(
        CameraService.collapseCjkNewlines('OK\nです google'),
        'OK\nです google',
      );
    });
  });
}
