import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One cached /explain answer: the explanation body plus the source language
/// the server detected (ISO 639-1, e.g. "vi"). The detected lang lets the
/// "What is this?" sheet TTS the original phrase with a correct-pronunciation
/// voice so a traveller can speak the dish/place name aloud. Entries cached
/// before this field was added have [detectedSourceLang] == null — callers
/// must fall back gracefully (e.g. disable TTS) rather than assume.
///
/// [isStale] is set when the entry was returned via [ExplainCache.getStale]
/// AND its TTL has elapsed — the renderer should badge the result so the
/// user knows it might be outdated (currently used as an offline fallback
/// past the 7-day TTL: a traveller scans a dish on day 1, opens it on day
/// 10 with no signal — better to show day-1 data than an error).
class ExplainCacheHit {
  const ExplainCacheHit({
    required this.explanation,
    this.detectedSourceLang,
    this.isStale = false,
  });
  final String explanation;
  final String? detectedSourceLang;
  final bool isStale;
}

/// Disk-backed cache of `/explain` ("What is this?") results.
///
/// Reopening the sheet on a block the user already looked up costs zero
/// tokens — and unlike the previous in-memory map, this survives app
/// restarts (scan a menu today, reopen a dish tomorrow → still free).
///
/// - Keyed by `targetLang|scene|text` — the exact inputs sent to /explain,
///   because the answer is in the target language and framed per scene.
/// - Entries expire [_ttl] after they were stored (fixed expiry, not a
///   sliding window).
/// - Capped at [_maxEntries]; when full, the oldest entries are evicted.
/// - Persisted as a single JSON blob in SharedPreferences. Failures are
///   swallowed — the cache is an optimisation, never a correctness
///   dependency, so a corrupt/unavailable store just means a cache miss.
class ExplainCache {
  ExplainCache._();
  static final ExplainCache instance = ExplainCache._();

  static const _prefsKey = 'tk_explain_cache_v1';
  static const Duration _ttl = Duration(days: 7);
  static const int _maxEntries = 200;

  /// In-memory mirror, lazily loaded from disk on first access.
  Map<String, _ExplainEntry>? _mem;

  /// Dedupes concurrent first-loads (two sheets opening back-to-back).
  Future<void>? _loadFuture;

  String key(String text, String targetLang, String scene) =>
      '$targetLang|$scene|$text';

  /// Returns the cached hit for [cacheKey], or null on miss/expired.
  /// Note: expired entries are NOT removed here so they remain available
  /// to [getStale] as an offline fallback. They get evicted by the LRU
  /// cap during normal [put] traffic.
  Future<ExplainCacheHit?> get(String cacheKey) async {
    await _ensureLoaded();
    final entry = _mem![cacheKey];
    if (entry == null) return null;
    if (_isExpired(entry)) return null;
    return ExplainCacheHit(
      explanation: entry.explanation,
      detectedSourceLang: entry.detectedSourceLang,
    );
  }

  /// Returns the cached hit for [cacheKey] regardless of TTL, with
  /// `isStale` set when the entry has exceeded [_ttl]. Used by the
  /// /explain UI as an offline / network-error fallback so the user
  /// sees a (possibly outdated) result instead of a blank error
  /// state — critical for the traveller use case where the app
  /// might be offline for days at a time past the TTL.
  Future<ExplainCacheHit?> getStale(String cacheKey) async {
    await _ensureLoaded();
    final entry = _mem![cacheKey];
    if (entry == null) return null;
    return ExplainCacheHit(
      explanation: entry.explanation,
      detectedSourceLang: entry.detectedSourceLang,
      isStale: _isExpired(entry),
    );
  }

  /// Stores [explanation] (and the optional [detectedSourceLang] the server
  /// returned) under [cacheKey]. Empty explanations are ignored so a blank/
  /// failed response can still be retried later.
  Future<void> put(
    String cacheKey,
    String explanation, {
    String? detectedSourceLang,
  }) async {
    if (explanation.trim().isEmpty) return;
    await _ensureLoaded();
    _mem![cacheKey] = _ExplainEntry(
      explanation: explanation,
      detectedSourceLang: detectedSourceLang,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _pruneExpired();
    _enforceCap();
    await _persist();
  }

  Future<void> _ensureLoaded() {
    if (_mem != null) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final map = <String, _ExplainEntry>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          try {
            map[k] = _ExplainEntry.fromJson(v as Map<String, dynamic>);
          } catch (_) {
            // skip a malformed entry, keep the rest
          }
        });
      }
    } catch (_) {
      // corrupt or unavailable store — start empty
    }
    _mem = map;
    // Don't prune expired on load — keep them around for the offline
    // stale-fallback path. The size cap (_enforceCap on put) bounds
    // memory + disk growth regardless.
  }

  bool _isExpired(_ExplainEntry e) =>
      DateTime.now().millisecondsSinceEpoch - e.savedAt > _ttl.inMilliseconds;

  /// Drops expired entries. Returns true if anything was removed.
  bool _pruneExpired() {
    final before = _mem!.length;
    _mem!.removeWhere((_, e) => _isExpired(e));
    return _mem!.length != before;
  }

  /// Evicts oldest-by-savedAt entries until at most [_maxEntries] remain.
  void _enforceCap() {
    if (_mem!.length <= _maxEntries) return;
    final entries = _mem!.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    final removeCount = _mem!.length - _maxEntries;
    for (var i = 0; i < removeCount; i++) {
      _mem!.remove(entries[i].key);
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blob = _mem!.map((k, e) => MapEntry(k, e.toJson()));
      await prefs.setString(_prefsKey, jsonEncode(blob));
    } catch (e) {
      debugPrint('[ExplainCache] persist failed: $e');
    }
  }
}

class _ExplainEntry {
  const _ExplainEntry({
    required this.explanation,
    required this.savedAt,
    this.detectedSourceLang,
  });
  final String explanation;
  final int savedAt; // epoch millis
  /// ISO 639-1 code the server detected, or null for entries cached before
  /// this field existed (the JSON missing `s` is the backward-compat signal).
  final String? detectedSourceLang;

  Map<String, dynamic> toJson() => {
        'e': explanation,
        't': savedAt,
        if (detectedSourceLang != null) 's': detectedSourceLang,
      };

  factory _ExplainEntry.fromJson(Map<String, dynamic> j) => _ExplainEntry(
        explanation: j['e'] as String,
        savedAt: (j['t'] as num).toInt(),
        detectedSourceLang: j['s'] as String?,
      );
}
