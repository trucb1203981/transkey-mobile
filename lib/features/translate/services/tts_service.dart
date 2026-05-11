import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsState {
  const TtsState({
    this.isPlaying = false,
    this.currentText,
    this.rate = 1.0,
  });

  final bool isPlaying;
  final String? currentText;
  final double rate;

  TtsState copyWith({
    bool? isPlaying,
    String? currentText,
    double? rate,
    bool clearText = false,
  }) =>
      TtsState(
        isPlaying: isPlaying ?? this.isPlaying,
        currentText: clearText ? null : (currentText ?? this.currentText),
        rate: rate ?? this.rate,
      );
}

class TtsNotifier extends Notifier<TtsState> {
  late final FlutterTts _tts;

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

  @override
  TtsState build() {
    _tts = FlutterTts();

    _tts.setCompletionHandler(() {
      state = state.copyWith(isPlaying: false, clearText: true);
    });

    _tts.setPauseHandler(() {
      state = state.copyWith(isPlaying: false);
    });

    _tts.setContinueHandler(() {
      state = state.copyWith(isPlaying: true);
    });

    _tts.setErrorHandler((msg) {
      debugPrint('[TTS] Error: $msg');
      state = state.copyWith(isPlaying: false, clearText: true);
    });

    // Clean up when provider is disposed
    ref.onDispose(() {
      _tts.stop();
    });

    return const TtsState();
  }

  Future<void> speak(String text, {String lang = 'en'}) async {
    if (text.trim().isEmpty) return;

    final sameText = state.currentText == text.trim() && state.isPlaying;
    if (sameText) {
      await pause();
      return;
    }

    await _tts.stop();

    final locale = _langToLocale[lang] ?? 'en-US';
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(state.rate);

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
  }
}

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
