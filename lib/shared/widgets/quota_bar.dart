import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';

class QuotaBar extends StatelessWidget {
  const QuotaBar({
    super.key,
    required this.used,
    required this.limit,
    this.charsUsed,
    this.charsLimit,
    this.onWatchAd,
    this.isWatchingAd = false,
  });

  final int used;
  final int limit;
  final int? charsUsed;
  final int? charsLimit;
  /// When non-null, render a "+Ad" affordance the user can tap to
  /// proactively top up their daily quota without first hitting the
  /// 429 wall. Parent supplies the actual rewarded-ad flow.
  final VoidCallback? onWatchAd;
  /// Disable the "+Ad" affordance while an ad is loading / playing so
  /// rapid taps don't queue multiple grants.
  final bool isWatchingAd;

  Color get _barColor {
    final ratio = limit > 0 ? used / limit : 0.0;
    if (ratio > 0.95) return AppColors.red;
    if (ratio > 0.80) return AppColors.amber;
    return AppColors.primary;
  }

  bool get _isWarning => limit > 0 && (used / limit) > 0.80;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final ratio = limit > 0 ? used / limit : 0.0;
    final charsRatio = (charsLimit != null && charsLimit! > 0 && charsUsed != null)
        ? (charsUsed! / charsLimit!).clamp(0.0, 1.0)
        : null;

    return GestureDetector(
      onTap: _isWarning ? () => context.push('/upgrade') : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surface
              : const Color(0xFF6366F1).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: _isWarning
                ? _barColor.withValues(alpha: 0.4)
                : const Color(0xFF6366F1).withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_outlined, size: 16, color: _barColor),
                const SizedBox(width: 4),
                Text(
                  l.quotaTodayUsage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const Spacer(),
                if (onWatchAd != null)
                  InkWell(
                    onTap: isWatchingAd ? null : onWatchAd,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isWatchingAd
                                ? Icons.hourglass_top
                                : Icons.play_circle_outline,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            l.quotaWatchAd,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isWarning) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 11, color: _barColor),
                ],
              ],
            ),
            const SizedBox(height: 6),
            _MetricRow(
              icon: Icons.translate,
              label: l.usageRequests(used, limit),
              value: ratio.clamp(0.0, 1.0),
              color: _barColor,
              isDark: isDark,
              warning: _isWarning,
            ),
            if (charsRatio != null) ...[
              const SizedBox(height: 6),
              _MetricRow(
                icon: Icons.text_fields,
                label: l.usageCharacters(charsUsed!, charsLimit!),
                value: charsRatio,
                color: _barColor,
                isDark: isDark,
                warning: _isWarning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
    required this.warning,
  });

  final IconData icon;
  final String label;
  final double value;
  final Color color;
  final bool isDark;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 12,
            color: isDark
                ? AppColors.textSecondary
                : AppColors.textSecondaryLight),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor:
                  isDark ? AppColors.border : AppColors.borderLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: warning
                ? color
                : (isDark
                    ? AppColors.textSecondary
                    : AppColors.textSecondaryLight),
            fontSize: 11,
            fontWeight: warning ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
