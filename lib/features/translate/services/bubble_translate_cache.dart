import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent, bounded exact-match cache for the text translate/refine/reply
/// path shared by the floating bubble AND the TransKey keyboard
/// (`_translateForBubble`). Distinct from the camera's in-memory
/// [TranslationCache] (that one is OCR/scene-scoped and cleared per session).
///
/// Why: re-translating the exact same message (same text + langs + mode + tone
/// + flags) should be instant and FREE - return the stored result instead of
/// paying for another LLM round-trip. Backed by one JSON blob in
/// SharedPreferences; Dart's Map preserves insertion order, giving cheap LRU
/// (re-insert on hit, drop the oldest keys past the cap).
class BubbleTranslateCache {
  static const _prefsKey = 'tk_bubble_translate_cache_v1';
  static const _maxEntries = 300;

  /// Composite key from the normalized request. Text goes last so the
  /// fixed-arity prefix can't be confused with text containing the separator.
  static String keyFor({
    required String text,
    required String mode,
    required String targetLang,
    required String sourceLang,
    required String tone,
    required bool romanization,
    required bool suggestReplies,
    String? replyToOriginal,
  }) {
    final r = romanization ? '1' : '0';
    final s = suggestReplies ? '1' : '0';
    final reply = replyToOriginal ?? '';
    return '$mode$targetLang$sourceLang$tone$r$s'
        '$reply${text.trim()}';
  }

  Future<Map<String, dynamic>?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final hit = map[key];
      return hit is Map<String, dynamic> ? hit : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String key, Map<String, dynamic> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        try {
          map = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          map = {};
        }
      }
      // Re-insert at the end → most-recently-used.
      map.remove(key);
      map[key] = value;
      // Evict the oldest entries (front of insertion order) past the cap.
      if (map.length > _maxEntries) {
        final keys = map.keys.toList();
        final overflow = map.length - _maxEntries;
        for (var i = 0; i < overflow; i++) {
          map.remove(keys[i]);
        }
      }
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {
      // Best-effort: a cache write failure must never break translation.
    }
  }
}
