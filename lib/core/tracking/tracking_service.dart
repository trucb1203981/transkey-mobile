import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../api/dio_client.dart';
import '../diagnostics/app_log.dart';

const _kSessionId      = 'tk_track_session_id';
const _kSessionExpiry  = 'tk_track_session_expiry_ms';
const _kOptOut         = 'tk_track_opt_out';

/// A session is "the same trip" through the app. It rotates after this many
/// minutes of inactivity so funnel queries (open → camera → capture →
/// upgrade) reflect one user journey, not a multi-day blob.
const _kSessionIdleMinutes = 30;

/// In-memory event queue: events captured offline / during a backend hiccup
/// retry on the next successful send. We cap the queue so a long offline
/// stretch can't balloon memory.
const _kQueueMax = 100;

/// Properties common to every event. The backend can roll these up to
/// "% android users who hit upgrade_view" without each call site spelling
/// them out. Updated when the user logs in / changes plan.
class _CommonProps {
  String? platform;
  String? appVersion;
  String? osVersion;
  String? deviceModel;
  String? locale;
  String? userId;
  String? userPlan;

  Map<String, Object?> snapshot() => <String, Object?>{
        if (platform   != null) 'platform':    platform,
        if (appVersion != null) 'app_version': appVersion,
        if (osVersion  != null) 'os_version':  osVersion,
        if (deviceModel != null) 'device_model': deviceModel,
        if (locale     != null) 'locale':      locale,
        if (userId     != null) 'user_id':     userId,
        if (userPlan   != null) 'user_plan':   userPlan,
      };
}

/// Lightweight client-side analytics + crash reporter that talks to the
/// existing /analytics/* + /mobile/crashes endpoints. Designed to be
/// fire-and-forget: every public method swallows its own errors so analytics
/// can never break the app, and the in-memory queue + retry mean a flaky
/// network doesn't lose events.
///
/// Lifecycle:
///   1. `init()` — load session id / opt-out / device info (once at startup).
///   2. `appOpen()` — fire after init; rotates session if expired.
///   3. From anywhere: `screen()`, `event()`, `crash()`.
class TrackingService {
  TrackingService({required this.apiClient});

  final ApiClient apiClient;
  Dio get _dio => apiClient.dio;

  final _common = _CommonProps();
  final _queue  = <_QueuedSend>[];

  String _sessionId = '';
  bool   _optOut    = false;
  Completer<void>? _initCompleter;
  bool   _sendInFlight = false;
  Timer? _retryTimer;
  int    _retryAttempt = 0;
  String _lastPath = '/';

  bool   get optOut    => _optOut;
  String get sessionId => _sessionId;
  String get lastPath  => _lastPath;

