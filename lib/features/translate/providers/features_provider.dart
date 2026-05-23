import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/dio_client.dart';
import '../models/language.dart';

/// Shared-prefs keys mirrored to the Android bubble so the native
/// [ModePicker.kt] can render lock icons on plan-gated entries without
/// a method-channel round-trip to Dart on every render. Updated by
/// [FeaturesNotifier.fetch] every time /features resolves. Each entry
/// in the bubble that maps to a paid feature reads its corresponding
/// flag; missing key → false (locked) since [getBoolean] defaults to
/// our pessimistic `false` for paid features.
///
/// Keep these names in sync with the Kotlin side (see
/// [BubbleService.kt] → [readFeatureEnabled]).
///
/// NOTE: NO `flutter.` prefix here — the shared_preferences plugin
/// auto-prefixes every key with `flutter.` when persisting to native
/// Android SharedPreferences. Adding the prefix on the Dart side
/// would double it (`flutter.flutter.tk_feature_camera`) and the
/// bubble's read would never find it, leaving Pro users with a
/// locked entry in the popup.
const _kSharedCameraFlagKey   = 'tk_feature_camera';
const _kSharedLensFlagKey     = 'tk_feature_lens';
const _kSharedReplyFlagKey    = 'tk_feature_reply';
const _kSharedSummarizeKey    = 'tk_feature_summarize';
const _kSharedExplainKey      = 'tk_feature_explain';
const _kSharedRefineKey       = 'tk_feature_refine';
// Mirror of the SERVER-driven /features languages catalog so the bubble
// (Kotlin) can populate its source/target pickers from the same list the
// home tab shows, instead of the hardcoded ~30-language fallback. JSON
// shape: [{"code":"en","label":"English"}, ...]. Empty / missing → bubble
// falls back to its built-in list.
const _kSharedLangsCatalogKey = 'tk_lang_catalog';

class FeatureFlags {
  const FeatureFlags({
    this.translate = true,
    this.summarize = false,
    this.explain = false,
    this.refine = false,
    this.replyTranslate = false,
    this.replySuggestions = false,
    this.glossary = true,
    this.toneOverride = false,
    this.romanization = false,
    this.lens = false,
    this.camera = false,
    this.allowedTargetLangs = const <String>[],
    this.allowedSourceLangs = const <String>[],
    this.allowedReplyTargetLangs = const <String>[],
  });

  /// Default for the "unauthenticated / not yet fetched" window. Keep it
  /// pessimistic — translate + glossary on, every paid feature OFF — so a
  /// flaky cold-start never accidentally unlocks paid features. Refreshed
  /// when /features resolves (see [FeaturesNotifier.fetch]).
  static const freeDefaults = FeatureFlags();

  final bool translate;
  final bool summarize;
  final bool explain;
  final bool refine;
  final bool replyTranslate;
  final bool replySuggestions;
  final bool glossary;
  final bool toneOverride;
  final bool romanization;
  /// Bubble screen-scan (region OCR + translate-batch path). Distinct
  /// from [camera] in /admin/plans — admin can toggle each per plan.
  final bool lens;
  /// Camera-capture flow (photo of menu/sign → /translate-image).
  final bool camera;

  /// Empty list = unrestricted (every language in the catalog is offered).
  /// Non-empty = client must intersect with the catalog before showing.
  final List<String> allowedTargetLangs;
  final List<String> allowedSourceLangs;
  final List<String> allowedReplyTargetLangs;

  factory FeatureFlags.fromMap(Map<String, dynamic> map) => FeatureFlags(
        translate: map['translate'] as bool? ?? true,
        summarize: map['summarize'] as bool? ?? false,
        explain: map['explain'] as bool? ?? false,
        refine: map['refine'] as bool? ?? false,
        replyTranslate: map['reply_translate'] as bool? ?? false,
        replySuggestions: map['reply_suggestions'] as bool? ?? false,
        glossary: map['glossary'] as bool? ?? true,
        toneOverride: map['tone_override'] as bool? ?? false,
        romanization: map['romanization'] as bool? ?? false,
        lens:   map['lens']   as bool? ?? false,
        camera: map['camera'] as bool? ?? false,
        allowedTargetLangs: _asStringList(map['allowed_target_langs']),
        allowedSourceLangs: _asStringList(map['allowed_source_langs']),
        allowedReplyTargetLangs:
            _asStringList(map['allowed_reply_target_langs']),
      );
}

