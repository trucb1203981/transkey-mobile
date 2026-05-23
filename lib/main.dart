import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/dio_client.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/session_store.dart';
import 'core/bubble/bubble_manager.dart';
import 'core/locale/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/tracking/crash_reporter.dart';
import 'core/tracking/tracking_provider.dart';
import 'features/translate/providers/features_provider.dart';
import 'features/history/providers/history_provider.dart';
import 'features/translate/providers/language_settings_provider.dart';
import 'features/translate/models/translate_models.dart';
import 'shared/theme/app_theme.dart';
import 'l10n/generated/app_localizations.dart';

// Top-level channel & container so the Android side can invoke translateText
// even on a cold start, before the widget tree finishes building.
const _bubbleChannel = MethodChannel('transkey/bubble');
late final ProviderContainer _rootContainer;

/// App-level ScaffoldMessenger. Without an explicit key, MaterialApp's default
/// messenger is per-Scaffold and snackbars shown right after a route pop can
/// land on a disposing Scaffold's messenger — the snackbar mounts but its
/// auto-dismiss timer never starts (status callback doesn't fire). Routing
/// every snackbar through this key uses the SAME messenger across all routes,
/// so the lifecycle is consistent regardless of which screen called.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  // Wrap the entire boot in a zone so async errors that escape the widget
  // tree (unawaited futures, plugin handlers) still reach the crash reporter
  // instead of dying silently in release.
  runZonedGuarded<void>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // dotenv.load is the only true cold-start dependency before we can build the
      // ApiClient — fire it first; the bubble auto-start and ProviderContainer
      // creation don't block the first frame.
      await dotenv.load(fileName: '.env');

      _rootContainer = ProviderContainer();
      _wireBubbleChannel();

      // Tracking bootstrap (session id, platform/device, first app_open) +
      // crash reporter. Crash hooks MUST install before runApp so errors
      // during the first frame are captured. Init is fire-and-forget
      // network-wise: events queue until the API is reachable.
      final tracking = await bootstrapTracking(_rootContainer);
      CrashReporter(tracking).install();
      // Tag every subsequent event with the logged-in user's id + plan, so
      // funnels can split by plan ("conversion to pro by trial cohort") and
      // crashes link to a user when one logged in. Fires immediately with
      // the persisted session, and again on every login / logout / plan
      // change without each call site having to remember.
      _rootContainer.listen<AsyncValue<AuthState>>(
        authStateProvider,
        (previous, next) {
          final session = next.valueOrNull?.session;
          tracking.setUserId(session?.userId);
          tracking.setUserPlan(session?.plan);
          // Plan-upgrade detector: free → pro/trial fires
          // `upgrade_purchase_success`. The actual purchase happens on
          // LemonSqueezy + a webhook; the mobile observes the upgraded plan
          // when /auth/me refreshes. This is the most reliable conversion
          // signal we can get from the client.
          final previousPlan = previous?.valueOrNull?.session?.plan;
          final nextPlan = session?.plan;
          if (previousPlan != null &&
              nextPlan != null &&
              previousPlan != nextPlan &&
              previousPlan == 'free' &&
              (nextPlan == 'pro' || nextPlan == 'trial' || nextPlan == 'mobile')) {
            tracking.event('upgrade_purchase_success', properties: {
              'from_plan': previousPlan,
              'to_plan':   nextPlan,
            });
          }
          // Any auth-state change can shift which features are allowed:
          //   - login: free → newly-known plan
          //   - logout: plan → freeDefaults
          //   - /auth/me refresh after webhook: plan changed
          // Refresh featuresProvider so the UI gates re-evaluate. Cheap —
          // single /features call gated by JWT.
          if (previousPlan != nextPlan) {
            unawaited(_rootContainer.read(featuresProvider.notifier).refresh());
          }
        },
        fireImmediately: true,
      );

      // Initialise the AdMob SDK as early as possible so by the time a free
      // user exhausts their daily quota and the paywall offers "Watch ad",
      // a rewarded video has already been preloaded. MobileAds.initialize()
      // is idempotent and fast (~50 ms) once the platform side bootstraps.
      // Fire-and-forget; pre-loading the actual ad happens lazily inside
      // the paywall flow so the first frame doesn't wait on a network ad
      // fetch.
      unawaited(MobileAds.instance.initialize());

      runApp(UncontrolledProviderScope(
        container: _rootContainer,
        child: const TransKeyApp(),
      ));

      // Fire-and-forget: don't make the first frame wait on platform channels.
      // tryAutoStart() reads SharedPreferences + invokes the Android bubble plugin.
      unawaited(_rootContainer.read(bubbleManagerProvider.notifier).tryAutoStart());
    },
    (error, stack) {
      // Last-resort sink for anything the FlutterError / PlatformDispatcher
      // hooks miss. Container may not be ready if dotenv crashed pre-bootstrap;
      // guard the lookup so the crash path itself can't throw.
      try {
        _rootContainer.read(trackingServiceProvider).crash(
              name:    error.runtimeType.toString(),
              message: error.toString(),
              stack:   stack.toString(),
              fatal:   true,
              properties: {'source': 'zone_guard_main'},
            );
      } catch (_) {/* nothing else we can do */}
    },
  );
}

