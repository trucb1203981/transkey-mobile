import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/latin_dialogue_reconciliation.dart';

List<DialogueRead> decode(List values) => values
    .map((v) => (
          text: v['text'] as String,
          box: Rect.fromLTWH(
              (v['box'][0] as num).toDouble(),
              (v['box'][1] as num).toDouble(),
              (v['box'][2] as num).toDouble(),
              (v['box'][3] as num).toDouble()),
          confidence: (v['confidence'] as num?)?.toDouble(),
        ))
    .toList();
void main() {
  test('physical cafe paragraph assembly', () {
    final d = jsonDecode(
        File('test/fixtures/french_cafe_reads.json').readAsStringSync());
    final result = reconcileLatinDialogue(
        decode(d['result']), decode(d['page']),
        imageSize: const Size(1030, 1600));
    expect(result.singleWhere((r) => r.text.startsWith('UN')).text,
        contains('CAFE'));
    expect(
        result.any((r) => [
              'M',
              'VOL',
              'DEL',
              'HE',
              'KE',
              'REN',
              'TA',
              'ON',
              'E',
              'T'
            ].contains(r.text)),
        isFalse);
    expect(result.singleWhere((r) => r.text.startsWith('.SURTOUT')).text,
        contains('JOUR'));
    expect(result.singleWhere((r) => r.text.contains('EST BIEN')).text,
        contains('EXACT'));
    expect(result.singleWhere((r) => r.text.contains('MON VIEUX')).text,
        isNot(endsWith('\nT')));
    expect(result.singleWhere((r) => r.text.contains('QUELQUES MINUTES')).text,
        isNot(contains('SOLUTION')));
  });

  test('original French page keeps the caption and two balloons separate', () {
    final d = jsonDecode(
        File('test/fixtures/french_original_reads.json').readAsStringSync());
    final result = reconcileLatinDialogue(
        decode(d['result']), decode(d['page']),
        imageSize: const Size(1030, 1600));
    final caption =
        result.singleWhere((r) => r.text.startsWith('SPIROU RACONTE'));
    final left = result.singleWhere((r) => r.text.startsWith('SI JOSAIS'));
    final right = result.singleWhere((r) => r.text.startsWith('HELAS.ILM'));
    expect(caption.text, isNot(contains('IMPOSSIBLE')));
    expect(left.text, isNot(contains('RACONTE')));
    expect(right.text, isNot(contains('JOSAIS')));
  });

  DialogueRead read(String text, Rect box) =>
      (text: text, box: box, confidence: null);
  const size = Size(1000, 1600);
  test('keeps short dialogue and numerical identifiers without page support',
      () {
    final input = [
      read('OUI', const Rect.fromLTWH(10, 10, 40, 20)),
      read('10', const Rect.fromLTWH(100, 10, 40, 20)),
      read('I', const Rect.fromLTWH(200, 10, 10, 20))
    ];
    expect(reconcileLatinDialogue(input, [], imageSize: size), input);
  });
  test('page evidence groups text without rewriting names or quantities', () {
    final input = [
      read('MADAME, DEUX', const Rect.fromLTWH(10, 10, 100, 20)),
      read('CAFÉS POUR MARTIN', const Rect.fromLTWH(10, 32, 160, 20))
    ];
    final result = reconcileLatinDialogue(
        input,
        [
          read('MADAME, DEUX\nCAFES POUR MARTIN',
              const Rect.fromLTWH(10, 10, 160, 42))
        ],
        imageSize: size);
    expect(result.single.text, 'MADAME, DEUX\nCAFÉS POUR MARTIN');
  });
  test('shared large box cannot join overlapping independent paragraphs', () {
    final input = [
      read('FIRST PARAGRAPH', const Rect.fromLTWH(10, 10, 100, 40)),
      read('SECOND PARAGRAPH', const Rect.fromLTWH(15, 15, 100, 40))
    ];
    final page = [
      read('FIRST PARAGRAPH\nSECOND PARAGRAPH',
          const Rect.fromLTWH(10, 10, 105, 45))
    ];
    expect(reconcileLatinDialogue(input, page, imageSize: size), input);
  });
  test('unrelated nearby text cannot join just because its box fits', () {
    final input = [
      read('BONJOUR', const Rect.fromLTWH(10, 10, 100, 20)),
      read('AU REVOIR', const Rect.fromLTWH(10, 32, 100, 20))
    ];
    final page = [
      read('DIFFERENT UTTERANCE', const Rect.fromLTWH(10, 10, 100, 42))
    ];
    expect(reconcileLatinDialogue(input, page, imageSize: size), input);
  });

  test('physical mirrored sign needs native agreement before becoming a card',
      () {
    final d = jsonDecode(
        File('test/fixtures/french_cafe_reads.json').readAsStringSync());
    final result = reconcileLatinDialogue(
        decode(d['result']), decode(d['page']),
        imageSize: const Size(1030, 1600),
        firstEngine: decode(d['mlkit']),
        secondEngine: decode(d['vision']));
    expect(result.any((r) => r.text == '-eAR'), isFalse);
    expect(result.singleWhere((r) => r.text.startsWith('UN')).text,
        contains('CAFE'));
  });
  test('uncertain short reads retain agreement, page support and numbers', () {
    const box = Rect.fromLTWH(100, 100, 60, 20);
    final oui = read('OUI', box),
        typo = read('OUL', box),
        conflict = read('MAZ', box);
    expect(
        reconcileLatinDialogue([oui], [],
            imageSize: size, firstEngine: [oui], secondEngine: [typo]),
        [oui]);
    expect(
        reconcileLatinDialogue([oui], [oui],
            imageSize: size, firstEngine: [oui], secondEngine: [conflict]),
        [oui]);
    expect(
        reconcileLatinDialogue([oui], [], imageSize: size, firstEngine: [oui]),
        [oui]);
    final number = read('10', box);
    expect(
        reconcileLatinDialogue([number], [],
            imageSize: size, firstEngine: [number], secondEngine: [conflict]),
        [number]);
  });

  test('Android fragmented glyph rows disappear and missing UN is recovered',
      () {
    final d = jsonDecode(File('test/fixtures/french_cafe_android_reads.json')
        .readAsStringSync());
    final result = reconcileLatinDialogue(
        decode(d['result']), decode(d['page']),
        imageSize: const Size(1030, 1600),
        dialogueBoxes: const [Rect.fromLTWH(329.6, 537.3, 164.8, 77.25)]);
    expect(result.where((r) => r.text.contains('SOLUTION')).length, 1);
    expect(result.any((r) => r.text == 'MAIS OUI..'), isTrue);
    expect(
        result.any((r) =>
            ['M', '|VO\nDEL\nHE', 'ON\nE E', 'RE\nTAI'].contains(r.text)),
        isFalse);
    expect(result.singleWhere((r) => r.text.contains('CAFÉ..')).text,
        startsWith('UN\n'));
    expect(result.singleWhere((r) => r.text.startsWith('..SURTOUT')).text,
        contains('NUIT'));
  });

  test('gallery recompression cannot make conflicting page noise a witness',
      () {
    final d = jsonDecode(File('test/fixtures/french_cafe_gallery_reads.json')
        .readAsStringSync());
    final result = reconcileLatinDialogue(
        decode(d['result']), decode(d['page']),
        imageSize: const Size(1030, 1600),
        firstEngine: decode(d['firstEngine']),
        secondEngine: decode(d['secondEngine']));
    expect(result.any((r) => r.text == 'MAZ'), isFalse);
    expect(result.singleWhere((r) => r.text.contains('CEST BIEN')).text,
        contains('EXACT'));
    expect(result.any((r) => r.text.contains('G2')), isFalse);
    expect(result.singleWhere((r) => r.text.startsWith('UN')).text,
        contains('CAFE'));
  });
  test(
      'trailing identifiers survive absent or contradictory independent evidence',
      () {
    final r = read('EXACT.. X1', const Rect.fromLTWH(100, 100, 150, 30));
    final page = [read('EXACT', const Rect.fromLTWH(100, 100, 90, 30))];
    expect(reconcileLatinDialogue([r], page, imageSize: size, firstEngine: [r]),
        [r]);
    expect(
        reconcileLatinDialogue([r], page,
            imageSize: size, firstEngine: [r], secondEngine: [r]),
        [r]);
  });

  test('Android keeps neighboring panels independent', () {
    final d = jsonDecode(
        File('test/fixtures/french_original_android_reads.json')
            .readAsStringSync());
    final result = reconcileLatinDialogue(
        decode(d['result']), decode(d['page']),
        imageSize: const Size(1078, 1600));
    final caption =
        result.singleWhere((r) => r.text.startsWith('PIROU RACONTE'));
    final left = result.singleWhere((r) => r.text.startsWith('S1 JOSA'));
    expect(caption.text, isNot(contains('IMPOSSIBLE')));
    expect(left.text, isNot(contains('RACONTE')));
    expect(
        result.any(
            (r) => r.text.contains('HELAS') && r.text.contains('VOUS AIDER')),
        isTrue);
  });

  test(
      'short page recovery needs a small speech shape and preserves identifiers',
      () {
    final short = read('MAIS OUI', const Rect.fromLTWH(100, 100, 100, 20));
    expect(reconcileLatinDialogue([], [short], imageSize: size), isEmpty);
    expect(
        reconcileLatinDialogue([], [short],
            imageSize: size,
            dialogueBoxes: const [Rect.fromLTWH(0, 0, 1000, 1600)]),
        isEmpty);
    final a = read('MESSAGE CODE X1', const Rect.fromLTWH(100, 100, 150, 30));
    final b = read('MESSAGE CODE X2', const Rect.fromLTWH(100, 100, 150, 30));
    expect(reconcileLatinDialogue([a, b], [a], imageSize: size), [a, b]);
  });

  test('discarded crop cannot subsequently discard the selected paragraph', () {
    final selected =
        read('LA SEULE SOLUTION', const Rect.fromLTWH(100, 100, 90, 42));
    final extra =
        read('PLA SEULE SOLUTION', const Rect.fromLTWH(95, 95, 150, 50));
    expect(
        reconcileLatinDialogue([extra, selected], [selected], imageSize: size)
            .single
            .text,
        selected.text);
  });
}
