import 'dart:collection';
import 'dart:math' as math;

/// In-memory LRU cache for /translate-batch results, scoped to the
/// current camera session. Cleared when the camera screen disposes so
/// the cache cannot leak across feature uses or grow unbounded.
///
/// The point: when the user retakes with the camera essentially steady
/// (same menu, same sign, same document page), OCR usually returns the
/// exact same text — and even when it doesn't (auto-focus jitter,
/// lighting flicker, a single misread character) the previous capture's
/// translation is still correct. Reusing it skips the /translate-batch
/// round-trip entirely.
///
/// Two-tier lookup:
///   1. **Exact** on normalized text. Handles the steady-camera case
///      that drives ~all real-world hits.
///   2. **Fuzzy** via Levenshtein-based similarity ≥ [_fuzzyThreshold].
///      "85% match" in the colloquial sense — `1 − editDistance/maxLen`.
///      Length-prefilter skips entries whose length is too far off so
///      we don't pay O(n·m) against obviously-different strings.
///
/// Cache key includes (sourceLang, targetLang, scene): when any of
/// those change, lookups naturally miss — the cached translation is
/// only valid under the same routing/prompt assumptions the server
/// used to produce it.
class TranslationCache {
  TranslationCache._();
  static final TranslationCache instance = TranslationCache._();

  /// LRU cap. 50 ≈ a heavy menu (40-ish dishes) plus headroom. Capping
  /// keeps memory bounded on long sessions where the user wanders
  /// between many signs / pages.
  static const int _maxEntries = 50;

  /// Character-level similarity threshold. Matches the user's "85%
  /// match" framing — i.e. `1 − editDistance(a, b) / max(|a|, |b|) ≥
  /// 0.85`. Above this we trust the cached translation; below, we
  /// hit the API.
  static const double _fuzzyThreshold = 0.85;

  /// Texts below this length skip fuzzy matching. A 3-char OCR result
  /// flipping one char drags similarity to 0.66 — using the threshold
  /// there would either accept noise or reject everything. Exact
  /// match still works for short strings.
  static const int _minFuzzyChars = 6;

  /// Hard cap on Levenshtein input size. Pathological captures (entire
  /// document of dense text) shouldn't make the cache lookup itself
  /// slow. Beyond this, we exact-match only.
  static const int _maxLevenshteinChars = 400;

  final LinkedHashMap<String, _Entry> _store = LinkedHashMap();

  /// Returns a cached translation for [text] under (source, target,
  /// scene), or null on miss. Exact-match hits are O(1); fuzzy
  /// matching is length-prefiltered before paying for Levenshtein.
  String? lookup({
    required String text,
    required String sourceLang,
    required String targetLang,
    required String scene,
  }) {
    final norm = _normalize(text);
    if (norm.isEmpty) return null;

    final exactKey = _key(norm, sourceLang, targetLang, scene);
    final exact = _store[exactKey];
    if (exact != null) {
      // Re-insert to mark as most-recent for LRU eviction.
      _store.remove(exactKey);
      _store[exactKey] = exact;
      return exact.translation;
    }

    if (norm.length < _minFuzzyChars || norm.length > _maxLevenshteinChars) {
      return null;
    }

    _Entry? bestEntry;
    String? bestKey;
    double bestScore = 0;
    for (final entry in _store.entries) {
      final value = entry.value;
      if (value.sourceLang != sourceLang ||
          value.targetLang != targetLang ||
          value.scene != scene) {
        continue;
      }
      final cached = value.normalized;
      if (cached.length > _maxLevenshteinChars) continue;

      // Length pre-filter: similarity ≤ 1 − |Δlen| / maxLen. If even
      // the best-case (no substitutions, only insertions) can't reach
      // [_fuzzyThreshold], skip the O(n·m) Levenshtein call entirely.
      final shorter = math.min(norm.length, cached.length);
      final longer = math.max(norm.length, cached.length);
      final maxPossible = shorter / longer;
      if (maxPossible < _fuzzyThreshold) continue;

      final dist = _levenshtein(norm, cached);
      final score = 1 - dist / longer;
      if (score >= _fuzzyThreshold && score > bestScore) {
        bestScore = score;
        bestEntry = value;
        bestKey = entry.key;
      }
    }
    if (bestEntry != null && bestKey != null) {
      // Touch the fuzzy hit so it stays warm.
      _store.remove(bestKey);
      _store[bestKey] = bestEntry;
      return bestEntry.translation;
    }
    return null;
  }

  /// Stores [translation] for [text] under (source, target, scene).
  /// Empty translations are ignored — caching a failed/blank server
  /// response would pin the user to a bad result for the rest of the
  /// session.
  void store({
    required String text,
    required String sourceLang,
    required String targetLang,
    required String scene,
    required String translation,
  }) {
    if (translation.trim().isEmpty) return;
    final norm = _normalize(text);
    if (norm.isEmpty) return;
    // Skip caching when the translation is identical to the source —
    // either the server detected no-op (same language) or it failed
    // and echoed input back. Either way it isn't worth a slot.
    if (translation.trim() == text.trim()) return;

    final key = _key(norm, sourceLang, targetLang, scene);
    _store.remove(key);
    _store[key] = _Entry(
      sourceLang: sourceLang,
      targetLang: targetLang,
      scene: scene,
      normalized: norm,
      translation: translation,
    );
    if (_store.length > _maxEntries) {
      _store.remove(_store.keys.first);
    }
  }

  /// Drop every entry. Called from the camera screen's dispose() so
  /// scope stays per-session and the cache cannot influence later
  /// camera opens with different conditions (e.g. user switched
  /// scene/tone/prompts between sessions, server-side prompt updated
  /// after an app launch).
  void clear() => _store.clear();

  String _key(String norm, String src, String tgt, String scene) =>
      '$src|$tgt|$scene|$norm';

  /// Lowercase, drop punctuation/symbols (OCR-noisy — commas read as
  /// dots, quotes vary by font), collapse whitespace. CJK / Thai /
  /// Arabic etc. are preserved verbatim: those scripts ARE the signal.
  String _normalize(String text) {
    final lower = text.toLowerCase();
    final stripped =
        lower.replaceAll(RegExp(r'[\p{P}\p{S}]+', unicode: true), ' ');
    return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Two-row Levenshtein. O(n·m) time, O(min(n,m)) space — the
  /// space win lets us run fuzzy comparisons on long blocks without
  /// allocating a full DP matrix per lookup. Returns edit distance
  /// between [a] and [b].
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    // Keep the inner loop short — ensures the rolling row tracks the
    // smaller of the two strings.
    if (a.length > b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }
    final n = a.length;
    final m = b.length;
    final prev = List<int>.generate(n + 1, (i) => i);
    final curr = List<int>.filled(n + 1, 0);
    for (var j = 1; j <= m; j++) {
      curr[0] = j;
      final bj = b.codeUnitAt(j - 1);
      for (var i = 1; i <= n; i++) {
        final cost = a.codeUnitAt(i - 1) == bj ? 0 : 1;
        final del = prev[i] + 1;
        final ins = curr[i - 1] + 1;
        final sub = prev[i - 1] + cost;
        var best = del < ins ? del : ins;
        if (sub < best) best = sub;
        curr[i] = best;
      }
      for (var i = 0; i <= n; i++) {
        prev[i] = curr[i];
      }
    }
    return prev[n];
  }
}

class _Entry {
  _Entry({
    required this.sourceLang,
    required this.targetLang,
    required this.scene,
    required this.normalized,
    required this.translation,
  });
  final String sourceLang;
  final String targetLang;
  final String scene;
  final String normalized;
  final String translation;
}
