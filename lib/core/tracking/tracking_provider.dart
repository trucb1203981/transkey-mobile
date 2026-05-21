import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import 'tracking_service.dart';

/// Singleton TrackingService. Created lazily on first read; init() is called
/// from [bootstrapTracking] at app start so the session id + device info are
/// hot before any screen / event fires.
final trackingServiceProvider = Provider<TrackingService>((ref) {
  final api = ref.read(apiClientProvider);
  final service = TrackingService(apiClient: api);
  ref.onDispose(service.dispose);
  return service;
});

/// Call once from main() right after the ProviderContainer is built. Loads
/// session id + populates platform/version, then fires the first app_open.
/// Returns the same instance the provider exposes — kept here so call sites
/// inside main() don't need a BuildContext.
Future<TrackingService> bootstrapTracking(ProviderContainer container) async {
  final service = container.read(trackingServiceProvider);
  await service.init();
  unawaited(service.appOpen());
  return service;
}

/// UI-bound state for the "Help improve the app" toggle. Reads the persisted
/// opt-out flag from [TrackingService] and routes writes back through it so
/// the live service immediately stops sending when the user opts out.
class TrackingOptOutNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(trackingServiceProvider).optOut;

  Future<void> set(bool optOut) async {
    await ref.read(trackingServiceProvider).setOptOut(optOut);
    state = optOut;
  }
}

final trackingOptOutProvider =
    NotifierProvider<TrackingOptOutNotifier, bool>(TrackingOptOutNotifier.new);

