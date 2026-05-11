import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';
import 'upgrade_nudge_sheet.dart';

/// Wraps a child widget. If [locked] is true, shows it at 40% opacity
/// with a lock icon overlay. Tapping it opens [UpgradeNudgeSheet].
class FeatureGate extends StatelessWidget {
  const FeatureGate({
    super.key,
    required this.child,
    required this.featureName,
    this.locked = false,
  });

  final Widget child;
  final String featureName;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;

    return Opacity(
      opacity: 0.4,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                onTap: () => UpgradeNudgeSheet.show(
                  context,
                  featureName: featureName,
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
