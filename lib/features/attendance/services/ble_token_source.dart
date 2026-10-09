/// BLE token source — discovers the nearest ESP32 attendance beacon.
///
/// Uses [BleController] (via Riverpod [Ref]) to run a full BLE scan and
/// returns the highest-RSSI in-range [AttendanceSessionAdvertisement].
///
/// The rest of the attendance pipeline — [AttendanceController],
/// [AttendanceSubmissionScreen], and the backend API — require zero changes.

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../controllers/ble_controller.dart';
import '../models/ble_models.dart';
import 'attendance_token_source.dart';

/// Production BLE implementation of [AttendanceTokenSource].
///
/// Execution flow:
///   1. Resets [BleController] to idle (cancels any stale scan).
///   2. Subscribes to the controller's state [Stream] before starting.
///   3. Calls [BleController.startScan] (permission checks + native scan).
///   4. Awaits [BleScanComplete] — returns [BleScanComplete.bestBeacon].
///   5. On [BleDisabled] / [BlePermissionDenied] / [BleError] → throws.
///   6. On timeout ([AppConfig.bleScanDuration] + 5 s buffer) → returns null.
///
/// Returns null when no beacon is found (treated as "no session" by screen).
/// Throws on non-recoverable hardware/permission errors (shown as error state).
class BleAttendanceTokenSource implements AttendanceTokenSource {
  BleAttendanceTokenSource(this._ref);

  final Ref _ref;

  @override
  Future<AttendanceSessionAdvertisement?> discoverSession() async {
    final controller = _ref.read(bleControllerProvider.notifier);

    // Reset any previous scan — ensures a clean BleIdle starting state.
    controller.reset();

    // Completer resolves on the first terminal BLE state.
    final completer = Completer<AttendanceSessionAdvertisement?>();

    // Subscribe BEFORE startScan() to avoid missing fast terminal transitions
    // (e.g., BleDisabled is emitted synchronously inside startScan()).
    final sub = controller.stream.listen((state) {
      if (completer.isCompleted) return;

      switch (state) {
        case BleScanComplete():
          // bestBeacon = highest-RSSI advertisement that meets isInRange
          // (>= AppConfig.bleRssiThreshold).  Returns null when no beacon
          // passed the RSSI threshold.
          completer.complete(state.bestBeacon);

        case BleError(:final message):
          completer.completeError(
            Exception('BLE scan failed: $message'),
          );

        case BleDisabled():
          completer.completeError(
            Exception(
              'Bluetooth is disabled. '
              'Enable Bluetooth and try again.',
            ),
          );

        case BlePermissionDenied():
          completer.completeError(
            Exception(
              'Bluetooth permission denied. '
              'Allow Bluetooth access in Settings and try again.',
            ),
          );

        default:
          // BleIdle, BleCheckingPrerequisites, BleScanning — still in progress.
          break;
      }
    });

    // Start the scan. Performs Bluetooth state check + permission request +
    // native BLE scan setup. Returns quickly; BleScanComplete fires after
    // AppConfig.bleScanDuration via BleController's internal Dart Timer.
    try {
      await controller.startScan();
    } catch (e) {
      await sub.cancel();
      rethrow;
    }

    // Wait for terminal state. Timeout = scan window + 5 s safety buffer.
    // On timeout → null (treated as "no session found" by SessionDiscoveryScreen).
    try {
      return await completer.future.timeout(
        AppConfig.bleScanDuration + const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } finally {
      // Always cancel the subscription — whether we completed, errored, or timed out.
      await sub.cancel();
    }
  }

  @override
  void dispose() {
    // Reset the BLE controller: cancels timers, subscriptions, and native scan.
    dev.log('[BLE TOKEN] dispose() — resetting BleController', name: 'BleTokenSource');
    _ref.read(bleControllerProvider.notifier).reset();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Active token source provider — wired to [BleAttendanceTokenSource].
///
/// Discovers the nearest ESP32 beacon via [BleController].
/// The provider owns the lifecycle: [BleAttendanceTokenSource.dispose] is
/// called automatically when the provider is disposed.
///
/// To fall back to mock backend discovery during debugging:
///   1. Import mock_token_source.dart.
///   2. Return MockAttendanceTokenSource(apiClient: ref.watch(apiClientProvider)).
final tokenSourceProvider = Provider<AttendanceTokenSource>((ref) {
  final source = BleAttendanceTokenSource(ref);
  ref.onDispose(source.dispose);
  return source;
});
