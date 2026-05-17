import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/dio_client.dart';
import 'core/auth/session_store.dart';
import 'core/bubble/bubble_manager.dart';
import 'core/locale/locale_provider.dart';
import 'core/router/app_router.dart';
import 'features/history/providers/history_provider.dart';
import 'features/translate/models/translate_models.dart';
import 'shared/theme/app_theme.dart';
import 'l10n/generated/app_localizations.dart';

// Top-level channel & container so the Android side can invoke translateText
// even on a cold start, before the widget tree finishes building.
const _bubbleChannel = MethodChannel('transkey/bubble');
late final ProviderContainer _rootContainer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // dotenv.load is the only true cold-start dependency before we can build the
  // ApiClient — fire it first; the bubble auto-start and ProviderContainer
  // creation don't block the first frame.
  await dotenv.load(fileName: '.env');

  _rootContainer = ProviderContainer();
  _wireBubbleChannel();

  runApp(UncontrolledProviderScope(
    container: _rootContainer,
    child: const TransKeyApp(),
  ));

  // Fire-and-forget: don't make the first frame wait on platform channels.
  // tryAutoStart() reads SharedPreferences + invokes the Android bubble plugin.
  unawaited(_rootContainer.read(bubbleManagerProvider.notifier).tryAutoStart());
}

// ── Bubble channel: Android (BubbleService) ↔ Flutter ↔ Android (deliverResult) ──

