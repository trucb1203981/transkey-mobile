import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_speech_locales.dart';
import 'edge_speech_client.dart';
import 'edge_voices.dart';
import 'neural_speech_output.dart';
import 'speech_text.dart';
import 'speech_voice.dart';
import 'speech_diagnostics.dart';
export 'speech_voice.dart' show TtsVoice, TtsMode, TtsFailure;

class TtsState {
  const TtsState(
      {this.isPlaying = false,
      this.isLoading = false,
      this.currentText,
      this.currentLang,
      this.owner,
      this.rate = 1.0,
      this.mode = TtsMode.natural,
      this.voiceByLang = const {},
      this.error,
      this.errorSequence = 0});
  final bool isPlaying;
  final bool isLoading;
  final String? currentText;
  final String? currentLang;
  final String? owner;
  final double rate;
  final TtsMode mode;
  final Map<String, String> voiceByLang;
  final TtsFailure? error;
  final int errorSequence;
  bool get isBusy => isPlaying || isLoading;
  bool matches(String text, String lang, [String? scope]) =>
      isBusy &&
      currentText == text.trim() &&
      currentLang == normalizeSpeechLocale(lang) &&
      (scope == null || owner == scope);
  TtsState copyWith(
          {bool? isPlaying,
          bool? isLoading,
          String? currentText,
          String? currentLang,
          String? owner,
          double? rate,
          TtsMode? mode,
          Map<String, String>? voiceByLang,
          TtsFailure? error,
          int? errorSequence,
          bool clearText = false,
          bool clearError = false}) =>
      TtsState(
        isPlaying: isPlaying ?? this.isPlaying,
        isLoading: isLoading ?? this.isLoading,
        currentText: clearText ? null : currentText ?? this.currentText,
        currentLang: clearText ? null : currentLang ?? this.currentLang,
        owner: clearText ? null : owner ?? this.owner,
        rate: rate ?? this.rate,
        mode: mode ?? this.mode,
        voiceByLang: voiceByLang ?? this.voiceByLang,
        error: clearError ? null : error ?? this.error,
        errorSequence: errorSequence ?? this.errorSequence,
      );
}

final neuralSpeechOutputProvider =
    Provider<NeuralSpeechOutput>((ref) => StreamingSpeechOutput());
final edgeSpeechClientProvider =
    Provider<EdgeSpeechClient>((ref) => EdgeSpeechClient());