// ── Bubble channel: Android (BubbleService) ↔ Flutter ↔ Android (deliverResult) ──

void _wireBubbleChannel() {
  _bubbleChannel.setMethodCallHandler((call) async {
    if (call.method == 'langChanged') {
      // Native bubble service just wrote a new source / target / reply
      // language to SharedPreferences. Reload the Dart-side cache so the
      // home tab's language bar reflects the change WITHOUT requiring a
      // background+resume cycle — otherwise the user picks a lang in the
      // bubble, opens the app, and sees the OLD value until they swipe
      // away and back.
      try {
        await _rootContainer
            .read(languageSettingsProvider.notifier)
            .reload();
      } catch (e) {
        debugPrint('[bubbleChannel] langChanged reload failed: $e');
      }
      return null;
    }
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
    if (call.method == 'openCamera') {
      try {
        _rootContainer.read(trackingServiceProvider).event(
              'bubble_open_camera',
            );
        final router = _rootContainer.read(routerProvider);
        router.push('/camera');
      } catch (error) {
        debugPrint('[bubbleChannel] openCamera push failed: $error');
      }
      return null;
    }
    // NOTE: legacy `showCameraUpsell` handler was removed — the Camera
    // bubble path now routes through `showFeatureUpsell("Camera")` like
    // every other gated feature, keeping a single navigation flow.
    if (call.method == 'showFeatureUpsell') {
      // Generic upsell entry point — bubble passes the human-readable
      // feature name (e.g. "Lens", "Summarize") for tracking. Route to
      // the full /upgrade SCREEN (not a sheet) so the user lands on a
      // dedicated upgrade page with full plan comparison; a sheet over
      // whatever screen was last visible (often Settings) reads as
      // "the bubble dropped me on Settings — bug?" rather than a clear
      // upgrade prompt.
      try {
        final args = call.arguments as Map?;
        final featureName = (args?['featureName'] as String?) ?? 'Feature';
        _rootContainer.read(trackingServiceProvider).event(
              'bubble_feature_upsell',
              properties: {'feature': featureName},
            );
        final router = _rootContainer.read(routerProvider);
        router.push('/upgrade');
      } catch (error) {
        debugPrint('[bubbleChannel] showFeatureUpsell failed: $error');
      }
      return null;
    }
    if (call.method == 'openExplain') {
      // Bubble Lens overlay long-press hands us the source-language text of
      // the tapped region. Route to a thin /explain screen that opens the
      // "What is this?" sheet over a blank scaffold and pops itself when
      // the sheet closes — same UX as tapping a live OCR block on camera.
      try {
        final args = (call.arguments as Map?)?.cast<Object?, Object?>() ?? {};
        final text = (args['text'] as String?)?.trim();
        if (text == null || text.isEmpty) return null;
        _rootContainer.read(trackingServiceProvider).event(
          'bubble_open_explain',
          properties: {'length': text.length},
        );
        final router = _rootContainer.read(routerProvider);
        router.push('/explain', extra: text);
      } catch (error) {
        debugPrint('[bubbleChannel] openExplain push failed: $error');
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
        _rootContainer.read(trackingServiceProvider).event(
          'bubble_translate',
          properties: {
            'mode':        mode,
            'target_lang': targetLang,
            'length':      text.length,
            'has_context': replyToOriginal != null,
          },
        );
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
      _rootContainer.read(trackingServiceProvider).event(
        'lens_translate',
        properties: {
          'target_lang': targetLang,
          'source_lang': sourceLang ?? 'auto',
          'block_count': texts.length,
          'total_chars': texts.fold<int>(0, (sum, t) => sum + t.length),
        },
      );
      return await _translateBatchForLens(texts, targetLang, sourceLang);
    }
    if (call.method == 'lensVisionTranslate') {
      // Lens vision-fallback flow: when the source script is one ML Kit
      // can't read (Cyrillic / Thai / Arabic / …) or auto-mode produced
      // an empty ML Kit result, the native side hands us the captured
      // bitmap (base64 JPEG) plus the dims, and we route it through
      // /translate-image?withBoxes=true. The server (Gemini-first) returns
      // per-block boxes scaled to those exact dims, so the Lens overlay
      // can position chips over the source-text regions — same UX as the
      // ML Kit path, just driven by vision for unsupported scripts.
      final args = (call.arguments as Map?)?.cast<Object?, Object?>() ?? {};
      final imageB64 = args['imageBase64'] as String?;
      final targetLang = (args['targetLang'] as String?) ?? 'en';
      final sourceLang = args['sourceLang'] as String?;
      final imageWidth = (args['imageWidth'] as num?)?.toInt() ?? 0;
      final imageHeight = (args['imageHeight'] as num?)?.toInt() ?? 0;
      if (imageB64 == null || imageB64.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
        return <String, dynamic>{
          'blocks': const <Map<String, dynamic>>[],
          'error': 'bad_args',
        };
      }
      _rootContainer.read(trackingServiceProvider).event(
        'lens_vision_translate',
        properties: {
          'target_lang': targetLang,
          'source_lang': sourceLang ?? 'auto',
          'image_kb': (imageB64.length * 0.75 / 1024).round(),
        },
      );
      return await _lensVisionTranslate(
        imageB64, targetLang, sourceLang, imageWidth, imageHeight,
      );
    }
    return null;
  });
}

/// Lens vision fallback: forward a captured screen bitmap through
/// /translate-image with withBoxes=true so the overlay can position
/// chips over each source-text region, just like the ML Kit path —
/// but for scripts ML Kit can't read. The MethodChannel return shape
/// uses primitive types (parallel arrays + box ints) because complex
/// nested objects don't survive the platform-channel codec cleanly.
Future<Map<String, dynamic>> _lensVisionTranslate(
  String imageBase64,
  String targetLang,
  String? sourceLang,
  int imageWidth,
  int imageHeight,
) async {
  try {
    final session = await SessionStore().load();
    if (session == null || session.accessToken.isEmpty) {
      return <String, dynamic>{
        'blocks': const <Map<String, dynamic>>[],
        'error': 'not_logged_in',
      };
    }
    final api = _rootContainer.read(apiClientProvider);
    final response = await api.dio.post('/translate-image', data: {
      'imageBase64': imageBase64,
      'targetLang': targetLang,
      if (sourceLang != null && sourceLang.isNotEmpty && sourceLang != 'auto')
        'sourceLang': sourceLang,
      'withBoxes': true,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
    });
    final data = response.data as Map?;
    final rawBlocks = data?['blocks'];
    final out = <Map<String, dynamic>>[];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is! Map) continue;
        final original = (b['original'] as String?)?.trim() ?? '';
        final translation = (b['translation'] as String?)?.trim() ?? '';
        if (original.isEmpty && translation.isEmpty) continue;
        final box = b['box'];
        if (box is! List || box.length != 4) continue;
        int? n(int i) => box[i] is num ? (box[i] as num).toInt() : null;
        final ymin = n(0), xmin = n(1), ymax = n(2), xmax = n(3);
        if (ymin == null || xmin == null || ymax == null || xmax == null) continue;
        if (xmax <= xmin || ymax <= ymin) continue;
        out.add(<String, dynamic>{
          'original': original,
          'translation': translation,
          'ymin': ymin,
          'xmin': xmin,
          'ymax': ymax,
          'xmax': xmax,
        });
      }
    }
    return <String, dynamic>{
      'blocks': out,
      'sourceLang': data?['sourceLang'],
    };
  } on DioException catch (e) {
    debugPrint('[LensVision] Dio error: ${e.response?.statusCode} ${e.message}');
    return <String, dynamic>{
      'blocks': const <Map<String, dynamic>>[],
      'error': 'http_${e.response?.statusCode ?? 0}',
    };
  } catch (e) {
    debugPrint('[LensVision] Error: $e');
    return <String, dynamic>{
      'blocks': const <Map<String, dynamic>>[],
      'error': 'exception',
    };
  }
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

  // Aligned with ApiException.fromDio so the bubble overlay and the in-app
  // error UI surface identical wording for the same server codes.
  return switch (status) {
    401 => 'Please log in to TransKey',
    403 when serverCode == 'feature_disabled' => 'This feature requires a paid plan',
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
      scaffoldMessengerKey: scaffoldMessengerKey,
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
