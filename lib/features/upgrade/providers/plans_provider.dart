import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/locale/locale_provider.dart';
import '../services/purchases_service.dart';

/// Pick a localized string out of a server JSONB i18n map. Server stores
/// `{ "vi": "...", "en": "...", ... }`; client picks the APP locale the
/// user chose in settings, then falls back to English, then to the first
/// non-empty value. Returns null if [raw] is neither a String nor a
/// usable Map.
///
/// IMPORTANT: pass the APP locale (from `localeProvider`), NOT the
/// device locale — they diverge whenever the user picks an app language
/// different from the OS one. Same fallback chain as the admin's
/// `pickLocalized()` helper — keeps every consumer (admin Vue, mobile
/// Dart, desktop Electron) in sync.
String? _pickLocalized(dynamic raw, String locale) {
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is Map) {
    for (final key in [locale, 'en']) {
      final v = raw[key];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final v in raw.values) {
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return null;
}

/// Parse the server's `highlights` field. Two historical shapes:
/// (1) `List<String>` — legacy, plain bullet text.
/// (2) `Map<String, List<{ "text": "...", "type": "item|item_off" }>>` —
///     current shape, localized + includes off-state for "X" bullets.
/// We collapse (2) by picking the locale's array and extracting `text`
/// (consumers don't yet render the on/off distinction).
List<String> _parseHighlights(dynamic raw, String locale) {
  if (raw is List) {
    return raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }
  if (raw is Map) {
    dynamic list;
    for (final key in [locale, 'en']) {
      final v = raw[key];
      if (v is List) { list = v; break; }
    }
    list ??= raw.values.firstWhere((v) => v is List, orElse: () => const []);
    if (list is List) {
      return list
          .map((e) {
            if (e is String) return e;
            if (e is Map) return (e['text'] as String?) ?? '';
            return '';
          })
          .where((s) => s.isNotEmpty)
          .toList();
    }
  }
  return const <String>[];
}

/// One row from the server's /plans table — public, marketing-facing.
/// Prices are stored on the server in major currency units (e.g. dollars)
/// as raw numbers; we keep them as `num?` so a "free" plan with NULL
/// price doesn't crash.
class PlanInfo {
  const PlanInfo({
    required this.plan,
    required this.displayName,
    required this.sortOrder,
    this.reqLimit,
    this.charLimit,
    this.description,
    this.priceMonthly,
    this.price3Month,
    this.price6Month,
    this.priceAnnual,
    this.highlights = const [],
    this.glossaryLimit,
    this.features = const {},
  });

  /// Server plan key — `free` | `mobile` | `pro` | `trial`.
  final String plan;
  final String displayName;
  final int sortOrder;
  final int? reqLimit;
  final int? charLimit;
  final String? description;
  final num? priceMonthly;
  final num? price3Month;
  final num? price6Month;
  final num? priceAnnual;
  final List<String> highlights;
  final int? glossaryLimit;
  // Feature flag map: { 'reply' → true, 'summarize' → false, ... }
  final Map<String, bool> features;

  factory PlanInfo.fromMap(Map<String, dynamic> map, String locale) {
    final rawFeatures = map['features'];
    final features = switch (rawFeatures) {
      Map<String, dynamic> m => m.map(
          (k, v) => MapEntry(k, v == true || v == 1 || v == '1'),
        ),
      _ => const <String, bool>{},
    };
    // Server returns NUMERIC(10,2) prices either as a JSON number OR a
    // string ("6.00"). Tolerate both — `num.tryParse` returns null on
    // garbage so a malformed value renders as "missing" instead of
    // crashing the whole fetch.
    num? parsePrice(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }
    return PlanInfo(
      plan: map['plan'] as String,
      displayName: _pickLocalized(map['display_name'], locale) ?? (map['plan'] as String),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      reqLimit: (map['req_limit'] as num?)?.toInt(),
      charLimit: (map['char_limit'] as num?)?.toInt(),
      description: _pickLocalized(map['description'], locale),
      priceMonthly: parsePrice(map['price_monthly']),
      price3Month: parsePrice(map['price_3month']),
      price6Month: parsePrice(map['price_6month']),
      priceAnnual: parsePrice(map['price_annual']),
      highlights: _parseHighlights(map['highlights'], locale),
      glossaryLimit: (map['glossary_limit'] as num?)?.toInt(),
      features: features,
    );
  }
}

class PlansNotifier extends AsyncNotifier<List<PlanInfo>> {
  @override
  Future<List<PlanInfo>> build() async {
    // ref.watch on localeProvider so the plans list auto-refetches with
    // localized strings whenever the user changes app language in
    // Settings. The server is the source of truth for display_name /
    // description / highlights (all stored as JSONB i18n maps), so we
    // re-pick on every locale change instead of caching one snapshot.
    final localeAsync = ref.watch(localeProvider);
    final locale = localeAsync.valueOrNull?.languageCode ?? 'en';
    return _fetch(locale);
  }

  Future<List<PlanInfo>> _fetch(String locale) async {
    try {
      final api = ref.read(apiClientProvider);
      // X-Platform header (set by the API client) filters mobile-only plans
      // for desktop and vice versa — see server's filterPlansForPlatform.
      final response = await api.dio.get('/plans');
      final list = response.data as List<dynamic>;
      return list
          .map((e) => PlanInfo.fromMap(e as Map<String, dynamic>, locale))
          .toList();
    } catch (e) {
      debugPrint('[Plans] Fetch failed: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final locale =
          ref.read(localeProvider).valueOrNull?.languageCode ?? 'en';
      state = AsyncData(await _fetch(locale));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final plansProvider = AsyncNotifierProvider<PlansNotifier, List<PlanInfo>>(
  PlansNotifier.new,
);

/// Localized, store-charged monthly prices from RevenueCat, keyed by plan
/// ('mobile' / 'pro'). The upgrade screen prefers these over the server's
/// USD reference price so the plan cards + CTA buttons show the exact amount
/// and currency the App Store / Play will charge. Resolves to an empty map on
/// web / desktop or when RC isn't configured — the UI then falls back to the
/// server price. Not auto-disposed: the offering is cached by the RC SDK, so
/// one fetch per app session is enough.
final storeMonthlyPricesProvider =
    FutureProvider<Map<String, String>>((ref) async {
  return PurchasesService.monthlyPriceStrings();
});

/// Convenience selector — pluck a single plan by key.
PlanInfo? planByKey(List<PlanInfo>? list, String key) {
  if (list == null) return null;
  for (final p in list) {
    if (p.plan == key) return p;
  }
  return null;
}
