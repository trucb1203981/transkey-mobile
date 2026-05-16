import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/selectable_with_actions.dart';
import '../../../shared/widgets/toast.dart';
import '../../translate/widgets/tts_button.dart';
import '../models/history_entry.dart';
import '../providers/history_provider.dart';

class HistoryDetailSheet extends StatelessWidget {
  const HistoryDetailSheet({super.key, required this.entry});

  final HistoryEntry entry;

  static Future<void> show(BuildContext context, {required HistoryEntry entry}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => HistoryDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l = AppLocalizations.of(context)!;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : AppColors.surfaceLight,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.sheetRadius),
            ),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.border : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    // Badges
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        _chip(
                          context,
                          '${entry.sourceLang.toUpperCase()} → ${entry.targetLang.toUpperCase()}',
                        ),
                        _chip(context, entry.mode.label, isPrimary: true),
                        if (entry.isFavorite)
                          _chip(context, l.historyDetailFavoriteBadge, color: AppColors.amber),
                        if (entry.isLocked)
                          _chip(context, l.historyDetailLockedBadge),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Source text
                    Text(
                      l.historyDetailSourceLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.bgDark : const Color(0xFFF0EDE8),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.buttonRadius),
                      ),
                      child: SelectableWithActions(
                        entry.sourceText,
                        style: theme.textTheme.bodyLarge,
                        targetLang: entry.targetLang.isNotEmpty ? entry.targetLang : 'en',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Translation
                    Text(
                      l.historyDetailTranslationLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.buttonRadius),
                      ),
                      child: SelectableWithActions(
                        entry.translation,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        targetLang: entry.targetLang.isNotEmpty ? entry.targetLang : 'en',
                      ),
                    ),

                    // Romanization
                    if (entry.romanization != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l.historyDetailRomanizationLabel,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        entry.romanization!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.xl),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _actionBtn(
                          icon: Icons.copy,
                          label: l.historyDetailCopyTranslation,
                          onTap: () => _copy(context, entry.translation),
                        ),
                        _actionBtn(
                          icon: Icons.copy_outlined,
                          label: l.historyDetailCopySource,
                          onTap: () => _copy(context, entry.sourceText),
                        ),
                        _ttsActionBtn(entry, l),
                        Consumer(builder: (context, ref, _) {
                          return _actionBtn(
                            icon: entry.isFavorite
                                ? Icons.star
                                : Icons.star_border,
                            label: entry.isFavorite
                                ? l.historyDetailUnfavorite
                                : l.historyDetailFavoriteAction,
                            color: entry.isFavorite ? AppColors.amber : null,
                            onTap: () {
                              ref
                                  .read(historyProvider.notifier)
                                  .toggleFavorite(entry.id);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        Consumer(builder: (context, ref, _) {
                          return _actionBtn(
                            icon: entry.isLocked
                                ? Icons.lock
                                : Icons.lock_open,
                            label: entry.isLocked
                                ? l.historyDetailUnlock
                                : l.historyDetailLockAction,
                            onTap: () {
                              ref
                                  .read(historyProvider.notifier)
                                  .toggleLock(entry.id);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        Consumer(builder: (context, ref, _) {
                          return _actionBtn(
                            icon: Icons.delete_outline,
                            label: l.delete,
                            color: AppColors.red,
                            onTap: () {
                              if (entry.isLocked) return;
                              ref
                                  .read(historyProvider.notifier)
                                  .delete(entry.id);
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label,
      {bool isPrimary = false, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.15) ??
            (isPrimary
                ? AppColors.primary.withValues(alpha: 0.15)
                : Theme.of(context).brightness == Brightness.dark
                    ? AppColors.border
                    : AppColors.borderLight),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color ??
              (isPrimary
                  ? AppColors.primary
                  : Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textSecondary
                      : AppColors.textSecondaryLight),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color ?? AppColors.primary),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: color ?? AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ttsActionBtn(HistoryEntry entry, AppLocalizations l) {
    return InkWell(
      onTap: () {
        // TtsButton handles tap internally, but this provides the outer tap area
      },
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TtsButton(
              text: entry.translation,
              lang: entry.targetLang.isNotEmpty ? entry.targetLang : 'en',
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              l.historyDetailTtsLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    // Use overlay-based toast instead of SnackBar — the sheet's own backdrop
    // hides any SnackBar that anchors to the parent Scaffold below it, so
    // the user gets no feedback that the copy succeeded.
    showAppToast(context, AppLocalizations.of(context)!.copied);
  }
}
