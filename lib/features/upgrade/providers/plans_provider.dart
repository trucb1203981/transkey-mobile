import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';

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

  factory PlanInfo.fromMap(Map<String, dynamic> map) {
    final rawHighlights = map['highlights'];
    final highlights = switch (rawHighlights) {
      List<dynamic> list => list.map((e) => e.toString()).toList(),
      _ => const <String>[],
    };
    final rawFeatures = map['features'];
    final features = switch (rawFeatures) {
      Map<String, dynamic> m => m.map(
          (k, v) => MapEntry(k, v == true || v == 1 || v == '1'),
        ),
      _ => const <String, bool>{},
    };
    return PlanInfo(
      plan: map['plan'] as String,
      displayName: (map['display_name'] as String?) ?? (map['plan'] as String),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      reqLimit: (map['req_limit'] as num?)?.toInt(),
      charLimit: (map['char_limit'] as num?)?.toInt(),
      description: map['description'] as String?,
      priceMonthly: map['price_monthly'] as num?,
      price3Month: map['price_3month'] as num?,
      price6Month: map['price_6month'] as num?,
      priceAnnual: map['price_annual'] as num?,
      highlights: highlights,
      glossaryLimit: (map['glossary_limit'] as num?)?.toInt(),
      features: features,
    );
  }
}

class PlansNotifier extends AsyncNotifier<List<PlanInfo>> {
  @override
  Future<List<PlanInfo>> build() async {
    return _fetch();
  }

  Future<List<PlanInfo>> _fetch() async {
    try {
      final api = ref.read(apiClientProvider);
      // X-Platform header (set by the API client) filters mobile-only plans
      // for desktop and vice versa — see server's filterPlansForPlatform.
      final response = await api.dio.get('/plans');
      final list = response.data as List<dynamic>;
      return list
          .map((e) => PlanInfo.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Plans] Fetch failed: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final plansProvider = AsyncNotifierProvider<PlansNotifier, List<PlanInfo>>(
  PlansNotifier.new,
);

/// Convenience selector — pluck a single plan by key.
PlanInfo? planByKey(List<PlanInfo>? list, String key) {
  if (list == null) return null;
  for (final p in list) {
    if (p.plan == key) return p;
  }
  return null;
}
