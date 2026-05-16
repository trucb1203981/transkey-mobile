import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHistorySave = 'tk_history_save';
const _kRomanization = 'tk_romanization';
const _kReplySuggestions = 'tk_reply_suggestions';
const _kToneOverride = 'tk_tone_override';
const _kReplyToneOverride = 'tk_reply_tone_override';
const _kReplyLang = 'tk_reply_lang';
const _kAutoCloseSeconds = 'tk_auto_close_seconds';

class AppSettings {
  const AppSettings({
    this.historySave = true,
    this.romanization = false,
    this.replySuggestions = false,
    this.toneOverride = '',
    this.replyToneOverride = '',
    this.replyLang = '',
    this.autoCloseSeconds = 0,
  });

  final bool historySave;
  final bool romanization;
  final bool replySuggestions;
  final String toneOverride;
  final String replyToneOverride;
  final String replyLang;
  final int autoCloseSeconds;

  AppSettings copyWith({
    bool? historySave,
    bool? romanization,
    bool? replySuggestions,
    String? toneOverride,
    String? replyToneOverride,
    String? replyLang,
    int? autoCloseSeconds,
  }) =>
      AppSettings(
        historySave: historySave ?? this.historySave,
        romanization: romanization ?? this.romanization,
        replySuggestions: replySuggestions ?? this.replySuggestions,
        toneOverride: toneOverride ?? this.toneOverride,
        replyToneOverride: replyToneOverride ?? this.replyToneOverride,
        replyLang: replyLang ?? this.replyLang,
        autoCloseSeconds: autoCloseSeconds ?? this.autoCloseSeconds,
      );
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return _readFromPrefs();
  }

  Future<AppSettings> _readFromPrefs({bool forceReload = false}) async {
    final prefs = await SharedPreferences.getInstance();
    // shared_preferences keeps a Dart-side in-memory cache; native writes
    // (from BubbleService) won't show up until we reload. Skip for cold start
    // since the cache is already authoritative there.
    if (forceReload) await prefs.reload();
    return AppSettings(
      historySave: prefs.getBool(_kHistorySave) ?? true,
      romanization: prefs.getBool(_kRomanization) ?? false,
      replySuggestions: prefs.getBool(_kReplySuggestions) ?? false,
      toneOverride: prefs.getString(_kToneOverride) ?? '',
      replyToneOverride: prefs.getString(_kReplyToneOverride) ?? '',
      replyLang: prefs.getString(_kReplyLang) ?? '',
      autoCloseSeconds: prefs.getInt(_kAutoCloseSeconds) ?? 0,
    );
  }

  /// Re-read all settings from SharedPreferences. Use when external code
  /// (the floating bubble service on Android, or the Share Extension on iOS)
  /// may have changed values while the app was backgrounded — otherwise the
  /// in-memory state stays stale until next cold start.
  Future<void> reload() async {
    final fresh = await _readFromPrefs(forceReload: true);
    final current = state.valueOrNull;
    if (current != null &&
        current.historySave == fresh.historySave &&
        current.romanization == fresh.romanization &&
        current.replySuggestions == fresh.replySuggestions &&
        current.toneOverride == fresh.toneOverride &&
        current.replyToneOverride == fresh.replyToneOverride &&
        current.replyLang == fresh.replyLang &&
        current.autoCloseSeconds == fresh.autoCloseSeconds) {
      return;
    }
    state = AsyncData(fresh);
  }

  Future<void> setHistorySave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHistorySave, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(historySave: value));
  }

  Future<void> setRomanization(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRomanization, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(romanization: value));
  }

  Future<void> setReplySuggestions(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReplySuggestions, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(replySuggestions: value));
  }

  Future<void> setToneOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToneOverride, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(toneOverride: value));
  }

  Future<void> setReplyToneOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReplyToneOverride, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(replyToneOverride: value));
  }

  Future<void> setReplyLang(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReplyLang, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(replyLang: value));
  }

  Future<void> setAutoCloseSeconds(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAutoCloseSeconds, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(autoCloseSeconds: value));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

/// Tone options aligned with desktop + backend prompt sections.
/// See transkey-desktop/src/settings/settings.html and
/// transkey-web/api/src/translate/prompts.
const toneOptions = <(String, String)>[
  ('', 'auto'),
  ('business', 'business'),
  ('casual', 'casual'),
  ('formal', 'formal'),
  ('polite', 'polite'),
  ('technical', 'technical'),
  ('neutral', 'neutral'),
];
