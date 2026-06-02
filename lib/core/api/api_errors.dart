import 'package:dio/dio.dart';

import '../../l10n/generated/app_localizations.dart';

enum ApiErrorCode {
  unauthorized,        // valid session expired or rejected mid-app
  invalidCredentials,  // login/register/google-mobile rejected at the door
  emailNotVerified,
  emailAlreadyExists,  // register: email already has an account
  wrongPassword,       // change-password: current password is incorrect
  featureDisabled,
  deviceLimit,         // free plan: too many free accounts from this device
  proDeviceLimit,      // pro plan: already registered on 2 devices
  mobilePlanDesktopBlocked,
  textTooLong,
  quotaExceeded,
  rateLimit,
  maintenance,
  network,
  unknown,
}

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final ApiErrorCode code;
  final String message;
  final int? statusCode;

  /// Pull a plain string out of an error body's `message`. NestJS hand-thrown
  /// errors use a String; class-validator DTO failures use a List of strings.
  /// Returns null when there's nothing usable (so callers apply their fallback).
  static String? _flattenMessage(dynamic body) {
    if (body is! Map) return null;
    final m = body['message'];
    if (m is String && m.isNotEmpty) return m;
    if (m is List && m.isNotEmpty) return m.map((e) => e.toString()).join('\n');
    return null;
  }

  factory ApiException.fromDio(DioException err) {
    final status = err.response?.statusCode;
    final body = err.response?.data;

    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.unknown) {
      return const ApiException(
        code: ApiErrorCode.network,
        message: 'No internet connection',
      );
    }

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        code: ApiErrorCode.network,
        message: 'Connection timed out',
      );
    }

    final serverCode = body is Map
        ? (body['code'] as String? ?? body['error'] as String?)
        : null;

    // 401 on the auth-entry endpoints means "we don't believe these
    // credentials" — NOT "your session expired" (the user doesn't have
    // one yet). Map it to invalidCredentials so the UI shows the localized
    // "wrong email or password" copy instead of a re-login prompt.
    final path = err.requestOptions.path;
    final isCredentialAttempt = status == 401 && (
      path == '/auth/login' ||
      path == '/auth/register' ||
      path == '/auth/google/mobile'
    );

    switch (status) {
      case 400:
        if (serverCode == 'wrong_password') {
          return const ApiException(
            code: ApiErrorCode.wrongPassword,
            message: 'Current password is incorrect',
          );
        }
        // class-validator DTO failures return `message` as a List of
        // strings; flatten it (or take the plain string) so we never
        // cast-crash on the body.
        return ApiException(
          code: ApiErrorCode.unknown,
          message: _flattenMessage(body) ?? 'Invalid request',
          statusCode: status,
        );
      case 401:
        if (isCredentialAttempt) {
          return ApiException(
            code: ApiErrorCode.invalidCredentials,
            message: (body is Map ? body['message'] as String? : null)
                ?? 'Wrong email or password',
            statusCode: status,
          );
        }
        return const ApiException(
          code: ApiErrorCode.unauthorized,
          message: 'Session expired',
        );
      case 403:
        switch (serverCode) {
          case 'email_not_verified':
            return ApiException(
              code: ApiErrorCode.emailNotVerified,
              message: body?['message'] as String? ?? 'Please verify your email',
            );
          case 'feature_disabled':
            return const ApiException(
              code: ApiErrorCode.featureDisabled,
              message: 'This feature requires a paid plan',
            );
          case 'device_limit':
            return const ApiException(
              code: ApiErrorCode.deviceLimit,
              message: 'Too many devices on free plan',
            );
          case 'pro_device_limit':
            return const ApiException(
              code: ApiErrorCode.proDeviceLimit,
              message: 'Pro account already registered on 2 devices',
            );
          case 'mobile_plan_desktop_blocked':
            return const ApiException(
              code: ApiErrorCode.mobilePlanDesktopBlocked,
              message: 'Mobile plan cannot be used on desktop',
            );
          default:
            return ApiException(
              code: ApiErrorCode.unknown,
              message: body?['message'] ?? 'Forbidden',
              statusCode: status,
            );
        }
      case 409:
        if (serverCode == 'email_already_exists') {
          return const ApiException(
            code: ApiErrorCode.emailAlreadyExists,
            message: 'This email is already registered',
          );
        }
        return ApiException(
          code: ApiErrorCode.unknown,
          message: _flattenMessage(body) ?? 'Conflict',
          statusCode: status,
        );
      case 413:
        return const ApiException(
          code: ApiErrorCode.textTooLong,
          message: 'Text is too long',
        );
      case 429:
        if (serverCode == 'quota_exceeded') {
          return const ApiException(
            code: ApiErrorCode.quotaExceeded,
            message: 'Daily quota exceeded',
          );
        }
        return const ApiException(
          code: ApiErrorCode.rateLimit,
          message: 'Too many requests. Please wait a moment',
        );
      case 503:
        return const ApiException(
          code: ApiErrorCode.maintenance,
          message: 'Service is under maintenance',
        );
      default:
        return ApiException(
          code: ApiErrorCode.unknown,
          message: body?['message'] ?? err.message ?? 'Unknown error',
          statusCode: status,
        );
    }
  }

  bool get requiresUpgrade =>
      code == ApiErrorCode.featureDisabled || code == ApiErrorCode.deviceLimit;

  bool get requiresAuth => code == ApiErrorCode.unauthorized;

  bool get isRetryable =>
      code == ApiErrorCode.rateLimit ||
      code == ApiErrorCode.network ||
      code == ApiErrorCode.maintenance;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Map an [ApiErrorCode] to its localized user-facing string. The
/// `message` field on ApiException is an English fallback (set when the
/// exception is constructed without UI context — e.g. inside an
/// interceptor or background isolate); UI render paths should prefer
/// `code.localize(l)` so the string respects the user's app locale.
extension ApiErrorCodeL on ApiErrorCode {
  String localize(AppLocalizations l) => switch (this) {
    ApiErrorCode.unauthorized              => l.errorSessionExpired,
    ApiErrorCode.invalidCredentials        => l.errorInvalidCredentials,
    ApiErrorCode.emailNotVerified          => l.errorEmailNotVerified,
    ApiErrorCode.emailAlreadyExists        => l.errorEmailAlreadyExists,
    ApiErrorCode.wrongPassword             => l.errorWrongPassword,
    ApiErrorCode.featureDisabled           => l.errorFeatureRequiresPaid,
    ApiErrorCode.deviceLimit               => l.errorDeviceLimit,
    ApiErrorCode.proDeviceLimit            => l.proDeviceLimitError,
    ApiErrorCode.mobilePlanDesktopBlocked  => l.errorMobilePlanDesktopBlocked,
    ApiErrorCode.textTooLong               => l.errorTextTooLong,
    ApiErrorCode.quotaExceeded             => l.errorQuotaExceeded,
    ApiErrorCode.rateLimit                 => l.errorRateLimit,
    ApiErrorCode.maintenance               => l.errorMaintenance,
    ApiErrorCode.network                   => l.errorNetwork,
    ApiErrorCode.unknown                   => l.errorGeneric,
  };
}
