import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

void main() {
  test('adjacent native paragraphs retain independent text and positions', () {
    final result = CameraService.mapOcrParagraphs(const [
      OcrBlock(text: 'First panel', boundingBox: Rect.fromLTWH(20, 40, 200, 80)),
      OcrBlock(text: 'Second panel', boundingBox: Rect.fromLTWH(480, 20, 260, 100)),
    ], cropOrigin: const Offset(80, 795), ocrScale: 2,
        imageSize: const Size(1078, 1600));
    expect(result.map((p) => p.text), ['First panel', 'Second panel']);
    expect(result[0].boundingBox, const Rect.fromLTWH(90, 815, 100, 40));
    expect(result[1].boundingBox, const Rect.fromLTWH(320, 805, 130, 50));
    expect(result[0].boundingBox.overlaps(result[1].boundingBox), isFalse);
  });

  test('discard empty or out-of-photo native regions', () {
    final result = CameraService.mapOcrParagraphs(const [
      OcrBlock(text: '', boundingBox: Rect.fromLTWH(0, 0, 40, 40)),
      OcrBlock(text: 'Inside', boundingBox: Rect.fromLTWH(0, 0, 60, 40)),
      OcrBlock(text: 'Outside', boundingBox: Rect.fromLTWH(500, 500, 20, 20)),
    ], cropOrigin: const Offset(0, 0), ocrScale: 1,
        imageSize: const Size(100, 100));
    expect(result.single.text, 'Inside');
  });
}
