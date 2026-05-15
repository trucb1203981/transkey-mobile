import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/dio_client.dart';
import '../models/glossary_entry.dart';

const _kGlossaryKey = 'tk_glossary';
const _maxEntries = 50;

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
  final String? error;

  int get count => entries.length;
  bool get isFull => entries.length >= _maxEntries;

  GlossaryState copyWith({
    List<GlossaryEntry>? entries,
    bool? isLoading,
    bool? isSyncing,
    String? error,
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

  @override
  GlossaryState build() {
    _loadLocal();
    ref.onDispose(() => _pushDebounce?.cancel());
    return const GlossaryState();
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
    } catch (_) {}
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
        error: 'Failed to sync glossary',
      );
    }
  }

  /// Push full glossary to server (PUT /glossary)
  Future<void> push() async {
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.put(
        '/glossary',
        data: state.entries.map((e) => e.toMap()).toList(),
      );
      state = state.copyWith(isSyncing: false);
    } catch (e) {
      debugPrint('[Glossary] Push failed: $e');
      state = state.copyWith(
        isSyncing: false,
        error: 'Failed to sync glossary',
      );
    }
  }

  /// Add entry locally + push to server
  Future<bool> add(GlossaryEntry entry) async {
    if (state.isFull) {
      state = state.copyWith(error: 'Glossary limit reached ($_maxEntries)');
      return false;
    }

    if (entry.source.trim().isEmpty || entry.target.trim().isEmpty) {
      state = state.copyWith(error: 'Source and target are required');
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
      state = state.copyWith(error: 'Source and target are required');
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
