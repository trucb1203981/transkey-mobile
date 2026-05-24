import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tracking/tracking_provider.dart';
import '../tracking/tracking_service.dart';

enum BubbleState { idle, loading, result, error }

class BubbleManager extends StateNotifier<bool> {
  BubbleManager(this._tracking) : super(false) {
    _seedInitialState();
  }

  final TrackingService _tracking;

  static const _channel = MethodChannel('transkey/bubble');

  bool _hasPermission = false;

  /// Read the actual running state from native on construction so the
  /// in-app toggle is correct on cold start (e.g. system auto-resumed the
  /// bubble before the user opened the app).
  Future<void> _seedInitialState() async {
    if (!Platform.isAndroid) return;
    final running = await isRunning();
    if (running != state) state = running;
  }

  /// Apply a native-driven state change (BubbleService broadcasts via the
  /// `bubbleStateChanged` MethodChannel call when it flips the active
  /// pref). Lets paths that don't go through [startBubble]/[stopBubble] —
  /// keyboard-setup auto-start, drag-to-close, notification "Turn off",
  /// system restart — still propagate to the UI.
  void syncState(bool active) {
    if (state != active) state = active;
  }

  /// Check if we can draw over other apps (SYSTEM_ALERT_WINDOW).
  Future<bool> checkPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      _hasPermission = await _channel.invokeMethod<bool>('checkPermission') ?? false;
      return _hasPermission;
    } on PlatformException {
      return false;
    }
  }

  /// Request overlay permission — opens system settings.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      _hasPermission = result ?? false;
      return _hasPermission;
    } on PlatformException {
      return false;
    }
  }

  /// Start the floating bubble service. [source] feeds the tracking event
  /// so the dashboard can split intentional starts (user tapped the toggle
  /// / completed setup) from passive ones (auto-resume on cold start).
  Future<bool> startBubble({String source = 'user'}) async {
    if (!Platform.isAndroid || kIsWeb) return false;

    if (!_hasPermission) {
      _hasPermission = await checkPermission();
      if (!_hasPermission) return false;
    }

    try {
      await _channel.invokeMethod<void>('startBubble');
      state = true;
      _tracking.event('bubble_start', properties: {'source': source});
      return true;
    } on PlatformException catch (e) {
      debugPrint('[BubbleManager] startBubble failed: $e');
      return false;
    }
  }

  /// Stop the floating bubble service.
  Future<void> stopBubble() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopBubble');
      state = false;
      _tracking.event('bubble_stop');
    } on PlatformException catch (e) {
      debugPrint('[BubbleManager] stopBubble failed: $e');
    }
  }

  /// Update bubble visual state.
  Future<void> setBubbleState(BubbleState bubbleState) async {
    if (!Platform.isAndroid || !state) return;
    try {
      await _channel.invokeMethod<void>('setBubbleState', bubbleState.name);
    } on PlatformException catch (e) {
      debugPrint('[BubbleManager] setState failed: $e');
    }
  }

  /// Check if the bubble service is currently running.
  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Auto-start bubble if it was active before app restart.
  Future<void> tryAutoStart() async {
    if (!Platform.isAndroid || kIsWeb) return;
    final running = await isRunning();
    if (running) return; // already running
    final prefs = await SharedPreferences.getInstance();
    final wasActive = prefs.getBool('tk_bubble_active') ?? false;
    if (!wasActive) return;
    _hasPermission = await checkPermission();
    if (_hasPermission) await startBubble(source: 'auto_resume');
  }

  /// Show overlay permission dialog if needed, then start.
  Future<bool> requestAndStart() async {
    final has = await checkPermission();
    if (has) return await startBubble();
    return false;
  }

  /// True if our AccessibilityService is enabled in system settings.
  Future<bool> checkAccessibility() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('checkAccessibility') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open the system Accessibility settings so the user can enable TransKey.
  Future<void> requestAccessibility() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestAccessibility');
    } on PlatformException catch (e) {
      debugPrint('[BubbleManager] requestAccessibility failed: $e');
    }
  }

  /// Open the per-app details page in system Settings. Used by the
  /// Accessibility onboarding flow on Android 13+ — the "Allow restricted
  /// settings" toggle that unblocks the Accessibility opt-in lives there.
  Future<void> openAppDetails() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openAppDetails');
    } on PlatformException catch (e) {
      debugPrint('[BubbleManager] openAppDetails failed: $e');
    }
  }

  /// Replace text in the focused editable field of whichever app currently
  /// has input focus. Requires the Accessibility service to be enabled.
  /// Returns true on success.
  Future<bool> replaceFocusedText(String text) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'replaceFocusedText',
            {'text': text},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}

final bubbleManagerProvider = StateNotifierProvider<BubbleManager, bool>(
  (ref) => BubbleManager(ref.read(trackingServiceProvider)),
);
