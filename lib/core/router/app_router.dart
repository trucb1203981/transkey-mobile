import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/keyboard_setup_screen.dart';
import '../../features/settings/screens/change_password_screen.dart';
import '../../features/settings/screens/devices_screen.dart';
import '../../features/settings/screens/subscription_screen.dart';
import '../../features/translate/screens/home_screen.dart';
import '../../features/upgrade/screens/upgrade_screen.dart';

// ChangeNotifier that triggers GoRouter to re-run redirect whenever auth changes.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _sub = ref.listen<AsyncValue<AuthState>>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
  late final ProviderSubscription<AsyncValue<AuthState>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      // Still loading — don't redirect yet
      if (authState.isLoading) return null;
      final auth = authState.valueOrNull;
      final isLoggedIn = auth?.isLoggedIn ?? false;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      final isOnboarding = state.matchedLocation == '/onboarding';

      if (!isLoggedIn && !isAuthRoute && !isOnboarding) return '/auth/login';
      if (isLoggedIn && (isAuthRoute || isOnboarding)) return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/upgrade',
        builder: (context, state) => const UpgradeScreen(),
      ),
      GoRoute(
        path: '/keyboard-setup',
        builder: (context, state) => KeyboardSetupScreen(
          showSkip: state.uri.queryParameters['skip'] != 'false',
        ),
      ),
      GoRoute(
        path: '/settings/devices',
        builder: (context, state) => const DevicesScreen(),
      ),
      GoRoute(
        path: '/settings/subscription',
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/settings/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
    ],
  );

  _initDeepLinkListener(ref, router);
  return router;
});

StreamSubscription<Uri>? _deepLinkSub;

void _initDeepLinkListener(Ref ref, GoRouter router) {
  _deepLinkSub?.cancel();
  if (kIsWeb) return;

  try {
    final appLinks = AppLinks();
    _deepLinkSub = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('[DeepLink] Received: $uri');
        ref.read(authStateProvider.notifier).handleDeepLink(uri);
      },
      onError: (err) => debugPrint('[DeepLink] Error: $err'),
    );

    appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('[DeepLink] Initial: $uri');
        ref.read(authStateProvider.notifier).handleDeepLink(uri);
      }
    }).catchError((_) {});
  } catch (e) {
    debugPrint('[DeepLink] Init failed: $e');
  }
}
