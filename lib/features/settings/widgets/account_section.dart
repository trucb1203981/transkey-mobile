import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/session_store.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../upgrade/providers/usage_provider.dart';
import 'plan_badge.dart';

/// User card at the top of Settings: avatar + name + email + plan badge,
/// optional quota bar (free plan only), and primary action buttons
/// (Upgrade / Log out). Extracted from settings_screen because it owns
/// its own slice of state (usage, subscription end date formatting) and
/// kept the screen file at ~1000 LOC.
class AccountSection extends ConsumerWidget {
  const AccountSection({
    super.key,
    required this.session,
    required this.plan,
  });

  final AuthSession session;
  final String plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final t = AppLocalizations.of(context)!;
    final usage = ref.watch(usageProvider).valueOrNull;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border:
            Border.all(color: isDark ? AppColors.border : AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  _avatarInitial(session),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name ?? 'User',
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    PlanBadge(plan: plan),
                    _subscriptionLine(theme, plan, usage, t),
                  ],
                ),
              ),
            ],
          ),
          if (plan == 'free' && usage != null) ...[
            const SizedBox(height: AppSpacing.md),
            QuotaBar(
              used: usage.requestsUsed,
              limit: usage.requestsLimit,
              charsUsed: usage.charsUsed,
              charsLimit: usage.charsLimit,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _actionRow(context, ref, t),
          const SizedBox(height: AppSpacing.xs),
          _deleteAccountButton(context, ref, t),
        ],
      ),
    );
  }

  /// App Store Guideline 5.1.1(v): account deletion must be reachable
  /// in-app. Low-emphasis text button so it doesn't compete with the
  /// primary actions, but still discoverable right under them.
  Widget _deleteAccountButton(
      BuildContext context, WidgetRef ref, AppLocalizations t) {
    return TextButton(
      onPressed: () => _confirmDeleteAccount(context, ref, t),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      child: Text(
        t.accountDeleteButton,
        style: const TextStyle(
          fontSize: 12,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref, AppLocalizations t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.accountDeleteTitle),
        content: Text(t.accountDeleteWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(t.accountDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // Capture before the async gap — ref must not be used after the
    // settings screen is popped by the logout below.
    final api = ref.read(apiClientProvider);
    final auth = ref.read(authStateProvider.notifier);
    try {
      await api.dio.delete('/auth/me');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.accountDeleteFailed),
            backgroundColor: AppColors.red,
          ),
        );
      }
      return;
    }
    await auth.logout();
  }

  Widget _actionRow(BuildContext context, WidgetRef ref, AppLocalizations t) {
    final isFreeOrTrial = plan == 'free' || plan == 'trial';
    final isMobile = plan == 'mobile';
    void logout() => ref.read(authStateProvider.notifier).logout();
    final logoutButton = Expanded(
      child: OutlinedButton(
        onPressed: logout,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: const BorderSide(color: AppColors.red),
        ),
        child: Text(t.logOut),
      ),
    );
    return Row(
      children: [
        if (isFreeOrTrial)
          Expanded(
            child: ElevatedButton(
              onPressed: () => context.push('/upgrade'),
              child: Text(t.upgrade),
            ),
          ),
        if (isMobile)
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push('/upgrade'),
              child: Text(t.upgradeToPro),
            ),
          ),
        if (isFreeOrTrial || isMobile) const SizedBox(width: AppSpacing.sm),
        logoutButton,
      ],
    );
  }

  /// Subline under the plan badge: subscription type + end date (if any).
  /// Lets the user see at a glance whether they're on Mobile or Pro, and
  /// when access actually ends (for cancelled / trial users).
  Widget _subscriptionLine(
    ThemeData theme,
    String plan,
    UsageInfo? usage,
    AppLocalizations t,
  ) {
    String? typeLabel;
    String? endIso;
    if (plan == 'mobile') {
      typeLabel = t.planMobileSubscription;
      endIso = usage?.subEndsAt;
    } else if (plan == 'pro') {
      typeLabel = t.planProSubscription;
      endIso = usage?.subEndsAt;
    } else if (plan == 'trial') {
      typeLabel = t.planTrial;
      endIso = usage?.trialEndsAt;
    }
    if (typeLabel == null && endIso == null) return const SizedBox.shrink();

    final parts = <String>[
      if (typeLabel != null) typeLabel,
      if (endIso != null) t.subscriptionEndsOn(_formatIsoDate(endIso)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  String _formatIsoDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _avatarInitial(AuthSession session) {
    final source = (session.name?.trim().isNotEmpty ?? false)
        ? session.name!.trim()
        : session.email.trim();
    if (source.isEmpty) return '?';
    return source.characters.first.toUpperCase();
  }
}
