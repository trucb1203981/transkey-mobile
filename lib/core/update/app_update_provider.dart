import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A newer build of the app is live in the store.
class StoreUpdate {
  const StoreUpdate({required this.id, required this.storeUrl});

  /// What the store calls the new build: the version name on iOS, the
  /// versionCode on Android (Play does not expose the name). Used only to
  /// remember which update the user dismissed.
  final String id;
  final Uri storeUrl;
}

// The https form, not market://: Play claims this link and opens directly,
// while market:// makes MIUI ask "Google Play or GetApps?" first.
const _kPlayUrl =
    'https://play.google.com/store/apps/details?id=app.transkey.mobile';
const _kIosBundleId = 'app.transkey.mobile';
const _kDismissedKey = 'update_banner_dismissed';

/// QA only: `--dart-define=TK_FAKE_STORE_UPDATE=true` pretends the store has a
/// newer build, so the banner and the store hand-off can be checked on a
/// sideloaded Android build that Play In-App Updates refuses to answer.
const _kFakeUpdate = bool.fromEnvironment('TK_FAKE_STORE_UPDATE');

/// Checks the store once per launch. Null when up to date, when the check
/// cannot run (offline, a sideloaded or debug Android build that Play does not
/// own) or when the user dismissed this same update.
///
/// No backend: iOS asks the public App Store lookup, Android asks Google Play
/// In-App Updates, so a release shows up without anyone entering a version.
final appUpdateProvider = FutureProvider<StoreUpdate?>((ref) async {
  if (kIsWeb || (kDebugMode && !_kFakeUpdate)) return null;
  try {
    final StoreUpdate? update;
    if (_kFakeUpdate) {
      update = StoreUpdate(
        id: 'fake',
        storeUrl: Uri.parse(Platform.isAndroid
            ? _kPlayUrl
            : 'https://apps.apple.com/app/transkey-translate-keyboard/id0'),
      );
    } else if (Platform.isIOS) {
      update = await _checkAppStore();
    } else if (Platform.isAndroid) {
      update = await _checkPlay();
    } else {
      update = null;
    }
    if (update == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kDismissedKey) == update.id) return null;
    return update;
  } catch (e) {
    debugPrint('[AppUpdate] check failed: $e');
    return null;
  }
});

/// Hide the banner for [update] until the store has an even newer build.
Future<void> dismissStoreUpdate(WidgetRef ref, StoreUpdate update) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kDismissedKey, update.id);
  ref.invalidate(appUpdateProvider);
}

Future<StoreUpdate?> _checkPlay() async {
  final info = await InAppUpdate.checkForUpdate();
  if (info.updateAvailability != UpdateAvailability.updateAvailable) {
    return null;
  }
  return StoreUpdate(
    id: '${info.availableVersionCode ?? 'unknown'}',
    storeUrl: Uri.parse(_kPlayUrl),
  );
}

Future<StoreUpdate?> _checkAppStore() async {
  final installed = (await PackageInfo.fromPlatform()).version;
  // The lookup is per storefront; the device's region first, US as fallback.
  final region = PlatformDispatcher.instance.locale.countryCode?.toLowerCase();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));
  for (final country in {if (region != null) region, 'us'}) {
    final res = await dio.get<String>(
      'https://itunes.apple.com/lookup',
      queryParameters: {'bundleId': _kIosBundleId, 'country': country},
    );
    // Apple serves this as text/javascript, so Dio leaves it a string.
    final data = res.data == null ? null : jsonDecode(res.data!);
    final results = data is Map ? data['results'] : null;
    if (results is! List || results.isEmpty) continue;
    final app = results.first as Map<String, dynamic>;
    final latest = app['version'] as String?;
    final url = app['trackViewUrl'] as String?;
    if (latest == null || url == null) return null;
    if (compareVersions(latest, installed) <= 0) return null;
    // A build this iPhone cannot install is not an update for it.
    final minOs = app['minimumOsVersion'] as String?;
    if (minOs != null) {
      final os = (await DeviceInfoPlugin().iosInfo).systemVersion;
      if (compareVersions(os, minOs) < 0) return null;
    }
    return StoreUpdate(id: latest, storeUrl: Uri.parse(url));
  }
  return null;
}

/// Compares dotted numeric versions ("2.7.10" > "2.7.9"); a missing or
/// non-numeric part counts as 0.
@visibleForTesting
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split('.')
      .map((p) => int.tryParse(p.split(RegExp(r'[^0-9]')).first) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}
