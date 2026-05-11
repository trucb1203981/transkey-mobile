import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDeviceFingerprintKey = 'tk_device_fingerprint';

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
    return _secureStorage.read(key: _kDeviceFingerprintKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDeviceFingerprintKey, value);
      return;
    }
    await _secureStorage.write(key: _kDeviceFingerprintKey, value: value);
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
    try {
      final info = await _deviceInfo.deviceInfo;
      final data = info.data;
      if (info.data.containsKey('identifierForVendor')) {
        return '${data['identifierForVendor']}_${data['utsname']?['machine'] ?? 'ios'}';
      }
      return '${data['id'] ?? 'unknown'}_${data['manufacturer'] ?? 'unknown'}_${data['model'] ?? 'unknown'}';
    } catch (e) {
      debugPrint('[DeviceId] Failed to get device info: $e');
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
