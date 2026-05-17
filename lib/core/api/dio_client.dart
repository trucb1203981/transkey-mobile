import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_provider.dart';
import '../auth/session_store.dart';
import '../device/device_id.dart';

String get kBaseUrl =>
    dotenv.env['TRANSKEY_API_URL'] ?? 'https://api.transkey.app';

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

  void invalidateSessionCache() {
    _cachedSession = null;
    _sessionLoaded = false;
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
    // Respect any Authorization already set on the request (e.g. refresh
    // interceptor passing a known-good token explicitly).
    if (token != null &&
        token.isNotEmpty &&
        !options.headers.containsKey('Authorization')) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    final fingerprint = await deviceId.getFingerprint();
    options.headers['X-Device-ID'] = fingerprint;
    options.headers['X-Platform'] = 'mobile';

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

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Don't try to refresh if the failing request IS the refresh endpoint
    if (err.requestOptions.path == '/auth/refresh') {
      onAuthFailed();
      handler.next(err);
      return;
    }

    try {
      final session = await sessionStore.load();
      if (session == null) {
        onAuthFailed();
        handler.next(err);
        return;
      }

      debugPrint('[AuthRefresh] Attempting token refresh...');
      final refreshResponse = await dio.post(
        '/auth/refresh',
        options: Options(headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        }),
      );

      final newToken = refreshResponse.data['accessToken'] as String;
      final expiresAt = refreshResponse.data['expiresAt'] as String?;

      await sessionStore.save(
        session.copyWith(accessToken: newToken, expiresAt: expiresAt),
      );
      onSessionChanged();

      // Retry the original request with new token
      final retryOptions = err.requestOptions.copyWith(
        headers: {
          ...err.requestOptions.headers,
          'Authorization': 'Bearer $newToken',
        },
      );

      final retryResponse = await dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } catch (e) {
      debugPrint('[AuthRefresh] Refresh failed: $e');
      onAuthFailed();
      handler.next(err);
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
    debugPrint('[Retry] Attempt ${retryCount + 1}/$_maxRetries after ${delay.inSeconds}s');

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
