import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks the native side to sample the dominant background colour just
/// outside each OCR bounding box.
///
/// The overlay uses this so each translation card paints a solid panel
/// that matches the surrounding photo: a card sitting over a white menu
/// looks like a white card, over a coffee table it picks up the wood
/// tone, etc. The capture text underneath is then visually replaced
/// (rather than chip-stamped) and the translation can sit at the exact
/// pixel position the source text occupied.
///
/// Android-only. iOS / desktop fall back to opaque dark grey so the
/// overlay still works, just without the photo-matched tint.
class BgColorSampler {
  static const _channel = MethodChannel('transkey/bg_sampler');

  /// Default fallback colour when sampling is unavailable or fails.
  /// Dark with high alpha so white text stays legible on any photo.
  static const Color fallback = Color(0xE6111111);

  /// Sample one colour per [rects] (image-space pixel coords). Returns
  /// a list of the same length and order. Failures degrade gracefully
  /// to [fallback] for the whole batch.
  static Future<List<Color>> sample({
    required String imagePath,
    required List<Rect> rects,
  }) async {
    if (rects.isEmpty) return const <Color>[];
    if (!Platform.isAndroid) {
      return List<Color>.filled(rects.length, fallback);
    }
    try {
      final raw = await _channel.invokeListMethod<int>('sample', {
        'imagePath': imagePath,
        'rects': rects
            .map((r) => {
                  'left': r.left.round(),
                  'top': r.top.round(),
                  'right': r.right.round(),
                  'bottom': r.bottom.round(),
                })
            .toList(),
      });
      if (raw == null || raw.length != rects.length) {
        return List<Color>.filled(rects.length, fallback);
      }
      return raw.map((argb) => Color(argb)).toList();
    } catch (e) {
      debugPrint('[BgColorSampler] failed: $e');
      return List<Color>.filled(rects.length, fallback);
    }
  }
}
