import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/core/camera/ocr_quantity_repair.dart';

void main() {
  test('physical iOS corner-bracket reads agree without changing digits', () {
    expect(
        agreedQuantityRepair('唐揚げ14個］', ['唐揚げ「4個］'], ['唐揚げ「4個］']), '唐揚げ「4個］');
  });

  test('repair requires two pixel reads agreeing on the bracketed quantity',
      () {
    expect(
        agreedQuantityRepair('唐揚(14個]', ['唐揚げ［4個］'], ['唐揚げ[4個]']), '唐揚げ［4個］');
    expect(agreedQuantityRepair('唐揚げ14個］', ['唐揚げ［4個］'], ['唐揚げ14個］']), isNull);
  });

  test('a true fourteen is never rewritten by a text-only rule', () {
    expect(needsQuantityRepair('唐揚げ［14個］'), isFalse);
    expect(agreedQuantityRepair('唐揚げ14個］', ['唐揚げ［14個］'], ['唐揚げ［14個］']),
        '唐揚げ［14個］');
    expect(agreedQuantityRepair('唐揚げ［14個］', ['唐揚げ［4個］'], ['唐揚げ［4個］']), isNull);
  });

  test('disagreement, empty output, and neighboring lines retain original', () {
    const original = '唐揚げ14個］';
    for (final other in [
      <String>[],
      [''],
      ['唐揚げ［5個］'],
      ['唐揚げ［4個］', '580円']
    ]) {
      expect(agreedQuantityRepair(original, ['唐揚げ［4個］'], other), isNull);
    }
  });

  test('different dish or unit cannot replace the original label', () {
    for (final other in ['唐場げ［4個］', '焼き鳥［4個］', '唐揚げ［4本］']) {
      expect(agreedQuantityRepair('唐揚げ14個］', [other], [other]), isNull);
    }
  });

  test('whole-menu numbers, prices and already balanced labels are excluded',
      () {
    for (final text in [
      '580円',
      '唐揚げ14個］580円',
      '［唐揚げ2個］',
      '唐揚げ［4個］',
      'ラーメン',
      'CHICKEN [14 pcs]',
      '14個'
    ]) {
      expect(needsQuantityRepair(text), isFalse, reason: text);
    }
  });

  test('full-width digits and mixed bracket families are recognized', () {
    expect(needsQuantityRepair('唐揚げ（１４個］'), isTrue);
    expect(
        agreedQuantityRepair('唐揚げ（１４個］', ['唐揚げ［４個］'], ['唐揚げ[4個]']), '唐揚げ［４個］');
  });

  test('Latin quantity labels use the same agreement guard', () {
    expect(
        agreedQuantityRepair(
            'CHICKEN 14 pcs]', ['CHICKEN [4 pcs]'], ['CHICKEN [4 pcs]']),
        'CHICKEN [4 pcs]');
  });

  test('candidate work is capped and crops stay inside the upright image', () {
    final plans = quantityRepairRegions(
        List.generate(10,
            (i) => (text: '唐揚げ14個］', box: Rect.fromLTWH(0, i * 30, 120, 20))),
        const Size(1000, 1000));
    expect(plans, hasLength(4));
    expect(plans.expand((p) => p.views), hasLength(8));
    for (final view in plans.expand((p) => p.views)) {
      expect(view.left, greaterThanOrEqualTo(0));
      expect(view.top, greaterThanOrEqualTo(0));
      expect(view.right, lessThanOrEqualTo(1000));
      expect(view.bottom, lessThanOrEqualTo(1000));
      expect(view.isEmpty, isFalse);
    }
  });

  test('invalid, vertical and large regions do not trigger extra reads', () {
    final plans = quantityRepairRegions([
      (text: '唐揚げ14個］', box: Rect.zero),
      (text: '唐揚げ14個］', box: const Rect.fromLTWH(0, 0, 10, 30)),
      (text: '唐揚げ14個］', box: const Rect.fromLTWH(0, 0, 200, 80)),
      (text: '唐揚げ14個］', box: const Rect.fromLTWH(1100, 0, 100, 20)),
    ], const Size(1000, 1000));
    expect(plans, isEmpty);
  });
}
