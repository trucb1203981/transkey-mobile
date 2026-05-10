import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  /// Returns a stable SHA-256 fingerprint for this device.
  /// Computes once, then caches in secure storage for subsequent launches.
  Future<String> getFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    final stored = await _secureStorage.read(key: _kDeviceFingerprintKey);
    if (stored != null) {
      _cachedFingerprint = stored;
      return stored;
    }

    final raw = await _buildRawId();
    final hash = sha256.convert(raw.codeUnits).toString();

    await _secureStorage.write(key: _kDeviceFingerprintKey, value: hash);
    _cachedFingerprint = hash;
    return hash;
  }

  Future<String> _buildRawId() async {
    try {
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return '${info.identifierForVendor ?? "unknown"}_${info.utsname.machine}';
      } else {
        final info = await _deviceInfo.androidInfo;
        return '${info.id}_${info.manufacturer}_${info.model}';
      }
    } catch (e) {
      debugPrint('[DeviceId] Failed to get device info: $e');
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
