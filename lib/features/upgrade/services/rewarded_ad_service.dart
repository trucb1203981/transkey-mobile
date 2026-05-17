import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Loads + shows AdMob rewarded video ads and surfaces the reward
/// callback as a simple [Future<bool>]. One service instance per
/// paywall presentation; dispose when the sheet is dismissed.
///
/// Account-approval gate: AdMob blocks all ad loads until the
/// publisher account is approved by Google review (~1-7 days post-
/// signup). While pending, we ship Google's public test unit IDs so
/// dev / TestFlight / internal users can still exercise the full
/// paywall → ad → reward → grant flow. Swap to production IDs after
/// approval (see PRODUCTION constants below + AndroidManifest).
class RewardedAdService {
  // ACTIVE — Google public test units, always fill, no approval needed.
  static const _adUnitAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _adUnitIOS     = 'ca-app-pub-3940256099942544/1712485313';

  // PRODUCTION — TransKey AdMob (pending Google review at time of
  // writing). Swap into the constants above when approval lands.
  // ignore: unused_field
  static const _prodAdUnitAndroid = 'ca-app-pub-4388572340562895/8963970428';

  RewardedAd? _ad;
  Completer<RewardedAd?>? _loadCompleter;

  String get _adUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS ? _adUnitIOS : _adUnitAndroid;

  /// Preload one ad. Safe to call multiple times — concurrent calls
  /// share the same in-flight Future, idempotent if an ad is already
  /// loaded. Return the loaded ad (or null on failure) so callers can
  /// await readiness instead of polling.
  Future<RewardedAd?> preload() {
    if (_ad != null) return Future.value(_ad);
    if (_loadCompleter != null) return _loadCompleter!.future;
    final completer = Completer<RewardedAd?>();
    _loadCompleter = completer;
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
