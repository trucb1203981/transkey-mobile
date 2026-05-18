import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The small horizontal pill rendered at the top of bottom sheets, used
/// as a visual affordance that the sheet can be dragged. Matches Material
/// 3's drag handle styling. Extracted from upgrade_nudge_sheet.dart so
/// other sheets (option picker, language picker, etc.) can share it
/// without depending on the upgrade screen.
class DragHandle extends StatelessWidget {
  const DragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.border : AppColors.borderLight,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
