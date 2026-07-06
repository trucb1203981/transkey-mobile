import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_provider.dart';
import '../auth/session_store.dart';
import '../device/device_id.dart';
import '../diagnostics/app_log.dart';

String get kBaseUrl =>
    dotenv.env['TRANSKEY_API_URL'] ?? 'https://api.transkey.app';

/// Endpoints that mint a NEW session from credentials (not from an existing
/// token). The header interceptor must NOT attach a stale bearer here, and
/// the refresh interceptor must NOT try to refresh on their 401 (a 401 means
/// "wrong credentials", not "expired session"). Mirrors the server's
/// credential-attempt list in api_errors.dart.
const _credentialPaths = {
  '/auth/login',
  '/auth/register',
  '/auth/google/mobile',
  '/auth/guest',
};

class ApiClient {
  ApiClient({
    required DeviceIdService deviceId,
    required SessionStore sessionStore,
    required void Function() onAuthFailed,
  })  : _deviceId = deviceId,
        _sessionStore = sessionStore,
        _onAuthFailed = onAuthFailed {
    _dio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _headers = _HeadersInterceptor(
      deviceId: _deviceId,
      sessionStore: _sessionStore,
    );
    _dio.interceptors.addAll([
      _headers,
      _AuthRefreshInterceptor(
        dio: _dio,
        sessionStore: _sessionStore,
        onAuthFailed: _onAuthFailed,
        onSessionChanged: () => _headers.invalidateSessionCache(),
      ),
      _RetryInterceptor(dio: _dio),
    ]);
  }

  final DeviceIdService _deviceId;
  final SessionStore _sessionStore;
  final void Function() _onAuthFailed;
  late final Dio _dio;
  late final _HeadersInterceptor _headers;

  Dio get dio => _dio;

  /// Drop the in-memory session cache. Call after manual session writes
  /// (e.g. handleDeepLink) so the next request uses the fresh token.
  void invalidateSessionCache() => _headers.invalidateSessionCache();
}

// ────────────────────────────────────────────────
// Interceptor 1 — Mandatory headers
// ────────────────────────────────────────────────

class _HeadersInterceptor extends Interceptor {
  _HeadersInterceptor({
    required this.deviceId,
    required this.sessionStore,
  });

  final DeviceIdService deviceId;
  final SessionStore sessionStore;

  AuthSession? _cachedSession;
  bool _sessionLoaded = false;

  // Bare OS version (Android release e.g. '14', iOS systemVersion e.g. '17.5').
  // Immutable for the process lifetime, so resolve once and cache; sent as
  // X-OS-Version so the admin "OS" column can show the granular version.
  String? _osVersion;
  bool _osVersionLoaded = false;

  void invalidateSessionCache() {
    _cachedSession = null;
    _sessionLoaded = false;
  }

  Future<String?> _getOsVersion() async {
    if (_osVersionLoaded) return _osVersion;
    _osVersionLoaded = true;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        _osVersion = (await info.androidInfo).version.release;
      } else if (Platform.isIOS) {
        _osVersion = (await info.iosInfo).systemVersion;
      }
    } catch (_) {
      _osVersion = null;
    }
    return _osVersion;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_sessionLoaded) {
      _cachedSession = await sessionStore.load();
      _sessionLoaded = true;
    }
    final token = _cachedSession?.accessToken;
    // NEVER attach a bearer token to a credential-attempt endpoint. These
    // mint a brand-new session from email/password (or a Google idToken),
    // so any token we hold is irrelevant — and attaching a STALE one is
    // actively harmful: if a prior logout's secure-storage delete timed
    // out, `load()` above still returns the old session, and sending that
    // expired/rotated token with /auth/login can make the server reject
    // the request → user "can't log in with the correct password". Keep
    // login isolated from whatever session state is lying around.
    final isCredentialAttempt = _credentialPaths.contains(options.path);
    // Respect any Authorization already set on the request (e.g. refresh
    // interceptor passing a known-good token explicitly).
    if (!isCredentialAttempt &&
        token != null &&
        token.isNotEmpty &&
        !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    final fingerprint = await deviceId.getFingerprint();
    options.headers['X-Device-ID'] = fingerprint;
    // Server's PlatformGuard only recognises `desktop|ios|android` —
    // sending the generic `mobile` here gets normalised to `desktop`
    // (fail-closed), which excludes the `mobile` plan (allowed_platforms
    // = ios+android) from /plans for this client. Always send the actual
    // OS so per-platform plan filtering works.
    options.headers['X-Platform'] = Platform.isIOS ? 'ios' : 'android';
    final osVersion = await _getOsVersion();
    if (osVersion != null && osVersion.isNotEmpty) {
      options.headers['X-OS-Version'] = osVersion;
    }

    handler.next(options);
  }
}

// ────────────────────────────────────────────────
// Interceptor 2 — JWT auto-refresh
// ────────────────────────────────────────────────

class _AuthRefreshInterceptor extends Interceptor {
  _AuthRefreshInterceptor({
    required this.dio,
    required this.sessionStore,
    required this.onAuthFailed,
    required this.onSessionChanged,
  });

  final Dio dio;
  final SessionStore sessionStore;
  final void Function() onAuthFailed;
  final void Function() onSessionChanged;

