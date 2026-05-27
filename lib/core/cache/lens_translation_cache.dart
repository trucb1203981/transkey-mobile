import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Tier-2 persistent cache for Lens translations.
///
/// The Lens flow already has a tier-1 in-memory LRU `_lensTransCache` in
/// `main.dart` that survives the Flutter engine's lifetime. This tier-2
/// store survives APP RESTARTS — so a manga reader who scans the same
/// recurring phrases ("やめろ!", "助けて!", character names, etc.) across
/// sessions skips the LLM round-trip entirely on the second day.
///
/// Storage shape (one row per cache entry):
/// ```
/// hash         TEXT PRIMARY KEY    -- SHA1(source||target||sourceLang)
/// source_text  TEXT NOT NULL       -- for debugging / re-derivation
/// target_lang  TEXT NOT NULL
/// source_lang  TEXT                -- nullable for 'auto'
/// translation  TEXT NOT NULL
/// created_at   INTEGER NOT NULL    -- epoch ms
/// last_used_at INTEGER NOT NULL    -- epoch ms (LRU)
/// ```
///
/// Eviction policy:
///   - TTL 30 days on `created_at` (older entries cleaned on `pruneIfNeeded`)
///   - LRU cap 10,000 entries (oldest `last_used_at` evicted)
///
/// Open-then-cache: the [Database] handle is opened lazily on first call
/// and reused. All writes are fire-and-forget so the hot translate path
/// never awaits disk I/O.
class LensTranslationCache {
  LensTranslationCache._();
  static final LensTranslationCache instance = LensTranslationCache._();

  static const _kFileName = 'lens_cache.db';
  static const _kTable = 'translations';
  static const _kMaxEntries = 10000;
  static const _kTtl = Duration(days: 30);
  // Run the LRU + TTL prune once per app session, not on every put — the
  // expensive query is the COUNT(*) which is sub-ms anyway but no need.
  bool _prunedThisSession = false;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final pending = _opening;
    if (pending != null) return pending;

