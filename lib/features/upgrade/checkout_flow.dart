import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/dio_client.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/tracking/tracking_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import 'services/purchases_service.dart';

/// Single checkout entry point shared by every upgrade surface (the full
/// upgrade screen AND the feature-lock nudge sheet). On Android with
/// RevenueCat ready it routes through Google Play Billing; everywhere else
/// (iOS, desktop, web, or RC not configured) it falls back to the
/// LemonSqueezy web checkout.
///
/// This lives in one place on purpose: a second checkout path (the nudge
/// sheet) had kept calling LemonSqueezy directly on Android, so tapping a
/// paid feature opened a web browser instead of Play Billing. Centralising
/// the branch prevents that drift.
Future<void> startPlanCheckout(
  BuildContext context,
  WidgetRef ref,
  String plan,
) async {
  final l = AppLocalizations.of(context)!;

  if ((Platform.isAndroid || Platform.isIOS) && PurchasesService.isReady) {
    await _checkoutViaRevenueCat(context, ref, plan, l);
    return;
  }

  // App Store guideline 3.1.1: digital plans on iOS MUST go through Apple
  // IAP. If RC isn't configured, fail with an error — opening the web
  // checkout here is an instant review rejection.
  if (Platform.isIOS) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.upgradeCheckoutFailed), backgroundColor: AppColors.red),
    );
    return;
  }

  // LemonSqueezy web checkout — desktop / web / Android without RC.
  try {
    final api = ref.read(apiClientProvider);
    final response =
        await api.dio.get('/auth/checkout', queryParameters: {'plan': plan});
    final url = response.data['url'] as String?;
    if (url != null) await launchUrl(Uri.parse(url));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.upgradeCheckoutFailed), backgroundColor: AppColors.red),
      );
    }
  }
}

/// Restore previously-purchased subscriptions (Play policy requirement).
/// No-op fallback when RC isn't ready (iOS / pre-config).
Future<void> restorePlanPurchases(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context)!;
  if (!PurchasesService.isReady) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.upgradeCheckoutFailed)),
    );
    return;
  }
  try {
    final info = await PurchasesService.restorePurchases();
    await ref.read(authStateProvider.notifier).refreshUser();
    if (!context.mounted) return;
    final restoredAny = info.entitlements.active.isNotEmpty;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(
        restoredAny ? l.upgradeRestoreSuccess : l.upgradeRestoreNothing,
      )),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.upgradeCheckoutFailed), backgroundColor: AppColors.red),
      );
    }
  }
}

