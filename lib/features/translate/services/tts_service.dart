import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  factory TtsVoice.fromMap(Map<dynamic, dynamic> map) => TtsVoice(
        name: map['name']?.toString() ?? '',
        locale: map['locale']?.toString() ?? '',
      );

  Map<String, String> toPluginMap() => {'name': name, 'locale': locale};
}

class TtsState {
  const TtsState({
    this.isPlaying = false,
    this.currentText,
    this.rate = 0.75,
    this.voiceByLang = const {},
  });

  final bool isPlaying;
  final String? currentText;
  final double rate;
  final Map<String, String> voiceByLang;

  TtsState copyWith({
    bool? isPlaying,
    String? currentText,
    double? rate,
    Map<String, String>? voiceByLang,
    bool clearText = false,
  }) =>
      TtsState(
        isPlaying: isPlaying ?? this.isPlaying,
        currentText: clearText ? null : (currentText ?? this.currentText),
        rate: rate ?? this.rate,
        voiceByLang: voiceByLang ?? this.voiceByLang,
      );
}

class TtsNotifier extends Notifier<TtsState> {
  late final FlutterTts _tts;

  static const _kRateKey = 'tk_tts_rate';
  static const _kVoicePrefix = 'tk_tts_voice_';

  // ISO 639-1 code → BCP-47 locale used by Android TextToSpeech / iOS
  // AVSpeechSynthesizer. Falls back to the raw code (which both engines
  // accept as a 2-letter shortcut) for any language not listed here, so
  // OS-level voice resolution still works for the long tail of catalog
  // languages. Old fallback was hard-coded 'en-US' — meant Thai/Hindi/etc.
  // were read with an English voice, which sounded wrong.
  static const _langToLocale = <String, String>{
    // Tier 1 — popular, widely-installed TTS voices
    'en':  'en-US', 'vi':  'vi-VN', 'zh':  'zh-CN', 'zh-TW': 'zh-TW',
    'ja':  'ja-JP', 'ko':  'ko-KR', 'fr':  'fr-FR', 'de':  'de-DE',
    'es':  'es-ES', 'pt':  'pt-BR', 'it':  'it-IT', 'ru':  'ru-RU',
    // European
    'nl':  'nl-NL', 'pl':  'pl-PL', 'uk':  'uk-UA', 'cs':  'cs-CZ',
    'sk':  'sk-SK', 'hu':  'hu-HU', 'ro':  'ro-RO', 'el':  'el-GR',
    'sv':  'sv-SE', 'no':  'nb-NO', 'fi':  'fi-FI', 'da':  'da-DK',
    'is':  'is-IS', 'bg':  'bg-BG', 'hr':  'hr-HR', 'sr':  'sr-RS',
    'bs':  'bs-BA', 'sl':  'sl-SI', 'mk':  'mk-MK', 'sq':  'sq-AL',
    'ca':  'ca-ES', 'eu':  'eu-ES', 'gl':  'gl-ES', 'et':  'et-EE',
    'lv':  'lv-LV', 'lt':  'lt-LT', 'be':  'be-BY', 'mt':  'mt-MT',
    'ga':  'ga-IE', 'cy':  'cy-GB', 'lb':  'lb-LU', 'fy':  'fy-NL',
    // Middle East
    'ar':  'ar-SA', 'he':  'he-IL', 'fa':  'fa-IR', 'tr':  'tr-TR',
    'az':  'az-AZ', 'hy':  'hy-AM', 'ka':  'ka-GE',
    // South Asia
    'hi':  'hi-IN', 'bn':  'bn-IN', 'ur':  'ur-PK', 'pa':  'pa-IN',
    'ta':  'ta-IN', 'te':  'te-IN', 'mr':  'mr-IN', 'gu':  'gu-IN',
    'kn':  'kn-IN', 'ml':  'ml-IN', 'or':  'or-IN', 'si':  'si-LK',
    'ne':  'ne-NP',
    // Southeast Asia
    'th':  'th-TH', 'id':  'id-ID', 'ms':  'ms-MY', 'fil': 'fil-PH',
    'my':  'my-MM', 'km':  'km-KH', 'lo':  'lo-LA', 'jv':  'jv-ID',
    'su':  'su-ID',
    // Central + East Asia
    'mn':  'mn-MN', 'kk':  'kk-KZ', 'uz':  'uz-UZ', 'ky':  'ky-KG',
    // Africa
    'sw':  'sw-KE', 'am':  'am-ET', 'ha':  'ha-NG', 'yo':  'yo-NG',
    'ig':  'ig-NG', 'zu':  'zu-ZA', 'xh':  'xh-ZA', 'af':  'af-ZA',
    'so':  'so-SO', 'mg':  'mg-MG',
    // Americas + Other
    'ht':  'ht-HT', 'eo':  'eo',    'la':  'la',    'haw': 'haw-US',
    'mi':  'mi-NZ', 'sm':  'sm-WS', 'yi':  'yi',
  };

