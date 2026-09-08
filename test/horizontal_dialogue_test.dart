import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/vision_dialogue_geometry.dart';

void main() {
  test('physical French lines retain three independent dialogue positions', () {
    final data = jsonDecode(File('test/fixtures/french_dialogue_native.json')
        .readAsStringSync()) as Map;
    final lines = data['lines'] as List;
    final w = (data['width'] as num).toDouble();
    final h = (data['height'] as num).toDouble();
    final groups = groupHorizontalDialogueLines(lines
        .map((l) => Rect.fromLTWH(
              l['left'] * w,
              l['top'] * h,
              l['width'] * w,
              l['height'] * h,
            ))
        .toList());
    final texts =
        groups.map((g) => g.map((i) => lines[i]['text']).join(' ')).toList();
    expect(texts, hasLength(3));
    expect(texts.singleWhere((t) => t.contains('JOSAIS')),
        contains("D'UNE IMPASSE"));
    expect(
        texts.singleWhere((t) => t.contains('SPIROU')), contains('LAVENTURE'));
    expect(
        texts.singleWhere((t) => t.contains('HELAS')), contains('VOUS AIDER'));
    expect(groups.expand((g) => g).toSet(),
        Set.of(List.generate(lines.length, (i) => i)));
  });

  test(
      'physical wide crop keeps left dialogue, caption and right balloon apart',
      () {
    final data = jsonDecode(File('test/fixtures/french_dialogue_region.json')
        .readAsStringSync()) as Map;
    final lines = data['lines'] as List;
    final w = (data['width'] as num).toDouble();
    final h = (data['height'] as num).toDouble();
    final groups = groupHorizontalDialogueLines(lines
        .map((l) => Rect.fromLTWH(
              l['left'] * w,
              l['top'] * h,
              l['width'] * w,
              l['height'] * h,
            ))
        .toList());
    expect(groups, hasLength(3));
    expect(groups.singleWhere((g) => g.contains(0)), [0, 1, 2, 3, 4, 5, 6]);
    expect(groups.singleWhere((g) => g.contains(7)), [7, 8]);
    expect(groups.singleWhere((g) => g.contains(9)), [9, 10, 11]);
  });

  test('a long paragraph cannot grow its permitted inter-line gap', () {
    final boxes = [
      for (var i = 0; i < 6; i++) Rect.fromLTWH(10, i * 12, 100, 10),
      const Rect.fromLTWH(10, 100, 100, 10),
    ];
    expect(groupHorizontalDialogueLines(boxes), [
      [0, 1, 2, 3, 4, 5],
      [6]
    ]);
  });

  test('interleaved columns stay separate and retain short final lines', () {
    expect(
        groupHorizontalDialogueLines(const [
          Rect.fromLTWH(10, 10, 100, 10),
          Rect.fromLTWH(200, 10, 100, 10),
          Rect.fromLTWH(10, 22, 100, 10),
          Rect.fromLTWH(200, 22, 100, 10),
          Rect.fromLTWH(40, 34, 30, 10),
        ]),
        [
          [0, 2, 4],
          [1, 3]
        ]);
  });

  test('same row fragments join only across a small word gap', () {
    expect(
        groupHorizontalDialogueLines(const [
          Rect.fromLTWH(10, 10, 50, 10),
          Rect.fromLTWH(65, 10, 50, 10),
          Rect.fromLTWH(200, 10, 50, 10),
        ]),
        [
          [0, 1],
          [2]
        ]);
  });

  test('empty input and invalid rectangles are preserved without merging', () {
    expect(groupHorizontalDialogueLines([]), isEmpty);
    expect(
        groupHorizontalDialogueLines(
            const [Rect.zero, Rect.fromLTWH(1, 1, 50, 10)]),
        [
          [0],
          [1]
        ]);
  });
}