class TtsNotifier extends Notifier<TtsState> {
  late final FlutterTts _tts;
  late Future<void> _preferences;
  SpeechCancellation? _cancellation;
  Future<void>? _active;
  int _request = 0;
  bool _disposed = false;
  static const _rateKey = 'tk_tts_rate';
  static const _modeKey = 'tk_tts_mode';
  static const _voicePrefix = 'tk_tts_voice_';
  static const _naturalVoicePrefix = 'tk_tts_neural_voice_';
  static String localeFor(String lang) {
    final normalized = normalizeSpeechLocale(lang);
    for (final entry in deviceSpeechLocales.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    return normalized == 'nb' ? 'nb-NO' : normalized;
  }

  @override
  TtsState build() {
    _tts = FlutterTts();
    _preferences = Future.microtask(_loadPreferences);
    ref.onDispose(() {
      _disposed = true;
      _request++;
      _cancellation?.cancel();
      unawaited(_tts.stop());
    });
    return const TtsState();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    final mode = prefs.getString(_modeKey) == 'device'
        ? TtsMode.device
        : TtsMode.natural;
    final prefix = mode == TtsMode.natural ? _naturalVoicePrefix : _voicePrefix;
    final voices = <String, String>{
      for (final key in prefs.getKeys().where((key) => key.startsWith(prefix)))
        normalizeSpeechLocale(key.substring(prefix.length)):
            prefs.getString(key) ?? ''
    };
    final rate = prefs.getDouble(_rateKey) ?? 1.0;
    state = state.copyWith(
        rate: rate.isFinite ? rate.clamp(0.25, 1.75) : 1,
        mode: mode,
        voiceByLang: voices);
  }

  Future<List<TtsVoice>> voicesFor(String lang) async {
    await _preferences;
    if (state.mode == TtsMode.natural) return edgeVoicesFor(lang);
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final target = normalizeSpeechLocale(localeFor(lang));
      final base = target.split('-').first;
      return raw.whereType<Map>().map(TtsVoice.fromMap).where((voice) {
        final locale = normalizeSpeechLocale(voice.locale);
        return locale == target ||
            (!target.contains('-') && locale.startsWith('$base-'));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<TtsFailure?> speak(String text,
      {String lang = 'en', double? rate, String? owner}) async {
    if (text.trim().isEmpty) return null;
    if (state.matches(text, lang, owner)) {
      await stop();
      return null;
    }
    final id = ++_request;
    recordSpeechEvent(
        'request', {'id': id, 'lang': lang, 'mode': state.mode.name});
    final previous = _active;
    _cancellation?.cancel();
    state = state.copyWith(
        isPlaying: false,
        isLoading: true,
        currentText: text.trim(),
        currentLang: normalizeSpeechLocale(lang),
        owner: owner ?? 'app',
        clearError: true);
    await _tts.stop();
    await previous;
    await _preferences;
    if (_disposed || id != _request) return null;
    final cancellation = SpeechCancellation();
    _cancellation = cancellation;
    state = state.copyWith(
        isPlaying: false,
        isLoading: true,
        currentText: text.trim(),
        currentLang: normalizeSpeechLocale(lang),
        owner: owner ?? 'app',
        clearError: true);
    TtsFailure? failure;
    final task = _perform(text, lang, rate ?? state.rate, cancellation, id)
        .catchError((Object error, StackTrace stack) {
      recordSpeechEvent('failure', {
        'id': id,
        'type': error.runtimeType.toString(),
        'detail': error.toString().replaceAll(RegExp(r'https?://\S+'), '[url]'),
        'stack': stack.toString().split('\n').take(5).join('\n'),
      });
      if (_disposed ||
          id != _request ||
          cancellation.isCancelled ||
          error is SpeechCancelled) {
        return;
      }
      failure = error is TtsFailure ? error : TtsFailure.network;
      state = state.copyWith(
          error: failure, errorSequence: state.errorSequence + 1);
    }).whenComplete(() {
      recordSpeechEvent('finished', {
        'id': id,
        'cancelled': cancellation.isCancelled,
        'failed': failure != null,
      });
      if (!_disposed && id == _request) {
        state = state.copyWith(isPlaying: false, isLoading: false);
        _cancellation = null;
      }
    });
    _active = task;
    await task;
    if (identical(_active, task)) _active = null;
    return failure;
  }

  Future<void> _perform(String text, String lang, double rate,
      SpeechCancellation cancellation, int id) async {
    if (!rate.isFinite || rate < 0.25 || rate > 1.75) throw TtsFailure.playback;
    void started() {
      recordSpeechEvent('playing', {'id': id});
      if (!_disposed && id == _request && !cancellation.isCancelled) {
        state = state.copyWith(isPlaying: true, isLoading: false);
      }
    }

    final selected = state.voiceByLang[normalizeSpeechLocale(lang)];
    if (state.mode == TtsMode.natural) {
      final voice = resolveEdgeVoice(lang, selected);
      recordSpeechEvent('voice', {'id': id, 'name': voice.name, 'rate': rate});
      final chunks = speechChunks(cleanSpeechText(text));
      if (chunks.isEmpty) return;
      final client = ref.read(edgeSpeechClientProvider);
      Stream<List<int>> audio() async* {
        for (final chunk in chunks) {
          cancellation.check();
          yield* client.speak(chunk, voice, rate, cancellation);
        }
      }

      await ref
          .read(neuralSpeechOutputProvider)
          .play(audio(), cancellation, started);
    } else {
      if (await _tts.setLanguage(localeFor(lang)) != 1) {
        throw TtsFailure.unsupported;
      }
      cancellation.check();
      await _tts.setSpeechRate(rate * 0.5);
      cancellation.check();
      if (selected != null && selected.isNotEmpty) {
        final voices = await voicesFor(lang);
        final chosen =
            voices.where((voice) => voice.name == selected).firstOrNull;
        cancellation.check();
        if (chosen != null) await _tts.setVoice(chosen.toPluginMap());
      }
      await _tts.awaitSpeakCompletion(true);
      cancellation.check();
      final cancelled = Completer<void>();
      void stopDevice() {
        unawaited(_tts.stop());
        if (!cancelled.isCompleted) cancelled.complete();
      }

      cancellation.add(stopDevice);
      try {
        started();
        await Future.any([_tts.speak(cleanSpeechText(text)), cancelled.future])
            .timeout(const Duration(minutes: 10));
      } finally {
        cancellation.remove(stopDevice);
      }
    }
  }

  Future<bool> isLanguageAvailable(String lang) async {
    await _preferences;
    if (state.mode == TtsMode.natural) return edgeVoicesFor(lang).isNotEmpty;
    try {
      return await _tts.isLanguageAvailable(localeFor(lang)) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> pause() => stop();
  Future<void> stop({String? ownerPrefix}) async {
    if (ownerPrefix != null &&
        !(state.owner?.startsWith(ownerPrefix) ?? false)) {
      return;
    }
    _request++;
    _cancellation?.cancel();
    state = state.copyWith(
        isPlaying: false, isLoading: false, clearText: true, clearError: true);
    await _tts.stop();
    await _active;
  }

  Future<void> setRate(double rate) async {
    if (!rate.isFinite || rate < 0.25 || rate > 1.75) return;
    await _preferences;
    state = state.copyWith(rate: rate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rateKey, rate);
  }

  Future<void> setMode(TtsMode mode) async {
    await _preferences;
    await stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    await _loadPreferences();
  }

  Future<void> reload() async {
    await _preferences;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await _loadPreferences();
  }

  Future<void> setVoice(String lang, String voiceName) async {
    await _preferences;
    final key = normalizeSpeechLocale(lang);
    state = state.copyWith(voiceByLang: {...state.voiceByLang, key: voiceName});
    final prefs = await SharedPreferences.getInstance();
    final prefix =
        state.mode == TtsMode.natural ? _naturalVoicePrefix : _voicePrefix;
    await prefs.setString('$prefix$key', voiceName);
  }
}

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(TtsNotifier.new);
