import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/translate_models.dart';
import '../providers/features_provider.dart';

/// Row of feature actions (Translate / Summarize / Explain / Refine /
/// Reply) with a Camera button on the left. Translate is the primary
/// (filled purple). Mode order matches the bubble mode picker + result
/// panel tabs (BubbleService.ALL_MODES) so users see one consistent
/// ordering across home, popup, and panel. Each non-translate button
/// shows a padlock when the CURRENT user's plan doesn't enable it
/// (per [features]) so the gate is visible BEFORE they tap; the host
/// then routes through [onAction] to either run the feature or show
/// the upsell.
class FeatureButtons extends StatelessWidget {
  const FeatureButtons({
    super.key,
    required this.isDark,
    required this.features,
    required this.onAction,
    this.activeMode,
    this.onCamera,
  });

  final bool isDark;
  /// Per-feature enable map from server (`/features` endpoint). Drives
  /// the per-button padlock so the lock state matches admin config —
  /// NOT a hardcoded `isPro` check (admin can flip individual flags via
  /// /admin/features without redeploy).
  final FeatureFlags features;
  final void Function(TranslateMode mode) onAction;
  /// Currently-active mode whose button should render as primary
  /// (gradient + glow). Null means no result yet — Translate stays
  /// highlighted as the default action so cold-start users still see
  /// a clear primary affordance.
  final TranslateMode? activeMode;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final current = activeMode ?? TranslateMode.translate;
    return Row(
      children: [
        if (onCamera != null)
          _CameraBtn(
            isDark: isDark,
            locked: !features.camera,
            onTap: onCamera!,
          ),
        if (onCamera != null) const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.translate,
          label: l.translate,
          isDark: isDark,
          isPrimary: current == TranslateMode.translate,
          locked: !features.translate,
          onTap: () => onAction(TranslateMode.translate),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.summarize,
          label: l.summarize,
          isDark: isDark,
          isPrimary: current == TranslateMode.summarize,
          locked: !features.summarize,
          onTap: () => onAction(TranslateMode.summarize),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.lightbulb,
          label: l.explain,
          isDark: isDark,
          isPrimary: current == TranslateMode.explain,
          locked: !features.explain,
          onTap: () => onAction(TranslateMode.explain),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.auto_fix_high,
          label: l.refine,
          isDark: isDark,
          isPrimary: current == TranslateMode.refine,
          locked: !features.refine,
          onTap: () => onAction(TranslateMode.refine),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FeatureBtn(
          icon: Icons.reply,
          label: l.reply,
          isDark: isDark,
          isPrimary: current == TranslateMode.reply,
          locked: !features.replyTranslate,
          onTap: () => onAction(TranslateMode.reply),
        ),
      ],
    );
  }
}

class _CameraBtn extends StatelessWidget {
  const _CameraBtn({
    required this.isDark,
    required this.onTap,
    this.locked = false,
  });

  final bool isDark;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final fg = isDark ? AppColors.textSecondary : AppColors.textSecondaryLight;
    return Expanded(
      child: Material(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              border: Border.all(
                color: isDark ? AppColors.border : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.camera_alt, size: 18, color: fg),
                    if (locked)
                      const Positioned(
                        right: -6,
                        bottom: -4,
                        child: Icon(Icons.lock,
                            size: 11, color: AppColors.textSecondary),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l.cameraTitle,
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
    const purple = Color(0xFF6366F1);
    final fg = isPrimary
        ? Colors.white
        : locked
            ? purple
            : (isDark
                ? AppColors.textSecondary
                : AppColors.textSecondaryLight);

    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                )
              : locked
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF6366F1).withValues(alpha: 0.10),
                        const Color(0xFFA855F7).withValues(alpha: 0.10),
                      ],
                    )
                  : null,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: isPrimary || locked
              ? Colors.transparent
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
                        color: locked
                            ? purple.withValues(alpha: 0.4)
                            : (isDark
                                ? AppColors.border
                                : AppColors.borderLight),
                      ),
              ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    if (locked)
                      const Positioned(
                        right: -6,
                        bottom: -4,
                        child: Icon(Icons.lock,
                            size: 11, color: purple),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: locked ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
