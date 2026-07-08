import 'package:flutter/material.dart';

import '../../../shared/theme/app_glass.dart';
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
    final p = GlassPalette.forDark(isDark);

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
          decoration: AppGlass.card(isDark: isDark, shadow: false),
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
                    Icon(Icons.lock, size: 12, color: p.textTertiary),
                  ],
                  const Spacer(),
                  Text(
                    _formatDate(entry.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Source text (2 lines) — the "before"; dimmer than the result.
              Text(
                entry.sourceText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),

              // Translation (2 lines) — the result; bright so it reads clearly
              // over the glass (indigo-on-violet-tint was too low-contrast).
              Text(
                entry.translation,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
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
    final p = GlassPalette.forDark(isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPrimary
            ? AppGlass.gradStart.withValues(alpha: 0.22)
            : p.fillStrong,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPrimary ? p.accentStrong : p.textSecondary,
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
