import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../features/upgrade/providers/usage_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Surface plan-state info the user needs to act on:
///   - Trial countdown ("ends in 3 days") — promotes upgrade before expiry
///   - Subscription expired — user thought they were Pro, surprise downgrade
///
/// Banned plan has its own full-screen handling elsewhere — this widget
/// stays lightweight and inline-friendly.
class PlanStatusBanner extends ConsumerWidget {
  const PlanStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final session = ref.watch(authStateProvider).valueOrNull?.session;
    final usage = ref.watch(usageProvider).valueOrNull;

    if (session == null || usage == null) return const SizedBox.shrink();

    // Subscription expired takes priority — most critical state.
    if (usage.subExpired) {
      return _Banner(
        icon: Icons.warning_amber_rounded,
        bg: AppColors.red.withValues(alpha: 0.1),
        fg: AppColors.red,
        text: l.subscriptionExpiredBanner,
        cta: l.subscriptionExpiredRenew,
        onTap: () => context.push('/upgrade'),
      );
    }

    // Trial countdown — only when plan == trial AND trialEndsAt parseable.
    if (session.plan == 'trial' && usage.trialEndsAt != null) {
      final daysLeft = _daysUntil(usage.trialEndsAt!);
      if (daysLeft == null) return const SizedBox.shrink();
      final isUrgent = daysLeft <= 1;
      final label = switch (daysLeft) {
        <= 0 => l.trialEndsToday,
        1 => l.trialEndsTomorrow,
        _ => l.trialEndsInDays(daysLeft),
      };
      return _Banner(
        icon: Icons.schedule,
        bg: isUrgent
            ? AppColors.red.withValues(alpha: 0.1)
            : AppColors.amber.withValues(alpha: 0.12),
        fg: isUrgent ? AppColors.red : AppColors.amber,
        text: label,
        cta: l.trialUpgradeNow,
        onTap: () => context.push('/upgrade'),
      );
    }

    return const SizedBox.shrink();
  }

  /// Number of full days from now until [iso]. Negative or 0 means expired.
  /// Returns null on parse failure so the caller can skip rendering.
  static int? _daysUntil(String iso) {
    try {
      final end = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = end.difference(now);
      // Round towards "today" — 23h59m left should still read as today, not 0.
      return diff.inHours ~/ 24;
    } catch (_) {
      return null;
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.text,
    required this.cta,
    required this.onTap,
  });

  final IconData icon;
  final Color bg;
  final Color fg;
  final String text;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                cta,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: fg, size: 18),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
