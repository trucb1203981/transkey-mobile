import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/dio_client.dart';
import 'core/auth/auth_provider.dart';
import 'core/bubble/bubble_manager.dart';
import 'core/cache/lens_translation_cache.dart';
import 'core/locale/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/tracking/crash_reporter.dart';
import 'core/tracking/tracking_provider.dart';
import 'features/translate/providers/features_provider.dart';
import 'features/history/providers/history_provider.dart';
import 'features/history/storage/history_store.dart';
import 'features/translate/services/bubble_translate_cache.dart';
import 'features/translate/providers/language_settings_provider.dart';
import 'features/translate/models/translate_models.dart';
import 'features/upgrade/services/purchases_service.dart';
import 'shared/theme/app_theme.dart';
import 'l10n/generated/app_localizations.dart';

// Top-level channel & container so the Android side can invoke translateText
// even on a cold start, before the widget tree finishes building.
const _bubbleChannel = MethodChannel('transkey/bubble');
late final ProviderContainer _rootContainer;

/// Persistent exact-match cache for bubble/keyboard text translations, so an
/// identical request returns instantly without paying for another API call.
final _bubbleTranslateCache = BubbleTranslateCache();

/// App-level ScaffoldMessenger. Without an explicit key, MaterialApp's default
/// messenger is per-Scaffold and snackbars shown right after a route pop can
/// land on a disposing Scaffold's messenger — the snackbar mounts but its
/// auto-dismiss timer never starts (status callback doesn't fire). Routing
/// every snackbar through this key uses the SAME messenger across all routes,
/// so the lifecycle is consistent regardless of which screen called.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Credit the bundled offline keyboard dictionaries in the app's license page
/// (shown via showLicensePage). EDRDG requires the acknowledgement statement
/// below; CC-CEDICT is CC-BY-SA 4.0; jieba is MIT.
void _registerDictionaryLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['TransKey keyboard dictionaries'],
      'Japanese kana->kanji conversion uses the JMdict/EDICT dictionary files. '
      'These files are the property of the Electronic Dictionary Research and '
      'Development Group (EDRDG), and are used in conformance with the Group\'s '
      'licence. See https://www.edrdg.org/edrdg/licence.html\n\n'
      'Chinese pinyin->hanzi conversion uses CC-CEDICT, licensed under '
      'Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0). '
      'See https://www.mdbg.net/chinese/dictionary?page=cc-cedict\n\n'
      'Chinese word frequencies are derived from "jieba" (MIT License), '
      'Copyright (c) Sun Junyi. See https://github.com/fxsjy/jieba',
    );
  });
}

