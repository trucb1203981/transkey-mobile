import 'package:dio/dio.dart';

enum ApiErrorCode {
  unauthorized,
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

    final serverCode = body is Map ? body['code'] as String? : null;

    switch (status) {
      case 401:
        return const ApiException(
          code: ApiErrorCode.unauthorized,
          message: 'Session expired',
        );
      case 403:
        switch (serverCode) {
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
