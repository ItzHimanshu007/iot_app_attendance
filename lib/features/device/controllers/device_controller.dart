import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_models.dart';
import '../repository/device_repository.dart';
import '../services/device_fingerprint_service.dart';

// ── Device State ──────────────────────────────────────────────────────────────

sealed class DeviceState {
  const DeviceState();
}

class DeviceInitial extends DeviceState {
  const DeviceInitial();
}

class DeviceChecking extends DeviceState {
  const DeviceChecking();
}

class DeviceUnregistered extends DeviceState {
  const DeviceUnregistered({this.metadata});
  final DeviceMetadata? metadata;
}

class DeviceRegistering extends DeviceState {
  const DeviceRegistering();
}

class DeviceRegistered extends DeviceState {
  const DeviceRegistered({required this.device});
  final DeviceInfo device;
}

class DeviceInactive extends DeviceState {
  const DeviceInactive({required this.device});
  final DeviceInfo? device;
}

class DeviceMismatch extends DeviceState {
  const DeviceMismatch();
}

class DeviceError extends DeviceState {
  const DeviceError(this.message);
  final String message;
}

// ── Device Controller ─────────────────────────────────────────────────────────

/// Manages device registration and validation lifecycle.
class DeviceController extends StateNotifier<DeviceState> {
  DeviceController({
    required DeviceRepository repository,
    required DeviceFingerprintInterface fingerprintService,
  })  : _repo = repository,
        _fingerprint = fingerprintService,
        super(const DeviceInitial());

  final DeviceRepository _repo;
  final DeviceFingerprintInterface _fingerprint;

  // ── Check & initialize ────────────────────────────────────────────────────

  /// Check device registration status on app launch / screen open.
  Future<void> checkDeviceStatus() async {
    state = const DeviceChecking();

    try {
      final status = await _repo.validateDevice();

      switch (status) {
        case DeviceRegistrationStatus.registered:
          final device = await _repo.getMyDevice();

          if (device == null) {
            // Backend inconsistency: validateDevice() returned registered but
            // getMyDevice() returned null. Clear the stale local cache and
            // treat as unregistered so the student sees the registration flow.
            dev.log(
              '[DEVICE] Inconsistency — validateDevice=registered but getMyDevice=null. '
              'Clearing local registration → DeviceUnregistered',
              name: 'DeviceController',
            );
            await _repo.clearLocalRegistration();
            final meta = await _fingerprint.getDeviceMetadata();
            state = DeviceUnregistered(metadata: meta);
            dev.log('[DEVICE] Transition → DeviceUnregistered', name: 'DeviceController');
          } else {
            dev.log(
              '[DEVICE] Transition → DeviceRegistered  id=${device.id}  active=${device.isActive}',
              name: 'DeviceController',
            );
            state = DeviceRegistered(device: device);
          }

        case DeviceRegistrationStatus.unregistered:
          final meta = await _fingerprint.getDeviceMetadata();
          dev.log('[DEVICE] Transition → DeviceUnregistered (unregistered)', name: 'DeviceController');
          state = DeviceUnregistered(metadata: meta);

        case DeviceRegistrationStatus.inactive:
          final device = await _repo.getMyDevice();
          dev.log('[DEVICE] Transition → DeviceInactive', name: 'DeviceController');
          state = DeviceInactive(device: device);

        case DeviceRegistrationStatus.mismatch:
          dev.log('[DEVICE] Transition → DeviceMismatch', name: 'DeviceController');
          state = const DeviceMismatch();

        case DeviceRegistrationStatus.unknown:
          // Offline — check local cache
          final localReg = await _repo.isLocallyRegistered();
          if (localReg) {
            final device = await _repo.getMyDevice();
            if (device != null) {
              dev.log(
                '[DEVICE] Transition → DeviceRegistered (from cache)  id=${device.id}',
                name: 'DeviceController',
              );
              state = DeviceRegistered(device: device);
            } else {
              dev.log(
                '[DEVICE] Cache says registered but getMyDevice=null → DeviceUnregistered',
                name: 'DeviceController',
              );
              await _repo.clearLocalRegistration();
              final meta = await _fingerprint.getDeviceMetadata();
              state = DeviceUnregistered(metadata: meta);
            }
          } else {
            final meta = await _fingerprint.getDeviceMetadata();
            dev.log('[DEVICE] Transition → DeviceUnregistered (unknown/offline)', name: 'DeviceController');
            state = DeviceUnregistered(metadata: meta);
          }
      }
    } catch (e) {
      dev.log('[DEVICE] checkDeviceStatus error: $e', name: 'DeviceController');
      state = DeviceError('Failed to check device status: $e');
    }
  }

  // ── Registration ──────────────────────────────────────────────────────────

  /// Register this device with the backend.
  ///
  /// Called after biometric authentication succeeds.
  Future<void> registerDevice() async {
    state = const DeviceRegistering();

    try {
      final device = await _repo.registerDevice();
      state = DeviceRegistered(device: device);
    } catch (e) {
      state = DeviceError('Registration failed: $e');
    }
  }

  /// Refresh registration status from server.
  Future<void> refresh() => checkDeviceStatus();

  /// Reset to initial state (e.g., on sign out).
  void reset() => state = const DeviceInitial();
}

// ── Providers ─────────────────────────────────────────────────────────────────

final deviceControllerProvider =
    StateNotifierProvider<DeviceController, DeviceState>((ref) {
  return DeviceController(
    repository: ref.watch(deviceRepositoryProvider),
    fingerprintService: ref.watch(deviceFingerprintProvider),
  );
});

/// Whether device is fully registered and active.
final isDeviceReadyProvider = Provider<bool>((ref) {
  return ref.watch(deviceControllerProvider) is DeviceRegistered;
});
