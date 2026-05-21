import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../models/phrasebook_entry.dart';

/// AsyncNotifier owning the user's saved-dish list. Loads from
/// `GET /phrasebook` on first read; subsequent mutations (save / edit
/// note / delete) optimistically update local state then call the API.
///
/// Optimistic updates are safe here because the server endpoints don't
/// reject any well-formed request — failure modes are network errors
/// (which we surface as snackbar + revert) or 401 (refresh token path
/// in the dio interceptor handles re-auth, then the original request
/// retries).
class PhrasebookNotifier extends AsyncNotifier<List<PhrasebookEntry>> {
  @override
  Future<List<PhrasebookEntry>> build() async {
    return _load();
  }

  Future<List<PhrasebookEntry>> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/phrasebook');
      final data = response.data as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>?) ?? const [];
      return items
          .map((e) => PhrasebookEntry.fromMap(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[PhrasebookEntryes] load failed: $e');
      return const [];
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  /// Save a recovered dish. Returns the persisted entry (with server-
  /// assigned id) so callers can chain UI feedback off it (e.g. "Saved!"
  /// snackbar + navigate to the saved list).
  Future<PhrasebookEntry?> save({
    required String recognizedText,
    required String explanation,
    required String targetLang,
    String? originalText,
    String? sourceLang,
    String scene = 'menu',
    String? category,
    String? note,
  }) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/phrasebook', data: {
        'recognizedText': recognizedText,
        if (originalText != null) 'originalText': originalText,
        'explanation': explanation,
        'scene': scene,
        'targetLang': targetLang,
        if (sourceLang != null) 'sourceLang': sourceLang,
        if (category != null) 'category': category,
        if (note != null) 'note': note,
      });
      final dish = PhrasebookEntry.fromMap(response.data as Map<String, dynamic>);

      // Re-load instead of in-place insert: server may have dedupe-
      // updated an existing row in which case "add to top of list" is
      // wrong (the existing row's createdAt is older than what we'd
      // think). Cheap GET buys us a correct ordering.
      await refresh();
      ref.read(trackingServiceProvider).event('phrasebook_save', properties: {
        'category':    category ?? 'other',
        'scene':       scene,
        'source_lang': sourceLang,
        'has_note':    note != null && note.isNotEmpty,
      });
      return dish;
    } catch (error) {
      debugPrint('[PhrasebookEntryes] save failed: $error');
      ref.read(trackingServiceProvider).event('error_shown', properties: {
        'kind':   'phrasebook_save_failed',
        'source': 'phrasebook',
      });
      return null;
    }
  }

  Future<bool> updateNote(int id, String? note) async {
    final previous = state.valueOrNull;
    if (previous == null) return false;
    // Optimistic UI: update locally first.
    state = AsyncData([
      for (final dish in previous) dish.id == id ? dish.copyWith(note: note) : dish,
    ]);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.patch('/phrasebook/$id', data: {'note': note ?? ''});
      ref.read(trackingServiceProvider).event('phrasebook_edit_note',
          properties: {
            'has_note': note != null && note.isNotEmpty,
            'length':   note?.length ?? 0,
          });
      return true;
    } catch (error) {
      debugPrint('[PhrasebookEntryes] updateNote failed: $error');
      // Revert on failure so the UI doesn't lie about persistence.
      state = AsyncData(previous);
      return false;
    }
  }

  /// Re-categorise an entry. Optimistic — moves the entry into the new
  /// bucket locally first, then PATCHes the server. Reverts on failure so
  /// the filter chips don't show stale state.
  Future<bool> updateCategory(int id, String category) async {
    final previous = state.valueOrNull;
    if (previous == null) return false;
    state = AsyncData([
      for (final dish in previous)
        dish.id == id ? dish.copyWith(category: category) : dish,
    ]);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.patch('/phrasebook/$id', data: {'category': category});
      ref.read(trackingServiceProvider).event('phrasebook_change_category',
          properties: {'to': category});
      return true;
    } catch (error) {
      debugPrint('[Phrasebook] updateCategory failed: $error');
      state = AsyncData(previous);
      return false;
    }
  }

  Future<bool> delete(int id) async {
    final previous = state.valueOrNull;
    if (previous == null) return false;
    state = AsyncData(previous.where((d) => d.id != id).toList(growable: false));
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/phrasebook/$id');
      ref.read(trackingServiceProvider).event('phrasebook_delete');
      return true;
    } catch (error) {
      debugPrint('[PhrasebookEntryes] delete failed: $error');
      state = AsyncData(previous);
      return false;
    }
  }
}

final phrasebookProvider =
    AsyncNotifierProvider<PhrasebookNotifier, List<PhrasebookEntry>>(
  PhrasebookNotifier.new,
);
