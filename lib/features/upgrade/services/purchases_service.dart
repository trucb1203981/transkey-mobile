import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/diagnostics/app_log.dart';

/// Thin wrapper around RevenueCat's `purchases_flutter` SDK for Google Play
/// Billing on Android. The RevenueCat dashboard is configured to map our
/// Play subscription products onto two entitlements named `mobile` and `pro`
/// — those names line up 1:1 with the TransKey users.plan column, so the
/// backend webhook (api/src/revenuecat) just reads `entitlement_ids[0]` to
/// update the user's plan.
///
/// Why this service exists (vs calling `Purchases.*` directly):
///  - `init()` is a no-op when REVENUECAT_API_KEY_ANDROID is missing or
///    still a placeholder, so a fresh clone / staging build without RC
///    credentials still runs. Callers check `isReady` before showing UI.
///  - `syncAuth()` normalises the logIn/logOut split — call it with the
///    TransKey users.id (string) on login, with null on logout.
///  - The SDK throws `PurchasesErrorCode.purchaseCancelledError` on user
///    cancel; we surface that as `null` from [purchasePackage] so callers
///    don't have to import the platform exception type just to check it.
/// A store (Apple App Store / Google Play) subscription as RevenueCat sees
/// it. Used by the subscription management screen to show the real status +
/// a deep link to the store's manage/cancel UI for users who bought through
/// IAP — those users have NO LemonSqueezy record, so the backend
/// `/auth/subscription` is empty for them and can't drive that screen.
class StoreSubscription {
  const StoreSubscription({
    required this.active,
    this.entitlementId,
    this.expirationDate,
    this.willRenew = false,
    this.managementUrl,
  });

  final bool active;
  final String? entitlementId; // 'mobile' | 'pro'
  final String? expirationDate; // ISO-8601, null for lifetime
  final bool willRenew;
  final String? managementUrl; // store-specific manage/cancel URL, may be null
}

class PurchasesService {
  PurchasesService._();

  static bool _configured = false;

  /// True when [init] completed successfully and we can call SDK methods.
  /// False before the first init, on platforms we haven't provisioned, or
  /// when the API key env var is unset / still a placeholder.
  static bool get isReady => _configured;

  /// Initialise the RevenueCat SDK. Safe to call multiple times — the
  /// second call short-circuits via the `_configured` flag. Call from
  /// `main()` AFTER `dotenv.load()` has run.
  static Future<void> init() async {
    if (_configured) return;

    // Android -> Google Play Billing, iOS -> Apple In-App Purchase. Both go
    // through the same RC entitlements (mobile/pro) and the same backend
    // webhook, so everything past init is store-agnostic.
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final envKey = Platform.isAndroid
        ? 'REVENUECAT_API_KEY_ANDROID'
        : 'REVENUECAT_API_KEY_IOS';
    final key = dotenv.env[envKey];
    if (key == null || key.isEmpty || key.startsWith('REPLACE_')) {
      AppLog.w('RC', '$envKey not set — billing disabled');
      return;
    }

    try {
      await Purchases.setLogLevel(LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
      AppLog.i('RC', 'configured (${Platform.isAndroid ? 'Android' : 'iOS'})');
    } catch (e) {
      AppLog.w('RC', 'configure failed', e);
    }
  }

  /// Tell RevenueCat which TransKey user owns the current device.
  /// - `userId` non-null/non-empty → `Purchases.logIn(userId)` so any
  ///   subsequent purchase event reaches our webhook with our user id as
  ///   `app_user_id` (the backend just parses it to int and updates that
  ///   user's plan).
  /// - `userId` null → `Purchases.logOut()` so RC reverts to an anonymous
  ///   id; prevents leaking the previous user's purchases to a new login.
  ///
  /// Safe no-op when [isReady] is false.
  static Future<void> syncAuth(String? userId) async {
    if (!_configured) return;
    try {
      if (userId == null || userId.isEmpty) {
        await Purchases.logOut();
      } else {
        await Purchases.logIn(userId);
      }
    } catch (e) {
      AppLog.w('RC', 'syncAuth($userId) failed', e);
    }
  }

  /// Fetch the offerings configured in the RevenueCat dashboard. The SDK
  /// caches the result for the rest of the session — callers can invoke
  /// freely. Returns null when RC isn't ready or the offering fetch fails.
  static Future<Offerings?> getOfferings() async {
    if (!_configured) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      AppLog.w('RC', 'getOfferings failed', e);
      return null;
    }
  }

