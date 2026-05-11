import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';

const _kHistoryKey = 'tk_history';
const _maxEntries = 500;

class HistoryStore {
  Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryKey);
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
    final trimmed = entries.length > _maxEntries
        ? _keepLocked(entries.sublist(entries.length - _maxEntries))
        : entries;
    final encoded = jsonEncode(trimmed.map((e) => e.toMap()).toList());
    await prefs.setString(_kHistoryKey, encoded);
  }

  Future<void> add(HistoryEntry entry) async {
    final entries = await load();
    entries.insert(0, entry);
    await save(entries);
  }

  Future<void> delete(String id) async {
    final entries = await load();
    final target = entries.firstWhere(
      (e) => e.id == id,
      orElse: () => entries.first, // won't match if empty
    );
    if (target.isLocked) return;
    entries.removeWhere((e) => e.id == id);
    await save(entries);
  }

  Future<void> toggleFavorite(String id) async {
    final entries = await load();
    final idx = entries.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    entries[idx] = entries[idx].copyWith(isFavorite: !entries[idx].isFavorite);
    await save(entries);
  }

  Future<void> toggleLock(String id) async {
    final entries = await load();
    final idx = entries.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    entries[idx] = entries[idx].copyWith(isLocked: !entries[idx].isLocked);
    await save(entries);
  }

  Future<void> clear() async {
    final entries = await load();
    final locked = entries.where((e) => e.isLocked).toList();
    await save(locked);
  }

  Future<void> clearNonFavorites() async {
    final entries = await load();
    final kept = entries.where((e) => e.isFavorite || e.isLocked).toList();
    await save(kept);
  }

  /// When trimming to max size, preserve locked entries.
  List<HistoryEntry> _keepLocked(List<HistoryEntry> trimmed) {
    final removed = trimmed.where((e) => e.isLocked).toList();
    if (removed.isEmpty) return trimmed;
    // Put locked entries at the front so they survive
    return [...removed, ...trimmed.where((e) => !e.isLocked)];
  }
}
