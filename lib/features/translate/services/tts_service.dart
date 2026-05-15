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
    this.rate = 1.0,
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

  static const _langToLocale = <String, String>{
    'vi': 'vi-VN',
    'en': 'en-US',
    'ja': 'ja-JP',
    'zh': 'zh-CN',
    'ko': 'ko-KR',
    'fr': 'fr-FR',
    'es': 'es-ES',
    'de': 'de-DE',
    'pt': 'pt-BR',
    'ru': 'ru-RU',
    'th': 'th-TH',
    'id': 'id-ID',
    'ms': 'ms-MY',
    'it': 'it-IT',
    'ar': 'ar-SA',
    'hi': 'hi-IN',
  };

  static String localeFor(String lang) => _langToLocale[lang] ?? 'en-US';

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
    final rate = prefs.getDouble(_kRateKey) ?? 1.0;
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

  Future<void> speak(String text, {String lang = 'en'}) async {
    if (text.trim().isEmpty) return;

    final sameText = state.currentText == text.trim() && state.isPlaying;
    if (sameText) {
      await pause();
      return;
    }

    await _tts.stop();

    final locale = localeFor(lang);
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(state.rate);

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

  Future<void> setVoice(String lang, String voiceName) async {
    final updated = {...state.voiceByLang, lang: voiceName};
    state = state.copyWith(voiceByLang: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kVoicePrefix$lang', voiceName);
  }
}

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