  /// Single in-flight refresh shared by every 401 that arrives while it's
  /// running. Without this, N concurrent 401s (typical first-foreground
  /// burst: /usage + /features + /subscription all firing together) each
  /// fire their own POST /auth/refresh. The server rotates the token on
  /// the first call so the others race a rejected stale token — second
  /// refresh 401s → forceLogout fires even though the first refresh
  /// actually succeeded, and the user gets kicked back to the login
  /// screen for no reason.
  ///
  /// The Completer resolves with the new access-token on success or null
  /// on failure (caller treats null as "refresh failed → forward original
  /// 401"). All concurrent callers await the same Completer, then retry
  /// their own request with the shared new token.
  Completer<String?>? _inFlightRefresh;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // A 401 from a credential-attempt endpoint means "wrong email/password"
    // (or rejected Google idToken) — NOT an expired session. Do NOT trigger
    // a token refresh or forceLogout here: there is no session to refresh,
    // and firing onAuthFailed() would spuriously clear state mid-login and
    // surface a confusing "session expired" instead of "invalid credentials".
    // Let the original 401 propagate so the UI shows the right message.
    if (_credentialPaths.contains(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    // Don't try to refresh if the failing request IS the refresh endpoint
    if (err.requestOptions.path == '/auth/refresh') {
      onAuthFailed();
      handler.next(err);
      return;
    }

    final newToken = await _refreshOnce();
    if (newToken == null) {
      handler.next(err);
      return;
    }

    // Retry the original request with the (shared) new token.
    try {
      final retryOptions = err.requestOptions.copyWith(
        headers: {
          ...err.requestOptions.headers,
          'Authorization': 'Bearer $newToken',
        },
      );
      final retryResponse = await dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } catch (retryError) {
      // Retry itself bombed (e.g. another non-401 error from the server).
      // Surface the retry error, not the original 401, so the upstream
      // handler knows the cause.
      if (retryError is DioException) {
        handler.next(retryError);
      } else {
        handler.next(err);
      }
    }
  }

  /// Returns the new access token, or null if the refresh failed. Callers
  /// that arrive while a refresh is already in flight await that same
  /// promise rather than firing their own.
  Future<String?> _refreshOnce() async {
    final existing = _inFlightRefresh;
    if (existing != null) {
      AppLog.d('AuthRefresh', 'Joining in-flight refresh');
      return existing.future;
    }
    final completer = Completer<String?>();
    _inFlightRefresh = completer;
    try {
      final session = await sessionStore.load();
      if (session == null) {
        onAuthFailed();
        completer.complete(null);
        return null;
      }
      AppLog.d('AuthRefresh', 'Attempting token refresh...');
      final refreshResponse = await dio.post(
        '/auth/refresh',
        options: Options(headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        }),
      );
      final newToken = refreshResponse.data['accessToken'] as String;
      // Tolerant: backend currently returns ISO 8601 string, but historically
      // returned a milliseconds-since-epoch number. A naive `as String?` on
      // the number form throws and the catch below calls onAuthFailed, which
      // looks like a silent logout to the user. Accept both shapes here so
      // future backend shape changes don't trigger the loop.
      final expiresAtRaw = refreshResponse.data['expiresAt'];
      final expiresAt = expiresAtRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(expiresAtRaw.toInt())
              .toIso8601String()
          : expiresAtRaw as String?;
      await sessionStore.save(
        session.copyWith(accessToken: newToken, expiresAt: expiresAt),
      );
      onSessionChanged();
      completer.complete(newToken);
      return newToken;
    } catch (e) {
      AppLog.w('AuthRefresh', 'Refresh failed', e);
      onAuthFailed();
      completer.complete(null);
      return null;
    } finally {
      // Clear the slot so the NEXT refresh cycle (after the current token
      // expires hours from now) starts fresh.
      _inFlightRefresh = null;
    }
  }
}

// ────────────────────────────────────────────────
// Interceptor 3 — Retry (408 / 429 / 5xx)
// ────────────────────────────────────────────────

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor({required this.dio});

  static const _maxRetries = 2;

  final Dio dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    if (!_isRetryable(status, err.response?.data)) {
      handler.next(err);
      return;
    }

    final retryCount = (err.requestOptions.extra['retryCount'] as int?) ?? 0;
    if (retryCount >= _maxRetries) {
      handler.next(err);
      return;
    }

    final delay = Duration(seconds: retryCount + 1);
    AppLog.d('Retry', 'Attempt ${retryCount + 1}/$_maxRetries after ${delay.inSeconds}s');

    await Future<void>.delayed(delay);

    final retryOptions = err.requestOptions.copyWith(
      extra: {
        ...err.requestOptions.extra,
        'retryCount': retryCount + 1,
      },
    );

    try {
      // Reuse the configured Dio so Headers/Auth interceptors re-apply.
      // Using a fresh Dio() would drop Authorization/X-Device-ID/X-Platform.
      final response = await dio.fetch(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _isRetryable(int? status, dynamic body) {
    if (status == null) return false;
    if (status == 408 || (status >= 500 && status < 600)) return true;
    if (status == 429) {
      // 429 covers both quota_exceeded (daily limit — reset at midnight,
      // retry is pure waste and adds ~6s before the paywall appears) and
      // rate_limit (short burst — back-off retry can succeed). Only retry
      // the latter.
      final code = body is Map ? (body['code'] ?? body['error']) as String? : null;
      return code != 'quota_exceeded';
    }
    return false;
  }
}

// ────────────────────────────────────────────────
// Riverpod providers
// ────────────────────────────────────────────────

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore();
});

final deviceIdProvider = Provider<DeviceIdService>((ref) {
  return DeviceIdService(
    // Match the secure-storage config used by SessionStore — see notes there.
    secureStorage: const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    deviceInfo: DeviceInfoPlugin(),
  );
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    deviceId: ref.watch(deviceIdProvider),
    sessionStore: ref.watch(sessionStoreProvider),
    onAuthFailed: () {
      ref.read(authStateProvider.notifier).forceLogout();
    },
  );
});
