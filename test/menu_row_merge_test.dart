import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// Pins the menu-scene row grouping rules (CameraService._pairRowSegments
/// via mergeMenuRowsForTest): photo-grid caption rows must NOT merge into
/// one mega-dish, while classic "dish … price" list rows still pair into
/// one wide block with the price text stripped.
void main() {
  final service = CameraService();

  OcrBlock block(String text, double left, double top,
          {double width = 120, double height = 20}) =>
      OcrBlock(
        text: text,
        boundingBox: Rect.fromLTWH(left, top, width, height),
      );

  group('photo-grid menu rows', () {
    test('caption columns on one visual row stay separate dishes', () {
      // 5 captions, 20px tall, column gap 40px (> 1.5 × line height).
      // Old behavior: no price between them → all chained into one block.
      final captions = [
        'Mì xào sốt đặc',
        'Mì miso thịt heo quay',
        'Mì xào đậu',
        'Mì tương soy',
        'Mì muối',
      ];
      final row = [
        for (var i = 0; i < captions.length; i++)
          block(captions[i], i * 160.0, 1000),
      ];

      final out = service.mergeMenuRowsForTest(row);

      expect(out.map((b) => b.text).toList(), captions);
    });

    test('noisy price tags end a group and stay out of the dish text', () {
      // Photo-grid price tag OCR'd with noise ("1500a 03A 1.350 Ta") sits
      // on the same visual row as the next caption. It must close the
      // group AND its text must not leak into the dish sent to translate.
      final row = [
        block('1500a 03A 1.350 Ta', 0, 1000),
        block('Mì Tân Carang cay nóng', 140, 1000, width: 200),
      ];

      final out = service.mergeMenuRowsForTest(row);

      expect(out, hasLength(1));
      expect(out.single.text, 'Mì Tân Carang cay nóng');
    });

    test('standalone noisy price row is dropped', () {
      final out = service.mergeMenuRowsForTest([block('1.300 R', 0, 1000)]);
      expect(out, isEmpty);
    });
  });

  group('classic list menu rows', () {
    test('dish + far price → one dish block, price never its own card', () {
      // The pure-price segment is dropped by the noise filter BEFORE row
      // pairing (letterCount < 2 = noise), so only the dish survives.
      final row = [
        block('Phở bò', 0, 1000, width: 200),
        block('65.000', 500, 1000, width: 80),
      ];

      final out = service.mergeMenuRowsForTest(row);

      expect(out, hasLength(1));
      expect(out.single.text, 'Phở bò');
    });

    test('inline trailing price is stripped from a single-block dish row',
        () {
      final out =
          service.mergeMenuRowsForTest([block('Phở bò 65k', 0, 1000)]);
      expect(out, hasLength(1));
      expect(out.single.text, 'Phở bò');
    });

    test('mega noisy tag line from the real capture is filtered', () {
      // Exact shape from the 2026-06-10 device screenshot: a full row of
      // photo price tags OCR'd as one line (18 digits / 10 letters),
      // which previously leaked INTO the dish text.
      const tagLine = '1500a 03A 1.350 Ta 1200 CEna 1200 Sb';
      final mixedRow = [
        block(tagLine, 0, 1000, width: 300),
        block('Mì Tân Carang cay nóng', 340, 1000, width: 200),
      ];
      final mixed = service.mergeMenuRowsForTest(mixedRow);
      expect(mixed, hasLength(1));
      expect(mixed.single.text, 'Mì Tân Carang cay nóng');

      // Standalone on its own visual row → dropped entirely.
      final alone = service.mergeMenuRowsForTest([
        block(tagLine, 0, 1000, width: 300),
      ]);
      expect(alone, isEmpty);
    });

    test('a caption split into close fragments stays one dish', () {
      // ML Kit sometimes splits one caption at a small gap (10px << 1.5
      // × line height) — fragments must merge back, not become 2 dishes.
      final row = [
        block('Phở', 0, 1000, width: 60),
        block('bò', 70, 1000, width: 40),
      ];

      final out = service.mergeMenuRowsForTest(row);

      expect(out, hasLength(1));
      expect(out.single.text, 'Phở bò');
    });

    test('dish keeps a small number in its name', () {
      final row = [
        block('Phở 24', 0, 1000, width: 200),
        block('Combo 2', 320, 1000, width: 200),
      ];

      final out = service.mergeMenuRowsForTest(row);

      expect(out.map((b) => b.text).toList(), ['Phở 24', 'Combo 2']);
    });
  });
}
