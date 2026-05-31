import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/tracking/tracking_provider.dart';
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
  String? _userId;

  @override
  HistoryState build() {
    // Watch auth state so provider auto-rebuilds on login/logout.
    final authState = ref.watch(authStateProvider).valueOrNull;
    _userId = authState?.session?.userId;
    if (_userId != null) {
      _loadFromStorage();
    }
    return const HistoryState();
  }

  HistoryStore _store() => HistoryStore(userId: _userId!);

  Future<void> _loadFromStorage() async {
    final store = _store();
    final loaded = await store.load();
    // Merge instead of replace: during the cold-start window between build()
    // (state = empty) and this load completing, the bubble service can call
    // addFromTranslate and prepend a new entry into state. A naive replace
    // would trample that entry in the UI (the file still has it, but the
    // user wouldn't see it until next launch). Dedupe by id, keep prepended
    // in-memory entries at the front.
    final loadedIds = loaded.map((e) => e.id).toSet();
    final unmerged = state.entries.where((e) => !loadedIds.contains(e.id));
    state = state.copyWith(entries: [...unmerged, ...loaded]);
  }

  Future<String> addFromTranslate({
    required String sourceText,
    required String translation,
    String sourceLang = '',
    String targetLang = '',
    String? romanization,
    TranslateMode mode = TranslateMode.translate,
  }) async {
    if (_userId == null) return '';
    final entry = HistoryEntry(
      sourceText: sourceText,
      translation: translation,
      sourceLang: sourceLang,
      targetLang: targetLang,
      romanization: romanization,
      mode: mode,
    );

    final store = _store();
    await store.add(entry);
    state = state.copyWith(entries: [entry, ...state.entries]);
    return entry.id;
  }

  Future<void> delete(String id) async {
    if (_userId == null) return;
    final store = _store();
    await store.delete(id);
    state = state.copyWith(
      entries: state.entries.where((e) => e.id != id).toList(),
    );
    ref.read(trackingServiceProvider).event('history_delete');
  }

  Future<void> toggleFavorite(String id) async {
    if (_userId == null) return;
    final store = _store();
    await store.toggleFavorite(id);
    final entries = state.entries.map((e) {
      if (e.id == id) return e.copyWith(isFavorite: !e.isFavorite);
      return e;
    }).toList();
    state = state.copyWith(entries: entries);
  }

  Future<void> toggleLock(String id) async {
    if (_userId == null) return;
    final store = _store();
    await store.toggleLock(id);
    final entries = state.entries.map((e) {
      if (e.id == id) return e.copyWith(isLocked: !e.isLocked);
      return e;
    }).toList();
    state = state.copyWith(entries: entries);
  }

  Future<void> clearAll() async {
    if (_userId == null) return;
    final store = _store();
    await store.clear();
    state = state.copyWith(
      entries: state.entries.where((e) => e.isLocked).toList(),
    );
    ref.read(trackingServiceProvider).event('history_clear',
        properties: {'mode': 'all'});
  }

  Future<void> clearNonFavorites() async {
    if (_userId == null) return;
    final store = _store();
    await store.clearNonFavorites();
    state = state.copyWith(
      entries: state.entries.where((e) => e.isFavorite || e.isLocked).toList(),
    );
    ref.read(trackingServiceProvider).event('history_clear',
        properties: {'mode': 'non_favorites'});
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
