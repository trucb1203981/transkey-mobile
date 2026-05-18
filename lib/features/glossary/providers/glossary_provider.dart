import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../models/glossary_entry.dart';

const _kGlossaryKey = 'tk_glossary';
const _maxEntries = 50;

/// Discriminated error states. The provider stores the enum; the UI
/// layer maps it to a localized message via [errorMessage]. Avoids
/// hardcoding English strings inside the provider where there's no
/// BuildContext to look up the user's locale.
enum GlossaryError { syncFailed, limitReached, sourceTargetRequired }

class GlossaryState {
  const GlossaryState({
    this.entries = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.error,
  });

  final List<GlossaryEntry> entries;
  final bool isLoading;
  final bool isSyncing;
  final GlossaryError? error;

  int get count => entries.length;
  bool get isFull => entries.length >= _maxEntries;

  GlossaryState copyWith({
    List<GlossaryEntry>? entries,
    bool? isLoading,
    bool? isSyncing,
    GlossaryError? error,
    bool clearError = false,
  }) =>
      GlossaryState(
        entries: entries ?? this.entries,
        isLoading: isLoading ?? this.isLoading,
        isSyncing: isSyncing ?? this.isSyncing,
        error: clearError ? null : (error ?? this.error),
      );
}

class GlossaryNotifier extends Notifier<GlossaryState> {
  Timer? _pushDebounce;
  bool _hasInitialPulled = false;

  @override
  GlossaryState build() {
    _loadLocal();
    ref.onDispose(() => _pushDebounce?.cancel());
    return const GlossaryState();
  }

  /// Pull from server once per session when the user first opens the glossary
  /// screen. Without this, fresh installs / cleared local storage show an
  /// empty list even though the user has entries on desktop / web.
  /// Idempotent — safe to call from initState every screen visit.
  Future<void> ensureInitialPull() async {
    if (_hasInitialPulled) return;
    final auth = ref.read(authStateProvider).valueOrNull;
    // Skip when not logged in yet — pull would 401 → trigger logout.
    if (auth?.session == null) return;
    _hasInitialPulled = true;
    // Flush any pending local edits first so the server-side pull doesn't
    // trample uncommitted user changes.
    await flushPendingPush();
    await pull();
  }

  /// Coalesce rapid add/update/delete sequences into a single PUT. Users
  /// editing multiple entries shouldn't trigger N round-trips.
  void _schedulePush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 1500), push);
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kGlossaryKey);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = list
          .map((e) => GlossaryEntry.fromMap(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(entries: entries);
    } catch (e) {
      // Corrupt JSON — fall back to empty glossary. Next push() will
      // overwrite the bad blob with the in-memory state.
      debugPrint('[Glossary] _loadLocal failed (corrupt JSON?): $e');
    }
  }

  Future<void> _saveLocal(List<GlossaryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kGlossaryKey,
      jsonEncode(entries.map((e) => e.toMap()).toList()),
    );
  }

  /// Pull glossary from server (GET /glossary)
  Future<void> pull() async {
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/glossary');
      final list = response.data as List<dynamic>;
      final entries = list
          .map((e) => GlossaryEntry.fromMap(e as Map<String, dynamic>))
          .toList();

      await _saveLocal(entries);
      state = state.copyWith(entries: entries, isSyncing: false);
    } catch (e) {
      debugPrint('[Glossary] Pull failed: $e');
      state = state.copyWith(
        isSyncing: false,
        error: GlossaryError.syncFailed,
      );
    }
  }

  /// Push full glossary to server (PUT /glossary).
  ///
  /// Body shape MUST be `{ entries: [...] }` — server's `@Body()` DTO
  /// validates `Array.isArray(body.entries)` and 400s with `invalid_body`
  /// if you send the bare array. (Mobile previously sent the bare array
  /// and every save silently failed → next pull() wiped local entries
  /// because the server still had the pre-sync state.)
  Future<void> push() async {
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put(
        '/glossary',
        data: {
          'entries': state.entries.map((e) => e.toMap()).toList(),
        },
      );
      state = state.copyWith(isSyncing: false);
    } catch (e) {
      debugPrint('[Glossary] Push failed: $e');
      state = state.copyWith(
        isSyncing: false,
        error: GlossaryError.syncFailed,
      );
    }
  }

  /// Add entry locally + push to server
  Future<bool> add(GlossaryEntry entry) async {
    if (state.isFull) {
      state = state.copyWith(error: GlossaryError.limitReached);
      return false;
    }

    if (entry.source.trim().isEmpty || entry.target.trim().isEmpty) {
      state = state.copyWith(error: GlossaryError.sourceTargetRequired);
      return false;
    }

    final updated = [entry, ...state.entries];
    await _saveLocal(updated);
    state = state.copyWith(entries: updated, clearError: true);

    _schedulePush();
    return true;
  }

  /// Update entry at index locally + push
  Future<bool> update(int index, GlossaryEntry entry) async {
    if (index < 0 || index >= state.entries.length) return false;
    if (entry.source.trim().isEmpty || entry.target.trim().isEmpty) {
      state = state.copyWith(error: GlossaryError.sourceTargetRequired);
      return false;
    }

    final updated = [...state.entries];
    updated[index] = entry;
    await _saveLocal(updated);
    state = state.copyWith(entries: updated, clearError: true);

    _schedulePush();
    return true;
  }

  /// Delete entry at index locally + push
  Future<void> delete(int index) async {
    if (index < 0 || index >= state.entries.length) return;

    final updated = [...state.entries]..removeAt(index);
    await _saveLocal(updated);
    state = state.copyWith(entries: updated, clearError: true);

    _schedulePush();
  }

  /// Flush any pending debounced push immediately. Call before navigating
  /// away from the glossary screen so changes don't sit local-only.
  Future<void> flushPendingPush() async {
    if (_pushDebounce?.isActive ?? false) {
      _pushDebounce!.cancel();
      await push();
    }
  }
}

final glossaryProvider =
    NotifierProvider<GlossaryNotifier, GlossaryState>(GlossaryNotifier.new);
