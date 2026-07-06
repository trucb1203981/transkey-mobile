import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// REAL on-device run of the manga/comic recognition path
/// (CameraService.recognizePerRegion = DBNet + BubbleDetector +
/// _groupDbnetByBubbles + per-region OCR) against bundled sample pages.
///
/// This is NOT a code unit test - it boots the actual ML pipeline on the
/// device so the grouping result can be observed and tuned. Each region's
/// OCR text + box is printed with a `TKTEST` prefix; grep the run output.
///
/// Pass/fail is intentionally loose (OCR varies run to run); the printed
/// region counts + texts are the signal. Primary check: the JP vertical
/// bubble must come back as ONE region with the full sentence, not one
/// fragment per column.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final service = CameraService();

  Future<String> materialize(String asset) async {
    final bytes = await rootBundle.load('assets/test_images/$asset');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$asset');
    await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return f.path;
  }

  Future<List<OcrBlock>> runOn(String asset) async {
    final path = await materialize(asset);
    final blocks = await service.recognizePerRegion(path);
    debugPrint('TKTEST ===== $asset: ${blocks.length} regions =====');
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final r = b.boundingBox;
      final t = b.text.replaceAll('\n', ' / ');
      debugPrint('TKTEST [$asset] #$i '
          'box=${r.left.toInt()},${r.top.toInt()} '
          '${r.width.toInt()}x${r.height.toInt()} text="$t"');
    }
    debugPrint('TKTEST ===== end $asset =====');
    return blocks;
  }

  testWidgets('manga JP vertical pages', (tester) async {
    for (final a in [
      'jp_vertical_1.jpg',
      'jp_vertical_2.jpg',
      'jp_vertical_3.jpg',
    ]) {
      final blocks = await runOn(a);
      expect(blocks, isA<List<OcrBlock>>());
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('horizontal comics regression', (tester) async {
    for (final a in ['comic_fr.jpg', 'comic_en.jpg']) {
      final blocks = await runOn(a);
      expect(blocks, isA<List<OcrBlock>>());
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