  /// Idempotent + safe to await concurrently. Uses a Completer so two
  /// callers racing into `init()` both observe the SAME completion, not
  /// the early-return-while-still-loading anti-pattern (`_initialized = true`
  /// set before await would let caller B run as if init were done while
  /// caller A is still loading prefs).
  Future<void> init() async {
    final existing = _initCompleter;
    if (existing != null) return existing.future;
    final completer = _initCompleter = Completer<void>();
    try {
      final prefs = await SharedPreferences.getInstance();
      _optOut = prefs.getBool(_kOptOut) ?? false;
      _sessionId = await _ensureSession(prefs);
      await _populateDeviceInfo();
    } catch (error, stack) {
      // Init failure: leave _sessionId empty so events become no-ops, but
      // DON'T throw — app boot must not depend on analytics.
      AppLog.w('Tracking', 'init failed', error, stack);
    } finally {
      // Complete either way so concurrent waiters unblock. The next init()
      // call after a successful completion is a no-op (early-return via
      // `existing.future`).
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Fire on every app launch. Rotates the session if it has expired since
  /// the previous launch, then sends the first pageview to seed the
  /// backend's session row (events require a session to exist).
  Future<void> appOpen() async {
    await init();
    if (_optOut) return;
    await _maybeRotateSession();
    await _pageview('/');
    await event('app_open');
  }

  /// Record a screen change. Backed by /analytics/pageview so the existing
  /// dashboard's "top pages" table includes mobile routes.
  Future<void> screen(String name, {Map<String, Object?>? properties}) async {
    await init();
    _lastPath = name;
    if (_optOut) return;
    await _maybeRotateSession();
    await _pageview(name);
    if (properties != null && properties.isNotEmpty) {
      await event('screen_view', properties: {'name': name, ...properties});
    }
  }

  /// Record a custom user event. Common properties (platform/app_version/…)
  /// are merged automatically; per-call properties win on key collision.
  Future<void> event(String name, {Map<String, Object?>? properties}) async {
    await init();
    if (_optOut) return;
    if (_sessionId.isEmpty) return;
    final merged = <String, Object?>{
      ..._common.snapshot(),
      if (properties != null) ...properties,
    };
    _enqueue(_QueuedSend(
      path:    '/analytics/event',
      payload: {
        'sessionId': _sessionId,
        'name':      name,
        'path':      _lastPath,
        'properties': merged,
      },
    ));
  }

  /// Record a crash / handled exception. Crashes flow through their OWN
  /// endpoint (no session FK) and are NOT gated by opt-out — stability data
  /// has no PII and missing it leaves us blind to production breakage.
  Future<void> crash({
    required String name,
    String? message,
    String? stack,
    bool fatal = false,
    Map<String, Object?>? properties,
  }) async {
    await init();
    final payload = <String, Object?>{
      'name':         name,
      if (message != null) 'message': _truncate(message, 2000),
      if (stack   != null) 'stack':   _truncate(stack,  16000),
      'platform':     _common.platform ?? 'unknown',
      if (_common.appVersion  != null) 'appVersion':  _common.appVersion,
      if (_common.osVersion   != null) 'osVersion':   _common.osVersion,
      if (_common.deviceModel != null) 'deviceModel': _common.deviceModel,
      if (_common.userId      != null) 'userId':      _common.userId,
      'fatal': fatal,
      'properties': <String, Object?>{
        'last_screen': _lastPath,
        'session_id':  _sessionId,
        if (properties != null) ...properties,
      },
    };
    _enqueue(_QueuedSend(
      path:    '/mobile/crashes',
      payload: payload,
      isCrash: true,
    ));
  }

  Future<void> setUserId(String? userId) async {
    _common.userId = userId;
  }

  Future<void> setUserPlan(String? plan) async {
    _common.userPlan = plan;
  }

  void setLocale(String locale) {
    _common.locale = locale;
  }

  /// Toggle from the settings screen. When opting OUT we drop any QUEUED
  /// analytics events so anything captured before the user changed their
  /// mind isn't sent later. Crashes are NOT dropped — they contain no PII
  /// and have their own opt-out story (currently always on).
  ///
  /// Note: a `_sendBatch` already in flight when opt-out is set will finish
  /// processing its local batch. To prevent leaked analytics events from
  /// that in-flight batch, `_sendBatch` re-checks `_optOut` per item.
  Future<void> setOptOut(bool value) async {
    _optOut = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptOut, value);
    if (value) {
      // Keep crashes; drop everything else.
      _queue.retainWhere((item) => item.isCrash);
    }
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  Future<String> _ensureSession(SharedPreferences prefs) async {
    final existing = prefs.getString(_kSessionId);
    final expiry   = prefs.getInt(_kSessionExpiry) ?? 0;
    final now      = DateTime.now().millisecondsSinceEpoch;
    if (existing != null && expiry > now) {
      return existing;
    }
    final fresh = const Uuid().v4();
    await prefs.setString(_kSessionId, fresh);
    await prefs.setInt(_kSessionExpiry, now + _kSessionIdleMinutes * 60 * 1000);
    return fresh;
  }

  Future<void> _maybeRotateSession() async {
    final prefs  = await SharedPreferences.getInstance();
    final expiry = prefs.getInt(_kSessionExpiry) ?? 0;
    final now    = DateTime.now().millisecondsSinceEpoch;
    if (expiry <= now) {
      // Idle past the rotate window — start a new session.
      _sessionId = const Uuid().v4();
      await prefs.setString(_kSessionId, _sessionId);
    }
    // Always slide the expiry forward so an active user keeps the same
    // session for the duration of one journey.
    await prefs.setInt(
      _kSessionExpiry,
      now + _kSessionIdleMinutes * 60 * 1000,
    );
  }

  Future<void> _pageview(String path) async {
    if (_sessionId.isEmpty) return;
    _enqueue(_QueuedSend(
      path:    '/analytics/pageview',
      payload: {
        'sessionId': _sessionId,
        'path':      path,
      },
    ));
  }

  Future<void> _populateDeviceInfo() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      _common.appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {/* package_info unavailable — leave null */}

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _common.platform    = 'android';
        _common.osVersion   = 'Android ${a.version.release}';
        _common.deviceModel = '${a.manufacturer} ${a.model}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _common.platform    = 'ios';
        _common.osVersion   = '${i.systemName} ${i.systemVersion}';
        _common.deviceModel = i.utsname.machine;
      } else {
        _common.platform = 'other';
      }
    } catch (_) {
      _common.platform ??= 'unknown';
    }
  }

  void _enqueue(_QueuedSend item) {
    _queue.add(item);
    if (_queue.length > _kQueueMax) {
      // Naive `removeRange(0, ...)` evicts the OLDEST items — which, on a
      // long offline stretch followed by a crash, would silently throw the
      // crash away in favour of stale screen_view rows. Prefer dropping
      // older non-crash items; only drop crashes when there are no other
      // candidates left.
      final overflow = _queue.length - _kQueueMax;
      for (int dropped = 0; dropped < overflow;) {
        final analyticsIdx = _queue.indexWhere((item) => !item.isCrash);
        if (analyticsIdx == -1) {
          // Everything left in the queue is a crash — drop the oldest
          // crash as a last resort to honour the cap.
          _queue.removeAt(0);
        } else {
          _queue.removeAt(analyticsIdx);
        }
        dropped++;
      }
    }
    _drainQueue();
  }

  void _drainQueue() {
    // `_sendInFlight` prevents concurrent `_sendBatch` runs. Without it,
    // every `_enqueue` during an in-flight send would spawn another batch
    // → 2 parallel posts of the same payload (PG insert duplicates, FK
    // session races, dashboard double-counts).
    if (_sendInFlight) return;
    if (_retryTimer != null) return; // already waiting for backoff
    if (_queue.isEmpty) return;
    final batch = List<_QueuedSend>.from(_queue);
    _queue.clear();
    _sendInFlight = true;
    _sendBatch(batch).whenComplete(() {
      _sendInFlight = false;
      // Anything `_enqueue`-d while we were sending sits in `_queue` now.
      // Kick a drain so it doesn't wait for the NEXT event before going out.
      if (_retryTimer == null && _queue.isNotEmpty) _drainQueue();
    });
  }

  Future<void> _sendBatch(List<_QueuedSend> batch) async {
    final ua = _userAgent();
    final failed = <_QueuedSend>[];
    for (final item in batch) {
      // Privacy: re-check opt-out per item so events queued before opt-out
      // but still mid-send are dropped. Crashes always go through.
      if (_optOut && !item.isCrash) continue;
      try {
        await _dio.post(
          item.path,
          data: item.payload,
          options: Options(
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            // Override Dio's default short UA ("Dart/3.x (dart:io)" — 19
            // chars) which the backend's bot detector trims as a bot.
            // Without this every mobile analytics event is silently dropped.
            headers: {'User-Agent': ua},
          ),
        );
      } catch (_) {
        // No need to block following events on a failed pageview anymore —
        // the backend's `trackEvent` now upserts the session itself
        // (migration-7 fix), so an event can succeed even when the pageview
        // that "would have seeded" the session never landed.
        failed.add(item);
      }
    }
    if (failed.isEmpty) {
      _retryAttempt = 0;
      return;
    }
    // Re-queue failed items at the front, then back off.
    _queue.insertAll(0, failed);
    _retryAttempt += 1;
    final delaySeconds = (1 << _retryAttempt).clamp(1, 30);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      _retryTimer = null;
      _drainQueue();
    });
  }

  String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  /// Build a >= 20-char User-Agent so the backend's bot detector
  /// (`MIN_UA_LENGTH = 20`) doesn't drop our events. Falls back to a stable
  /// string before device info loads (e.g. very first event during init).
  String _userAgent() {
    final platform = _common.platform ?? 'unknown';
    final version  = _common.appVersion ?? '0.0.0';
    final model    = _common.deviceModel ?? 'device';
    return 'TransKey-Mobile/$version ($platform; $model)';
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

class _QueuedSend {
  _QueuedSend({
    required this.path,
    required this.payload,
    this.isCrash = false,
  });
  final String path;
  final Map<String, Object?> payload;
  /// Crashes survive opt-out and aren't blocked by a failed pageview —
  /// they go to their own endpoint with no session FK.
  final bool isCrash;
}
