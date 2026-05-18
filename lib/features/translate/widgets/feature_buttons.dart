import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/translate_models.dart';

/// Five-up row of feature actions (Translate / Reply / Summarize /
/// Explain / Refine). Translate is the primary (filled purple);
/// Summarize / Explain / Refine show a lock icon for free users so the
/// gate is visible BEFORE they tap, then the host handles the upsell.
class FeatureButtons extends StatelessWidget {
  const FeatureButtons({
    super.key,
    required this.isDark,
    required this.isPro,
    required this.onAction,
  });

  final bool isDark;
  /// Drives the lock icon on summarize / explain / refine. Free users
  /// see a padlock; tapping still routes through [onAction] so the host
  /// can decide whether to gate (paywall) or proceed.
  final bool isPro;
  final void Function(TranslateMode mode) onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Row(
      children: [
        _FeatureBtn(
          icon: Icons.translate,
          label: l.translate,
          isDark: isDark,
          isPrimary: true,
          onTap: () => onAction(TranslateMode.translate),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.reply_outlined,
          label: l.reply,
          isDark: isDark,
          onTap: () => onAction(TranslateMode.reply),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.summarize_outlined,
          label: l.summarize,
          isDark: isDark,
          locked: !isPro,
          onTap: () => onAction(TranslateMode.summarize),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.lightbulb_outline,
          label: l.explain,
          isDark: isDark,
          locked: !isPro,
          onTap: () => onAction(TranslateMode.explain),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.auto_fix_high,
          label: l.refine,
          isDark: isDark,
          locked: !isPro,
          onTap: () => onAction(TranslateMode.refine),
        ),
      ],
    );
  }
}

class _FeatureBtn extends StatelessWidget {
  const _FeatureBtn({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.isPrimary = false,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final bool isPrimary;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = isPrimary
        ? Colors.white
        : (isDark
            ? AppColors.textSecondary
            : AppColors.textSecondaryLight);

    return Expanded(
      child: Material(
        color: isPrimary
            ? AppColors.primary
            : (isDark ? AppColors.surface : AppColors.surfaceLight),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              border: isPrimary
                  ? null
                  : Border.all(
                      color: isDark
                          ? AppColors.border
                          : AppColors.borderLight,
                    ),
            ),
            child: Column(
              children: [
                Icon(
                  locked ? Icons.lock_outline : icon,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