  /// Localized, store-charged MONTHLY price per plan, keyed by plan name
  /// ('mobile' / 'pro'), read from the current RevenueCat offering — e.g.
  /// `{'mobile': '$4.99', 'pro': '$7.99'}` in the US, `{'mobile': '₫119.000'}`
  /// in Vietnam. The plan cards prefer this over the server's USD reference
  /// price so the displayed amount + currency always match what Apple / Play
  /// actually charges (App Store doesn't allow showing a price that differs
  /// from the StoreKit price). Empty when RC isn't ready or no monthly
  /// product is found — callers fall back to the server price.
  static Future<Map<String, String>> monthlyPriceStrings() async {
    if (!_configured) return {};
    final offerings = await getOfferings();
    final offering = offerings?.current
        ?? offerings?.all['default']
        ?? (offerings != null && offerings.all.isNotEmpty
            ? offerings.all.values.first
            : null);
    if (offering == null) return {};
    final out = <String, String>{};
    for (final pkg in offering.availablePackages) {
      final id = pkg.storeProduct.identifier;
      if (id == 'mobile_monthly') {
        out['mobile'] = pkg.storeProduct.priceString;
      } else if (id == 'pro_monthly') {
        out['pro'] = pkg.storeProduct.priceString;
      }
    }
    return out;
  }

  /// Buy a package. Returns the post-purchase [CustomerInfo] on success,
  /// `null` when the user cancels the native Play Billing sheet, or
  /// rethrows for any other error so the caller can show an error toast.
  static Future<CustomerInfo?> purchasePackage(Package pkg) async {
    try {
      // purchases_flutter 8.x returns CustomerInfo directly (no wrapper).
      return await Purchases.purchasePackage(pkg);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        // User dismissed the Play Billing sheet — not an error, not a
        // success. Caller treats null as "nothing happened".
        return null;
      }
      rethrow;
    }
  }

  /// Read the current user's store subscription from RevenueCat. Returns
  /// null when RC isn't ready or the lookup fails; otherwise a
  /// [StoreSubscription] whose `active` reflects whether a `mobile`/`pro`
  /// entitlement is currently active. `managementUrl` deep-links to the
  /// store's subscription management (the only place an Apple/Play
  /// subscription can actually be cancelled).
  static Future<StoreSubscription?> storeSubscription() async {
    if (!_configured) return null;
    try {
      final info = await Purchases.getCustomerInfo();
      final ent =
          info.entitlements.active['pro'] ?? info.entitlements.active['mobile'];
      return StoreSubscription(
        active: ent != null,
        entitlementId: ent?.identifier,
        expirationDate: ent?.expirationDate,
        willRenew: ent?.willRenew ?? false,
        managementUrl: info.managementURL,
      );
    } catch (e) {
      AppLog.w('RC', 'storeSubscription failed', e);
      return null;
    }
  }

  /// Re-link any purchases the Play account has against the current RC
  /// user — needed after reinstall / device switch, AND mandated by Play
  /// policy: every paid app must offer an explicit "Restore purchases"
  /// action. Returns the resulting [CustomerInfo] so the caller can show
  /// what got restored (or "nothing to restore").
  static Future<CustomerInfo> restorePurchases() async {
    return Purchases.restorePurchases();
  }
}
