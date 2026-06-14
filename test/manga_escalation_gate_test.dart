import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// Pins the manga "smart escalation" gate
/// (CameraService.shouldEscalateMangaToVision). The on-device hybrid manga
/// path used to keep its read whenever the total char count cleared a floor -
/// but a vertical-Japanese page that Apple Vision / ML Kit misread into LONG
/// Latin gibberish ("rudtrudt HIPION") has a HIGH char count, so it shipped
/// garbage and never escalated to the server vision-LLM. This gate replaces
/// the on-device read with a whole-page vision pass ONLY when the page is a
/// real CJK page that the on-device engines garbled, and never for genuine
/// Latin (Western) comics (which read perfectly on-device and must not pay for
/// a server call).
OcrBlock _b(String text) =>
    OcrBlock(text: text, boundingBox: const Rect.fromLTWH(0, 0, 100, 100));

void main() {
  group('shouldEscalateMangaToVision', () {
    test('garbled vertical-JP page (some CJK + many Latin misreads) escalates',
        () {
      // The real "みーは" page signature: a few bubbles read correctly as
      // Japanese, the dense vertical ones came back as Latin gibberish.
      final blocks = [
        _b('怒り'),
        _b('今日も人に迷惑をかけて'),
        _b('より良い財産'),
        _b('rudtrudt HIPION'),
        _b('dCAS Sorr'),
        _b('Iwayama'),
        _b('HIPIONnn'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isTrue);
    });

    test('clean Japanese page stays on-device (no Latin garble)', () {
      final blocks = [
        _b('怒り'),
        _b('今日も'),
        _b('ありがとう'),
        _b('元気ですか'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isFalse);
    });

    test('Latin (German) comic never escalates - not a CJK page', () {
      final blocks = [
        _b('GUTEN TAG'),
        _b('WAS IST DAS'),
        _b('HALLO WELT'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isFalse);
    });

    test('empty / whitespace-only page does not escalate', () {
      expect(CameraService.shouldEscalateMangaToVision(const []), isFalse);
      expect(
        CameraService.shouldEscalateMangaToVision([_b('   '), _b('!?…')]),
        isFalse,
      );
    });

    test('mostly-CJK page with ONE Latin sound effect stays on-device', () {
      // A lone "BOOM" SFX must not drag a good page to the server.
      final blocks = [
        _b('怒り'),
        _b('今日も'),
        _b('ありがとう'),
        _b('元気'),
        _b('こんにちは'),
        _b('さようなら'),
        _b('BOOM'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isFalse);
    });

    test('short Latin blocks (< 4 letters) are not counted as garble', () {
      // "RPH" (3 letters) is too short to be the garble signature.
      final blocks = [
        _b('怒り'),
        _b('今日も'),
        _b('ありがとう'),
        _b('RPH'),
        _b('OK!'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isFalse);
    });

    test('exactly 1/3 of blocks garbled on a CJK page escalates', () {
      final blocks = [
        _b('怒り'),
        _b('今日も'),
        _b('rudtrudt'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isTrue);
    });

    test('just under 1/3 of blocks garbled, CJK-dominant page, stays on-device',
        () {
      // 2 garble / 7 blocks < 1/3 (block-ratio signal off), AND the garble is
      // only a small share of the page's chars (char-ratio signal off too), so
      // a genuine CJK page with a couple of short misreads keeps the on-device
      // read. (Long garble that dominates the char count escalates via the
      // char-ratio signal - covered by the "garbled vertical-JP page" case.)
      final blocks = [
        _b('怒鳴り散らして'),
        _b('今日も人に迷惑を'),
        _b('ありがとうございます'),
        _b('元気ですか'),
        _b('こんにちは'),
        _b('rudt'),
        _b('dCAS'),
      ];
      expect(CameraService.shouldEscalateMangaToVision(blocks), isFalse);
    });
  });
}
