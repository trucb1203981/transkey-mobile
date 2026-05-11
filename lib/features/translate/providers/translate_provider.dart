import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/api/dio_client.dart';
import '../../history/providers/history_provider.dart';
import '../models/translate_models.dart';

class TranslateState {
  const TranslateState({
    this.isLoading = false,
    this.result,
    this.error,
    this.mode = TranslateMode.translate,
    this.sourceText = '',
  });

  final bool isLoading;
  final TranslateResult? result;
  final String? error;
  final TranslateMode mode;
  final String sourceText;

  TranslateState copyWith({
    bool? isLoading,
    TranslateResult? result,
    String? error,
    TranslateMode? mode,
    String? sourceText,
    bool clearResult = false,
    bool clearError = false,
  }) =>
      TranslateState(
        isLoading: isLoading ?? this.isLoading,
        result: clearResult ? null : (result ?? this.result),
        error: clearError ? null : (error ?? this.error),
        mode: mode ?? this.mode,
        sourceText: sourceText ?? this.sourceText,
      );
}

class TranslateNotifier extends AsyncNotifier<TranslateState> {
  @override
  Future<TranslateState> build() async => const TranslateState();

  static const _maxCacheSize = 50;
  final _cache = <String, TranslateResult>{};

  String _cacheKey(String text, String targetLang, TranslateMode mode) =>
      '$text|$targetLang|${mode.value}';

  Future<void> translate({
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    await _execute(
      text: text,
      targetLang: targetLang,
      sourceLang: sourceLang ?? 'auto',
      mode: TranslateMode.translate,
      body: {
        'text': text,
        'targetLang': targetLang,
        if (sourceLang != null && sourceLang != 'auto')
          'sourceLang': sourceLang,
      },
    );
  }

  Future<void> summarize({
    required String text,
    required String targetLang,
  }) async {
    await _execute(
      text: text,
      targetLang: targetLang,
      mode: TranslateMode.summarize,
      body: {'text': text, 'targetLang': targetLang},
      endpoint: '/summarize',
    );
  }

  Future<void> explain({
    required String text,
    required String targetLang,
  }) async {
    await _execute(
      text: text,
      targetLang: targetLang,
      mode: TranslateMode.explain,
      body: {'text': text, 'targetLang': targetLang},
      endpoint: '/explain',
    );
  }

  Future<void> refine({required String text}) async {
    await _execute(
      text: text,
      targetLang: '',
      mode: TranslateMode.refine,
      body: {'text': text},
      endpoint: '/refine',
    );
  }

  Future<void> _execute({
    required String text,
    required String targetLang,
    required TranslateMode mode,
    required Map<String, dynamic> body,
    String sourceLang = '',
    String endpoint = '/translate',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final currentState = state.valueOrNull ?? const TranslateState();
    state = AsyncData(currentState.copyWith(
      isLoading: true,
      clearError: true,
      mode: mode,
      sourceText: trimmed,
    ));

    // Check cache
    final key = _cacheKey(trimmed, targetLang, mode);
    if (_cache.containsKey(key)) {
      state = AsyncData(currentState.copyWith(
        result: _cache[key],
        mode: mode,
        sourceText: trimmed,
      ));
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post(endpoint, data: body);
      final result = TranslateResult.fromMap(
        response.data as Map<String, dynamic>,
      );

      // Update cache
      _cache[key] = result;
      if (_cache.length > _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }

      state = AsyncData((state.valueOrNull ?? currentState).copyWith(
        isLoading: false,
        result: result,
        mode: mode,
        sourceText: trimmed,
      ));

      // Auto-save to history
      ref.read(historyProvider.notifier).addFromTranslate(
            sourceText: trimmed,
            translation: result.translation,
            sourceLang: sourceLang,
            targetLang: targetLang,
            romanization: result.romanization,
            mode: mode,
          );
    } catch (e) {
      String message;
      if (e is ApiException) {
        message = e.message;
      } else {
        debugPrint('[Translate] Error: $e');
        message = 'Something went wrong';
      }
      state = AsyncData((state.valueOrNull ?? currentState).copyWith(
        isLoading: false,
        error: message,
        mode: mode,
        sourceText: trimmed,
      ));
    }
  }

  void clearResult() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      clearResult: true,
      clearError: true,
    ));
  }

  void setMode(TranslateMode mode) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      mode: mode,
      clearResult: true,
      clearError: true,
    ));
  }
}

final translateProvider =
    AsyncNotifierProvider<TranslateNotifier, TranslateState>(
  TranslateNotifier.new,
);
