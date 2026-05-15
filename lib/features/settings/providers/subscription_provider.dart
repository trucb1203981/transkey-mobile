import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';

class SubscriptionInfo {
  const SubscriptionInfo({
    required this.active,
    this.status,
    this.renewsAt,
    this.endsAt,
    this.trialEndsAt,
  });

  final bool active;
  final String? status;
  final String? renewsAt;
  final String? endsAt;
  final String? trialEndsAt;

  bool get isCancelled => status == 'cancelled';

  factory SubscriptionInfo.fromMap(Map<String, dynamic> map) => SubscriptionInfo(
        active: map['active'] as bool? ?? false,
        status: map['status'] as String?,
        renewsAt: map['renews_at'] as String?,
        endsAt: map['ends_at'] as String?,
        trialEndsAt: map['trial_ends_at'] as String?,
      );
}

class SubscriptionNotifier extends AsyncNotifier<SubscriptionInfo> {
  @override
  Future<SubscriptionInfo> build() async {
    return _fetch();
  }

  Future<SubscriptionInfo> _fetch() async {
    final api = ref.read(apiClientProvider);
    final response = await api.dio.get('/auth/subscription');
    return SubscriptionInfo.fromMap(response.data as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      debugPrint('[Subscription] fetch failed: $e');
      state = AsyncError(e, st);
    }
  }

  /// Returns null on success, or an error message.
  Future<String?> cancel() async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/auth/subscription/cancel');
      await refresh();
      return null;
    } catch (e) {
      debugPrint('[Subscription] cancel failed: $e');
      return e.toString();
    }
  }
}

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, SubscriptionInfo>(
  SubscriptionNotifier.new,
);
