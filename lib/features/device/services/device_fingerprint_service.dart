import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../services/secure_storage_service.dart';
import '../models/device_models.dart';

// ── Interface ─────────────────────────────────────────────────────────────────

/// Interface for device fingerprint operations — enables mock injection.
abstract class DeviceFingerprintInterface {
  /// Generate (or return cached) SHA-256 device fingerprint.
  Future<String> getFingerprint();

  /// Collect raw device hardware metadata.
  Future<DeviceMetadata> getDeviceMetadata();

  /// Check if the fingerprint matches the one stored locally.
  Future<bool> isRegistered();

  /// Clear the locally stored fingerprint.
  Future<void> clearFingerprint();
}

// ── Real Implementation ───────────────────────────────────────────────────────

/// Production device fingerprint service.
///
/// Generates a SHA-256 hash from:
///   androidId + deviceModel + manufacturer + brand + sdkVersion
///
/// The raw hardware IDs are never transmitted — only the hash.
/// The hash is cached in [SecureStorageService] to avoid repeated
/// platform channel calls.
class DeviceFingerprintService implements DeviceFingerprintInterface {
  DeviceFingerprintService({
    required SecureStorageService storage,
    DeviceInfoPlugin? deviceInfo,
  })  : _storage = storage,
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final SecureStorageService _storage;
  final DeviceInfoPlugin _deviceInfo;

  // In-memory cache — avoid repeated platform calls per session
  String? _cachedFingerprint;
  DeviceMetadata? _cachedMetadata;

  @override
  Future<String> getFingerprint() async {
    // Return in-memory cache first
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    // Try persisted fingerprint from secure storage
    final stored = await _storage.getDeviceFingerprint();
    if (stored != null && stored.isNotEmpty) {
      _cachedFingerprint = stored;
      return stored;
    }

    // Generate fresh fingerprint from hardware
    final meta = await getDeviceMetadata();
    final fp = _computeFingerprint(meta);

    // Persist for future launches
    await _storage.setDeviceFingerprint(fp);
    await _storage.setAndroidId(meta.androidId);
    _cachedFingerprint = fp;
    return fp;
  }

  @override
  Future<DeviceMetadata> getDeviceMetadata() async {
    if (_cachedMetadata != null) return _cachedMetadata!;

    final androidInfo = await _deviceInfo.androidInfo;
    final appVersion = AppConfig.appVersion;

    _cachedMetadata = DeviceMetadata(
      androidId: androidInfo.id,          // Unique Android hardware ID
      deviceModel: androidInfo.model,
      manufacturer: androidInfo.manufacturer,
      brand: androidInfo.brand,
      sdkVersion: androidInfo.version.sdkInt,
      osVersion: 'Android ${androidInfo.version.release}',
      appVersion: appVersion,
    );
    return _cachedMetadata!;
  }

  @override
  Future<bool> isRegistered() => _storage.isDeviceRegistered();

  @override
  Future<void> clearFingerprint() async {
    _cachedFingerprint = null;
    _cachedMetadata = null;
    await _storage.setDeviceFingerprint('');
    await _storage.setDeviceRegistered(false);
  }

  // ── SHA-256 fingerprint computation ────────────────────────────────────────

  /// Compute SHA-256 of concatenated hardware identifiers.
  ///
  /// Input string: "{androidId}:{model}:{manufacturer}:{brand}:{sdk}"
  /// Only the hex digest is stored/transmitted.
  String _computeFingerprint(DeviceMetadata meta) {
    final raw =
        '${meta.androidId}:${meta.deviceModel}:${meta.manufacturer}:${meta.brand}:${meta.sdkVersion}';
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString(); // 64-char lowercase hex
  }
}

// ── Mock Implementation ───────────────────────────────────────────────────────

/// Mock device fingerprint service — unit tests and UI development.
class MockDeviceFingerprintService implements DeviceFingerprintInterface {
  MockDeviceFingerprintService({
    this.simulatedFingerprint =
        'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
    this.simulatedRegistered = false,
  });

  final String simulatedFingerprint;
  final bool simulatedRegistered;

  static DeviceMetadata get defaultMetadata => DeviceMetadata(
        androidId: 'mock-android-id-12345',
        deviceModel: 'Pixel 7',
        manufacturer: 'Google',
        brand: 'Google',
        sdkVersion: 33,
        osVersion: 'Android 13',
        appVersion: '0.1.0+1',
      );

  @override
  Future<String> getFingerprint() async => simulatedFingerprint;

  @override
  Future<DeviceMetadata> getDeviceMetadata() async => defaultMetadata;

  @override
  Future<bool> isRegistered() async => simulatedRegistered;

  @override
  Future<void> clearFingerprint() async {}
}

// ── Providers ─────────────────────────────────────────────────────────────────

final deviceFingerprintProvider = Provider<DeviceFingerprintInterface>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return DeviceFingerprintService(storage: storage);
});
