import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';

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
  });

  final bool translate;
  final bool summarize;
  final bool explain;
  final bool refine;
  final bool replyTranslate;
  final bool replySuggestions;
  final bool glossary;
  final bool toneOverride;
  final bool romanization;

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
      );
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
      final flags = FeatureFlags.fromMap(
        response.data as Map<String, dynamic>,
      );
      state = FeaturesState(
        flags: flags,
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      // Keep previous flags on error
      state = current.copyWith(isLoading: false);
    }
  }

  /// Fetch only if cache is stale or empty.
  Future<void> refreshIfNeeded() async {
    if (state.isStale) await fetch();
  }
}

final featuresProvider =
    NotifierProvider<FeaturesNotifier, FeaturesState>(
  FeaturesNotifier.new,
);