/// Android-only RevenueCat -> Google Play Billing path.
///
/// Prefers the dashboard "current" offering, falling back to the one named
/// `default`, then any offering, so a missed "Set current" toggle in the
/// RevenueCat dashboard doesn't dead-end the flow. Filters packages by the
/// plan-name prefix (`mobile_*` / `pro_*`) so the same Mobile / Pro button
/// reaches the right sub-options; one match buys directly, multiple shows
/// the period picker. After a successful purchase, refreshes /auth/me so the
/// new plan (already set server-side by the RevenueCat webhook) lands in
/// local state.
Future<void> _checkoutViaRevenueCat(
  BuildContext context,
  WidgetRef ref,
  String plan,
  AppLocalizations l,
) async {
  // Capture provider references up front. The success path pops this sheet
  // (Navigator.maybePop below) before the 4s background refresh runs, so the
  // WidgetRef is no longer usable by then. These notifier/service objects are
  // app-scoped (non-autoDispose) and stay valid for the app lifetime, so the
  // background work + error tracking use them instead of `ref` — otherwise
  // "Cannot use ref after the widget was disposed" crashes the zone guard.
  final authNotifier = ref.read(authStateProvider.notifier);
  final tracking = ref.read(trackingServiceProvider);
  try {
    final offerings = await PurchasesService.getOfferings();
    final offering = offerings?.current
        ?? offerings?.all['default']
        ?? (offerings != null && offerings.all.isNotEmpty
            ? offerings.all.values.first
            : null);
    if (offering == null) {
      throw StateError('No RevenueCat offering available');
    }
    final packages = offering.availablePackages
        .where((p) => p.storeProduct.identifier.startsWith('${plan}_'))
        .toList();
    if (packages.isEmpty) {
      throw StateError('No packages match plan "$plan"');
    }

    if (!context.mounted) return;
    final Package? chosen = packages.length == 1
        ? packages.first
        : await _showPackagePicker(context, packages, plan);
    if (chosen == null) return; // user dismissed picker — silent no-op

    tracking.event('upgrade_purchase_start',
        properties: {'plan': plan, 'product_id': chosen.storeProduct.identifier});

    final info = await PurchasesService.purchasePackage(chosen);
    if (info == null) {
      tracking.event('upgrade_purchase_cancel',
          properties: {'plan': plan, 'product_id': chosen.storeProduct.identifier});
      return;
    }

    // RC SDK has already verified the purchase with Play Billing before
    // returning this CustomerInfo, so the entitlements are authoritative
    // RIGHT NOW. Update the local session optimistically so the UI flips off
    // 'free' the instant the snackbar appears — otherwise the user sits on
    // 'free' for 1-3s while our backend webhook handler processes, which
    // feels like a scam ("I paid and nothing happened"). The background
    // refresh below then syncs server-side fields (sub_ends_at, billing
    // dates) once the webhook lands.
    final expected = info.entitlements.active.containsKey('pro')
        ? 'pro'
        : info.entitlements.active.containsKey('mobile')
            ? 'mobile'
            : null;
    final session = authNotifier.currentSession;
    if (session != null && expected != null && session.plan != expected) {
      await authNotifier.updateSession(session.copyWith(plan: expected));
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.upgradePurchaseSuccess)),
    );
    Navigator.of(context).maybePop();

    // Background: sync server-side state after the webhook has had time to
    // land. If the backend somehow still shows the old plan (webhook stuck
    // / slow), re-apply the optimistic plan so the UI doesn't regress —
    // the next launch's /auth/me will normalize when the webhook eventually
    // finishes.
    unawaited(Future.delayed(const Duration(seconds: 4), () async {
      await authNotifier.refreshUser();
      final s = authNotifier.currentSession;
      if (s != null && expected != null && s.plan != expected) {
        await authNotifier.updateSession(s.copyWith(plan: expected));
      }
    }));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.upgradeCheckoutFailed), backgroundColor: AppColors.red),
      );
    }
    tracking.event('upgrade_purchase_fail',
        properties: {'plan': plan, 'error': e.runtimeType.toString()});
  }
}

/// Play appends the app name in parentheses, e.g. "Mobile Monthly (TransKey -
/// AI translate)". Strip a trailing parenthetical so the picker shows just the
/// plan/period name instead of wrapping onto two cramped lines.
String _cleanProductTitle(String raw) {
  final cleaned = raw.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  return cleaned.isNotEmpty ? cleaned : raw;
}

/// Bottom sheet to pick a billing period when a plan has more than one
/// package (mobile weekly vs monthly, pro monthly vs yearly). Returns the
/// chosen [Package] or null if dismissed.
Future<Package?> _showPackagePicker(
  BuildContext context,
  List<Package> packages,
  String plan,
) {
  return showModalBottomSheet<Package>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              plan == 'pro'
                  ? AppLocalizations.of(sheetCtx)!.upgradePickProPeriod
                  : AppLocalizations.of(sheetCtx)!.upgradePickMobilePeriod,
              style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final pkg in packages) ...[
              OutlinedButton(
                onPressed: () => Navigator.of(sheetCtx).pop(pkg),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pkg.storeProduct.title.isNotEmpty
                                ? _cleanProductTitle(pkg.storeProduct.title)
                                : pkg.storeProduct.identifier,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                          if (pkg.storeProduct.description.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              pkg.storeProduct.description,
                              style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Text(
                      pkg.storeProduct.priceString,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    ),
  );
}
