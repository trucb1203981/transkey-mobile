import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to save auth data into iOS App Group for Share/Keyboard extensions.
class AppGroupBridge {
  static const _channel = MethodChannel('transkey/appgroup');

  /// Save token, deviceId, plan, baseURL to shared App Group.
  static Future<void> saveAuth({
    required String token,
    required String deviceId,
    required String plan,
    required String baseURL,
  }) async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('saveAuth', {
        'token': token,
        'deviceId': deviceId,
        'plan': plan,
        'baseURL': baseURL,
      });
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] saveAuth failed: $e');
    }
  }

  /// Clear auth data from App Group (on logout).
  static Future<void> clearAuth() async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('clearAuth');
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] clearAuth failed: $e');
    }
  }
}
