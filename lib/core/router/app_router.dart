import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/keyboard_setup_screen.dart';
import '../../features/translate/screens/home_screen.dart';
import '../../features/upgrade/screens/upgrade_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
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
