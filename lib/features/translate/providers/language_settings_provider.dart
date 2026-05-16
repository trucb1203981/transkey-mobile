import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSourceLangKey = 'tk_source_lang';
const _kTargetLangKey = 'tk_target_lang';
const _kRecentTargetsKey = 'tk_recent_target_langs';
const _kDefaultSourceLang = 'auto';
const _kDefaultTargetLang = 'en';
const _kRecentTargetsMax = 4;

/// Returns the most recently chosen target languages, newest first. Used by
/// the language picker to surface frequent choices above the full list.
Future<List<String>> loadRecentTargetLangs() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_kRecentTargetsKey) ?? const [];
}

Future<void> _pushRecentTarget(String code) async {
  if (code.isEmpty || code == 'auto') return;
  final prefs = await SharedPreferences.getInstance();
  final list = (prefs.getStringList(_kRecentTargetsKey) ?? const <String>[]).toList()
    ..remove(code)
    ..insert(0, code);
  if (list.length > _kRecentTargetsMax) list.length = _kRecentTargetsMax;
  await prefs.setStringList(_kRecentTargetsKey, list);
}

class LanguageSettings {
  const LanguageSettings({required this.sourceLang, required this.targetLang});

  final String sourceLang;
  final String targetLang;

  LanguageSettings copyWith({String? sourceLang, String? targetLang}) =>
      LanguageSettings(
        sourceLang: sourceLang ?? this.sourceLang,
        targetLang: targetLang ?? this.targetLang,
      );
}

class LanguageSettingsNotifier extends AsyncNotifier<LanguageSettings> {
  @override
  Future<LanguageSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return LanguageSettings(
      sourceLang: prefs.getString(_kSourceLangKey) ?? _kDefaultSourceLang,
      targetLang: prefs.getString(_kTargetLangKey) ?? _kDefaultTargetLang,
    );
  }

  Future<void> setSourceLang(String code) async {
    final current = state.valueOrNull;
    if (current == null || current.sourceLang == code) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSourceLangKey, code);
    state = AsyncData(current.copyWith(sourceLang: code));
  }

  Future<void> setTargetLang(String code) async {
    final current = state.valueOrNull;
    if (current == null || current.targetLang == code) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTargetLangKey, code);
    await _pushRecentTarget(code);
    state = AsyncData(current.copyWith(targetLang: code));
  }

  Future<void> swap() async {
    final current = state.valueOrNull;
    if (current == null || current.sourceLang == _kDefaultSourceLang) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSourceLangKey, current.targetLang);
    await prefs.setString(_kTargetLangKey, current.sourceLang);
    // The old source becomes the new target — record it so the picker's
    // "Recent" section reflects every way the user reaches a target lang.
    await _pushRecentTarget(current.sourceLang);
    state = AsyncData(LanguageSettings(
      sourceLang: current.targetLang,
      targetLang: current.sourceLang,
    ));
  }

  /// Re-reads from SharedPreferences. Use when external code (native bubble
  /// service) may have changed the values — e.g. when the app resumes from
  /// background after the user changed languages in the floating popup.
  /// Calls prefs.reload() to invalidate the shared_preferences Dart-side
  /// cache so native writes become visible.
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final source = prefs.getString(_kSourceLangKey) ?? _kDefaultSourceLang;
    final target = prefs.getString(_kTargetLangKey) ?? _kDefaultTargetLang;
    final current = state.valueOrNull;
    if (current != null &&
        current.sourceLang == source &&
        current.targetLang == target) {
      return;
    }
    state = AsyncData(LanguageSettings(sourceLang: source, targetLang: target));
  }
}

final languageSettingsProvider =
    AsyncNotifierProvider<LanguageSettingsNotifier, LanguageSettings>(
  LanguageSettingsNotifier.new,
);
