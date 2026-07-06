import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/translate_models.dart';

/// Fraud warning shown above a translation when the server flags [ScamRisk].
/// Red for a high-confidence scam, amber for a softer caution. The reason line
/// is the server's explanation (paid plans) or a generic caution (free plans).
/// Shared by the home result card and the text-selection result sheet so both
/// look identical.
class ScamBanner extends StatelessWidget {
  const ScamBanner({super.key, required this.scamRisk});

  final ScamRisk scamRisk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final high = scamRisk.isHigh;
    final color = high ? AppColors.red : AppColors.amber;
    final title = high ? l.scamHighTitle : l.scamLowTitle;
    final detail = (scamRisk.reason != null && scamRisk.reason!.isNotEmpty)
        ? scamRisk.reason!
        : l.scamGenericHint;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_maybe_rounded, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
