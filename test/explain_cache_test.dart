import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transkey_mobile/features/translate/services/explain_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ExplainCache: TTL, hit/miss, empty-skip, persistence, detectedSourceLang', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fresh = now - const Duration(days: 1).inMilliseconds; // within 7d
    final stale = now - const Duration(days: 8).inMilliseconds; // > 7d → expired
    // Mix of new-shape (with `s`) and legacy-shape (without `s`) entries.
    final blob = jsonEncode({
      'en|menu|Pho bo': {'e': 'Beef noodle soup', 't': fresh, 's': 'vi'},
      'en|menu|Old dish': {'e': 'stale answer', 't': stale, 's': 'vi'},
      'en|menu|Legacy item': {'e': 'No detected lang', 't': fresh}, // pre-v2 entry
    });
    SharedPreferences.setMockInitialValues({'tk_explain_cache_v1': blob});

    final c = ExplainCache.instance;

    // fresh entry with detected lang → hit
    final hit = await c.get('en|menu|Pho bo');
    expect(hit?.explanation, 'Beef noodle soup');
    expect(hit?.detectedSourceLang, 'vi');

    // legacy entry → hit, detectedSourceLang is null (backward compat)
    final legacy = await c.get('en|menu|Legacy item');
    expect(legacy?.explanation, 'No detected lang');
    expect(legacy?.detectedSourceLang, isNull);

    // stale entry → expired → miss
    expect(await c.get('en|menu|Old dish'), isNull);
    // never-seen key → miss
    expect(await c.get('en|menu|Unknown'), isNull);

    // key() shape
    expect(c.key('Bun bo', 'en', 'menu'), 'en|menu|Bun bo');

    // put + get round-trip carries detectedSourceLang
    final k = c.key('Bun bo', 'en', 'menu');
    await c.put(k, 'Spicy beef noodle soup', detectedSourceLang: 'vi');
    final round = await c.get(k);
    expect(round?.explanation, 'Spicy beef noodle soup');
    expect(round?.detectedSourceLang, 'vi');

    // put without detectedSourceLang stays null on read
    await c.put('en|menu|NoLang', 'Some answer');
    expect((await c.get('en|menu|NoLang'))?.detectedSourceLang, isNull);

    // empty / whitespace answers are not cached
    await c.put('en|menu|Empty', '   ', detectedSourceLang: 'vi');
    expect(await c.get('en|menu|Empty'), isNull);

    // disk reflects: expired pruned, new entry persisted, `s` field stored
    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('tk_explain_cache_v1')!) as Map<String, dynamic>;
    expect(stored.containsKey('en|menu|Old dish'), isFalse, reason: 'expired pruned');
    expect(stored.containsKey('en|menu|Bun bo'), isTrue, reason: 'put persisted');
    expect(stored.containsKey('en|menu|Pho bo'), isTrue, reason: 'fresh kept');
    expect((stored['en|menu|Bun bo'] as Map)['s'], 'vi', reason: 'detected lang persisted');
    expect((stored['en|menu|NoLang'] as Map).containsKey('s'), isFalse,
        reason: 'absent detected lang not written');
  });
}
