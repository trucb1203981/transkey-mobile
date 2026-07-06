import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';
import 'package:transkey_mobile/features/translate/widgets/camera_result_overlay.dart';

/// Pins the manga "overlay double" suppression in CameraResultOverlay.
///
/// Reproduced on device 2026-06-15 (French Tintin comic, Comic scene): each top
/// bubble rendered TWO stacked cards - a short translated card ("Kết quả: Chúng
/// ta phải") on top of the full raw-source card ("RESULTAT NOUS DEVONS
/// REMETTRE..."). The two come from different pipeline stages (OCR vs vision
/// catch-up) so the upstream block-dedup never sees them together; the overlay
/// is the last line of defence. When two rendered manga cards overlap by a
/// majority of the smaller, the higher-value card wins (translated beats raw
/// source) and the other is dropped.
void main() {
  OcrBlock blk(String text, double l, double t, double w, double h) =>
      OcrBlock(text: text, boundingBox: Rect.fromLTWH(l, t, w, h));

  // The two overlay-double blocks share the SAME bubble box (guaranteed
  // rendered overlap): a clean read that translated + the full garbled read
  // that echoed raw source (empty translation -> the card renders the source).
  final dupTranslated = blk('ORIG', 40, 100, 130, 60);
  final dupRawSource = blk('RAW TWIN', 40, 100, 130, 60);
  // A genuinely distinct bubble far away - must never be suppressed.
  final distinct = blk('AUTRE', 40, 420, 120, 50);

  final blocks = [dupTranslated, dupRawSource, distinct];
  // index-aligned translations: dup raw-source has NO translation (echoes
  // source); the other two are translated.
  final translations = ['Dich ngan', '', 'Rieng biet'];

  Widget harness({required bool manga}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 640,
              child: CameraResultOverlay(
                blocks: blocks,
                translations: translations,
                imageSize: const Size(320, 640), // scale 1, no letterbox
                mangaMode: manga,
              ),
            ),
          ),
        ),
      );

  testWidgets('manga: raw-source duplicate over a translated card is dropped',
      (tester) async {
    await tester.pumpWidget(harness(manga: true));
    await tester.pump();

    // Translated duplicate stays; the overlapping raw-source twin is gone.
    expect(find.text('Dich ngan'), findsOneWidget);
    expect(find.text('RAW TWIN'), findsNothing);
    // The distinct bubble is untouched.
    expect(find.text('Rieng biet'), findsOneWidget);
  });

  testWidgets('distinct non-overlapping bubbles all survive in manga mode',
      (tester) async {
    // Three bubbles spread out so none overlaps - suppression must keep all.
    final spread = [
      blk('A', 20, 60, 100, 40),
      blk('B', 20, 220, 100, 40),
      blk('C', 20, 400, 100, 40),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 640,
            child: CameraResultOverlay(
              blocks: spread,
              translations: const ['Mot', 'Hai', 'Ba'],
              imageSize: const Size(320, 640),
              mangaMode: true,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Mot'), findsOneWidget);
    expect(find.text('Hai'), findsOneWidget);
    expect(find.text('Ba'), findsOneWidget);
  });
}
