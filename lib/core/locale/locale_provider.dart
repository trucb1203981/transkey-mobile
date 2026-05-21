import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tracking/tracking_provider.dart';

const _kLocaleKey = 'tk_ui_locale';

final localeProvider =
    AsyncNotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

class LocaleNotifier extends AsyncNotifier<Locale> {
  @override
  Future<Locale> build() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey) ?? 'en';
    return Locale(code);
  }

  Future<void> setLocale(String languageCode) async {
    final previous = state.valueOrNull?.languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, languageCode);
    state = AsyncData(Locale(languageCode));
    final tracking = ref.read(trackingServiceProvider);
    tracking.setLocale(languageCode);
    if (previous != languageCode) {
      tracking.event('app_lang_change',
          properties: {'from': previous, 'to': languageCode});
    }
  }
}
