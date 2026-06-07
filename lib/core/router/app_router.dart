import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../tracking/tracking_provider.dart';
import '../tracking/tracking_router_observer.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/screens/banned_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/keyboard_setup_screen.dart';
import '../../features/settings/screens/change_password_screen.dart';
import '../../features/settings/screens/devices_screen.dart';
import '../../features/settings/screens/guide_screen.dart';
import '../../features/settings/screens/keyboard_settings_screen.dart';
import '../../features/settings/screens/subscription_screen.dart';
import '../../features/translate/screens/camera_screen.dart';
import '../../features/phrasebook/screens/phrasebook_screen.dart';
import '../../features/translate/screens/explain_screen.dart';
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

  final tracking = ref.read(trackingServiceProvider);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    observers: [TrackingRouterObserver(tracking)],
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      // Still loading — don't redirect yet
      if (authState.isLoading) return null;
      final auth = authState.valueOrNull;
      final isLoggedIn = auth?.isLoggedIn ?? false;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      final isOnboarding = state.matchedLocation == '/onboarding';
      final isBannedRoute = state.matchedLocation == '/banned';

      // Banned users see the full-screen notice — block every other route.
      // Logout (from inside BannedScreen) clears session, redirect then
      // sends them to /auth/login.
      if (isLoggedIn && (auth?.session?.isBanned ?? false)) {
        return isBannedRoute ? null : '/banned';
      }

      if (!isLoggedIn && !isAuthRoute && !isOnboarding) return '/auth/login';
      if (isLoggedIn && (isAuthRoute || isOnboarding || isBannedRoute)) return '/';

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
        path: '/banned',
        builder: (context, state) => const BannedScreen(),
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
      GoRoute(
        path: '/settings/guide',
        builder: (context, state) => const GuideScreen(),
      ),
      GoRoute(
        path: '/settings/keyboard',
        builder: (context, state) => const KeyboardSettingsScreen(),
      ),
      GoRoute(
        path: '/camera',
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: '/phrasebook',
        builder: (context, state) => const PhrasebookScreen(),
      ),
      GoRoute(
        path: '/explain',
        // Native bubble Lens overlay routes here on long-press of a block so
        // the user can run "What is this?" on the region-selected text. The
        // text travels in [state.extra] (a Dart string). Empty/null text
        // collapses to a no-op screen that immediately pops.
        builder: (context, state) {
          final text = state.extra is String ? state.extra as String : '';
          return ExplainScreen(text: text);
        },
      ),
    ],
  );

  _initDeepLinkListener(ref, router);
  ref.onDispose(() {
    _deepLinkSub?.cancel();
    _deepLinkSub = null;
  });
  return router;
});

StreamSubscription<Uri>? _deepLinkSub;

void _initDeepLinkListener(Ref ref, GoRouter router) {
  _deepLinkSub?.cancel();
  if (kIsWeb) return;

  try {
    // transkey://upgrade — fired by the iOS keyboard extension's "Upgrade"
    // CTA when a free user hits the daily quota. Route to the upgrade screen
    // (same destination as the bubble/keyboard upsell on Android); auth links
    // (transkey://auth/...) still go through the auth handler.
    bool handleUpgradeLink(Uri uri) {
      if (uri.host != 'upgrade') return false;
      ref.read(trackingServiceProvider).event('keyboard_quota_upsell');
      router.push('/upgrade');
      return true;
    }

    final appLinks = AppLinks();
    _deepLinkSub = appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('[DeepLink] Received: $uri');
        if (handleUpgradeLink(uri)) return;
        ref.read(authStateProvider.notifier).handleDeepLink(uri);
      },
      onError: (err) => debugPrint('[DeepLink] Error: $err'),
    );

    appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('[DeepLink] Initial: $uri');
        if (handleUpgradeLink(uri)) return;
        ref.read(authStateProvider.notifier).handleDeepLink(uri);
      }
    }).catchError((_) {});
  } catch (e) {
    debugPrint('[DeepLink] Init failed: $e');
  }
}
