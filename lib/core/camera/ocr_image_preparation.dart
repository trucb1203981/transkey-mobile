import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// OCR working image with the transform back to the upright source image.
class PreparedOcrImage {
  const PreparedOcrImage({
    required this.path,
    this.scaleX = 1,
    this.scaleY = 1,
    this.temporaryDirectory,
  });

  final String path;
  final double scaleX;
  final double scaleY;
  final String? temporaryDirectory;

  Rect toSourceRect(Rect rect) => Rect.fromLTRB(
        rect.left * scaleX,
        rect.top * scaleY,
        rect.right * scaleX,
        rect.bottom * scaleY,
      );

  /// Deletes only the scratch directory owned by this preparation call.
  Future<void> dispose() async {
    final directory = temporaryDirectory;
    if (directory == null) return;
    try {
      await File(path).delete();
      await Directory(directory).delete();
    } on FileSystemException catch (error) {
      debugPrint('[OCR] Scratch cleanup failed: ${error.osError?.errorCode}');
    }
  }
}

/// Keep dense text readable locally. Vision upload limits are independent.
int galleryMaxEdgeForScene(String scene) => switch (scene) {
      'menu' || 'document' || 'manga' => 2560,
      'sign' => 1280,
      _ => 2048,
    };

int androidOcrMaxEdgeForScene(String scene) => switch (scene) {
      'menu' || 'document' || 'screenshot' => 2048,
      'manga' => 2560,
      _ => 1600,
    };

/// Decode, normalize EXIF orientation, resize, and encode off the UI isolate.
Future<PreparedOcrImage> prepareOcrImage(
  String path, {
  required int maxEdge,
}) {
  if (maxEdge < 1) throw ArgumentError.value(maxEdge, 'maxEdge');
  return compute(_prepareOcrImage, (path: path, maxEdge: maxEdge));
}

Future<PreparedOcrImage> _prepareOcrImage(
  ({String path, int maxEdge}) args,
) async {
  final bytes = await File(args.path).readAsBytes();
  final decoded = img.decodeImage(bytes);
  // Preserve native OCR support for formats the Dart decoder cannot read.
  if (decoded == null) return PreparedOcrImage(path: args.path);

  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  final upright = orientation == 1 ? decoded : img.bakeOrientation(decoded);
  final sourceWidth = upright.width;
  final sourceHeight = upright.height;
  final longest = math.max(sourceWidth, sourceHeight);
  if (longest <= args.maxEdge && orientation == 1) {
    return PreparedOcrImage(path: args.path);
  }

  final ratio = math.min(1.0, args.maxEdge / longest);
  final working = ratio == 1
      ? upright
      : img.copyResize(
          upright,
          width: math.max(1, (sourceWidth * ratio).round()),
          height: math.max(1, (sourceHeight * ratio).round()),
          interpolation: img.Interpolation.average,
        );
  final directory = await Directory.systemTemp.createTemp('tk_ocr_');
  final output = File('${directory.path}/prepared.jpg');
  try {
    await output.writeAsBytes(img.encodeJpg(working, quality: 90));
    return PreparedOcrImage(
      path: output.path,
      scaleX: sourceWidth / working.width,
      scaleY: sourceHeight / working.height,
      temporaryDirectory: directory.path,
    );
  } catch (_) {
    if (await output.exists()) await output.delete();
    await directory.delete();
    rethrow;
  }
}
