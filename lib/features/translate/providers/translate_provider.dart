import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/api/dio_client.dart';
import '../../history/providers/history_provider.dart';
import '../../settings/providers/app_settings_provider.dart';
import '../../upgrade/providers/usage_provider.dart';
import '../models/translate_models.dart';

class TranslateState {
  const TranslateState({
    this.isLoading = false,
    this.result,
    this.error,
    this.errorCode,
    this.mode = TranslateMode.translate,
    this.sourceText = '',
    this.lastHistoryId,
  });

  final bool isLoading;
  final TranslateResult? result;
  final String? error;
  // Machine-readable companion to `error` — lets the UI dispatch a
  // specific affordance (e.g. paywall sheet on quota_exceeded) instead
  // of pattern-matching the human-facing error string.
  final ApiErrorCode? errorCode;
  final TranslateMode mode;
  final String sourceText;
  // ID of the history entry that mirrors `result`. Lets HomeScreen wire the
  // ★ button to toggleFavorite without re-deriving identity from text.
  final String? lastHistoryId;

  TranslateState copyWith({
    bool? isLoading,
    TranslateResult? result,
    String? error,
    ApiErrorCode? errorCode,
    TranslateMode? mode,
    String? sourceText,
    String? lastHistoryId,
    bool clearResult = false,
    bool clearError = false,
    bool clearHistoryId = false,
  }) =>
      TranslateState(
        isLoading: isLoading ?? this.isLoading,
        result: clearResult ? null : (result ?? this.result),
        error: clearError ? null : (error ?? this.error),
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
        mode: mode ?? this.mode,
        sourceText: sourceText ?? this.sourceText,
        lastHistoryId: clearHistoryId
            ? null
            : (lastHistoryId ?? this.lastHistoryId),
      );
}

class TranslateNotifier extends AsyncNotifier<TranslateState> {
  @override
  Future<TranslateState> build() async => const TranslateState();

  static const _maxCacheSize = 50;
  final _cache = <String, TranslateResult>{};

  // Monotonic request token: only the latest in-flight request is allowed to
  // write to state. Drop responses from earlier (now-stale) requests so a
  // fast-then-slow translate sequence can't overwrite the newer result.
  int _requestSeq = 0;

  // Cache key must include every input that changes the server response —
  // otherwise toggling tone / romanization and re-translating returns the
  // previous result. The body Map is passed in (already built per-mode) so
  // we don't have to keep this in sync with prompt-building logic.
  String _cacheKey(
    String text,
    String targetLang,
    TranslateMode mode,
    Map<String, dynamic> body,
  ) {
    final tone = body['toneOverride'] ?? '';
    final roman = body['withRomanization'] == true ? '1' : '0';
    final isReply = body['isReply'] == true ? '1' : '0';
    final suggestions = body['suggestReplies'] == true ? '1' : '0';
    final source = body['sourceLang'] ?? 'auto';
    return '$text|$source|$targetLang|${mode.value}|$tone|$roman|$isReply|$suggestions';
  }

  Future<AppSettings> _settings() async {
    return ref.read(appSettingsProvider.future);
  }

  Future<void> translate({
    required String text,
    required String targetLang,
    String? sourceLang,
    bool isReply = false,
  }) async {
    final s = await _settings();
    final src = sourceLang ?? 'auto';
    final tone = isReply
        ? (s.replyToneOverride.isNotEmpty ? s.replyToneOverride : s.toneOverride)
        : s.toneOverride;
    final effectiveTarget =
        isReply && s.replyLang.isNotEmpty ? s.replyLang : targetLang;

    await _execute(
      text: text,
      targetLang: effectiveTarget,
      sourceLang: src,
      mode: isReply ? TranslateMode.reply : TranslateMode.translate,
      body: {
        'text': text,
        'targetLang': effectiveTarget,
        if (isReply) 'isReply': true,
        if (src != 'auto') 'sourceLang': src,
        if (s.romanization) 'withRomanization': true,
        if (tone.isNotEmpty) 'toneOverride': tone,
        // Backend DTO uses `suggestReplies` (see translate-web TranslateDto);
        // any other key — `withSuggestions`, `suggestions` — is silently
        // dropped by class-validator and the user never gets quick replies.
        // Only meaningful in plain translate mode: Reply mode already
        // generates a single targeted reply, so a second "suggest more
        // replies" pass would be redundant + cost extra tokens.
        if (!isReply && s.replySuggestions) 'suggestReplies': true,
      },
    );
  }

