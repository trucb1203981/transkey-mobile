import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';

class UserDevice {
  const UserDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.firstSeenAt,
    required this.lastUsedAt,
  });

  final String deviceId;
  final String? deviceName;
  final String platform; // 'desktop' | 'mobile'
  final String firstSeenAt;
  final String lastUsedAt;

  factory UserDevice.fromMap(Map<String, dynamic> map) => UserDevice(
        deviceId: map['deviceId'] as String,
        deviceName: map['deviceName'] as String?,
        platform: map['platform'] as String? ?? 'desktop',
        firstSeenAt: map['firstSeenAt'] as String? ?? '',
        lastUsedAt: map['lastUsedAt'] as String? ?? '',
      );
}

class DevicesNotifier extends AsyncNotifier<List<UserDevice>> {
  @override
  Future<List<UserDevice>> build() async {
    return _fetch();
  }

  Future<List<UserDevice>> _fetch() async {
    final api = ref.read(apiClientProvider);
    final response = await api.dio.get('/auth/user/devices');
    final list = (response.data['devices'] as List?) ?? const [];
    return list
        .map((e) => UserDevice.fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _fetch());
    } catch (e, st) {
      debugPrint('[Devices] fetch failed: $e');
      state = AsyncError(e, st);
    }
  }

  Future<bool> remove(String deviceId) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.delete('/auth/user/devices/$deviceId');
      final current = state.valueOrNull ?? const <UserDevice>[];
      state = AsyncData(
        current.where((d) => d.deviceId != deviceId).toList(growable: false),
      );
      return true;
    } catch (e) {
      debugPrint('[Devices] remove failed: $e');
      return false;
    }
  }
}

final devicesProvider =
    AsyncNotifierProvider<DevicesNotifier, List<UserDevice>>(
  DevicesNotifier.new,
);
