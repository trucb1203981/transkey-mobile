import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';

const _kHistoryKeyLegacy = 'tk_history';
const _maxEntries = 500;

class HistoryStore {
  final String userId;

  HistoryStore({required this.userId});

  String get _historyKey => 'tk_history_$userId';

  // Single in-process write lock. The Bubble service + in-app translate flow
  // can both call addFromTranslate concurrently; without serialization the
  // load-modify-save cycle silently drops entries.
  static Future<void> _lock = Future.value();

  Future<T> _serialize<T>(Future<T> Function() fn) {
    final pending = _lock.then((_) => fn());
    _lock = pending
        .then<void>((_) => null)
        .catchError((_) => null);
    return pending;
  }

  Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();

    // One-time migration: if user-scoped key has no data but legacy key
    // does, copy the data over and remove the legacy key.
    if (!prefs.containsKey(_historyKey) &&
        prefs.containsKey(_kHistoryKeyLegacy)) {
      final legacy = prefs.getString(_kHistoryKeyLegacy);
      if (legacy != null) {
        await prefs.setString(_historyKey, legacy);
        await prefs.remove(_kHistoryKeyLegacy);
      }
    }

    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => HistoryEntry.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = _trimKeepLocked(entries);
    final encoded = jsonEncode(trimmed.map((e) => e.toMap()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  Future<void> add(HistoryEntry entry) => _serialize(() async {
        final entries = await load();
        entries.insert(0, entry);
        await save(entries);
      });

  Future<void> delete(String id) => _serialize(() async {
        final entries = await load();
        final idx = entries.indexWhere((e) => e.id == id);
        if (idx == -1) return;
        if (entries[idx].isLocked) return;
        entries.removeAt(idx);
        await save(entries);
      });

  Future<void> toggleFavorite(String id) => _serialize(() async {
        final entries = await load();
        final idx = entries.indexWhere((e) => e.id == id);
        if (idx == -1) return;
        entries[idx] =
            entries[idx].copyWith(isFavorite: !entries[idx].isFavorite);
        await save(entries);
      });

  Future<void> toggleLock(String id) => _serialize(() async {
        final entries = await load();
        final idx = entries.indexWhere((e) => e.id == id);
        if (idx == -1) return;
        entries[idx] =
            entries[idx].copyWith(isLocked: !entries[idx].isLocked);
        await save(entries);
      });

  Future<void> clear() => _serialize(() async {
        final entries = await load();
        final locked = entries.where((e) => e.isLocked).toList();
        await save(locked);
      });

  Future<void> clearNonFavorites() => _serialize(() async {
        final entries = await load();
        final kept =
            entries.where((e) => e.isFavorite || e.isLocked).toList();
        await save(kept);
      });

  /// Trim to _maxEntries keeping the newest, but always preserve locked
  /// entries even if they fall outside the window.
  List<HistoryEntry> _trimKeepLocked(List<HistoryEntry> entries) {
    if (entries.length <= _maxEntries) return entries;
    final head = entries.take(_maxEntries).toList();
    final headIds = head.map((e) => e.id).toSet();
    final extraLocked = entries
        .skip(_maxEntries)
        .where((e) => e.isLocked && !headIds.contains(e.id));
    return [...head, ...extraLocked];
  }
}
