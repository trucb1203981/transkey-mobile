import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/vision_dialogue_geometry.dart';

void main() {
  test('Japanese page fragments form six dialogues without expanding into art',
      () {
    final boxes = [
      const Rect.fromLTRB(125, 348, 250, 486),
      const Rect.fromLTRB(322, 510, 376, 557),
      const Rect.fromLTRB(314, 558, 385, 610),
      const Rect.fromLTRB(625, 591, 656, 622),
      const Rect.fromLTRB(617, 623, 664, 654),
      const Rect.fromLTRB(654, 655, 692, 686),
      const Rect.fromLTRB(654, 687, 685, 722),
      const Rect.fromLTRB(617, 719, 664, 754),
      const Rect.fromLTRB(107, 687, 131, 722),
      const Rect.fromLTRB(100, 719, 131, 754),
      const Rect.fromLTRB(640, 911, 678, 941),
      const Rect.fromLTRB(616, 942, 694, 994),
      const Rect.fromLTRB(515, 960, 555, 1257.5),
    ];
    final bubbles = [
      const Rect.fromLTRB(186, 519.6, 262.8, 602.4),
      const Rect.fromLTRB(276, 519.6, 394.8, 666),
      const Rect.fromLTRB(403.2, 519.6, 550.8, 560.4),
      const Rect.fromLTRB(415.2, 552, 547.2, 784.8),
      const Rect.fromLTRB(559.2, 564, 704.4, 846),
      const Rect.fromLTRB(247.2, 642, 394.8, 843.6),
      const Rect.fromLTRB(54, 656.4, 184.8, 843.6),
      const Rect.fromLTRB(280.8, 1198.8, 386.4, 1323.6),
    ];
    final result = groupDialogueBoxes(boxes, bubbles,
        imageSize: const Size(720, 1600), joinVerticalFragments: true);
    expect(result.map((g) => g.indices), [
      [0],
      [1, 2],
      [3, 4, 5, 6, 7],
      [8, 9],
      [10, 11],
      [12],
    ]);
    expect(result[1].box, const Rect.fromLTRB(314, 510, 385, 610));
    expect(result.last.box, boxes.last);
  });

  test('neighboring detected balloons never join across a small vertical gap',
      () {
    final boxes = [
      const Rect.fromLTRB(110, 110, 150, 150),
      const Rect.fromLTRB(110, 155, 150, 195),
    ];
    final result = groupDialogueBoxes(
        boxes,
        [
          const Rect.fromLTRB(100, 100, 160, 152),
          const Rect.fromLTRB(100, 153, 160, 205),
        ],
        imageSize: const Size(720, 1600),
        joinVerticalFragments: true);
    expect(result.map((g) => g.indices), [
      [0],
      [1]
    ]);
  });

  test('orphan grouping is opt-in and bounded by distance and page height', () {
    const boxes = [
      Rect.fromLTRB(20, 10, 40, 50),
      Rect.fromLTRB(20, 51, 40, 90),
      Rect.fromLTRB(20, 400, 40, 460),
      Rect.fromLTRB(20, 461, 40, 750),
    ];
    expect(groupDialogueBoxes(boxes, [], imageSize: const Size(720, 1600)),
        hasLength(4));
    final result = groupDialogueBoxes(boxes, [],
        imageSize: const Size(720, 1600), joinVerticalFragments: true);
    expect(result.map((g) => g.indices), [
      [0, 1],
      [2],
      [3]
    ]);
  });

  test('large white panel cannot merge separate dialogue', () {
    final result = groupDialogueBoxes([
      const Rect.fromLTRB(10, 10, 40, 50),
      const Rect.fromLTRB(400, 500, 440, 550),
    ], [
      const Rect.fromLTWH(0, 0, 720, 1000)
    ], imageSize: const Size(720, 1600));
    expect(result, hasLength(2));
    expect(
        groupDialogueBoxes([], [], imageSize: const Size(720, 1600)), isEmpty);
  });

  test('unique substantial native text anchors correct model coordinates', () {
    const wrong = Rect.fromLTRB(334, 1182, 436, 1234);
    const correct = Rect.fromLTRB(515, 960, 555, 1257.5);
    expect(
        alignDialogueAnchors([
          (text: 'あけみちゃ･･･', box: wrong),
        ], [
          (text: 'あけみちゃ.', box: correct),
        ]),
        [correct]);
  });

  test('short, repeated and differing native content cannot move a dialogue',
      () {
    const original = Rect.fromLTWH(100, 100, 20, 20);
    const elsewhere = Rect.fromLTWH(500, 500, 20, 20);
    final result = alignDialogueAnchors([
      (text: 'はい', box: original),
      (text: 'hello!', box: original),
      (text: 'Price 15', box: original),
    ], [
      (text: 'はい', box: elsewhere),
      (text: 'hello', box: elsewhere),
      (text: 'hello', box: original),
      (text: 'Price 19', box: elsewhere),
    ]);
    expect(result, [original, original, original]);
    expect(
        alignDialogueAnchors([
          (text: 'hello', box: original),
          (text: 'hello', box: elsewhere),
        ], [
          (text: 'hello', box: original),
        ]),
        [original, elsewhere]);
  });
}