List<String> _asStringList(dynamic raw) {
  if (raw is List) {
    return raw.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

List<Language> _parseLanguages(dynamic raw) {
  if (raw is! List) return const <Language>[];
  final out = <Language>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final code = item['code'] as String?;
    if (code == null || code.isEmpty) continue;
    if (item['enabled'] == false) continue;
    // Backend `label` is "🇰🇷 한국어" — flag + native name. Strip the flag
    // for mobile since iOS/Android render flags inconsistently and the
    // Material list tile shows them as raw codepoints. Native name alone
    // reads cleaner. English name (separate field) is the subtitle.
    final label = (item['label'] as String?) ?? code;
    final firstSpace = label.indexOf(' ');
    final native = firstSpace >= 0 ? label.substring(firstSpace + 1).trim() : label;
    out.add(Language(
      code: code,
      nativeName: native.isEmpty ? code : native,
      name: item['english_name'] as String?,
      isLowResource: item['is_low_resource'] as bool? ?? false,
    ));
  }
  return out;
}

class FeaturesState {
  const FeaturesState({
    this.flags = const FeatureFlags(),
    this.isLoading = false,
    this.fetchedAt,
  });

  final FeatureFlags flags;
  final bool isLoading;
  final DateTime? fetchedAt;

  bool get isStale {
    if (fetchedAt == null) return true;
    return DateTime.now().difference(fetchedAt!).inMinutes >= 5;
  }

  FeaturesState copyWith({
    FeatureFlags? flags,
    bool? isLoading,
    DateTime? fetchedAt,
  }) =>
      FeaturesState(
        flags: flags ?? this.flags,
        isLoading: isLoading ?? this.isLoading,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
}

class FeaturesNotifier extends Notifier<FeaturesState> {
  @override
  FeaturesState build() => const FeaturesState();

  Future<void> fetch() async {
    final current = state;
    if (current.isLoading) return;

    state = current.copyWith(isLoading: true);

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/features');
      final data = response.data as Map<String, dynamic>;
      final flags = FeatureFlags.fromMap(data);
      // Update the catalog lookup *before* notifying listeners so widgets
      // re-rendered by the state change see fresh language names.
      final languages = _parseLanguages(data['languages']);
      if (languages.isNotEmpty) {
        setDynamicLanguageCatalog(languages);
      }
      state = FeaturesState(
        flags: flags,
        fetchedAt: DateTime.now(),
      );
      // Mirror plan-gated feature flags to SharedPreferences so the
      // Android bubble (Kotlin) can render lock icons on entries the
      // user's plan doesn't include. The bubble runs OUTSIDE the
      // Flutter activity (foreground service overlay) so a method-
      // channel call would race the engine startup; reading prefs is
      // synchronous and survives process restarts.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kSharedCameraFlagKey, flags.camera);
        await prefs.setBool(_kSharedLensFlagKey, flags.lens);
        await prefs.setBool(_kSharedReplyFlagKey, flags.replyTranslate);
        await prefs.setBool(_kSharedSummarizeKey, flags.summarize);
        await prefs.setBool(_kSharedExplainKey, flags.explain);
        await prefs.setBool(_kSharedRefineKey, flags.refine);
        // Mirror the server-driven language catalog so the bubble picker
        // shows the SAME list as the home language bar (admin can
        // enable/disable per plan via /admin/features without an app
        // release). Store as a compact JSON array of {code,label} —
        // Kotlin parses it on picker open. Falls back to the bubble's
        // built-in 30-language list if the pref is missing/empty.
        if (languages.isNotEmpty) {
          final encoded = jsonEncode(languages
              .map((l) => {'code': l.code, 'label': l.nativeName})
              .toList());
          await prefs.setString(_kSharedLangsCatalogKey, encoded);
        }
      } catch (e) {
        // Persistence is best-effort — if it fails the bubble falls
        // back to "no gate" (current behaviour), which the server
        // catches with a 403 anyway.
        debugPrint('[Features] persist feature flags failed: $e');
      }
    } catch (_) {
      // Keep previous flags on error
      state = current.copyWith(isLoading: false);
    }
  }

  /// Fetch only if cache is stale or empty.
  Future<void> refreshIfNeeded() async {
    if (state.isStale) await fetch();
  }

  /// Force-refresh, ignoring TTL. Used when auth state changes — login,
  /// logout, plan upgrade via webhook — because the allowed feature set
  /// might be completely different for the new identity.
  Future<void> refresh() async {
    state = state.copyWith(fetchedAt: null);
    await fetch();
  }
}

final featuresProvider =
    NotifierProvider<FeaturesNotifier, FeaturesState>(
  FeaturesNotifier.new,
);
