import 'package:dio/dio.dart';

import 'api_errors.dart';

enum ErrorAction { none, retry, upgrade, login }

class AppError {
  const AppError({
    required this.message,
    this.action = ErrorAction.none,
  });

  final String message;
  final ErrorAction action;

  factory AppError.fromDio(DioException err) {
    final api = ApiException.fromDio(err);
    return AppError.fromApiException(api);
  }

  factory AppError.fromApiException(ApiException err) {
    switch (err.code) {
      case ApiErrorCode.unauthorized:
        return const AppError(
          message: 'Session expired',
          action: ErrorAction.login,
        );
      case ApiErrorCode.emailNotVerified:
        return const AppError(
          message: 'Email not verified. Please check your inbox.',
        );
      case ApiErrorCode.featureDisabled:
        return const AppError(
          message: 'Requires Mobile (\$3) or Pro (\$6) plan',
          action: ErrorAction.upgrade,
        );
      case ApiErrorCode.deviceLimit:
        return const AppError(
          message: 'Device limit reached. Upgrade to add more.',
          action: ErrorAction.upgrade,
        );
      case ApiErrorCode.textTooLong:
        return const AppError(
          message: 'Text too long (max 5000 characters)',
        );
      case ApiErrorCode.quotaExceeded:
        return const AppError(
          message: 'Daily limit reached. Upgrade for more.',
          action: ErrorAction.upgrade,
        );
      case ApiErrorCode.rateLimit:
        return const AppError(
          message: 'Too many requests. Try again in a moment.',
          action: ErrorAction.retry,
        );
      case ApiErrorCode.maintenance:
        return const AppError(
          message: 'Service under maintenance',
          action: ErrorAction.retry,
        );
      case ApiErrorCode.network:
        return const AppError(
          message: 'No internet connection',
          action: ErrorAction.retry,
        );
      case ApiErrorCode.mobilePlanDesktopBlocked:
        return const AppError(
          message: 'Mobile plan only works on mobile devices',
        );
      case ApiErrorCode.unknown:
        return AppError(message: err.message);
    }
  }
}
