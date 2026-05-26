import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/tracking/tracking_provider.dart';

const _kHistorySave = 'tk_history_save';
const _kRomanization = 'tk_romanization';
const _kReplySuggestions = 'tk_reply_suggestions';
const _kToneOverride = 'tk_tone_override';
const _kReplyToneOverride = 'tk_reply_tone_override';
const _kReplyLang = 'tk_reply_lang';
const _kAutoCloseSeconds = 'tk_auto_close_seconds';
const _kCaptureKeepaliveSeconds = 'tk_capture_keepalive_s';
const _kBubbleIdleMinutes = 'tk_bubble_idle_minutes';

/// How long the native screen-capture grant stays alive after a scan so
/// the next scan (double-tap repeat, or another menu pick) can reuse the
/// grant without re-prompting. Native reads this same key from prefs.
/// 0 = release immediately. Max 300s (5 min) enforced both sides.
const captureKeepaliveOptions = <int>[0, 60, 180, 300];
const captureKeepaliveDefault = 180;

/// How long the bubble stays alive with no interaction before auto-stopping.
/// Native BubbleService reads `tk_bubble_idle_minutes` from SharedPrefs.
/// 0 = never auto-stop. Max 120 min.
const bubbleIdleOptions = <int>[0, 5, 10, 30, 60, 120];
const bubbleIdleDefault = 10;

class AppSettings {
  const AppSettings({
    this.historySave = true,
    this.romanization = false,
    this.replySuggestions = false,
    this.toneOverride = '',
    this.replyToneOverride = '',
    this.replyLang = '',
    this.autoCloseSeconds = 0,
    this.captureKeepaliveSeconds = captureKeepaliveDefault,
    this.bubbleIdleMinutes = bubbleIdleDefault,
  });

  final bool historySave;
  final bool romanization;
  final bool replySuggestions;
  final String toneOverride;
  final String replyToneOverride;
  final String replyLang;
  final int autoCloseSeconds;
  final int captureKeepaliveSeconds;
  final int bubbleIdleMinutes;

  AppSettings copyWith({
    bool? historySave,
    bool? romanization,
    bool? replySuggestions,
    String? toneOverride,
    String? replyToneOverride,
    String? replyLang,
    int? autoCloseSeconds,
    int? captureKeepaliveSeconds,
    int? bubbleIdleMinutes,
  }) =>
      AppSettings(
        historySave: historySave ?? this.historySave,
        romanization: romanization ?? this.romanization,
        replySuggestions: replySuggestions ?? this.replySuggestions,
        toneOverride: toneOverride ?? this.toneOverride,
        replyToneOverride: replyToneOverride ?? this.replyToneOverride,
        replyLang: replyLang ?? this.replyLang,
        autoCloseSeconds: autoCloseSeconds ?? this.autoCloseSeconds,
        captureKeepaliveSeconds:
            captureKeepaliveSeconds ?? this.captureKeepaliveSeconds,
        bubbleIdleMinutes:
            bubbleIdleMinutes ?? this.bubbleIdleMinutes,
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
      captureKeepaliveSeconds:
          prefs.getInt(_kCaptureKeepaliveSeconds) ?? captureKeepaliveDefault,
      bubbleIdleMinutes:
          prefs.getInt(_kBubbleIdleMinutes) ?? bubbleIdleDefault,
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
        current.autoCloseSeconds == fresh.autoCloseSeconds &&
        current.captureKeepaliveSeconds == fresh.captureKeepaliveSeconds &&
        current.bubbleIdleMinutes == fresh.bubbleIdleMinutes) {
      return;
    }
    state = AsyncData(fresh);
  }

  /// One-liner so every setter fires `settings_change` with the same shape.
  /// Keeps event volume bounded — only fires on a write, not on every read,
  /// and rolls all setting writes into one queryable bucket.
  void _trackChange(String key, Object value) {
    ref.read(trackingServiceProvider).event('settings_change',
        properties: {'key': key, 'value': value});
  }

  Future<void> setHistorySave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHistorySave, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(historySave: value));
    _trackChange('history_save', value);
  }

  Future<void> setRomanization(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRomanization, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(romanization: value));
    _trackChange('romanization', value);
  }

  Future<void> setReplySuggestions(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReplySuggestions, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(replySuggestions: value));
    _trackChange('reply_suggestions', value);
  }

  Future<void> setToneOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToneOverride, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(toneOverride: value));
    _trackChange('tone_override', value.isEmpty ? 'auto' : value);
  }

  Future<void> setReplyToneOverride(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReplyToneOverride, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(replyToneOverride: value));
    _trackChange('reply_tone_override', value.isEmpty ? 'auto' : value);
  }

  Future<void> setReplyLang(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReplyLang, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(replyLang: value));
    _trackChange('reply_lang', value.isEmpty ? 'auto' : value);
  }

  Future<void> setAutoCloseSeconds(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAutoCloseSeconds, value);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(autoCloseSeconds: value));
    _trackChange('auto_close_seconds', value);
  }

  Future<void> setCaptureKeepaliveSeconds(int value) async {
    final clamped = value.clamp(0, 300);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCaptureKeepaliveSeconds, clamped);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(captureKeepaliveSeconds: clamped));
    _trackChange('capture_keepalive_seconds', clamped);
  }

  Future<void> setBubbleIdleMinutes(int value) async {
    final clamped = value.clamp(0, 120);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBubbleIdleMinutes, clamped);
    final current = state.valueOrNull ?? const AppSettings();
    state = AsyncData(current.copyWith(bubbleIdleMinutes: clamped));
    _trackChange('bubble_idle_minutes', clamped);
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
