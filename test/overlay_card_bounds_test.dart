import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/widgets/overlay_card_bounds.dart';

void main() {
  test('dense rows remain separate when translations need several lines', () {
    const sources = [
      Rect.fromLTWH(20, 110, 100, 12),
      Rect.fromLTWH(22, 132, 110, 12),
      Rect.fromLTWH(20, 154, 100, 12),
    ];
    final output = [
      for (var i = 0; i < sources.length; i++)
        boundOverlayCard(
          desired: Rect.fromLTWH(sources[i].left, sources[i].top, 170, 90),
          source: sources[i],
          neighbors: sources.where((s) => s != sources[i]),
          imageBounds: const Rect.fromLTWH(0, 100, 320, 400),
        ),
    ];
    expect(output[0].bottom, lessThan(output[1].top));
    expect(output[1].bottom, lessThan(output[2].top));
    expect(output.every((r) => r.width > 0 && r.height > 0), isTrue);
  });

  test('long footer stays inside the letterboxed photo', () {
    final rect = boundOverlayCard(
      desired: const Rect.fromLTWH(260, 480, 180, 160),
      source: const Rect.fromLTWH(260, 480, 60, 20),
      neighbors: const [],
      imageBounds: const Rect.fromLTWH(0, 100, 320, 400),
    );
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.bottom, lessThanOrEqualTo(500));
    expect(rect.width, 180);
  });

  test('symmetric cells preserve distinct cards across a dense panel grid', () {
    final sources = [
      for (var row = 0; row < 4; row++)
        for (var col = 0; col < 3; col++)
          Rect.fromLTWH(10 + col * 100, 50 + row * 100, 70, 35),
    ];
    final cards = [
      for (final source in sources)
        boundOverlayCard(
          desired:
              Rect.fromCenter(center: source.center, width: 200, height: 220),
          source: source,
          neighbors: sources.where((s) => s != source),
          imageBounds: const Rect.fromLTWH(0, 30, 320, 430),
        ),
    ];
    for (var i = 0; i < cards.length; i++) {
      expect(cards[i].isEmpty, isFalse);
      for (var j = i + 1; j < cards.length; j++) {
        expect(cards[i].overlaps(cards[j]), isFalse, reason: 'cards $i and $j');
      }
    }
  });
}
