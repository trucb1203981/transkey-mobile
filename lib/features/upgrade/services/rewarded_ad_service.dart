import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Loads + shows AdMob rewarded video ads and surfaces the reward
/// callback as a simple [Future<bool>]. One service instance per
/// paywall presentation; dispose when the sheet is dismissed.
///
/// Server-side gating: ad UI is hidden unless `/features.ads_enabled`
/// is true (FeatureFlags.adsEnabled). The server keeps that flag OFF
/// until the AdMob publisher account is approved by Google review and
/// flips it to ON without an app update — so this class assumes any
/// call site has already checked the flag.
///
/// Per-platform unit IDs: production unit in release builds, Google's
/// public TEST unit in debug to avoid invalid-traffic strikes from
/// developer devices hitting real impressions.
class RewardedAdService {
  // Android — TransKey AdMob production rewarded unit.
  static const _adUnitAndroidProd = 'ca-app-pub-4388572340562895/8963970428';
  // Android — Google public test unit (always fills with test creative).
  static const _adUnitAndroidTest = 'ca-app-pub-3940256099942544/5224354917';

  // iOS — TransKey AdMob production rewarded unit (AdMob console > TransKey
  // iOS > quota_rewarded_ios).
  static const _adUnitIOSProd = 'ca-app-pub-4388572340562895/6127564268';
  // iOS — Google public test unit (always fills with test creative).
  static const _adUnitIOSTest = 'ca-app-pub-3940256099942544/1712485313';

  RewardedAd? _ad;
  Completer<RewardedAd?>? _loadCompleter;

  String get _adUnitId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final hasProd = !_adUnitIOSProd.startsWith('REPLACE_');
      return kReleaseMode && hasProd ? _adUnitIOSProd : _adUnitIOSTest;
    }
    return kReleaseMode ? _adUnitAndroidProd : _adUnitAndroidTest;
  }

  /// Preload one ad. Safe to call multiple times — concurrent calls
  /// share the same in-flight Future, idempotent if an ad is already
  /// loaded. Return the loaded ad (or null on failure) so callers can
  /// await readiness instead of polling.
  Future<RewardedAd?> preload() async {
    if (_ad != null) return Future.value(_ad);
    if (_loadCompleter != null) return _loadCompleter!.future;
    final completer = Completer<RewardedAd?>();
    _loadCompleter = completer;
    // iOS App Tracking Transparency: must be resolved before the first ad
    // request. No-op once the user has answered (status != notDetermined);
    // on deny AdMob automatically serves non-personalized ads.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await AppTrackingTransparency.requestTrackingAuthorization();
      } catch (_) {
        // Never block ad loading on the ATT dialog failing.
      }
    }
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadCompleter = null;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (err) {
          debugPrint('[RewardedAd] load failed: ${err.message}');
          _ad = null;
          _loadCompleter = null;
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    ).catchError((e) {
      debugPrint('[RewardedAd] preload threw: $e');
      _loadCompleter = null;
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  /// Show the loaded ad. Returns `true` if the user finished watching
  /// AND earned the reward, `false` for any other outcome (ad not
  /// loaded, user dismissed early, ad failed). Disposes the ad
  /// regardless so the next preload starts fresh.
  Future<bool> showAndAwaitReward() async {
    // Await the in-flight load (or kick off a fresh one). preload()
    // shares a single Future across concurrent callers so this works
    // whether the paywall already started loading or we're a cold
    // first-tap caller.
    final ad = _ad ?? await preload();
    if (ad == null) return false;
    _ad = null; // ownership transferred to the SDK once show() fires

    var earned = false;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        debugPrint('[RewardedAd] showed');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[RewardedAd] dismissed, earned=$earned');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        debugPrint('[RewardedAd] show failed: ${err.message}');
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      await ad.show(onUserEarnedReward: (_, reward) {
        debugPrint('[RewardedAd] earned reward: ${reward.type}=${reward.amount}');
        earned = true;
      });
    } catch (e) {
      debugPrint('[RewardedAd] show threw: $e');
      return false;
    }
    // Wait for the dismissal callback before returning so the paywall
    // sheet doesn't race ahead and try to credit before the user
    // actually finished. SDK's show() returns as soon as the ad is
    // presented, not when the user closes it.
    return completer.future;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