void _wireBubbleChannel() {
  _bubbleChannel.setMethodCallHandler((call) async {
    if (call.method == 'openPermissions') {
      // BubbleService's accessibility banner tapped — surface the in-app
      // permissions walkthrough rather than dumping the user into system
      // settings cold. The setup screen shows all three statuses in one
      // place (overlay / restricted / accessibility) with one-tap grant
      // buttons per row.
      try {
        final router = _rootContainer.read(routerProvider);
        router.push('/accessibility-setup');
      } catch (e) {
        debugPrint('[bubbleChannel] openPermissions push failed: $e');
      }
      return null;
    }
    if (call.method == 'translateText') {
      final args = (call.arguments as Map?)?.cast<Object?, Object?>() ?? {};
      final text = args['text'] as String?;
      final mode = (args['mode'] as String?) ?? 'translate';
      final targetLang = (args['targetLang'] as String?) ?? 'en';
      final reqId = (args['requestId'] as num?)?.toInt() ?? -1;
      final replyToOriginal = args['replyToOriginal'] as String?;
      if (text != null && text.isNotEmpty) {
        // Run async without awaiting so the Result.success() returns immediately.
        unawaited(_translateForBubble(text, mode, targetLang, reqId, replyToOriginal: replyToOriginal));
      }
      return null;
    }
    if (call.method == 'translateBatch') {
      // Mobile "Lens" / scan-screen flow: native side hands us N OCR text
      // blocks; we batch-translate them in a single /translate-batch call
      // and return the array of translations (same order, same length).
      // Awaiting here is fine because this call replaces N parallel
      // /translate round-trips and the caller already shows a spinner.
      final args = (call.arguments as Map?)?.cast<Object?, Object?>() ?? {};
      final texts = (args['texts'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      final targetLang = (args['targetLang'] as String?) ?? 'en';
      final sourceLang = args['sourceLang'] as String?;
      if (texts.isEmpty) return <String>[];
      return await _translateBatchForLens(texts, targetLang, sourceLang);
    }
    return null;
  });
}

Future<List<String>> _translateBatchForLens(
  List<String> texts,
  String targetLang,
  String? sourceLang,
) async {
  try {
    final session = await SessionStore().load();
    if (session == null || session.accessToken.isEmpty) {
      // Logged out — return originals so the overlay still shows SOMETHING
      // rather than blowing up the native side.
      return texts;
    }
    final api = _rootContainer.read(apiClientProvider);
    final response = await api.dio.post('/translate-batch', data: {
      'texts': texts,
      'targetLang': targetLang,
      if (sourceLang != null && sourceLang.isNotEmpty && sourceLang != 'auto')
        'sourceLang': sourceLang,
      'appHint': 'lens',
    });
    final data = response.data as Map?;
    final raw = data?['translations'] as List?;
    if (raw == null) return texts;
    // Backend guarantees same-length array via parseBatchResponse fallback;
    // mirror that guarantee here in case middleware ever drops items.
    final out = <String>[];
    for (var i = 0; i < texts.length; i++) {
      final value = i < raw.length ? raw[i] : null;
      out.add(value is String && value.trim().isNotEmpty ? value : texts[i]);
    }
    return out;
  } on DioException catch (e) {
    debugPrint('[LensTranslate] Dio error: ${e.response?.statusCode} ${e.message}');
    return texts;
  } catch (e) {
    debugPrint('[LensTranslate] Error: $e');
    return texts;
  }
}

Future<void> _translateForBubble(
  String text,
  String mode,
  String targetLang,
  int requestId, {
  String? replyToOriginal,
}) async {
  try {
    final session = await SessionStore().load();
    if (session == null || session.accessToken.isEmpty) {
      await _sendResultToBubble(
          error: 'Please log in to TransKey', requestId: requestId);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    // The floating bubble's settings sheet writes directly to native
    // SharedPreferences. Without reload() the Dart-side cache returns stale
    // values, so a toggle the user just flipped in the popup would have no
    // effect on the very next bubble-triggered translation.
    await prefs.reload();
    final romanizationEnabled = prefs.getBool('tk_romanization') ?? false;
    final sourceLang = prefs.getString('tk_source_lang') ?? 'auto';
    final toneValue = prefs.getString('tk_tone_override') ?? '';
    final replyToneOverride = prefs.getString('tk_reply_tone_override') ?? '';
    final replyLang = prefs.getString('tk_reply_lang') ?? '';
    final replySuggestions = prefs.getBool('tk_reply_suggestions') ?? false;

    // Reply mode honours user's reply-specific preferences. Falls back to the
    // general translate tone/lang when the reply-specific value is empty.
    final isReply = mode == 'reply';
    final effectiveTone =
        isReply && replyToneOverride.isNotEmpty ? replyToneOverride : toneValue;
    final effectiveTargetLang =
        isReply && replyLang.isNotEmpty ? replyLang : targetLang;

    final endpoint = switch (mode) {
      'summarize' => '/summarize',
      'explain' => '/explain',
      'refine' => '/refine',
      _ => '/translate', // translate + reply
    };

    final Map<String, dynamic> body = switch (mode) {
      'refine' => {
          'text': text,
          if (toneValue.isNotEmpty) 'toneOverride': toneValue,
        },
      'reply' => {
          'text': text,
          'targetLang': effectiveTargetLang,
          'isReply': true,
          if (replyToOriginal != null) 'replyToOriginal': replyToOriginal,
          if (sourceLang != 'auto') 'sourceLang': sourceLang,
          if (romanizationEnabled) 'withRomanization': true,
          if (effectiveTone.isNotEmpty) 'toneOverride': effectiveTone,
          // Reply mode produces a single targeted reply that the user pastes
          // straight back — suggesting more replies on top would just be
          // noise (and pay for a bigger combined prompt). Suggestions live
          // on the plain translate flow only.
        },
      'translate' => {
          'text': text,
          'targetLang': effectiveTargetLang,
          if (sourceLang != 'auto') 'sourceLang': sourceLang,
          if (romanizationEnabled) 'withRomanization': true,
          if (effectiveTone.isNotEmpty) 'toneOverride': effectiveTone,
          // Match desktop: ask for quick-reply suggestions on the regular
          // translate flow too. Backend gates with `looksConversational(text)`
          // so non-conversational input still pays only the translate-only
          // prompt cost.
          if (replySuggestions) 'suggestReplies': true,
        },
      _ => {
          'text': text,
          'targetLang': effectiveTargetLang,
          if (sourceLang != 'auto') 'sourceLang': sourceLang,
          if (romanizationEnabled) 'withRomanization': true,
          if (toneValue.isNotEmpty) 'toneOverride': toneValue,
        },
    };

    final api = _rootContainer.read(apiClientProvider);
    final response = await api.dio.post(endpoint, data: body);
    final data = response.data as Map?;

    final output = (data?['translation'] ??
            data?['summary'] ??
            data?['explanation'] ??
            data?['refined'] ??
            data?['text']) as String? ??
        '';
    if (output.isEmpty) {
      await _sendResultToBubble(
          error: 'Empty response from server', requestId: requestId);
      return;
    }
    final romanization = data?['romanization'] as String?;
    final detectedLang = data?['detectedLang'] as String?;
    // Suggestions arrive as [{source, target}, ...]. Pass as two parallel
    // string arrays so the platform channel can use plain primitives — the
    // popup renders both (bilingual, like desktop) and copies the SOURCE
    // string on tap (the reply to send back to the conversation partner).
    final rawSuggestions = data?['suggestions'] as List?;
    final pairs = rawSuggestions
            ?.whereType<Map>()
            .map((s) => (
                  source: (s['source'] as String? ?? '').trim(),
                  target: (s['target'] as String? ?? '').trim(),
                ))
            .where((p) => p.source.isNotEmpty || p.target.isNotEmpty)
            .toList(growable: false) ??
        const [];
    await _sendResultToBubble(
      translation: output,
      romanization: romanization,
      detectedLang: detectedLang,
      suggestionSources: pairs.map((p) => p.source).toList(growable: false),
      suggestionTargets: pairs.map((p) => p.target).toList(growable: false),
      requestId: requestId,
    );

    // Save to history for translate/reply modes if user has historySave on
    // (default true). Mirrors the in-app flow in translate_provider.dart.
    final historySave = prefs.getBool('tk_history_save') ?? true;
    if (historySave && (mode == 'translate' || mode == 'reply')) {
      final modeEnum = mode == 'reply' ? TranslateMode.reply : TranslateMode.translate;
      unawaited(
        _rootContainer.read(historyProvider.notifier).addFromTranslate(
              sourceText: text,
              translation: output,
              sourceLang: detectedLang ?? sourceLang,
              targetLang: effectiveTargetLang,
              romanization: romanization,
              mode: modeEnum,
            ),
      );
    }
  } on DioException catch (e) {
    debugPrint('[BubbleTranslate] Dio error: ${e.response?.statusCode} ${e.message}');
    await _sendResultToBubble(
        error: _friendlyDioError(e), requestId: requestId);
  } catch (e) {
    debugPrint('[BubbleTranslate] Error: $e');
    await _sendResultToBubble(
        error: 'Translation failed', requestId: requestId);
  }
}

String _friendlyDioError(DioException e) {
  final status = e.response?.statusCode;
  final body = e.response?.data;
  final serverCode =
      body is Map ? (body['code'] ?? body['error']) as String? : null;

  return switch (status) {
    401 => 'Please log in to TransKey',
    403 when serverCode == 'feature_disabled' => 'This feature requires Pro plan',
    403 when serverCode == 'email_not_verified' => 'Please verify your email',
    413 => 'Text is too long',
    429 when serverCode == 'quota_exceeded' => 'Daily quota exceeded',
    429 => 'Too many requests — wait a moment',
    503 => 'Service under maintenance',
    _ => 'Translation failed',
  };
}

Future<void> _sendResultToBubble({
  String? translation,
  String? romanization,
  String? detectedLang,
  List<String>? suggestionSources,
  List<String>? suggestionTargets,
  String? error,
  required int requestId,
}) async {
  try {
    await _bubbleChannel.invokeMethod('deliverResult', {
      'translation': translation,
      'romanization': romanization,
      'detectedLang': detectedLang,
      'suggestionSources': suggestionSources,
      'suggestionTargets': suggestionTargets,
      'error': error,
      'requestId': requestId,
    });
  } catch (e) {
    debugPrint('[BubbleTranslate] Failed to deliver result: $e');
  }
}

// ── App widget ──

class TransKeyApp extends ConsumerWidget {
  const TransKeyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale =
        ref.watch(localeProvider).valueOrNull ?? const Locale('en');

    return MaterialApp.router(
      title: 'TransKey',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
