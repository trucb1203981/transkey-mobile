import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BubbleState { idle, loading, result, error }

class BubbleManager extends StateNotifier<bool> {
  BubbleManager() : super(false);

  static const _channel = MethodChannel('transkey/bubble');

  bool _hasPermission = false;

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

  /// Start the floating bubble service.
  Future<bool> startBubble() async {
    if (!Platform.isAndroid || kIsWeb) return false;

    if (!_hasPermission) {
      _hasPermission = await checkPermission();
      if (!_hasPermission) return false;
    }

    try {
      await _channel.invokeMethod<void>('startBubble');
      state = true;
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

  /// Show overlay permission dialog if needed, then start.
  Future<bool> requestAndStart() async {
    final has = await checkPermission();
    if (has) return await startBubble();
    return false;
  }
}

final bubbleManagerProvider =
    StateNotifierProvider<BubbleManager, bool>((ref) => BubbleManager());
