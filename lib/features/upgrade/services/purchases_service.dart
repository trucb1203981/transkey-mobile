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

    // Only Android is provisioned today. iOS will get its own RC API key
    // when the iOS build goes to TestFlight; until then, calling RC on
    // iOS would fail with "no entitlement configured".
    if (!Platform.isAndroid) return;

    final key = dotenv.env['REVENUECAT_API_KEY_ANDROID'];
    if (key == null || key.isEmpty || key.startsWith('REPLACE_')) {
      AppLog.w('RC', 'REVENUECAT_API_KEY_ANDROID not set — billing disabled');
      return;
    }

    try {
      await Purchases.setLogLevel(LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
      AppLog.i('RC', 'configured (Android)');
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

  /// Re-link any purchases the Play account has against the current RC
  /// user — needed after reinstall / device switch, AND mandated by Play
  /// policy: every paid app must offer an explicit "Restore purchases"
  /// action. Returns the resulting [CustomerInfo] so the caller can show
  /// what got restored (or "nothing to restore").
  static Future<CustomerInfo> restorePurchases() async {
    return Purchases.restorePurchases();
  }
}
