import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/page_ocr_quality.dart';

void main() {
  test('automatic Latin read restores clean quantity punctuation', () {
    const broad = 'CHICKEN 「4 pcsl CHICKEN [14 pcsl CHICKEN [24 pcsl';
    const automatic = 'CHICKEN [4 pcs] CHICKEN [14 pcs] CHICKEN [24 pcs]';
    expect(shouldCheckLatinVision(broad), isTrue);
    expect(acceptsLatinVisionAlternative(broad, automatic), isTrue);
  });
  test('Latin alternative cannot change numbers or introduce another script',
      () {
    const broad = 'CHICKEN [4 pcs] CHICKEN [14 pcs] CHICKEN [24 pcs]';
    expect(acceptsLatinVisionAlternative(broad, broad.replaceFirst('14', '4')),
        isFalse);
    expect(acceptsLatinVisionAlternative(broad, '$broad お茶'), isFalse);
    expect(
        acceptsLatinVisionAlternative(
            broad, broad.replaceFirst('CHICKEN', 'СНICKEN')),
        isFalse);
    expect(acceptsLatinVisionAlternative(broad, 'CHICKEN'), isFalse);
    expect(
        acceptsLatinVisionAlternative(
            broad, broad.replaceFirst('CHICKEN', 'TURKEY')),
        isFalse);
  });
  test('Japanese and short Latin labels do not add a page read', () {
    expect(
        shouldCheckLatinVision('CHICKEN CHICKEN CHICKEN CHICKEN お茶'), isFalse);
    expect(shouldCheckLatinVision('KIDS MENU'), isFalse);
    expect(shouldCheckLatinVision(''), isFalse);
  });

  const french = 'DEMANDONS AU COMTE DE NOUS FAIRE UNE PIQURE DE X1, '
      'CE PRODUIT QUI DONNE UNE FORCE EXTRAORDINAIRE, ET NOUS IRONS AU '
      'CIRQUE REPRENDRE DE FORCE NOTRE MARSUPILAMI. HELAS NON ET A CE PROPOS.';
  test('substantial French page survives isolated CJK hallucinations', () {
    expect(prefersLatinPage(french, '$french ッイコ'), isTrue);
  });
  test('CJK page with Latin labels does not select Latin for every crop', () {
    expect(
        prefersLatinPage(
            french,
            '返事しろーっ おい 鷺沢 ここにいんだろ '
            'お子さまランチ メニュー ラーメン うどん'),
        isFalse);
  });
  test('short or empty Latin evidence cannot force a page script', () {
    expect(prefersLatinPage('KIDS MENU 590', 'お子さまランチ'), isFalse);
    expect(prefersLatinPage('', ''), isFalse);
  });
  test('bottom-right French dialogue is recovered with its native rectangle',
      () {
    final candidates = [
      (
        text: 'HELAS IL M EST IMPOSSIBLE DE VOUS AIDER',
        box: const Rect.fromLTRB(641, 840, 793, 911),
        confidence: 0.6
      ),
      (
        text: 'SI J AI BIEN COMPRIS VOUS VOULEZ PENETRER DANS CE CIRQUE',
        box: const Rect.fromLTRB(559, 1198, 836, 1270),
        confidence: 0.6
      ),
    ];
    expect(
        uncoveredParagraphs(
            existing: [const Rect.fromLTRB(640, 839, 798, 915)],
            candidates: candidates,
            imageSize: const Size(1078, 1600)),
        [1]);
  });
  test('overlapping accepted boxes cannot double-count coverage', () {
    const paragraph = (
      text: 'A complete missing paragraph',
      box: Rect.fromLTWH(100, 100, 100, 80),
      confidence: 0.7
    );
    expect(
        uncoveredParagraphs(existing: [
          const Rect.fromLTWH(100, 100, 30, 80),
          const Rect.fromLTWH(100, 100, 30, 80),
        ], candidates: [
          paragraph,
          paragraph
        ], imageSize: const Size(1000, 1500)),
        [0]);
  });
  test('a page paragraph covering two accepted crops is not added again', () {
    expect(
        uncoveredParagraphs(existing: [
          const Rect.fromLTWH(100, 100, 30, 80),
          const Rect.fromLTWH(170, 100, 30, 80),
        ], candidates: [
          (
            text: 'Two unrelated panels merged by the page recognizer',
            box: const Rect.fromLTWH(100, 100, 100, 80),
            confidence: 0.7
          ),
        ], imageSize: const Size(1000, 1500)),
        isEmpty);
  });
  test('weak reads, artwork noise, and panel-sized boxes are excluded', () {
    expect(
        uncoveredParagraphs(existing: [], candidates: [
          (
            text: 'uncertain random letters',
            box: const Rect.fromLTWH(100, 100, 100, 80),
            confidence: 0.2
          ),
          (
            text: 'ED',
            box: const Rect.fromLTWH(467, 1069, 21, 21),
            confidence: 0.8
          ),
          (
            text: 'An entire image is not one dialogue',
            box: const Rect.fromLTWH(0, 0, 1000, 1500),
            confidence: 0.8
          ),
        ], imageSize: const Size(1000, 1500)),
        isEmpty);
  });
}
