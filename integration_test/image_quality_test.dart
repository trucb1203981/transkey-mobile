import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transkey_mobile/core/camera/camera_service.dart';

/// Real native OCR on reproducible images, without a server/model request.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.allTestsPassed.future.then((passed) {
    debugPrint('QUALITY_SUITE passed=$passed tests=${binding.results.length}');
  });

  Future<File> fixture(
      {required int width,
      required int height,
      required String text,
      required Offset origin,
      required double fontSize,
      bool exifRotated = false}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontFamily: 'sans-serif')),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - origin.dx);
    painter.paint(canvas, origin);
    painter.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    picture.dispose();
    var bytes = data.buffer.asUint8List();
    if (exifRotated) {
      final stored = img.copyRotate(img.decodePng(bytes)!, angle: -90);
      stored.exif.imageIfd.orientation = 6;
      bytes = img.encodeJpg(stored, quality: 95);
    }
    final dir = await getTemporaryDirectory();
    return File(
        '${dir.path}/quality_${width}_${height}_${exifRotated ? 'exif' : 'plain'}.jpg')
      ..writeAsBytesSync(bytes);
  }

  for (final sample in [
    (
      width: 3000,
      height: 2200,
      text: 'FRESH COFFEE',
      origin: const Offset(1550, 1650),
      font: 80.0,
      scene: 'menu',
      aggressive: false,
      exif: false
    ),
    (
      width: 1800,
      height: 3000,
      text: 'PLEASE KEEP THIS TICKET',
      origin: const Offset(180, 2400),
      font: 70.0,
      scene: 'document',
      aggressive: true,
      exif: true
    ),
    (
      width: 1000,
      height: 700,
      text: 'OPEN DAILY',
      origin: const Offset(150, 400),
      font: 70.0,
      scene: 'sign',
      aggressive: false,
      exif: false
    ),
  ]) {
    testWidgets(
        'native OCR ${sample.scene} preserves text and source coordinates',
        (tester) async {
      final file = await fixture(
          width: sample.width,
          height: sample.height,
          text: sample.text,
          origin: sample.origin,
          fontSize: sample.font,
          exifRotated: sample.exif);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final watch = Stopwatch()..start();
      final blocks = await CameraService().recognizeText(file.path,
          autoDetect: false,
          scene: sample.scene,
          aggressivePasses: sample.aggressive);
      final matching = blocks.where(
          (b) => b.text.replaceAll(RegExp(r'\s+'), ' ').contains(sample.text));
      expect(matching, isNotEmpty,
          reason: 'Native OCR must read the reference text');
      final box = matching.first.boundingBox;
      expect(box.left, closeTo(sample.origin.dx, sample.font));
      expect(box.top, closeTo(sample.origin.dy, sample.font));
      expect(box.right, lessThanOrEqualTo(sample.width.toDouble()));
      expect(box.bottom, lessThanOrEqualTo(sample.height.toDouble()));
      debugPrint(
          'QUALITY_RESULT scene=${sample.scene} elapsed_ms=${watch.elapsedMilliseconds} '
          'source=${sample.width}x${sample.height} box=$box');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
