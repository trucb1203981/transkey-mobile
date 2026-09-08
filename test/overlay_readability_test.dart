import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';
import 'package:transkey_mobile/features/translate/widgets/camera_result_overlay.dart';

void main() {
  for (final manga in [true, false]) {
    testWidgets(
        'long ${manga ? "comic" : "menu"} text stays in its cell and opens in full',
        (tester) async {
      final translations = [
        List.filled(12, 'First complete dialogue.').join(' '),
        List.filled(8, 'A different answer.').join(' '),
      ];
      final blocks = [
        const OcrBlock(
            text: 'First source', boundingBox: Rect.fromLTWH(20, 50, 110, 24)),
        const OcrBlock(
            text: 'Different answer',
            boundingBox: Rect.fromLTWH(22, 95, 100, 24)),
      ];
      String? opened;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
              width: 320,
              height: 500,
              child: CameraResultOverlay(
                blocks: blocks,
                translations: translations,
                imageSize: const ui.Size(320, 400),
                mangaMode: manga,
                menuMode: !manga,
                fontScale: 1.5,
                showOriginalAlways: true,
                onBlockTap: (_, __, text) => opened = text,
              )),
        ),
      ))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final first = find.byKey(const ValueKey('ocr-card-0'));
      final second = find.byKey(const ValueKey('ocr-card-1'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(tester.getRect(first).overlaps(tester.getRect(second)), isFalse);
      for (final translation in translations) {
        final preview = tester.widget<Text>(find.text(translation));
        expect(preview.overflow, TextOverflow.ellipsis);
        expect(preview.maxLines, greaterThanOrEqualTo(1));
      }
      await tester.tap(first);
      expect(opened, translations.first);
    });
  }
}
