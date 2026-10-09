import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions.dart';
import '../../../services/api_client.dart';
import '../../../services/secure_storage_service.dart';
import '../models/device_models.dart';
import '../services/device_fingerprint_service.dart';

/// Device repository — bridges fingerprint service and FastAPI device endpoints.
///
/// Endpoints consumed (from backend/app/api/v1/users.py):
///   POST /api/v1/users/me/device  → register device
///   GET  /api/v1/users/me/device  → get current device
class DeviceRepository {
  DeviceRepository({
    required ApiClient apiClient,
    required SecureStorageService storage,
    required DeviceFingerprintInterface fingerprintService,
  })  : _api = apiClient,
        _storage = storage,
        _fingerprint = fingerprintService;

  final ApiClient _api;
  final SecureStorageService _storage;
  final DeviceFingerprintInterface _fingerprint;

  // ── Registration ───────────────────────────────────────────────────────────

  /// Register this device with the backend.
  ///
  /// Flow:
  ///   1. Generate/retrieve SHA-256 fingerprint
  ///   2. Collect device metadata
  ///   3. POST /users/me/device
  ///   4. Persist registration status locally
  Future<DeviceInfo> registerDevice() async {
    final fingerprint = await _fingerprint.getFingerprint();
    final meta = await _fingerprint.getDeviceMetadata();

    final request = DeviceRegisterRequest(
      androidId: meta.androidId,
      deviceModel: meta.deviceModel,
      deviceManufacturer: meta.manufacturer,
      deviceFingerprint: fingerprint,
      osVersion: meta.osVersion,
      appVersion: meta.appVersion,
    );

    try {
      final device = await _api.post<DeviceInfo>(
        '/users/me/device',
        data: request.toJson(),
        fromJson: (data) => DeviceInfo.fromJson(data as Map<String, dynamic>),
      );

      // Persist registration state
      await _storage.setDeviceRegistered(true);
      await _storage.setDeviceId(device.id);
      await _storage.setDeviceFingerprint(fingerprint);

      return device;
    } on ConflictException {
      // Device already registered — treat as success, fetch current
      final existing = await getMyDevice();
      if (existing != null) {
        await _storage.setDeviceRegistered(true);
        await _storage.setDeviceId(existing.id);
        return existing;
      }
      rethrow;
    }
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  /// Get the registered device from the backend and validate it matches
  /// the current device fingerprint.
  Future<DeviceRegistrationStatus> validateDevice() async {
    try {
      final remoteDevice = await getMyDevice();

      if (remoteDevice == null) {
        await _storage.setDeviceRegistered(false);
        return DeviceRegistrationStatus.unregistered;
      }

      if (!remoteDevice.isActive) {
        await _storage.setDeviceRegistered(false);
        return DeviceRegistrationStatus.inactive;
      }

      // Verify fingerprint matches this device
      final currentFp = await _fingerprint.getFingerprint();
      if (remoteDevice.deviceFingerprint != currentFp) {
        await _storage.setDeviceRegistered(false);
        return DeviceRegistrationStatus.mismatch;
      }

      // All good
      await _storage.setDeviceRegistered(true);
      await _storage.setDeviceId(remoteDevice.id);
      return DeviceRegistrationStatus.registered;
    } on NotFoundException {
      await _storage.setDeviceRegistered(false);
      return DeviceRegistrationStatus.unregistered;
    } on NetworkException {
      // Can't reach server — fall back to local cache
      final localRegistered = await _storage.isDeviceRegistered();
      return localRegistered
          ? DeviceRegistrationStatus.registered
          : DeviceRegistrationStatus.unknown;
    } catch (_) {
      return DeviceRegistrationStatus.unknown;
    }
  }

  /// Fetch the current device from backend.
  ///
  /// Returns null when the student has no registered device.
  /// The backend returns HTTP 200 with a null body (not 404) in that case,
  /// so we guard against null before casting.
  Future<DeviceInfo?> getMyDevice() async {
    try {
      return await _api.get<DeviceInfo?>(
        '/users/me/device',
        fromJson: (data) {
          if (data == null) {
            dev.log(
              '[DEVICE] GET /users/me/device returned null — no device registered',
              name: 'DeviceRepository',
            );
            return null;
          }
          return DeviceInfo.fromJson(data as Map<String, dynamic>);
        },
      );
    } on NotFoundException {
      return null;
    }
  }

  /// Clear the local device-registered flag.
  ///
  /// Called when the backend reports registered but getMyDevice() returns null
  /// — an inconsistency that should reset the local cache.
  Future<void> clearLocalRegistration() async {
    await _storage.setDeviceRegistered(false);
  }

  /// Refresh device status from backend without full validation.
  Future<DeviceRegistrationStatus> refreshDeviceStatus() => validateDevice();

  // ── Local helpers ──────────────────────────────────────────────────────────

  /// Whether device is considered registered (from local cache).
  Future<bool> isLocallyRegistered() => _storage.isDeviceRegistered();
}

/// Provider for DeviceRepository.
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(
    apiClient: ref.watch(apiClientProvider),
    storage: ref.watch(secureStorageProvider),
    fingerprintService: ref.watch(deviceFingerprintProvider),
  );
});
