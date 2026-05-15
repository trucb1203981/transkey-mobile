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
  });

  final int used;
  final int limit;
  final int? charsUsed;
  final int? charsLimit;

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
    final isDark = theme.brightness == Brightness.dark;
    final ratio = limit > 0 ? used / limit : 0.0;

    return GestureDetector(
      onTap: _isWarning ? () => context.push('/upgrade') : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : AppColors.surfaceLight,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.border : AppColors.borderLight,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    backgroundColor:
                        isDark ? AppColors.border : AppColors.borderLight,
                    valueColor: AlwaysStoppedAnimation<Color>(_barColor),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppLocalizations.of(context)!.usageRequests(used, limit),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isWarning ? _barColor : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
                  fontSize: 11,
                  fontWeight: _isWarning ? FontWeight.w600 : null,
                ),
              ),
              if (charsUsed != null && charsLimit != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppLocalizations.of(context)!.usageCharacters(charsUsed!, charsLimit!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _isWarning ? _barColor : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
                    fontSize: 11,
                    fontWeight: _isWarning ? FontWeight.w600 : null,
                  ),
                ),
              ],
              if (_isWarning) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.arrow_forward_ios, size: 12, color: _barColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