  /// Resolve a language code to a BCP-47 locale TTS engines can understand.
  /// For languages not in the explicit map, return the raw code — most TTS
  /// engines (Android + iOS) accept 2-letter ISO codes as a fallback and
  /// will try their best to find a matching voice.
  static String localeFor(String lang) => _langToLocale[lang] ?? lang;

  @override
  TtsState build() {
    _tts = FlutterTts();

    _tts.setCompletionHandler(() {
      state = state.copyWith(isPlaying: false, clearText: true);
    });
    _tts.setPauseHandler(() => state = state.copyWith(isPlaying: false));
    _tts.setContinueHandler(() => state = state.copyWith(isPlaying: true));
    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] Error: $msg');
      state = state.copyWith(isPlaying: false, clearText: true);
    });

    ref.onDispose(() {
      _tts.stop();
    });

    // Load persisted prefs without blocking build().
    Future.microtask(_loadPersistedPrefs);

    return const TtsState();
  }

  Future<void> _loadPersistedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rate = prefs.getDouble(_kRateKey) ?? 0.75;
    final keys = prefs.getKeys().where((k) => k.startsWith(_kVoicePrefix));
    final voices = <String, String>{
      for (final k in keys)
        k.substring(_kVoicePrefix.length): prefs.getString(k) ?? ''
    }..removeWhere((_, v) => v.isEmpty);
    state = state.copyWith(rate: rate, voiceByLang: voices);
  }

  Future<List<TtsVoice>> voicesFor(String lang) async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final locale = localeFor(lang).toLowerCase();
      final langCode = lang.toLowerCase();
      final voices = raw
          .whereType<Map>()
          .map(TtsVoice.fromMap)
          .where((v) {
            final l = v.locale.toLowerCase();
            return l == locale ||
                l.startsWith('$langCode-') ||
                l.startsWith('${langCode}_');
          })
          .toList();
      return voices;
    } catch (e) {
      debugPrint('[TTS] getVoices failed: $e');
      return const [];
    }
  }

  Future<void> speak(String text, {String lang = 'en', double? rate}) async {
    if (text.trim().isEmpty) return;

    // Tap-to-stop toggle: if THIS exact text is currently playing, kill
    // playback. Use stop() (not pause()) because Android's TTS engine
    // ignores pause for a current in-flight utterance — it would keep
    // talking until the sentence ended, leaving the user mashing the
    // button. stop() also drops the queued audio, so the next tap starts
    // from the beginning instead of resuming mid-word.
    final sameText = state.currentText == text.trim() && state.isPlaying;
    if (sameText) {
      await stop();
      return;
    }

    await _tts.stop();

    final locale = localeFor(lang);
    // setLanguage returns 1 on success, 0 if the OS has no voice for that
    // locale. Don't silently fall back to the OS default (often en-US) —
    // that would read e.g. Vietnamese text with an English voice. Bail out
    // instead so the caller can surface "TTS not available for this lang".
    final ok = await _tts.setLanguage(locale);
    if (ok != 1) {
      debugPrint('[TTS] setLanguage($locale) returned $ok — no voice installed');
      state = state.copyWith(isPlaying: false, clearText: true);
      return;
    }
    // Optional per-call rate override — used by travel surfaces (camera
    // "What is this?" + saved phrasebook) that want a slower pace so a
    // local listener can catch each syllable. Doesn't persist; the global
    // rate in [state.rate] is untouched.
    await _tts.setSpeechRate(rate ?? state.rate);

    final voiceName = state.voiceByLang[lang];
    if (voiceName != null && voiceName.isNotEmpty) {
      try {
        await _tts.setVoice({'name': voiceName, 'locale': locale});
      } catch (e) {
        debugPrint('[TTS] setVoice failed for $voiceName: $e');
      }
    }

    await _tts.speak(text.trim());
    state = state.copyWith(isPlaying: true, currentText: text.trim());
  }

  /// Check if the OS has a TTS voice installed for a language. Callers can
  /// use this to hide/disable the speak button for unsupported languages.
  Future<bool> isLanguageAvailable(String lang) async {
    try {
      final locale = localeFor(lang);
      final result = await _tts.isLanguageAvailable(locale);
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> pause() async {
    await _tts.pause();
    state = state.copyWith(isPlaying: false);
  }

  Future<void> stop() async {
    await _tts.stop();
    state = state.copyWith(isPlaying: false, clearText: true);
  }

  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
    state = state.copyWith(rate: rate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kRateKey, rate);
  }

  /// Re-read TTS rate from SharedPreferences. The floating bubble's settings
  /// sheet writes `tk_tts_rate` directly via native Android code — without
  /// this reload the in-app TTS would keep using the rate that was cached at
  /// cold start, ignoring any change the user made from the popup.
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final rate = prefs.getDouble(_kRateKey) ?? 0.75;
    if (rate != state.rate) {
      state = state.copyWith(rate: rate);
    }
  }

  Future<void> setVoice(String lang, String voiceName) async {
    final updated = {...state.voiceByLang, lang: voiceName};
    state = state.copyWith(voiceByLang: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kVoicePrefix$lang', voiceName);
  }
}

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
