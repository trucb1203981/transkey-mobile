import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tracking_service.dart';

/// Wires Flutter / Dart error hooks into [TrackingService.crash] so every
/// uncaught exception lands in `mobile_crashes`. Call once from main() AFTER
/// the tracking service is initialised; safe to call from inside
/// runZonedGuarded.
///
/// Three hooks cover the realistic surface:
///  1. [FlutterError.onError] — widget / framework errors during build / paint.
///  2. [PlatformDispatcher.instance.onError] — async errors that escape the
///     widget tree (e.g. unawaited futures inside the root zone).
///  3. The caller wraps `runApp` in `runZonedGuarded` and forwards uncaught
///     zone errors via [reportZoneError].
class CrashReporter {
  CrashReporter(this._tracking);

  final TrackingService _tracking;

  /// Hook Flutter's two error sinks. The previous handler (if any — usually
  /// the framework's red-error-screen renderer in debug) is preserved so the
  /// developer experience doesn't change.
  void install() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _send(
        name:    _exceptionTypeName(details.exception, fallback: 'FlutterError'),
        message: details.exceptionAsString(),
        stack:   details.stack?.toString(),
        fatal:   false,
        context: {
          if (details.library != null) 'library': details.library,
          if (details.context != null) 'context': details.context!.toDescription(),
        },
      );
      previousFlutter?.call(details);
    };

    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _send(
        name:    _exceptionTypeName(error),
        message: error.toString(),
        stack:   stack.toString(),
        fatal:   true,
        context: {'source': 'platform_dispatcher'},
      );
      final handled = previousPlatform?.call(error, stack) ?? false;
      return handled;
    };
  }

  /// Forward an error caught by `runZonedGuarded`. Marked fatal because the
  /// zone guard catches root-zone async errors that would otherwise crash
  /// the isolate.
  void reportZoneError(Object error, StackTrace stack) {
    _send(
      name:    _exceptionTypeName(error),
      message: error.toString(),
      stack:   stack.toString(),
      fatal:   true,
      context: {'source': 'zone_guard'},
    );
  }

  /// Manual report for caught-but-noteworthy errors (e.g. failed background
  /// sync where the app keeps running). Non-fatal by default.
  void reportHandled(Object error, StackTrace stack,
      {Map<String, Object?>? context}) {
    _send(
      name:    _exceptionTypeName(error),
      message: error.toString(),
      stack:   stack.toString(),
      fatal:   false,
      context: {'source': 'manual', ...?context},
    );
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  void _send({
    required String name,
    required String message,
    String? stack,
    required bool fatal,
    Map<String, Object?>? context,
  }) {
    unawaited(_tracking.crash(
      name:       name,
      message:    message,
      stack:      stack,
      fatal:      fatal,
      properties: context,
    ));
  }

  String _exceptionTypeName(Object error, {String fallback = 'Exception'}) {
    final runtime = error.runtimeType.toString();
    if (runtime.isEmpty || runtime == 'Object') return fallback;
    return runtime;
  }
}
