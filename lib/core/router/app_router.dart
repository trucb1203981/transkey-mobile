import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uni_links/uni_links.dart';

import '../auth/auth_provider.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';

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
        builder: (context, state) => const _HomePlaceholder(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const AuthScreen(),
      ),
    ],
  );

  // Listen for deep links
  _initDeepLinkListener(ref, router);

  return router;
});

StreamSubscription<Uri?>? _deepLinkSub;

void _initDeepLinkListener(Ref ref, GoRouter router) {
  // Clean up previous subscription
  _deepLinkSub?.cancel();

  if (kIsWeb) return;

  try {
    _deepLinkSub = uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          debugPrint('[DeepLink] Received: $uri');
          ref.read(authStateProvider.notifier).handleDeepLink(uri);
        }
      },
      onError: (err) {
        debugPrint('[DeepLink] Error: $err');
      },
    );

    // Also check initial link (app opened via deep link while cold-starting)
    getInitialUri().then((Uri? uri) {
      if (uri != null) {
        debugPrint('[DeepLink] Initial: $uri');
        ref.read(authStateProvider.notifier).handleDeepLink(uri);
      }
    }).catchError((_) {});
  } catch (e) {
    debugPrint('[DeepLink] Init failed: $e');
  }
}

// Placeholder — will be replaced by HomeScreen in translate feature
class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TransKey')),
      body: const Center(child: Text('Home — coming soon')),
    );
  }
}
