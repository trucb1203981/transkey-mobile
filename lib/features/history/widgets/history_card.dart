import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/history_entry.dart';
import 'history_detail_sheet.dart';

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.entry,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: entry.isLocked
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onToggleFavorite();
          return false;
        }
        if (entry.isLocked) return false;
        return true;
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.md),
        color: AppColors.amber.withValues(alpha: 0.2),
        child: Icon(
          entry.isFavorite ? Icons.star : Icons.star_border,
          color: AppColors.amber,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        color: entry.isLocked
            ? AppColors.textSecondary.withValues(alpha: 0.2)
            : AppColors.red.withValues(alpha: 0.2),
        child: Icon(
          entry.isLocked ? Icons.lock : Icons.delete_outline,
          color: entry.isLocked ? AppColors.textSecondary : AppColors.red,
        ),
      ),
      child: InkWell(
        onTap: () => HistoryDetailSheet.show(context, entry: entry),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badges row
              Row(
                children: [
                  _badge(
                    context,
                    _langLabel(entry.sourceLang, entry.targetLang),
                    isDark,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _badge(context, entry.mode.label, isDark, isPrimary: true),
                  if (entry.isFavorite) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.star, size: 14, color: AppColors.amber),
                  ],
                  if (entry.isLocked) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.lock, size: 12, color: AppColors.textSecondary),
                  ],
                  const Spacer(),
                  Text(
                    _formatDate(entry.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondary
                          : AppColors.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Source text (2 lines)
              Text(
                entry.sourceText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondary
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),

              // Translation (2 lines, primary color)
              Text(
                entry.translation,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String label, bool isDark,
      {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPrimary
            ? AppColors.primary.withValues(alpha: 0.15)
            : (isDark ? AppColors.border : AppColors.borderLight),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPrimary ? AppColors.primary : null,
        ),
      ),
    );
  }

  String _langLabel(String source, String target) {
    if (source.isEmpty && target.isEmpty) return '';
    final s = source.isEmpty ? 'Auto' : source.toUpperCase();
    final t = target.isEmpty ? '' : target.toUpperCase();
    if (t.isEmpty) return s;
    return '$s → $t';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }
}
