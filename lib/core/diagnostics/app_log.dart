import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight structured logger for the mobile app.
///
/// Wraps `dart:developer.log` so log lines carry a stable `[tag]` prefix
/// and a numeric `level` (DartDevTools renders these as filterable rows
/// and the Android logcat bridge tags them as `verbose / info / warning
/// / severe`).
///
/// Why not just `debugPrint`:
///  - debugPrint has no level — every line is verbose, can't filter
///  - debugPrint strips nothing in release builds (still prints from the
///    Flutter engine), so production users emit logs we never see
///  - developer.log respects DevTools' "show level" toggle and supports
///    an `error` object that DevTools renders inline with the stack
///
/// Usage:
/// ```dart
/// AppLog.d('Auth', 'login response received');
/// AppLog.w('Glossary', 'sync failed', err);
/// AppLog.e('Lens', 'capture pipeline broke', err, stack);
/// ```
///
/// Migrating from debugPrint:
///  - `debugPrint('[Auth] ...')` → `AppLog.d('Auth', '...')`
///  - `debugPrint('[Foo] failed: $e')` → `AppLog.w('Foo', 'failed', e)`
class AppLog {
  AppLog._();

  /// Verbose / debug. Use for routine flow tracing. Stripped from logcat
  /// output in release builds (DevTools still shows them in debug).
  static void d(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(tag, message, _kDebug, error, stack);

  /// Informational milestone. Use for user-visible state changes (logged
  /// in, switched language, paid plan activated).
  static void i(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(tag, message, _kInfo, error, stack);

  /// Recoverable issue. Use when a feature falls back to defaults (e.g.
  /// glossary JSON corrupted → loaded empty; refresh failed → retried).
  static void w(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(tag, message, _kWarning, error, stack);

  /// Unrecoverable failure. Use when the user sees a broken outcome
  /// (translation failed, payment couldn't apply, force-logout triggered).
  static void e(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(tag, message, _kSevere, error, stack);

  // dart:developer.log() level constants (mirrors java.util.logging.Level).
  static const _kDebug   = 500;
  static const _kInfo    = 800;
  static const _kWarning = 900;
  static const _kSevere  = 1000;

  static void _log(
    String tag,
    String message,
    int level,
    Object? error,
    StackTrace? stack,
  ) {
    // dart:developer.log skips the lower-level rendering in release builds
    // for severity < INFO — keeps end-user devices quiet without us having
    // to wrap every d() call in kDebugMode.
    if (!kDebugMode && level < _kInfo) return;
    developer.log(
      message,
      name: tag,
      level: level,
      error: error,
      stackTrace: stack,
    );
  }
}
