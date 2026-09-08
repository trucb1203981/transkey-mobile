import 'dart:collection';

/// Bounded translation reuse for the current camera session.
///
/// Only whitespace is normalized. OCR similarity is not semantic equivalence:
/// changing one digit, a negation, or a CJK glyph can change the meaning. Keep
/// exact reuse fast without silently returning a previous image's translation.
/// Source language, target language, and scene are part of every key.
class TranslationCache {
  TranslationCache._();
  static final TranslationCache instance = TranslationCache._();

  /// LRU cap. 50 ≈ a heavy menu (40-ish dishes) plus headroom. Capping
  /// keeps memory bounded on long sessions where the user wanders
  /// between many signs / pages.
  static const int _maxEntries = 50;

  final LinkedHashMap<String, _Entry> _store = LinkedHashMap();

  /// Returns an exact cached translation in constant time, or null.
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

    return null;
  }

  /// Stores [translation] for [text] under (source, target, scene).
  /// Empty translations are ignored: caching a failed/blank server
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
    // Skip caching when the translation is identical to the source:
    // either the server detected no-op (same language) or it failed
    // and echoed input back. Either way it isn't worth a slot.
    if (translation.trim() == text.trim()) return;

    final key = _key(norm, sourceLang, targetLang, scene);
    _store.remove(key);
    _store[key] = _Entry(
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

  /// Preserve case, numbers, punctuation, signs, and every script verbatim.
  String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _Entry {
  const _Entry({required this.translation});
  final String translation;
}
