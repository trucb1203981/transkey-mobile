import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/app_group_bridge.dart';
import '../tracking/tracking_provider.dart';

const _kLocaleKey = 'tk_ui_locale';

// UI locales we ship (must match l10n/*.arb + the keyboard's APP_UI_LANGS).
const _supportedUiLangs = {
  'en', 'vi', 'ar', 'de', 'es', 'fr', 'id', 'it', 'ja', 'ko', 'pt', 'ru', 'th',
  'zh',
};

final localeProvider =
    AsyncNotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends AsyncNotifier<Locale> {
  @override
  Future<Locale> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kLocaleKey);
    final lang = (stored != null && stored.isNotEmpty)
        ? stored
        // No explicit choice yet: prefer the device language if we ship it,
        // otherwise fall back to English. Not persisted, so it keeps following
        // the device until the user picks a language. Mirrors the keyboard.
        : _resolveDeviceLang();
    // Mirror to the App Group on startup so the iOS keyboard extension shows
    // its chips/labels in the current app language from the first launch.
    AppGroupBridge.saveUiLang(lang);
    return Locale(lang);
  }

  String _resolveDeviceLang() {
    var lang = PlatformDispatcher.instance.locale.languageCode;
    if (lang == 'in') lang = 'id'; // legacy code for Indonesian
    return _supportedUiLangs.contains(lang) ? lang : 'en';
  }

  Future<void> setLocale(String languageCode) async {
    final previous = state.valueOrNull?.languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, languageCode);
    state = AsyncData(Locale(languageCode));
    // Keep the iOS keyboard extension's labels in sync with the app language.
    AppGroupBridge.saveUiLang(languageCode);
    final tracking = ref.read(trackingServiceProvider);
    tracking.setLocale(languageCode);
    if (previous != languageCode) {
      tracking.event('app_lang_change',
          properties: {'from': previous, 'to': languageCode});
    }
  }
}
