import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/subscription_provider.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final subAsync = ref.watch(subscriptionProvider);
    final plan =
        ref.watch(authStateProvider).valueOrNull?.session?.plan ?? 'free';

    return Scaffold(
      appBar: AppBar(title: Text(l.subscriptionTitle)),
      body: subAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (sub) {
          if (!sub.active && sub.status == null) {
            // Empty subscription on a paid plan = admin-granted (no LemonSqueezy
            // record). Tell the user clearly instead of the cryptic "No active
            // subscription" — they ARE on Pro, just not through self-serve
            // billing, so the cancel button wouldn't have anything to cancel.
            final isPaidPlan = plan == 'pro' || plan == 'mobile' || plan == 'trial';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaidPlan
                          ? Icons.workspace_premium_outlined
                          : Icons.info_outline,
                      size: 48,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      isPaidPlan
                          ? l.subscriptionAdminGranted
                          : l.subscriptionInactive,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(subscriptionProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _row(l.subscriptionStatus, sub.status ?? '—'),
                if (sub.renewsAt != null)
                  _row(l.subscriptionRenewsAt, _formatDate(sub.renewsAt!)),
                if (sub.endsAt != null)
                  _row(l.subscriptionEndsAt, _formatDate(sub.endsAt!)),
                if (sub.trialEndsAt != null)
                  _row(l.subscriptionTrialEndsAt,
                      _formatDate(sub.trialEndsAt!)),
                if (sub.isCancelled)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(l.subscriptionCancelled,
                        style: const TextStyle(
                          color: AppColors.amber,
                          fontWeight: FontWeight.w500,
                        )),
                  ),
                const SizedBox(height: AppSpacing.xl),
                if (sub.active && !sub.isCancelled)
                  OutlinedButton(
                    onPressed: () => _confirmCancel(context, ref, l),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: Text(l.subscriptionCancel),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _confirmCancel(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.subscriptionCancel),
        content: Text(l.subscriptionCancelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(l.confirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await ref.read(subscriptionProvider.notifier).cancel();
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.subscriptionCancelFailed),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }
}
