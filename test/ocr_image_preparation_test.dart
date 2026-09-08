import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:transkey_mobile/core/camera/camera_service.dart';
import 'package:transkey_mobile/core/camera/ocr_image_preparation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory inputDirectory;
  const channel = MethodChannel('google_mlkit_text_recognizer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    inputDirectory = await Directory.systemTemp.createTemp('tk_input_test_');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await inputDirectory.delete(recursive: true);
  });

  Future<File> fixture(int width, int height, {int orientation = 1}) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    image.exif.imageIfd.orientation = orientation;
    return File('${inputDirectory.path}/source.jpg')
      ..writeAsBytesSync(img.encodeJpg(image));
  }

  test('rounded resize restores both axes exactly and cleans scratch only',
      () async {
    final source = await fixture(2401, 1803);
    final prepared = await prepareOcrImage(source.path, maxEdge: 1600);
    final working = img.decodeJpg(await File(prepared.path).readAsBytes())!;
    expect(working.width, 1600);
    expect(working.height, 1201);
    expect(
        prepared.toSourceRect(Rect.fromLTWH(
            0, 0, working.width.toDouble(), working.height.toDouble())),
        const Rect.fromLTWH(0, 0, 2401, 1803));
    await prepared.dispose();
    expect(await Directory(prepared.temporaryDirectory!).exists(), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('small images are not re-encoded or removed', () async {
    final source = await fixture(320, 240);
    final before = await source.readAsBytes();
    final prepared = await prepareOcrImage(source.path, maxEdge: 1600);
    expect(prepared.path, source.path);
    expect(prepared.toSourceRect(const Rect.fromLTWH(10, 20, 30, 40)),
        const Rect.fromLTWH(10, 20, 30, 40));
    await prepared.dispose();
    expect(await source.readAsBytes(), before);
  });

  for (final orientation in [5, 6, 7, 8]) {
    test('EXIF $orientation normalizes orientation before computing scale',
        () async {
      final source = await fixture(300, 200, orientation: orientation);
      final prepared = await prepareOcrImage(source.path, maxEdge: 150);
      final working = img.decodeJpg(await File(prepared.path).readAsBytes())!;
      expect((working.width, working.height), (100, 150));
      expect(working.exif.imageIfd.orientation ?? 1, 1);
      expect(prepared.toSourceRect(const Rect.fromLTWH(0, 0, 100, 150)),
          const Rect.fromLTWH(0, 0, 200, 300));
      await prepared.dispose();
    });
  }

  test('parallel preparations have separate scratch files', () async {
    final source = await fixture(300, 200);
    final prepared = await Future.wait([
      prepareOcrImage(source.path, maxEdge: 150),
      prepareOcrImage(source.path, maxEdge: 150),
    ]);
    expect(prepared[0].path, isNot(prepared[1].path));
    await prepared[0].dispose();
    expect(await File(prepared[1].path).exists(), isTrue);
    await prepared[1].dispose();
  });

  test('CameraService returns source coordinates and releases its work file',
      () async {
    final source = await fixture(2400, 1800);
    String? workingPath;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'vision#startTextRecognizer') return null;
      final data = (call.arguments as Map)['imageData'] as Map;
      workingPath = data['path'] as String;
      expect(await File(workingPath!).exists(), isTrue);
      return {
        'text': 'CLEAR SOURCE TEXT',
        'blocks': [
          {
            'text': 'CLEAR SOURCE TEXT',
            'rect': {
              'left': 800.0,
              'top': 600.0,
              'right': 1200.0,
              'bottom': 680.0
            },
            'recognizedLanguages': <String>[],
            'points': <Object>[],
            'lines': <Object>[]
          },
        ]
      };
    });
    final blocks = await CameraService()
        .recognizeText(source.path, autoDetect: false, aggressivePasses: false);
    expect(
        blocks.single.boundingBox, const Rect.fromLTRB(1200, 900, 1800, 1020));
    expect(await File(workingPath!).exists(), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('native OCR failures also release the prepared file', () async {
    final source = await fixture(2400, 1800);
    String? workingPath;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'vision#startTextRecognizer') return null;
      workingPath =
          ((call.arguments as Map)['imageData'] as Map)['path'] as String;
      throw PlatformException(code: 'ocr_failed');
    });
    await expectLater(
        CameraService().recognizeText(source.path,
            autoDetect: false, aggressivePasses: false),
        throwsA(isA<PlatformException>()));
    expect(await File(workingPath!).exists(), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('dense gallery scenes retain detail without changing upload limits', () {
    expect(galleryMaxEdgeForScene('menu'), 2560);
    expect(galleryMaxEdgeForScene('document'), 2560);
    expect(galleryMaxEdgeForScene('manga'), 2560);
    expect(galleryMaxEdgeForScene('screenshot'), 2048);
    expect(galleryMaxEdgeForScene('sign'), 1280);
    expect(androidOcrMaxEdgeForScene('menu'), 2048);
  });
}
