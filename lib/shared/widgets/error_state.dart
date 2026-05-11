import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/error_handler.dart';
import '../../shared/theme/app_theme.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
  });

  final AppError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon,
            size: 48,
            color: _color,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            error.message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: _color,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (error.action != ErrorAction.none) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => _onAction(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _color,
                ),
                child: Text(_buttonLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData get _icon {
    switch (error.action) {
      case ErrorAction.login:
        return Icons.logout;
      case ErrorAction.upgrade:
        return Icons.lock_outline;
      case ErrorAction.retry:
        return Icons.refresh;
      case ErrorAction.none:
        return Icons.error_outline;
    }
  }

  Color get _color {
    switch (error.action) {
      case ErrorAction.upgrade:
        return AppColors.primary;
      case ErrorAction.login:
        return AppColors.amber;
      case ErrorAction.retry:
        return AppColors.red;
      case ErrorAction.none:
        return AppColors.red;
    }
  }

  String get _buttonLabel {
    switch (error.action) {
      case ErrorAction.retry:
        return 'Retry';
      case ErrorAction.upgrade:
        return 'Upgrade';
      case ErrorAction.login:
        return 'Log in again';
      case ErrorAction.none:
        return '';
    }
  }

  void _onAction(BuildContext context) {
    switch (error.action) {
      case ErrorAction.retry:
        onRetry?.call();
      case ErrorAction.upgrade:
        context.push('/upgrade');
      case ErrorAction.login:
        context.go('/auth/login');
      case ErrorAction.none:
        break;
    }
  }
}
