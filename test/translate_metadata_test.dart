import 'package:flutter_test/flutter_test.dart';
import 'package:transkey_mobile/features/translate/models/translate_models.dart';

void main() {
  test('Explain legacy field reaches shared result and source history', () {
    final result = TranslateResult.fromMap({
      'explanation': 'No entry',
      'detectedSourceLang': 'ja',
    });
    expect(result.translation, 'No entry');
    expect(result.detectedLang, 'ja');
  });

  test('all text modes accept the unified language contract', () {
    for (final field in ['translation', 'summary', 'explanation', 'refined']) {
      final result = TranslateResult.fromMap({
        field: 'Test result',
        'detectedLang': 'uk',
        'detectedSourceLang': 'uk',
      });
      expect(result.translation, 'Test result');
      expect(result.detectedLang, 'uk');
    }
  });

  test('bubble and main result share alias precedence and normalization', () {
    expect(
        parseDetectedLanguage(
            {'detectedLang': ' VI ', 'detectedSourceLang': 'ja'}),
        'vi');
    expect(
        parseDetectedLanguage(
            {'detectedLang': 'auto', 'detectedSourceLang': 'mr'}),
        'mr');
    expect(
        parseDetectedLanguage({'detectedLang': '', 'detectedSourceLang': 'ur'}),
        'ur');
    expect(
        parseDetectedLanguage(
            {'detectedLang': 123, 'detectedSourceLang': 'fa'}),
        'fa');
    expect(parseDetectedLanguage({'detectedLang': 'und'}), isNull);
    expect(parseDetectedLanguage({}), isNull);
  });
}
