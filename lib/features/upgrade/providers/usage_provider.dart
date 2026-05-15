import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';

class UsageInfo {
  const UsageInfo({
    required this.plan,
    required this.requestsUsed,
    required this.requestsLimit,
    required this.charsUsed,
    required this.charsLimit,
    this.glossaryLimit = 50,
    this.trialEndsAt,
    this.trialUsed = false,
    this.subEndsAt,
    this.subExpired = false,
    this.firstMonthDiscount = false,
  });

  final String plan;
  final int requestsUsed;
  final int requestsLimit;
  final int charsUsed;
  final int charsLimit;
  final int glossaryLimit;
  final String? trialEndsAt;
  final bool trialUsed;
  final String? subEndsAt;
  final bool subExpired;
  final bool firstMonthDiscount;

  factory UsageInfo.fromMap(Map<String, dynamic> map) {
    final quota = (map['quota'] as Map?)?.cast<String, dynamic>() ?? const {};
    return UsageInfo(
      plan: map['plan'] as String? ?? 'free',
      requestsUsed: (quota['used'] as num?)?.toInt() ?? 0,
      requestsLimit: (quota['limit'] as num?)?.toInt() ?? 0,
      charsUsed: (quota['charsUsed'] as num?)?.toInt() ?? 0,
      charsLimit: (quota['charsLimit'] as num?)?.toInt() ?? 0,
      glossaryLimit: (map['glossaryLimit'] as num?)?.toInt() ?? 50,
      trialEndsAt: map['trialEndsAt'] as String?,
      trialUsed: map['trialUsed'] as bool? ?? false,
      subEndsAt: map['subEndsAt'] as String?,
      subExpired: map['subExpired'] as bool? ?? false,
      firstMonthDiscount: map['firstMonthDiscount'] as bool? ?? false,
    );
  }
}

class UsageNotifier extends AsyncNotifier<UsageInfo?> {
  DateTime? _fetchedAt;
  static const _ttl = Duration(minutes: 1);

  @override
  Future<UsageInfo?> build() async {
    return _fetch();
  }

  Future<UsageInfo?> _fetch() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/usage');
      final usage = UsageInfo.fromMap(response.data as Map<String, dynamic>);
      _fetchedAt = DateTime.now();
      return usage;
    } catch (e) {
      debugPrint('[Usage] Fetch failed: $e');
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _fetch());
  }

  Future<void> refreshIfStale() async {
    if (_fetchedAt == null ||
        DateTime.now().difference(_fetchedAt!) > _ttl) {
      await refresh();
    }
  }
}

final usageProvider =
    AsyncNotifierProvider<UsageNotifier, UsageInfo?>(UsageNotifier.new);