void main() async {
  // Wrap the entire boot in a zone so async errors that escape the widget
  // tree (unawaited futures, plugin handlers) still reach the crash reporter
  // instead of dying silently in release.
  runZonedGuarded<void>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _registerDictionaryLicenses();
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
          // Mirror the TransKey user id into RevenueCat so any in-app
          // purchase the user makes through Play Billing reaches our
          // /revenuecat/webhook with `app_user_id` = our users.id (the
          // backend parses it back to int and updates that user's plan).
          // No-op when RC isn't initialised yet (e.g. on iOS, or until
          // REVENUECAT_API_KEY_ANDROID is set).
          unawaited(PurchasesService.syncAuth(session?.userId));
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

      // Initialise RevenueCat for Google Play Billing. Safe no-op on iOS or
      // when the API key env var isn't set yet — callers (upgrade screen)
      // check PurchasesService.isReady before showing Buy UI.
      //
      // Race fix: the authStateProvider listener above fires immediately at
      // startup and calls syncAuth(userId), but init() usually hasn't
      // finished configuring RC yet, so that first syncAuth is a no-op
      // (PurchasesService._configured is still false). Without re-syncing,
      // RC stays anonymous for a restored session — a purchase then attaches
      // to an anonymous app_user_id, the webhook can't map it to a user, and
      // the plan never upgrades. So once init() resolves, sync the CURRENT
      // session explicitly. Subsequent login/logout changes are still handled
      // by the listener.
      unawaited(PurchasesService.init().then((_) {
        final session = _rootContainer.read(authStateProvider).valueOrNull?.session;
        return PurchasesService.syncAuth(session?.userId);
      }));

      runApp(UncontrolledProviderScope(
        container: _rootContainer,
        child: const TransKeyApp(),
      ));

      // Fire-and-forget: don't make the first frame wait on platform channels.
      // tryAutoStart() reads SharedPreferences + invokes the Android bubble plugin.
      unawaited(_rootContainer.read(bubbleManagerProvider.notifier).tryAutoStart());

      // Pre-warm the session cache so the very first Lens trigger doesn't pay
      // a FlutterSecureStorage.read() disk round-trip. The result is stored in
      // SessionStore._cache and returned instantly on subsequent load() calls.
      unawaited(_rootContainer.read(sessionStoreProvider).load());

      // Open the Lens translation cache DB so the first cache lookup on a
      // Lens scan doesn't pay the openDatabase() cost (~20-80ms). The connection
      // is reused for the whole app session. See LensTranslationCache.
      LensTranslationCache.instance.warmUp();
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
    if (call.method == 'bubbleStateChanged') {
      // Native BubbleService just flipped its active state — sync the
      // Riverpod state so the Settings toggle and any other UI watching
      // bubbleManagerProvider reflects truth without polling.
      final active = call.arguments as bool? ?? false;
      try {
        _rootContainer
            .read(bubbleManagerProvider.notifier)
            .syncState(active);
      } catch (e) {
        debugPrint('[bubbleChannel] bubbleStateChanged sync failed: $e');
      }
      return null;
    }
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
    if (call.method == 'openKeyboardSettings') {
      // The keyboard's settings panel "open full settings" button — surface
      // the in-app keyboard-settings screen (native brings MainActivity to
      // the front; this just navigates the shared engine's router).
      try {
        final router = _rootContainer.read(routerProvider);
        router.push('/settings/keyboard');
      } catch (error) {
        debugPrint('[bubbleChannel] openKeyboardSettings push failed: $error');
      }
      return null;
    }
    if (call.method == 'getRecentHistory') {
      // Keyboard's inline history panel: return the recent translations as
      // {translation, source} maps (newest first) so the native list can
      // re-insert a past result without opening the app.
      try {
        final userId = _rootContainer
            .read(authStateProvider)
            .valueOrNull
            ?.session
            ?.userId;
        if (userId == null) return const <Map<String, String>>[];
        final entries = await HistoryStore(userId: userId).load();
        return entries
            .take(25)
            .map((e) => {'translation': e.translation, 'source': e.sourceText})
            .toList(growable: false);
      } catch (error) {
        debugPrint('[bubbleChannel] getRecentHistory failed: $error');
        return const <Map<String, String>>[];
      }
    }
    if (call.method == 'setUiLocale') {
      // Keyboard's app-language picker: update the live app locale (also
      // persists flutter.tk_ui_locale, which the keyboard reads for labels).
      try {
        final code = (call.arguments as Map?)?['code'] as String?;
        if (code != null && code.isNotEmpty) {
          await _rootContainer.read(localeProvider.notifier).setLocale(code);
        }
      } catch (error) {
        debugPrint('[bubbleChannel] setUiLocale failed: $error');
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
  // Reset the once-per-scan mismatch guard, same as the batch entry, so
  // the vision-fallback path can fire its own banner independently.
  _lensMismatchEmitted = false;
  try {
    final session = await _rootContainer.read(sessionStoreProvider).load();
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
    // Source-mismatch surfacing for the vision path — same shape as the
    // batch path so the overlay shows one banner regardless of which OCR
    // route fed it. The vision fallback exists EXACTLY for this case
    // (user pinned ja but the screen is Arabic and ML Kit can't read it),
    // so this is the most useful place for the warning.
    final mismatch = data?['sourceMismatch'];
    if (mismatch is Map && !_lensMismatchEmitted) {
      _lensMismatchEmitted = true;
      _emitLensMismatch(
        mismatch['detected'] as String?,
        mismatch['requested'] as String?,
      );
    }
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

/// Dense Lens scans (a Chinese news website, a multi-column menu) return
/// 100+ OCR blocks in one go. /translate-batch tries to fit ALL of them
/// into one LLM round-trip, and the output JSON array can run past the
/// model's max_tokens budget (8k) — the response is cut mid-array, the
/// server's [parseBatchResponse] falls back to returning the originals,
/// and the user sees their chips render the source text unchanged. Cap
/// chunk size so each request stays inside a comfortable output budget,
/// then fire chunks in parallel so the total wall-time stays close to
/// one batch.
const _kLensBatchChunkSize = 20;

/// In-memory LRU cache of Lens translations, keyed by
/// `sourceLang|targetLang|sourceText`. Survives for the life of the
/// pre-warmed Flutter engine (i.e. the whole bubble-service session), so
/// re-scanning the same screen — e.g. after an accidental dismiss — skips
/// the expensive LLM round-trip entirely and only pays for capture + OCR.
///
/// Only ACTUAL translations are cached (value != original). A failed slot
/// that the server echoed back as the original is NOT cached, so a later
/// re-scan still gets a fresh attempt instead of a stuck bad result.
const _kLensCacheMax = 2000;
final _lensTransCache = <String, String>{};

String _lensCacheKey(String? sourceLang, String targetLang, String text) {
  final src = (sourceLang == null || sourceLang.isEmpty) ? 'auto' : sourceLang;
  return '$src|$targetLang|$text';
}

void _lensCachePut(String key, String value) {
  // Refresh LRU position: Dart maps keep insertion order, so remove+insert
  // moves this key to the most-recently-used (last) slot.
  _lensTransCache.remove(key);
  _lensTransCache[key] = value;
  if (_lensTransCache.length > _kLensCacheMax) {
    _lensTransCache.remove(_lensTransCache.keys.first);
  }
}

// Mirror of the server's residual-source-script check: any kana/hangul
// char or a 2+ Han run. A translation that still carries source script
// (e.g. a leaked "チュックさん") is a low-quality result we must NOT cache,
// otherwise a re-scan would serve the leak instantly instead of retrying.
final _kKanaHangulRe = RegExp(r'[぀-ゟ゠-ヿｦ-ﾟ가-힯]');
final _kHanRunRe = RegExp(r'[一-鿿㐀-䶿]{2,}');
bool _lensHasResidualSourceScript(String t) =>
    _kKanaHangulRe.hasMatch(t) || _kHanRunRe.hasMatch(t);

// Client mirror of the server's `isStructurallyUntranslatable` (translate.cjk.ts).
// A WHOLE block that is purely a URL / email / number / symbol run, OR has no
// 2+ consecutive letters anywhere, is something NO model will translate — it
// comes back as an exact echo. Filtering these client-side BEFORE the batch
// call saves the input tokens + the round-trip, and lets the overlay show them
// instantly. Critically this only matches PURE-noise WHOLE blocks: mixed
// content like "Truy cập example.com để xem" has a letter run and is NOT
// filtered, so a URL embedded in a sentence still reaches the model with its
// translatable context intact (the concern that ruled out naive URL stripping).
final _kUrlOnlyRe = RegExp(r'^https?://\S+$', caseSensitive: false);
final _kDomainOnlyRe = RegExp(
  r'^[\w.-]+\.(com|net|org|edu|gov|io|app|dev|co|jp|vn|uk|de|fr|ru|cn|kr|tw|hk|sg|in|au|ca|br)(/\S*)?$',
  caseSensitive: false,
);
final _kEmailRe = RegExp(r'^[\w.+-]+@[\w.-]+\.[a-z]{2,}$', caseSensitive: false);
final _kSymbolsNumsRe =
    RegExp(r'''^[\d\s%+|\-.,:/\\()\[\]{}<>~`!?@#$^&*"'_=]+$''');
final _kTwoLetterRunRe = RegExp(r'\p{L}{2,}', unicode: true);

bool _lensIsStructurallyUntranslatable(String text) {
  final t = text.trim();
  if (t.length < 2) return true;
  if (_kUrlOnlyRe.hasMatch(t)) return true;
  if (_kDomainOnlyRe.hasMatch(t)) return true;
  if (_kEmailRe.hasMatch(t)) return true;
  if (_kSymbolsNumsRe.hasMatch(t)) return true;
  if (!_kTwoLetterRunRe.hasMatch(t)) return true; // no 2+ consecutive letters
  return false;
}

/// Progressive-emit hook: push one chunk of translations up to the
/// native side so [LensOverlayView.applyTranslations] can patch the
/// already-shown chips in place. Fire-and-forget — any platform-side
/// error just means the user waits for the final batch return.
void _emitLensChunk(int startIdx, List<String> translations) {
  if (translations.isEmpty) return;
  unawaited(
    _bubbleChannel.invokeMethod('deliverLensChunk', {
      'startIdx': startIdx,
      'translations': translations,
    }).catchError((e) {
      debugPrint('[LensTranslate] deliverLensChunk failed: $e');
      return null;
    }),
  );
}

/// One-shot guard so a multi-chunk scan only surfaces ONE mismatch
/// banner even though every chunk independently reports the same
/// detected/requested pair. Reset at the start of each scan.
bool _lensMismatchEmitted = false;

/// Tell the native overlay that the user's pinned source language
/// disagrees with the script we actually saw, so it can show a
/// "Detected X — switch?" banner. Fire-and-forget.
void _emitLensMismatch(String? detected, String? requested) {
  if (detected == null || detected.isEmpty) return;
  unawaited(
    _bubbleChannel.invokeMethod('deliverLensMismatch', {
      'detected': detected,
      'requested': requested ?? '',
    }).catchError((e) {
      debugPrint('[LensTranslate] deliverLensMismatch failed: $e');
      return null;
    }),
  );
}

Future<List<String>> _translateBatchForLens(
  List<String> texts,
  String targetLang,
  String? sourceLang,
) async {
  _lensMismatchEmitted = false;
  try {
    final session = await _rootContainer.read(sessionStoreProvider).load();
    if (session == null || session.accessToken.isEmpty) {
      // Logged out — return originals so the overlay still shows SOMETHING
      // rather than blowing up the native side.
      return texts;
    }
    if (texts.length <= _kLensBatchChunkSize) {
      final translations = await _lensBatchChunk(texts, targetLang, sourceLang, 0, texts);
      // Single-chunk case: still emit progressively so the overlay's
      // placeholder chips update the moment the chunk lands (instead of
      // staying on the originals until the MethodChannel return resolves).
      _emitLensChunk(0, translations);
      return translations;
    }
    // Split into chunks of <= _kLensBatchChunkSize, dispatched in parallel.
    final chunks = <List<String>>[];
    final starts = <int>[];
    for (var i = 0; i < texts.length; i += _kLensBatchChunkSize) {
      starts.add(i);
      chunks.add(texts.sublist(i, math.min(i + _kLensBatchChunkSize, texts.length)));
    }
    debugPrint('[LensTranslate] split ${texts.length} blocks into ${chunks.length} chunks of <=$_kLensBatchChunkSize');
    // Fire each chunk and emit its result to the overlay AS SOON AS it
    // completes — the overlay shows originals as placeholders, so each
    // emit replaces a slab of chips with their real translation. The
    // overall Future.wait still aggregates for the final MethodChannel
    // return (which is now just a safety net since chips were already
    // patched in place).
    final futures = List<Future<List<String>>>.generate(chunks.length, (idx) {
      final start = starts[idx];
      return _lensBatchChunk(chunks[idx], targetLang, sourceLang, idx, texts).then((translations) {
        _emitLensChunk(start, translations);
        return translations;
      });
    });
    final results = await Future.wait(futures);
    return results.expand((r) => r).toList(growable: false);
  } catch (e) {
    debugPrint('[LensTranslate] Error: $e');
    return texts;
  }
}

Future<List<String>> _lensBatchChunk(
  List<String> texts,
  String targetLang,
  String? sourceLang,
  int chunkIdx,
  List<String> contextTexts,
) async {
  final tag = '[LensChunk#$chunkIdx]';
  final t0 = DateTime.now().millisecondsSinceEpoch;
  // Cache pre-pass: pull any already-translated texts out of the chunk so
  // we only spend an LLM call on the genuinely-new ones. On a full re-scan
  // of the same screen every slot hits, so the chunk returns ~instantly.
  //
  // Two-tier lookup:
  //   Tier 1 (in-memory `_lensTransCache`): hot path, ~2000 entries, survives
  //     the Flutter engine's lifetime — instant hit.
  //   Tier 2 ([LensTranslationCache] SQLite): cold path, ~10k entries, 30-day
  //     TTL, survives APP RESTART. Hit promotes to tier 1.
  final out = List<String>.from(texts);
  var missTexts = <String>[];
  var missIdx = <int>[];
  var noiseSkipped = 0;
  for (var i = 0; i < texts.length; i++) {
    // Noise pre-filter: a WHOLE block that's purely a URL / number / symbol
    // run (status-bar speed, page markers, prices, bare URLs) is left as-is
    // — no model translates it, so don't pay tokens or the round-trip. Mixed
    // sentences keep their letter runs and fall through to translation.
    if (_lensIsStructurallyUntranslatable(texts[i])) {
      out[i] = texts[i];
      noiseSkipped++;
      continue;
    }
    final cached = _lensTransCache[_lensCacheKey(sourceLang, targetLang, texts[i])];
    if (cached != null) {
      _lensCachePut(_lensCacheKey(sourceLang, targetLang, texts[i]), cached);
      out[i] = cached;
    } else {
      missTexts.add(texts[i]);
      missIdx.add(i);
    }
  }
  final t1Hits = texts.length - missTexts.length - noiseSkipped;

  // Tier 2: persistent SQLite for tier-1 misses. Manga has high text
  // repetition ACROSS app sessions (character speech patterns repeat
  // chapter to chapter); the persistent layer turns 2nd-day re-reads into
  // 0-cost hits.
  var t2Hits = 0;
  if (missTexts.isNotEmpty) {
    try {
      final t2 = await LensTranslationCache.instance
          .getBatch(missTexts, targetLang, sourceLang);
      if (t2.isNotEmpty) {
        final stillMissTexts = <String>[];
        final stillMissIdx = <int>[];
        for (var k = 0; k < missTexts.length; k++) {
          final hit = t2[missTexts[k]];
          if (hit != null) {
            out[missIdx[k]] = hit;
            // Promote to tier 1 so subsequent chunks / re-scans this session
            // skip the disk hop.
            _lensCachePut(_lensCacheKey(sourceLang, targetLang, missTexts[k]), hit);
            t2Hits++;
          } else {
            stillMissTexts.add(missTexts[k]);
            stillMissIdx.add(missIdx[k]);
          }
        }
        missTexts = stillMissTexts;
        missIdx = stillMissIdx;
      }
    } catch (e) {
      // Tier 2 is best-effort — DB failure must not break translation.
      debugPrint('$tag tier-2 cache lookup failed: $e');
    }
  }

  if (missTexts.isEmpty) {
    debugPrint('$tag no-llm n=${texts.length} (t1=$t1Hits t2=$t2Hits noise=$noiseSkipped)');
    return out;
  }
  try {
    final api = _rootContainer.read(apiClientProvider);
    // Lens batch can hit the slow path on the server (Llama-4 Scout fails →
    // retry Llama-3.3 70b → Gemini → Claude). Each hop takes 2-5s, so a
    // single chunk on the deep fallback chain can blow past the global 30s
    // Dio receiveTimeout. Bump per-request to 90s for batch translation.
    final response = await api.dio.post(
      '/translate-batch',
      data: {
        'texts': missTexts,
        // Full-screen text as disambiguation context so each chunk keeps
        // the surrounding meaning even though we only send the cache-miss
        // subset for translation. Cap to the DTO's limit (200).
        'contextTexts': contextTexts.length <= 200 ? contextTexts : contextTexts.sublist(0, 200),
        'targetLang': targetLang,
        if (sourceLang != null && sourceLang.isNotEmpty && sourceLang != 'auto')
          'sourceLang': sourceLang,
        'appHint': 'lens',
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    final dt = DateTime.now().millisecondsSinceEpoch - t0;
    final data = response.data as Map?;
    // Source-language mismatch: server compared the user's pinned source
    // against the dominant script and they disagree. Surface ONCE per
    // scan (the check+set is synchronous so parallel chunks can't double
    // -fire). Lets the overlay offer a "switch & re-translate" banner.
    final mismatch = data?['sourceMismatch'];
    if (mismatch is Map && !_lensMismatchEmitted) {
      _lensMismatchEmitted = true;
      _emitLensMismatch(
        mismatch['detected'] as String?,
        mismatch['requested'] as String?,
      );
    }
    final raw = data?['translations'] as List?;
    if (raw == null) {
      debugPrint('$tag dt=${dt}ms FAIL no-translations-field data=$data');
      return out; // cache hits (if any) still applied
    }
    // Merge fresh translations back into their original positions and cache
    // the GOOD ones (a translation that actually differs from the source).
    var fallback = 0;
    final tier2Writes = <String, String>{};
    for (var j = 0; j < missTexts.length; j++) {
      final value = j < raw.length ? raw[j] : null;
      final original = missTexts[j];
      final isGood = value is String && value.trim().isNotEmpty && value.trim() != original.trim();
      if (isGood) {
        out[missIdx[j]] = value;
        // Cache only clean results — a translation that still leaks source
        // script is shown (best we have) but NOT cached, so a re-scan gets
        // a fresh attempt at a clean translation instead of the leak.
        if (!_lensHasResidualSourceScript(value)) {
          _lensCachePut(_lensCacheKey(sourceLang, targetLang, original), value);
          tier2Writes[original] = value;
        }
      } else {
        out[missIdx[j]] = original;
        fallback++;
      }
    }
    // Tier 2 write: batched insert, fire-and-forget. Survives app restart.
    if (tier2Writes.isNotEmpty) {
      LensTranslationCache.instance.putBatch(tier2Writes, targetLang, sourceLang);
    }
    final provider = data?['provider'] ?? '?';
    final model = data?['model'] ?? '?';
    debugPrint('$tag dt=${dt}ms n=${texts.length} t1=$t1Hits t2=$t2Hits noise=$noiseSkipped sent=${missTexts.length} good=${missTexts.length - fallback} fallback=$fallback provider=$provider model=$model');
    if (fallback == missTexts.length) {
      final firstIn = missTexts.isNotEmpty ? missTexts.first : '';
      final firstRaw = raw.isNotEmpty ? raw.first.toString() : '';
      debugPrint('$tag whole-fallback in[0]="${firstIn.substring(0, math.min(60, firstIn.length))}" raw[0]="${firstRaw.substring(0, math.min(60, firstRaw.length))}"');
    }
    return out;
  } on DioException catch (e) {
    final dt = DateTime.now().millisecondsSinceEpoch - t0;
    debugPrint('$tag dt=${dt}ms DIO ${e.response?.statusCode} ${e.message}');
    return out; // keep any cache hits we already applied
  } catch (e) {
    final dt = DateTime.now().millisecondsSinceEpoch - t0;
    debugPrint('$tag dt=${dt}ms ERR $e');
    return out;
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
    final session = await _rootContainer.read(sessionStoreProvider).load();
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

    // Smart cache: an identical request (same text + langs + mode + tone +
    // flags) reuses the stored result with NO paid API round-trip.
    final cacheKey = BubbleTranslateCache.keyFor(
      text: text,
      mode: mode,
      targetLang: effectiveTargetLang,
      sourceLang: sourceLang,
      tone: effectiveTone,
      romanization: romanizationEnabled,
      suggestReplies: replySuggestions,
      replyToOriginal: isReply ? replyToOriginal : null,
    );
    final cached = await _bubbleTranslateCache.get(cacheKey);
    if (cached != null) {
      debugPrint('[BubbleTranslate] cache HIT mode=$mode '
          'tgt=$effectiveTargetLang len=${text.trim().length} (no server call)');
      await _sendResultToBubble(
        translation: cached['translation'] as String? ?? '',
        romanization: cached['romanization'] as String?,
        detectedLang: cached['detectedLang'] as String?,
        suggestionSources:
            (cached['suggestionSources'] as List?)?.cast<String>() ?? const [],
        suggestionTargets:
            (cached['suggestionTargets'] as List?)?.cast<String>() ?? const [],
        requestId: requestId,
      );
      return;
    }

    debugPrint('[BubbleTranslate] cache MISS mode=$mode '
        'tgt=$effectiveTargetLang len=${text.trim().length} -> server');
    final api = _rootContainer.read(apiClientProvider);
    final response = await api.dio
        .post(endpoint, data: body)
        .timeout(const Duration(seconds: 15));
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

    // Cache the fresh result so an identical future request is instant + free.
    unawaited(_bubbleTranslateCache.put(cacheKey, {
      'translation': output,
      'romanization': romanization,
      'detectedLang': detectedLang,
      'suggestionSources': pairs.map((p) => p.source).toList(growable: false),
      'suggestionTargets': pairs.map((p) => p.target).toList(growable: false),
    }));

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
