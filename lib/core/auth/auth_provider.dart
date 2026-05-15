import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import 'app_group_bridge.dart';
import 'session_store.dart';

class AuthState {
  const AuthState({
    this.isLoggedIn = false,
    this.session,
    this.isLoading = false,
    this.error,
  });

  final bool isLoggedIn;
  final AuthSession? session;
  final bool isLoading;
  final String? error; // OAuth error code (e.g. 'pro_device_limit')

  AuthState copyWith({
    bool? isLoggedIn,
    AuthSession? session,
    bool? isLoading,
    String? error,
  }) =>
      AuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        session: session ?? this.session,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final sessionStore = ref.read(sessionStoreProvider);
    final session = await sessionStore.load();
    if (session == null) {
      return const AuthState();
    }
    return AuthState(isLoggedIn: true, session: session);
  }

  /// Drop the in-memory token cache held by the API client so the next
  /// request reads the fresh value we just wrote to storage. Must be called
  /// after any sessionStore.save() / clear() that wasn't triggered by the
  /// auth-refresh interceptor (which invalidates internally).
  void _invalidateApiSessionCache() {
    ref.read(apiClientProvider).invalidateSessionCache();
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      // Hard 20s ceiling on the whole flow — protects against the spinner
      // hanging forever if a native-side step (secure storage, device info)
      // freezes the request pipeline.
      final response = await api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      }).timeout(const Duration(seconds: 20));

      final data = response.data;
      final user = data['user'] as Map<String, dynamic>;
      final session = AuthSession(
        accessToken: data['accessToken'] as String,
        userId: user['id'].toString(),
        email: user['email'] as String,
        name: user['name'] as String?,
        plan: user['plan'] as String? ?? 'free',
        expiresAt: data['expiresAt'] as String?,
      );

      final sessionStore = ref.read(sessionStoreProvider);
      await sessionStore.save(session);
      _invalidateApiSessionCache();
      await _syncToAppGroup(session);

      return AuthState(isLoggedIn: true, session: session);
    });
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'name': name,
      });

      final data = response.data;
      final user = data['user'] as Map<String, dynamic>;
      final session = AuthSession(
        accessToken: data['accessToken'] as String,
        userId: user['id'].toString(),
        email: user['email'] as String,
        name: user['name'] as String?,
        plan: user['plan'] as String? ?? 'free',
        expiresAt: data['expiresAt'] as String?,
      );

      final sessionStore = ref.read(sessionStoreProvider);
      await sessionStore.save(session);
      _invalidateApiSessionCache();
      await _syncToAppGroup(session);

      return AuthState(isLoggedIn: true, session: session);
    });
  }

  Future<void> logout() async {
    final sessionStore = ref.read(sessionStoreProvider);
    await sessionStore.clear();
    _invalidateApiSessionCache();
    await AppGroupBridge.clearAuth();
    state = const AsyncData(AuthState());
  }

  /// Pull fresh user info from /auth/me — picks up plan changes that
  /// happened outside this device (e.g. checkout completed on web).
  Future<void> refreshUser() async {
    final current = state.valueOrNull?.session;
    if (current == null) return;
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/auth/me');
      final data = response.data;
      final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? data as Map<String, dynamic>;
      final updated = current.copyWith(
        userId: user['id']?.toString() ?? current.userId,
        email: user['email'] as String? ?? current.email,
        name: (user['name'] as String?) ?? current.name,
        plan: user['plan'] as String? ?? current.plan,
      );
      final sessionStore = ref.read(sessionStoreProvider);
      await sessionStore.save(updated);
      _invalidateApiSessionCache();
      await _syncToAppGroup(updated);
      state = AsyncData(AuthState(isLoggedIn: true, session: updated));
    } catch (e) {
      debugPrint('[Auth] refreshUser failed: $e');
    }
  }

  /// Proactively refresh token if it's about to expire.
  Future<void> refreshIfNeeded() async {
    final sessionStore = ref.read(sessionStoreProvider);
    final session = await sessionStore.load();
    if (session == null) return;

    if (!sessionStore.isExpiringSoon(session)) return;

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post(
        '/auth/refresh',
        options: Options(headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        }),
      );

      final newToken = response.data['accessToken'] as String;
      final expiresAt = response.data['expiresAt'] as String?;
      final updated = session.copyWith(
        accessToken: newToken,
        expiresAt: expiresAt,
      );

      await sessionStore.save(updated);
      _invalidateApiSessionCache();
      state = AsyncData(AuthState(isLoggedIn: true, session: updated));
    } catch (e) {
      debugPrint('[Auth] Proactive refresh failed: $e');
    }
  }

  /// Called by the API client when refresh also fails — force logout.
  Future<void> forceLogout() async {
    debugPrint('[Auth] Force logout — session expired');
    await logout();
  }

  /// Update session (e.g., after plan upgrade).
  Future<void> updateSession(AuthSession session) async {
    final sessionStore = ref.read(sessionStoreProvider);
    await sessionStore.save(session);
    _invalidateApiSessionCache();
    await _syncToAppGroup(session);
    state = AsyncData(AuthState(isLoggedIn: true, session: session));
  }

  /// Handle deep link: transkey://auth?token=... or transkey://auth?error=...
  Future<void> handleDeepLink(Uri uri) async {
    if (uri.host != 'auth') return;

    // OAuth error (e.g. device limit, cancelled)
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      state = AsyncData(AuthState(error: error));
      return;
    }

    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;

    final session = AuthSession(
      accessToken: token,
      userId: uri.queryParameters['id'] ?? '',
      email: uri.queryParameters['email'] ?? '',
      name: uri.queryParameters['name'],
      plan: uri.queryParameters['plan'] ?? 'free',
      expiresAt: uri.queryParameters['expiresAt'],
    );

    final sessionStore = ref.read(sessionStoreProvider);
    await sessionStore.save(session);
    _invalidateApiSessionCache();
    await _syncToAppGroup(session);
    state = AsyncData(AuthState(isLoggedIn: true, session: session));
  }

  Future<void> _syncToAppGroup(AuthSession session) async {
    try {
      final deviceIdService = ref.read(deviceIdProvider);
      final deviceId = await deviceIdService.getFingerprint();
      final baseUrl = dotenv.env['TRANSKEY_API_URL'] ?? 'https://api.transkey.app';
      await AppGroupBridge.saveAuth(
        token: session.accessToken,
        deviceId: deviceId,
        plan: session.plan,
        baseURL: baseUrl,
      );
    } catch (e) {
      debugPrint('[Auth] AppGroup sync failed: $e');
    }
  }
}

final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
