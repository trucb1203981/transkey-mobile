import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:transkey_mobile/core/camera/adaptive_threshold.dart';

void main() {
  img.Image gradient({required bool bright, int contrast = 90}) {
    final image = img.Image(width: 180, height: 70);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final bg = bright ? 20 + x ~/ 3 : 130 + x ~/ 2;
        final stroke = y >= 25 && y < 45 && x % 24 >= 10 && x % 24 < 14;
        final value = stroke ? (bright ? bg + contrast : bg - contrast) : bg;
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    return image;
  }

  for (final bright in [false, true]) {
    test(
        'threshold preserves ${bright ? 'bright' : 'dark'} strokes across a lighting gradient',
        () {
      final image = gradient(bright: bright);
      adaptiveThreshold(image, bright: bright);
      for (final x in [11, 35, 83, 155]) {
        expect(image.getPixel(x, 35).r, 0);
        expect(image.getPixel(x, 10).r, 255);
      }
    });

    test(
        'non-square image threshold is invariant under a 90-degree rotation: $bright',
        () {
      final original = gradient(bright: bright, contrast: bright ? 10 : 30);
      final rotated = img.copyRotate(original, angle: 90);
      adaptiveThreshold(original, bright: bright);
      adaptiveThreshold(rotated, bright: bright);
      final restored = img.copyRotate(rotated, angle: -90);
      expect(restored.getBytes(), original.getBytes());
    });

    test('uniform background produces no false text: $bright', () {
      final image = img.Image(width: 40, height: 30);
      img.fill(image, color: img.ColorRgb8(120, 120, 120));
      adaptiveThreshold(image, bright: bright);
      expect(
          image.every((p) => p.r == 255 && p.g == 255 && p.b == 255), isTrue);
    });
  }
}
