import 'package:flutter/material.dart';

import 'tracking_service.dart';

/// NavigatorObserver that fires `screen()` on every push / pop / replace so
/// the analytics dashboard's "top pages" table covers mobile flows without
/// every screen having to remember to log itself.
///
/// Wire from main.dart via `MaterialApp.router(... observers: ...)` (or for
/// GoRouter: `GoRouter(..., observers: [TrackingRouterObserver(service)])`).
class TrackingRouterObserver extends NavigatorObserver {
  TrackingRouterObserver(this._tracking);
  final TrackingService _tracking;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _track(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _track(previousRoute);
    super.didPop(route, previousRoute);
  }

  void _track(Route<dynamic> route) {
    final name = _routeName(route);
    if (name == null) return;
    _tracking.screen(name);
  }

  /// Only emit when the route has a stable `RouteSettings.name` (which
  /// GoRouter sets to the `fullPath`). Skip anonymous routes — modal
  /// bottom sheets, dialogs, page-transition anims — because their
  /// `runtimeType.toString()` includes generic args (e.g.
  /// `ModalBottomSheetRoute<bool?>`) which fragments the analytics
  /// `top pages` aggregation into garbage rows that can't be told apart.
  /// If a sheet is worth tracking, fire an explicit `event()` from inside
  /// the sheet's `initState` (see CameraTipsSheet, PaywallSheet…).
  String? _routeName(Route<dynamic> route) {
    final settingsName = route.settings.name;
    if (settingsName != null && settingsName.isNotEmpty) return settingsName;
    return null;
  }
}
