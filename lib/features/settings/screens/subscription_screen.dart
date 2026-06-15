import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../upgrade/services/purchases_service.dart';
import '../providers/subscription_provider.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final subAsync = ref.watch(subscriptionProvider);
    final storeSub = ref.watch(storeSubscriptionProvider).valueOrNull;
    final plan =
        ref.watch(authStateProvider).valueOrNull?.session?.plan ?? 'free';

    return Scaffold(
      appBar: AppBar(title: Text(l.subscriptionTitle)),
      body: subAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint('[Subscription] load error: $e');
          return Center(child: Text(l.errorGeneric));
        },
        data: (sub) {
          if (!sub.active && sub.status == null) {
            // No LemonSqueezy record. If the user bought through Apple/Play
            // IAP, RevenueCat is the source of truth — show that subscription
            // with a deep link to the store's manage/cancel UI. An IAP
            // subscription can ONLY be cancelled in the store, never via our
            // backend, so this is the correct (and Apple-expected) path.
            if (storeSub != null && storeSub.active) {
              return _storeManagedView(context, l, storeSub);
            }
            // Otherwise: an admin-granted plan (no self-serve billing) or a
            // genuinely inactive free account. Tell the user clearly instead
            // of the cryptic "No active subscription" — they ARE on the plan,
            // just not through self-serve billing, so there's nothing to cancel.
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

  /// View for a store-managed (Apple/Play IAP) subscription. Shows the real
  /// renew/expiry date from RevenueCat and a button that deep-links to the
  /// store's subscription management (the only place an IAP sub can be
  /// changed or cancelled).
  Widget _storeManagedView(
      BuildContext context, AppLocalizations l, StoreSubscription sub) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (sub.expirationDate != null)
          _row(
            sub.willRenew ? l.subscriptionRenewsAt : l.subscriptionEndsAt,
            _formatDate(sub.expirationDate!),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l.subscriptionStoreManaged,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton(
          onPressed: () => _openStoreManagement(sub.managementUrl),
          child: Text(l.subscriptionManageButton),
        ),
      ],
    );
  }

  /// Open the store's subscription management page. Prefer RevenueCat's
  /// `managementURL`; fall back to the platform default when it's null.
  Future<void> _openStoreManagement(String? managementUrl) async {
    final url = managementUrl ??
        (Platform.isIOS
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://play.google.com/store/account/subscriptions');
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
