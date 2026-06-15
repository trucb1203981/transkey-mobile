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
    } on MissingPluginException {
      // iOS keyboard / share extensions + App Group are DEFERRED (need Xcode
      // targets + a paid account), so the native `transkey/appgroup` channel
      // isn't registered yet — there is nothing to write to. Degrade to a
      // no-op instead of letting the exception escape into the auth flow.
    }
  }

  /// Clear auth data from App Group (on logout).
  static Future<void> clearAuth() async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('clearAuth');
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] clearAuth failed: $e');
    } on MissingPluginException {
      // See saveAuth: the iOS App Group channel is deferred. clearAuth runs in
      // logout() with no caller-side try/catch, so an uncaught MissingPlugin
      // here would abort logout and leave the UI stuck "logged in".
    }
  }

  /// Mirror the translate language pair into the App Group so the keyboard
  /// and share extensions follow the app's choice.
  static Future<void> saveLanguages({
    required String source,
    required String target,
  }) async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('saveLanguages', {
        'source': source,
        'target': target,
      });
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] saveLanguages failed: $e');
    } on MissingPluginException {
      // App Group channel deferred (see saveAuth) - mirror is a no-op.
    }
  }

  /// Mirror the app's UI language into the App Group so the keyboard extension
  /// localizes its own chips/labels to match the language the user picked IN
  /// THE APP (not the iOS device language). Without this the keyboard always
  /// shows its hardcoded Vietnamese labels regardless of the app language.
  static Future<void> saveUiLang(String lang) async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('saveUiLang', {'lang': lang});
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] saveUiLang failed: $e');
    } on MissingPluginException {
      // App Group channel deferred (see saveAuth) - mirror is a no-op.
    }
  }

  /// Mirror plan-gated feature flags so the extensions gate exactly like the
  /// app: keyboard -> Reply/Refine chips, share extension ->
  /// Summarize/Explain/Refine buttons. Same server-driven flags as home.
  static Future<void> saveFeatures({
    required bool reply,
    required bool refine,
    required bool summarize,
    required bool explain,
  }) async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('saveFeatures', {
        'reply': reply,
        'refine': refine,
        'summarize': summarize,
        'explain': explain,
      });
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] saveFeatures failed: $e');
    } on MissingPluginException {
      // App Group channel deferred (see saveAuth) - mirror is a no-op.
    }
  }

  /// Mirror the server language catalog (JSON `[{code,label}, ...]`) so the
  /// keyboard picker shows the same admin-managed list as the app and the
  /// Android bubble/keyboard.
  static Future<void> saveLangCatalog(String json) async {
    if (!Platform.isIOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('saveLangCatalog', {'json': json});
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] saveLangCatalog failed: $e');
    } on MissingPluginException {
      // App Group channel deferred (see saveAuth) - mirror is a no-op.
    }
  }

  /// Read the pair back from the App Group. Returns null when unavailable.
  /// `dirty` is true when the KEYBOARD changed the pair since the last read
  /// (read-and-consume on the native side); the app should then adopt it.
  static Future<({String source, String target, bool dirty})?>
      readLanguages() async {
    if (!Platform.isIOS || kIsWeb) return null;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('readLanguages');
      if (map == null) return null;
      return (
        source: map['source'] as String? ?? 'auto',
        target: map['target'] as String? ?? 'en',
        dirty: map['dirty'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      debugPrint('[AppGroupBridge] readLanguages failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
