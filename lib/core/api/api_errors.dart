import 'package:dio/dio.dart';

import '../../l10n/generated/app_localizations.dart';

enum ApiErrorCode {
  unauthorized,        // valid session expired or rejected mid-app
  invalidCredentials,  // login/register/google-mobile rejected at the door
  emailNotVerified,
  featureDisabled,
  deviceLimit,
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
    // one yet). Surface the server's specific message ("Email hoặc mật
    // khẩu không đúng") so the user knows to retry their password rather
    // than thinking they need to re-login.
    final path = err.requestOptions.path;
    final isCredentialAttempt = status == 401 && (
      path == '/auth/login' ||
      path == '/auth/register' ||
      path == '/auth/google/mobile'
    );

    switch (status) {
      case 401:
        if (isCredentialAttempt) {
          return ApiException(
            code: ApiErrorCode.invalidCredentials,
            message: (body is Map ? body['message'] as String? : null)
                ?? 'Email hoặc mật khẩu không đúng',
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
              message: body?['message'] as String? ?? 'Email chưa xác nhận',
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
    ApiErrorCode.featureDisabled           => l.errorFeatureRequiresPaid,
    ApiErrorCode.deviceLimit               => l.errorDeviceLimit,
    ApiErrorCode.mobilePlanDesktopBlocked  => l.errorMobilePlanDesktopBlocked,
    ApiErrorCode.textTooLong               => l.errorTextTooLong,
    ApiErrorCode.quotaExceeded             => l.errorQuotaExceeded,
    ApiErrorCode.rateLimit                 => l.errorRateLimit,
    ApiErrorCode.maintenance               => l.errorMaintenance,
    ApiErrorCode.network                   => l.errorNetwork,
    ApiErrorCode.unknown                   => l.errorGeneric,
  };
}
