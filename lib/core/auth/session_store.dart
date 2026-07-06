import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSessionKey = 'tk_auth_session';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.userId,
    required this.email,
    this.name,
    this.plan = 'free',
    this.expiresAt,
    this.isAnonymous = false,
    this.hasPassword = true,
  });

  final String accessToken;
  final String userId;
  final String email;
  final String? name;
  final String plan;
  final String? expiresAt;

  /// False for accounts created via Google/Apple that have never set a password.
  /// Drives "Set password" (no current-password field) vs "Change password".
  /// Defaults to TRUE when unknown (older backend that doesn't send the flag yet)
  /// so existing password accounts keep the working change flow before deploy.
  final bool hasPassword;

  /// True for the device-bound guest session provisioned on first launch
  /// (App Store 5.1.1(v)). The app is fully usable, but account-only surfaces
  /// (the Settings account card, subscribing) prompt the user to sign in first.
  final bool isAnonymous;

  Map<String, dynamic> toMap() => {
        'accessToken': accessToken,
        'userId': userId,
        'email': email,
        'name': name,
        'plan': plan,
        'expiresAt': expiresAt,
        'isAnonymous': isAnonymous,
        'hasPassword': hasPassword,
      };

  factory AuthSession.fromMap(Map<String, dynamic> map) => AuthSession(
        accessToken: map['accessToken'] as String,
        userId: map['userId'] as String,
        email: map['email'] as String,
        name: map['name'] as String?,
        plan: map['plan'] as String? ?? 'free',
        expiresAt: map['expiresAt'] as String?,
        isAnonymous: map['isAnonymous'] as bool? ?? false,
        hasPassword: map['hasPassword'] as bool? ?? true,
      );

  AuthSession copyWith({
    String? accessToken,
    String? userId,
    String? email,
    String? name,
    String? plan,
    String? expiresAt,
    bool? isAnonymous,
    bool? hasPassword,
  }) =>
      AuthSession(
        accessToken: accessToken ?? this.accessToken,
        userId: userId ?? this.userId,
        email: email ?? this.email,
        name: name ?? this.name,
        plan: plan ?? this.plan,
        expiresAt: expiresAt ?? this.expiresAt,
        isAnonymous: isAnonymous ?? this.isAnonymous,
        hasPassword: hasPassword ?? this.hasPassword,
      );

  bool get isPro => plan == 'pro' || plan == 'mobile' || plan == 'trial';

  bool get isBanned => plan == 'banned';
}

// Use EncryptedSharedPreferences on Android (instead of the default Keystore-AES
// implementation) — it's far more reliable on Android 11+ where Keystore can
// hang on MIUI/ColorOS/FuntouchOS skins and on devices with locked-down TEEs.
// Both write through the same secure-storage API, so existing callers don't
// change. Reads/writes are still wrapped in a timeout below so a stuck native
// call can never freeze the login flow.
const _secureStorageOptions = AndroidOptions(
  encryptedSharedPreferences: true,
);

const _storageTimeout = Duration(seconds: 4);

class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: _secureStorageOptions);

  final FlutterSecureStorage _storage;

  // ── In-process static cache ────────────────────────────────────────────────
  // FlutterSecureStorage.read() is a JNI call into EncryptedSharedPreferences
  // that can take 5-30 ms on stock Android and up to 200-500 ms on
  // MIUI / ColorOS / FuntouchOS skins. The Lens hot path calls load() on
  // every trigger (batch AND vision), so the disk read adds visible latency.
  //
  // The session token changes only on login / logout / token refresh — all of
  // which go through save() or clear() below, which update _cache immediately.
  // The TTL is a safety net for edge-cases (process keeps running >30 min
  // after a password change on another device), not the primary eviction path.
  static AuthSession? _cache;
  static DateTime? _cachedAt;
  static const _kCacheTtl = Duration(minutes: 30);

  Future<void> save(AuthSession session) async {
    // Update cache immediately so the very next load() call (e.g. the Lens
    // batch that fires right after a token refresh) sees the new token.
    _cache = session;
    _cachedAt = DateTime.now();
    final value = jsonEncode(session.toMap());
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSessionKey, value);
      return;
    }
    try {
      await _storage
          .write(key: _kSessionKey, value: value)
          .timeout(_storageTimeout);
    } catch (e) {
      debugPrint('[SessionStore] secure write failed, falling back: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSessionKey, value);
    }
  }

  Future<AuthSession?> load() async {
    // Fast path: return cached session if it's still fresh.
    final now = DateTime.now();
    if (_cache != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _kCacheTtl) {
      return _cache;
    }
    // Cache miss / expired — read from secure storage and populate cache.
    final raw = await _readRaw();
    if (raw == null) {
      _cache = null;
      _cachedAt = null;
      return null;
    }
    try {
      final session = AuthSession.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _cache = session;
      _cachedAt = now;
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    // Invalidate cache immediately so the next load() returns null, even if
    // the secure-storage delete is still in flight.
    _cache = null;
    _cachedAt = null;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSessionKey);
      return;
    }
    // Neutralise BEFORE deleting: on some Android skins (MIUI/ColorOS) the
    // Keystore-backed delete intermittently times out, leaving the OLD
    // token in secure storage. A later login then reads that stale token on
    // cold start and gets bounced back to the login screen. Overwriting the
    // value with "" first means even a timed-out delete can't resurrect a
    // usable token — write and delete are two independent chances to clear,
    // and `_readRaw` treats an empty value as absent (falls through to prefs).
    try {
      await _storage
          .write(key: _kSessionKey, value: '')
          .timeout(_storageTimeout);
    } catch (e) {
      debugPrint('[SessionStore] secure tombstone write failed: $e');
    }
    try {
      await _storage.delete(key: _kSessionKey).timeout(_storageTimeout);
    } catch (e) {
      debugPrint('[SessionStore] secure delete failed: $e');
    }
    // Also clear any fallback copy.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
  }

  Future<String?> _readRaw() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kSessionKey);
    }
    try {
      final fromSecure = await _storage
          .read(key: _kSessionKey)
          .timeout(_storageTimeout);
      // Treat an empty value as ABSENT, not as a real session. clear()
      // writes "" as a tombstone, and an empty/whitespace blob can never be
      // a valid JSON session anyway — falling through to prefs here prevents
      // that tombstone from shadowing a freshly-saved session when a later
      // save() had to fall back to prefs (secure write timed out).
      if (fromSecure != null && fromSecure.trim().isNotEmpty) {
        return fromSecure;
      }
    } catch (e) {
      debugPrint('[SessionStore] secure read failed, falling back: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSessionKey);
  }

  bool isExpiringSoon(AuthSession session) {
    if (session.expiresAt == null) return false;
    try {
      final expires = DateTime.parse(session.expiresAt!);
      final threshold = DateTime.now().add(const Duration(days: 7));
      return expires.isBefore(threshold);
    } catch (_) {
      return false;
    }
  }
}
