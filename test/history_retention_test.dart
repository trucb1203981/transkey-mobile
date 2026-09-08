import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transkey_mobile/features/history/models/history_entry.dart';
import 'package:transkey_mobile/features/history/storage/history_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  HistoryEntry entry(String id, {bool favorite = false, bool locked = false}) =>
      HistoryEntry(
          id: id,
          sourceText: 'Source $id',
          translation: 'Result $id',
          isFavorite: favorite,
          isLocked: locked);

  test('automatic trimming retains old favorites and locked entries', () async {
    final store = HistoryStore(userId: 'retention-test');
    await store.save([
      for (var i = 0; i < 500; i++) entry('recent-$i'),
      entry('favorite', favorite: true),
      entry('locked', locked: true),
      entry('ordinary'),
    ]);
    await store.add(entry('newest'));
    final restored = await HistoryStore(userId: 'retention-test').load();
    final ids = restored.map((e) => e.id).toSet();
    expect(restored, hasLength(502));
    expect(restored.first.id, 'newest');
    expect(ids, containsAll(['favorite', 'locked']));
    expect(ids, isNot(contains('ordinary')));
    expect(ids, isNot(contains('recent-499')));
  });

  test('unfavorited old entries become eligible for automatic trimming',
      () async {
    final store = HistoryStore(userId: 'retention-test');
    await store.save([
      for (var i = 0; i < 500; i++) entry('recent-$i'),
      entry('favorite', favorite: true),
    ]);
    await store.toggleFavorite('favorite');
    expect((await store.load()).map((e) => e.id), isNot(contains('favorite')));
  });

  test('explicit delete still works for favorites and respects locks',
      () async {
    final store = HistoryStore(userId: 'retention-test');
    await store.add(entry('favorite', favorite: true));
    await store.add(entry('locked', locked: true));
    await store.delete('favorite');
    await store.delete('locked');
    expect((await store.load()).map((e) => e.id), ['locked']);
  });

  test('saved entries remain isolated by account', () async {
    await HistoryStore(userId: 'one').add(entry('favorite', favorite: true));
    expect(await HistoryStore(userId: 'two').load(), isEmpty);
  });
}
