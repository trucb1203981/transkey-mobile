import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../translate/models/translate_models.dart';
import '../models/history_entry.dart';
import '../storage/history_store.dart';

enum HistoryFilter { all, favorites, locked }

class HistoryState {
  const HistoryState({
    this.entries = const [],
    this.filter = HistoryFilter.all,
    this.searchQuery = '',
  });

  final List<HistoryEntry> entries;
  final HistoryFilter filter;
  final String searchQuery;

  List<HistoryEntry> get filtered {
    var result = entries;

    if (filter == HistoryFilter.favorites) {
      result = result.where((e) => e.isFavorite).toList();
    } else if (filter == HistoryFilter.locked) {
      result = result.where((e) => e.isLocked).toList();
    }

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((e) =>
              e.sourceText.toLowerCase().contains(q) ||
              e.translation.toLowerCase().contains(q))
          .toList();
    }

    return result;
  }

  HistoryState copyWith({
    List<HistoryEntry>? entries,
    HistoryFilter? filter,
    String? searchQuery,
  }) =>
      HistoryState(
        entries: entries ?? this.entries,
        filter: filter ?? this.filter,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

class HistoryNotifier extends Notifier<HistoryState> {
  @override
  HistoryState build() {
    _loadFromStorage();
    return const HistoryState();
  }

  Future<void> _loadFromStorage() async {
    final store = HistoryStore();
    final entries = await store.load();
    state = state.copyWith(entries: entries);
  }

  Future<String> addFromTranslate({
    required String sourceText,
    required String translation,
    String sourceLang = '',
    String targetLang = '',
    String? romanization,
    TranslateMode mode = TranslateMode.translate,
  }) async {
    final entry = HistoryEntry(
      sourceText: sourceText,
      translation: translation,
      sourceLang: sourceLang,
      targetLang: targetLang,
      romanization: romanization,
      mode: mode,
    );

    final store = HistoryStore();
    await store.add(entry);
    state = state.copyWith(entries: [entry, ...state.entries]);
    return entry.id;
  }

  Future<void> delete(String id) async {
    final store = HistoryStore();
    await store.delete(id);
    state = state.copyWith(
      entries: state.entries.where((e) => e.id != id).toList(),
    );
  }

  Future<void> toggleFavorite(String id) async {
    final store = HistoryStore();
    await store.toggleFavorite(id);
    final entries = state.entries.map((e) {
      if (e.id == id) return e.copyWith(isFavorite: !e.isFavorite);
      return e;
    }).toList();
    state = state.copyWith(entries: entries);
  }

  Future<void> toggleLock(String id) async {
    final store = HistoryStore();
    await store.toggleLock(id);
    final entries = state.entries.map((e) {
      if (e.id == id) return e.copyWith(isLocked: !e.isLocked);
      return e;
    }).toList();
    state = state.copyWith(entries: entries);
  }

  Future<void> clearAll() async {
    final store = HistoryStore();
    await store.clear();
    state = state.copyWith(
      entries: state.entries.where((e) => e.isLocked).toList(),
    );
  }

  Future<void> clearNonFavorites() async {
    final store = HistoryStore();
    await store.clearNonFavorites();
    state = state.copyWith(
      entries: state.entries.where((e) => e.isFavorite || e.isLocked).toList(),
    );
  }

  void setFilter(HistoryFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final historyProvider =
    NotifierProvider<HistoryNotifier, HistoryState>(HistoryNotifier.new);
