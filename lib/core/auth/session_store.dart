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
  });

  final String accessToken;
  final String userId;
  final String email;
  final String? name;
  final String plan;
  final String? expiresAt;

  Map<String, dynamic> toMap() => {
        'accessToken': accessToken,
        'userId': userId,
        'email': email,
        'name': name,
        'plan': plan,
        'expiresAt': expiresAt,
      };

  factory AuthSession.fromMap(Map<String, dynamic> map) => AuthSession(
        accessToken: map['accessToken'] as String,
        userId: map['userId'] as String,
        email: map['email'] as String,
        name: map['name'] as String?,
        plan: map['plan'] as String? ?? 'free',
        expiresAt: map['expiresAt'] as String?,
      );

  AuthSession copyWith({
    String? accessToken,
    String? userId,
    String? email,
    String? name,
    String? plan,
    String? expiresAt,
  }) =>
      AuthSession(
        accessToken: accessToken ?? this.accessToken,
        userId: userId ?? this.userId,
        email: email ?? this.email,
        name: name ?? this.name,
        plan: plan ?? this.plan,
        expiresAt: expiresAt ?? this.expiresAt,
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

  Future<void> save(AuthSession session) async {
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
    final raw = await _readRaw();
    if (raw == null) return null;
    try {
      return AuthSession.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSessionKey);
      return;
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
      if (fromSecure != null) return fromSecure;
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
