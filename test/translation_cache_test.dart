import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/services/translation_cache.dart';

void main() {
  final cache = TranslationCache.instance;
  void store(String text, {String translation = 'Translated result'}) {
    cache.store(
        text: text,
        sourceLang: 'auto',
        targetLang: 'vi',
        scene: 'menu',
        translation: translation);
  }

  String? lookup(String text,
          {String source = 'auto',
          String target = 'vi',
          String scene = 'menu'}) =>
      cache.lookup(
          text: text, sourceLang: source, targetLang: target, scene: scene);

  setUp(cache.clear);
  tearDown(cache.clear);

  test('reuses exact text with OCR whitespace differences', () {
    store('Grilled chicken\nwith rice');
    expect(lookup('  Grilled chicken   with rice  '), 'Translated result');
  });

  for (final pair in <(String, String)>[
    ('Price 100 dollars', 'Price 900 dollars'),
    ('Contains peanuts', 'Contains no peanuts'),
    ('This dish contains peanuts', 'This dish contains peaches'),
    ('これは安全です', 'これは危険です'),
    ('Dose: 1.5 mg', 'Dose: 1,5 mg'),
    ('Temperature +10 C', 'Temperature -10 C'),
    ('Total 50 dollars?', 'Total 50 dollars!'),
    ('Total: \$50', 'Total: €50'),
    ('May', 'may'),
  ]) {
    test('does not reuse changed content: ${pair.$2}', () {
      store(pair.$1);
      expect(lookup(pair.$2), isNull);
    });
  }

  test('language and scene changes never share cached translations', () {
    store('Grilled chicken');
    expect(lookup('Grilled chicken', source: 'en'), isNull);
    expect(lookup('Grilled chicken', target: 'ja'), isNull);
    expect(lookup('Grilled chicken', scene: 'document'), isNull);
  });

  test('empty and echoed responses cannot pin a bad result', () {
    store('Some text', translation: ' ');
    expect(lookup('Some text'), isNull);
    store('Some text', translation: 'Some text');
    expect(lookup('Some text'), isNull);
  });

  test('LRU stays bounded and a hit keeps an entry alive', () {
    for (var i = 0; i < 50; i++) {
      store('Dish $i');
    }
    expect(lookup('Dish 0'), isNotNull);
    store('Dish 50');
    expect(lookup('Dish 1'), isNull);
    expect(lookup('Dish 0'), isNotNull);
    expect(lookup('Dish 50'), isNotNull);
  });
}