  Future<void> summarize({
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    final s = await _settings();
    final src = sourceLang ?? 'auto';
    await _execute(
      text: text,
      targetLang: targetLang,
      sourceLang: src,
      mode: TranslateMode.summarize,
      body: {
        'text': text,
        'targetLang': targetLang,
        if (src != 'auto') 'sourceLang': src,
        if (s.romanization) 'withRomanization': true,
        if (s.toneOverride.isNotEmpty) 'toneOverride': s.toneOverride,
      },
      endpoint: '/summarize',
    );
  }

  Future<void> explain({
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    final s = await _settings();
    final src = sourceLang ?? 'auto';
    await _execute(
      text: text,
      targetLang: targetLang,
      sourceLang: src,
      mode: TranslateMode.explain,
      body: {
        'text': text,
        'targetLang': targetLang,
        if (src != 'auto') 'sourceLang': src,
        if (s.romanization) 'withRomanization': true,
      },
      endpoint: '/explain',
    );
  }

  Future<void> refine({required String text}) async {
    final s = await _settings();
    await _execute(
      text: text,
      targetLang: '',
      mode: TranslateMode.refine,
      body: {
        'text': text,
        if (s.toneOverride.isNotEmpty) 'toneOverride': s.toneOverride,
      },
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

    final reqId = ++_requestSeq;
    final currentState = state.valueOrNull ?? const TranslateState();
    state = AsyncData(currentState.copyWith(
      isLoading: true,
      clearError: true,
      mode: mode,
      sourceText: trimmed,
      clearHistoryId: true,
    ));

    // Check cache — still save to history so duplicate translations don't
    // silently disappear from the list.
    final key = _cacheKey(trimmed, targetLang, mode, body);
    if (_cache.containsKey(key)) {
      if (reqId != _requestSeq) return;
      final cached = _cache[key]!;
      // Guard history write with stale check too — otherwise rapid
      // translate-clear-translate sequences create phantom history entries
      // for results the user never actually saw.
      final historyId = reqId == _requestSeq
          ? await _maybeSaveHistory(
              trimmed: trimmed,
              result: cached,
              sourceLang: sourceLang,
              targetLang: targetLang,
              mode: mode,
            )
          : null;
      if (reqId != _requestSeq) return;
      state = AsyncData((state.valueOrNull ?? currentState).copyWith(
        isLoading: false,
        result: cached,
        mode: mode,
        sourceText: trimmed,
        lastHistoryId: historyId,
      ));
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post(endpoint, data: body);
      if (reqId != _requestSeq) return;
      final result = TranslateResult.fromMap(
        response.data as Map<String, dynamic>,
      );

      // Update cache
      _cache[key] = result;
      if (_cache.length > _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }

      // Re-check before crossing another await — translate-then-clear
      // shouldn't leave a history entry behind.
      if (reqId != _requestSeq) return;
      final historyId = await _maybeSaveHistory(
        trimmed: trimmed,
        result: result,
        sourceLang: sourceLang,
        targetLang: targetLang,
        mode: mode,
      );
      if (reqId != _requestSeq) return;

      state = AsyncData((state.valueOrNull ?? currentState).copyWith(
        isLoading: false,
        result: result,
        mode: mode,
        sourceText: trimmed,
        lastHistoryId: historyId,
      ));

      // Refresh usage in the background so the quota bar reflects the
      // request that just consumed quota.
      unawaited(ref.read(usageProvider.notifier).refresh());
    } catch (e) {
      if (reqId != _requestSeq) return;
      String message;
      ApiErrorCode? code;
      // Dio errors aren't auto-converted to ApiException by the
      // interceptor stack — do it inline so quota_exceeded / 429 / etc.
      // carry the right error code into TranslateState (the paywall
      // listener pattern-matches on errorCode == quotaExceeded).
      if (e is DioException) {
        final api = ApiException.fromDio(e);
        message = api.message;
        code = api.code;
      } else if (e is ApiException) {
        message = e.message;
        code = e.code;
      } else {
        debugPrint('[Translate] Error: $e');
        message = 'Something went wrong';
      }
      state = AsyncData((state.valueOrNull ?? currentState).copyWith(
        isLoading: false,
        error: message,
        errorCode: code,
        mode: mode,
        sourceText: trimmed,
      ));
    }
  }

  Future<String?> _maybeSaveHistory({
    required String trimmed,
    required TranslateResult result,
    required String sourceLang,
    required String targetLang,
    required TranslateMode mode,
  }) async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (!(settings?.historySave ?? true)) return null;
    return ref.read(historyProvider.notifier).addFromTranslate(
          sourceText: trimmed,
          translation: result.translation,
          sourceLang: sourceLang,
          targetLang: targetLang,
          romanization: result.romanization,
          mode: mode,
        );
  }

  void clearResult() {
    // Bump the request token so any in-flight response is ignored on arrival.
    _requestSeq++;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      clearResult: true,
      clearError: true,
      clearHistoryId: true,
      isLoading: false,
    ));
  }

  /// Drop the latest error (string + code) but keep the existing
  /// result and history intact. Used after the paywall sheet handles
  /// a 429 — we don't want the red error bar lingering after the user
  /// successfully watched an ad or dismissed.
  void clearError() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearError: true));
  }

  void setMode(TranslateMode mode) {
    _requestSeq++;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      mode: mode,
      clearResult: true,
      clearError: true,
      clearHistoryId: true,
      isLoading: false,
    ));
  }
}

final translateProvider =
    AsyncNotifierProvider<TranslateNotifier, TranslateState>(
  TranslateNotifier.new,
);
