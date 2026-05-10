import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
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
  final String? error;

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

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final data = response.data;
      final user = data['user'] as Map<String, dynamic>;
      final session = AuthSession(
        accessToken: data['accessToken'] as String,
        userId: user['id'] as String,
        email: user['email'] as String,
        name: user['name'] as String?,
        plan: user['plan'] as String? ?? 'free',
      );

      final sessionStore = ref.read(sessionStoreProvider);
      await sessionStore.save(session);

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
        userId: user['id'] as String,
        email: user['email'] as String,
        name: user['name'] as String?,
        plan: user['plan'] as String? ?? 'free',
      );

      final sessionStore = ref.read(sessionStoreProvider);
      await sessionStore.save(session);

      return AuthState(isLoggedIn: true, session: session);
    });
  }

  Future<void> logout() async {
    final sessionStore = ref.read(sessionStoreProvider);
    await sessionStore.clear();
    state = const AsyncData(AuthState());
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
    state = AsyncData(AuthState(isLoggedIn: true, session: session));
  }

  /// Handle deep link: transkey://auth?token=...&email=...&name=...&plan=...
  Future<void> handleDeepLink(Uri uri) async {
    if (uri.host != 'auth') return;

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
    state = AsyncData(AuthState(isLoggedIn: true, session: session));
  }
}

final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
