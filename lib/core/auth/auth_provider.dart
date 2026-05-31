import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_log.dart';
import '../../features/glossary/providers/glossary_provider.dart';
import '../../features/history/providers/history_provider.dart';
import '../../features/settings/providers/devices_provider.dart';
import '../../features/settings/providers/subscription_provider.dart';
import '../../features/translate/providers/translate_provider.dart';
import '../../features/upgrade/providers/usage_provider.dart';
import '../api/dio_client.dart';
import '../tracking/tracking_provider.dart';
import 'app_group_bridge.dart';
import 'session_store.dart';

class AuthState {
  const AuthState({
    this.isLoggedIn = false,
    this.session,
    this.isLoading = false,
    this.error,
    this.needsEmailVerification = false,
  });

  final bool isLoggedIn;
  final AuthSession? session;
  final bool isLoading;
  final String? error; // OAuth error code (e.g. 'pro_device_limit')

  /// True right after a register that requires email verification before
  /// login. The account exists but has NO session yet; the UI shows a
  /// "check your inbox" prompt instead of navigating into the app.
  final bool needsEmailVerification;

  AuthState copyWith({
    bool? isLoggedIn,
    AuthSession? session,
    bool? isLoading,
    String? error,
    bool? needsEmailVerification,
  }) =>
      AuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        session: session ?? this.session,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        needsEmailVerification:
            needsEmailVerification ?? this.needsEmailVerification,
      );
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  bool _loginInProgress = false;
  // Serialize refreshUser + refreshIfNeeded so they don't race on session state.
  Future<void>? _refreshChain;

  Future<T> _serializedRefresh<T>(Future<T> Function() work) async {
    final prev = _refreshChain ?? Future.value();
    final completer = Completer<void>();
    _refreshChain = completer.future;
    try {
      await prev;
      return await work();
    } finally {
      completer.complete();
    }
  }

  @override
  Future<AuthState> build() async {
    final sessionStore = ref.read(sessionStoreProvider);
    final session = await sessionStore.load();
    if (session == null) {
      return const AuthState();
    }
    return AuthState(isLoggedIn: true, session: session);
  }

  /// Current session snapshot, readable from outside the notifier without
  /// touching the `@protected` `state`. Lets callers that outlive their
  /// widget (e.g. a post-checkout background refresh after the sheet popped)
  /// read the latest session via the app-scoped notifier instead of a stale
  /// WidgetRef.
  AuthSession? get currentSession => state.valueOrNull?.session;

  /// Drop the in-memory token cache held by the API client so the next
  /// request reads the fresh value we just wrote to storage. Must be called
  /// after any sessionStore.save() / clear() that wasn't triggered by the
  /// auth-refresh interceptor (which invalidates internally).
  void _invalidateApiSessionCache() {
    ref.read(apiClientProvider).invalidateSessionCache();
  }

  /// Drop every per-user provider's cached state so the next account doesn't
  /// see the previous account's data. Without this, switching login leaves
  /// stale usage / history / glossary / subscription / devices visible until
  /// the providers happen to refetch (e.g. 1-minute usage TTL). Most visible
  /// symptom: a free user logged in after a pro user sees pro's 9999/999999
  /// quota until the next refresh, which is confusing AND incorrectly
  /// implies they're on Pro.
  void _invalidateUserScopedProviders() {
    ref.invalidate(usageProvider);
    ref.invalidate(translateProvider);
    // NOTE: do NOT invalidate historyProvider here. It already `ref.watch`es
    // authStateProvider, so it auto-rebuilds for the new user on every
    // login/logout. Invalidating it from inside the auth notifier creates a
    // circular dependency (auth -> history -> auth) that Riverpod throws as
    // CircularDependencyError, surfacing as a login/logout failure.
    ref.invalidate(glossaryProvider);
    ref.invalidate(subscriptionProvider);
    ref.invalidate(devicesProvider);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    if (_loginInProgress) return;
    _loginInProgress = true;
    try {
    final tracking = ref.read(trackingServiceProvider);
    tracking.event('login_attempt', properties: {'method': 'password'});
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
      _invalidateUserScopedProviders();
      await _syncToAppGroup(session);

      tracking.event('login_success',
          properties: {'method': 'password', 'plan': session.plan});
      return AuthState(isLoggedIn: true, session: session);
    });
    if (state.hasError) {
      tracking.event('login_fail', properties: {
        'method': 'password',
        'error':  state.error.runtimeType.toString(),
      });
    }
    } finally {
      _loginInProgress = false;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final tracking = ref.read(trackingServiceProvider);
    tracking.event('register_attempt');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'name': name,
      });

      final data = response.data;

      // Registration requires email verification before login. The API
      // returns an accessToken here, but using it would log unverified
      // accounts straight into the app (the password-login path is blocked
      // server-side until verified, so the token would be a backdoor). Don't
      // save a session; signal the UI to show a "check your inbox" prompt.
      // (Mirrors desktop auth.service + web AuthModal.)
      if (data['emailVerificationRequired'] == true) {
        tracking.event('register_success', properties: {'verify_required': true});
        return const AuthState(needsEmailVerification: true);
      }

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
      _invalidateUserScopedProviders();
      await _syncToAppGroup(session);

      tracking.event('register_success', properties: {'plan': session.plan});
      return AuthState(isLoggedIn: true, session: session);
    });
    if (state.hasError) {
      tracking.event('register_fail',
          properties: {'error': state.error.runtimeType.toString()});
    }
  }

  /// Native Google sign-in: the mobile app already used GoogleSignIn SDK to
  /// produce `idToken`. Verify-and-mint server-side via POST /auth/google/mobile
  /// — no browser, no deep link.
  Future<void> signInWithGoogleIdToken(String idToken) async {
    final tracking = ref.read(trackingServiceProvider);
    tracking.event('login_attempt', properties: {'method': 'google'});
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post(
        '/auth/google/mobile',
        data: {'idToken': idToken},
      ).timeout(const Duration(seconds: 20));

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
      _invalidateUserScopedProviders();
      await _syncToAppGroup(session);

      tracking.event('login_success',
          properties: {'method': 'google', 'plan': session.plan});
      return AuthState(isLoggedIn: true, session: session);
    });
    if (state.hasError) {
      tracking.event('login_fail', properties: {
        'method': 'google',
        'error':  state.error.runtimeType.toString(),
      });
    }
  }

  Future<void> logout() async {
    ref.read(trackingServiceProvider).event('logout');
    final sessionStore = ref.read(sessionStoreProvider);
    await sessionStore.clear();
    _invalidateApiSessionCache();
    _invalidateUserScopedProviders();
    await AppGroupBridge.clearAuth();
    state = const AsyncData(AuthState());
  }

  /// Pull fresh user info from /auth/me — picks up plan changes that
  /// happened outside this device (e.g. checkout completed on web).
  Future<void> refreshUser() => _serializedRefresh(() async {
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
      // No need to invalidate user-scoped providers — same user, just
      // updated metadata (plan changed via web checkout etc).
      await _syncToAppGroup(updated);
      state = AsyncData(AuthState(isLoggedIn: true, session: updated));
    } catch (e) {
      AppLog.w('Auth', 'refreshUser failed', e);
    }
  });

  /// Proactively refresh token if it's about to expire.
  Future<void> refreshIfNeeded() => _serializedRefresh(() async {
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
      // No invalidate — token refresh keeps the same user identity.
      state = AsyncData(AuthState(isLoggedIn: true, session: updated));
    } catch (e) {
      AppLog.w('Auth', 'Proactive refresh failed', e);
    }
  });

  /// Called by the API client when refresh also fails — force logout.
  Future<void> forceLogout() async {
    AppLog.w('Auth', 'Force logout — session expired');
    await logout();
  }

  /// Update session (e.g., after plan upgrade).
  Future<void> updateSession(AuthSession session) async {
    final sessionStore = ref.read(sessionStoreProvider);
    await sessionStore.save(session);
    _invalidateApiSessionCache();
    // Invalidate so the new plan's limits (Pro 9999 vs Free 20) are
    // immediately reflected in QuotaBar etc — same user identity but
    // plan-dependent state changes.
    _invalidateUserScopedProviders();
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
    _invalidateUserScopedProviders();
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
      AppLog.w('Auth', 'AppGroup sync failed', e);
    }
  }
}

final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
