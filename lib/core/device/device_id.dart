import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDeviceFingerprintKey = 'tk_device_fingerprint';
const _kStorageTimeout = Duration(seconds: 4);
const _kDeviceInfoTimeout = Duration(seconds: 3);
const _kBubbleChannel = MethodChannel('transkey/bubble');

class DeviceIdService {
  DeviceIdService({
    required FlutterSecureStorage secureStorage,
    required DeviceInfoPlugin deviceInfo,
  })  : _secureStorage = secureStorage,
        _deviceInfo = deviceInfo;

  final FlutterSecureStorage _secureStorage;
  final DeviceInfoPlugin _deviceInfo;

  String? _cachedFingerprint;

  Future<String> getFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    // Try reading from storage
    final stored = await _read();
    if (stored != null) {
      _cachedFingerprint = stored;
      return stored;
    }

    final raw = await _buildRawId();
    final hash = sha256.convert(raw.codeUnits).toString();

    await _write(hash);
    _cachedFingerprint = hash;
    return hash;
  }

  Future<String?> _read() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kDeviceFingerprintKey);
    }
    try {
      final v = await _secureStorage
          .read(key: _kDeviceFingerprintKey)
          .timeout(_kStorageTimeout);
      if (v != null) return v;
    } catch (e) {
      debugPrint('[DeviceId] secure read failed, falling back: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDeviceFingerprintKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDeviceFingerprintKey, value);
      return;
    }
    // Always mirror to SharedPreferences so a future secure-storage failure
    // can still recover the same fingerprint (keeps device identity stable).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceFingerprintKey, value);
    try {
      await _secureStorage
          .write(key: _kDeviceFingerprintKey, value: value)
          .timeout(_kStorageTimeout);
    } catch (e) {
      debugPrint('[DeviceId] secure write failed: $e');
    }
  }

  Future<String> _buildRawId() async {
    if (kIsWeb) {
      // Web: use a persistent random ID stored in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('tk_web_device_id');
      if (existing != null) return existing;
      final newId = 'web_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('tk_web_device_id', newId);
      return newId;
    }
    // Android: prefer SSAID. It survives reinstall (resets only on factory
    // reset / a different signing key) so cài lại doesn't mint a new device.
    // The Build.ID-based fingerprint below is the fallback for null/all-zero
    // SSAID (some custom ROMs) — it dies on uninstall, hence only a fallback.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ssaid = await _androidId();
      if (ssaid != null &&
          ssaid.isNotEmpty &&
          ssaid.replaceAll('0', '').isNotEmpty) {
        return 'ssaid_$ssaid';
      }
    }
    try {
      final info = await _deviceInfo.deviceInfo.timeout(_kDeviceInfoTimeout);
      final data = info.data;
      if (info.data.containsKey('identifierForVendor')) {
        return '${data['identifierForVendor']}_${data['utsname']?['machine'] ?? 'ios'}';
      }
      return '${data['id'] ?? 'unknown'}_${data['manufacturer'] ?? 'unknown'}_${data['model'] ?? 'unknown'}';
    } catch (e) {
      debugPrint('[DeviceId] Failed to get device info: $e');
      // Persist the fallback raw id so a second cold-start failure reuses the
      // same value instead of minting a new "device" each launch (which would
      // trip the Pro plan device limit).
      return _persistentFallbackId();
    }
  }

  Future<String?> _androidId() async {
    try {
      return await _kBubbleChannel
          .invokeMethod<String>('androidId')
          .timeout(_kDeviceInfoTimeout);
    } catch (e) {
      debugPrint('[DeviceId] androidId channel failed: $e');
      return null;
    }
  }

  Future<String> _persistentFallbackId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('tk_fallback_raw_id');
    if (existing != null) return existing;
    final newId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('tk_fallback_raw_id', newId);
    return newId;
  }
}