    final future = () async {
      try {
        final dir = await getApplicationSupportDirectory();
        // Avoid pulling in the package:path dependency for one join — both
        // platforms (iOS app sandbox, Android internal storage) use forward
        // slashes in the app's own filesystem.
        final path = '${dir.path}/$_kFileName';
        final db = await openDatabase(
          path,
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE $_kTable (
                hash         TEXT PRIMARY KEY,
                source_text  TEXT NOT NULL,
                target_lang  TEXT NOT NULL,
                source_lang  TEXT,
                translation  TEXT NOT NULL,
                created_at   INTEGER NOT NULL,
                last_used_at INTEGER NOT NULL
              )
            ''');
            await db.execute(
              'CREATE INDEX idx_last_used ON $_kTable(last_used_at)',
            );
          },
        );
        _db = db;
        return db;
      } finally {
        _opening = null;
      }
    }();
    _opening = future;
    return future;
  }

  /// Pre-warm the DB connection at app start so the first Lens scan doesn't
  /// pay the open cost. Fire-and-forget — caller doesn't await.
  void warmUp() {
    unawaited(
      _open().catchError((e, _) {
        if (kDebugMode) debugPrint('[LensCache] warmUp failed: $e');
        return Future<Database>.error(e);
      }),
    );
  }

  static String _hash(String? sourceLang, String targetLang, String text) {
    final src = (sourceLang == null || sourceLang.isEmpty) ? 'auto' : sourceLang;
    return sha1.convert(utf8.encode('$src|$targetLang|$text')).toString();
  }

  /// Batch lookup. Returns a map from source text → cached translation for
  /// every HIT. Misses are simply absent from the map.
  ///
  /// Bumps `last_used_at` on hits (in a single UPDATE) so LRU stays accurate.
  Future<Map<String, String>> getBatch(
    List<String> texts,
    String targetLang,
    String? sourceLang,
  ) async {
    if (texts.isEmpty) return const {};
    final Database db;
    try {
      db = await _open();
    } catch (_) {
      return const {}; // DB open failed — cache disabled this session
    }
    // Build hash→sourceText map so we can decode results back.
    final hashes = <String, String>{}; // hash → source text
    for (final t in texts) {
      hashes[_hash(sourceLang, targetLang, t)] = t;
    }
    if (hashes.isEmpty) return const {};
    final placeholders = List.filled(hashes.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT hash, translation FROM $_kTable WHERE hash IN ($placeholders)',
      hashes.keys.toList(growable: false),
    );
    if (rows.isEmpty) return const {};
    final result = <String, String>{};
    final hitHashes = <String>[];
    for (final r in rows) {
      final h = r['hash'] as String;
      final src = hashes[h];
      if (src == null) continue;
      result[src] = r['translation'] as String;
      hitHashes.add(h);
    }
    if (hitHashes.isNotEmpty) {
      // LRU touch — fire-and-forget so the hot read path returns immediately.
      final now = DateTime.now().millisecondsSinceEpoch;
      final ph = List.filled(hitHashes.length, '?').join(',');
      unawaited(
        db.rawUpdate(
          'UPDATE $_kTable SET last_used_at = ? WHERE hash IN ($ph)',
          [now, ...hitHashes],
        ).catchError((_) => 0),
      );
    }
    return result;
  }

  /// Batch upsert. Fire-and-forget — the caller (Lens translate path)
  /// must not wait for disk to flush. Skips entries where translation ==
  /// source (those aren't real translations).
  void putBatch(
    Map<String, String> entries,
    String targetLang,
    String? sourceLang,
  ) {
    if (entries.isEmpty) return;
    unawaited(_putBatchInternal(entries, targetLang, sourceLang));
  }

  Future<void> _putBatchInternal(
    Map<String, String> entries,
    String targetLang,
    String? sourceLang,
  ) async {
    final Database db;
    try {
      db = await _open();
    } catch (_) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final e in entries.entries) {
      final src = e.key;
      final translation = e.value;
      if (translation.trim().isEmpty || translation.trim() == src.trim()) {
        continue; // not a real translation, don't cache
      }
      batch.insert(
        _kTable,
        {
          'hash': _hash(sourceLang, targetLang, src),
          'source_text': src,
          'target_lang': targetLang,
          'source_lang': sourceLang ?? 'auto',
          'translation': translation,
          'created_at': now,
          'last_used_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    try {
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) debugPrint('[LensCache] putBatch failed: $e');
      return;
    }
    // First put after open → run the once-per-session prune.
    if (!_prunedThisSession) {
      _prunedThisSession = true;
      unawaited(_pruneIfNeeded(db));
    }
  }

  /// Drop entries older than [_kTtl], then enforce the [_kMaxEntries] cap
  /// via LRU on `last_used_at`. Both pieces are best-effort; failure here
  /// doesn't affect read/write correctness, just lets the table grow a bit.
  Future<void> _pruneIfNeeded(Database db) async {
    try {
      final cutoff = DateTime.now().subtract(_kTtl).millisecondsSinceEpoch;
      final ttlDeleted = await db.rawDelete(
        'DELETE FROM $_kTable WHERE created_at < ?',
        [cutoff],
      );
      final countRow = await db
          .rawQuery('SELECT COUNT(*) AS n FROM $_kTable');
      final count = (countRow.first['n'] as int?) ?? 0;
      var lruDeleted = 0;
      if (count > _kMaxEntries) {
        final excess = count - _kMaxEntries;
        lruDeleted = await db.rawDelete(
          'DELETE FROM $_kTable WHERE hash IN ('
          'SELECT hash FROM $_kTable ORDER BY last_used_at ASC LIMIT ?'
          ')',
          [excess],
        );
      }
      if (kDebugMode && (ttlDeleted > 0 || lruDeleted > 0)) {
        debugPrint('[LensCache] prune: ttl=$ttlDeleted lru=$lruDeleted '
            'remaining=${count - lruDeleted}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LensCache] prune failed: $e');
    }
  }

  /// Snapshot for diagnostics. Cheap — single COUNT(*) query.
  Future<({int count, int sizeBytes})> stats() async {
    try {
      final db = await _open();
      final row = await db.rawQuery('SELECT COUNT(*) AS n FROM $_kTable');
      final count = (row.first['n'] as int?) ?? 0;
      // Approximate size: SQLite page count × page size.
      final pages = await db.rawQuery('PRAGMA page_count');
      final pageSize = await db.rawQuery('PRAGMA page_size');
      final p = (pages.first.values.first as int?) ?? 0;
      final ps = (pageSize.first.values.first as int?) ?? 4096;
      return (count: count, sizeBytes: p * ps);
    } catch (_) {
      return (count: 0, sizeBytes: 0);
    }
  }

  /// Drop everything (used by the "clear cache" Settings action, if exposed).
  Future<void> clear() async {
    try {
      final db = await _open();
      await db.delete(_kTable);
    } catch (e) {
      if (kDebugMode) debugPrint('[LensCache] clear failed: $e');
    }
  }
}
