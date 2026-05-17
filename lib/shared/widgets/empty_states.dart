import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: isDark ? AppColors.border : AppColors.borderLight,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.inbox_outlined,
      message: 'No translation history yet',
    );
  }
}

class GlossaryEmptyState extends StatelessWidget {
  const GlossaryEmptyState({super.key, this.onAddEntry});

  final VoidCallback? onAddEntry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.menu_book_outlined,
      message: 'Glossary is empty',
      actionLabel: onAddEntry != null ? 'Add entry' : null,
      onAction: onAddEntry,
    );
  }
}
