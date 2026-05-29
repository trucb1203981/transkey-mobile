import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.tagline,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? tagline;
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
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.12),
                    const Color(0xFFA855F7).withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                ).createShader(bounds),
                child: Icon(
                  icon,
                  size: 44,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.textPrimary
                    : AppColors.textPrimaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            if (tagline != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                tagline!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondary
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(
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
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.history_rounded,
      message: l.historyEmpty,
      tagline: l.historyEmptyTagline,
    );
  }
}

class GlossaryEmptyState extends StatelessWidget {
  const GlossaryEmptyState({super.key, this.onAddEntry});

  final VoidCallback? onAddEntry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.menu_book_rounded,
      message: l.glossaryEmpty,
      tagline: l.glossaryEmptyTagline,
      actionLabel: onAddEntry != null ? l.glossaryEmptyAddCta : null,
      onAction: onAddEntry,
    );
  }
}
