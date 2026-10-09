/// Attendance token source abstraction.
///
/// Decouples the student attendance flow from the underlying discovery
/// mechanism.  Today the mock implementation fetches a token from the
/// backend.  Tomorrow the BLE implementation reads it from an ESP32
/// advertisement.  **The attendance submission pipeline is never touched.**
///
/// Swap is a single provider change in session_discovery_screen.dart:
///
///   TODAY:
///     Provider((_) => MockAttendanceTokenSource(...))
///
///   TOMORROW:
///     Provider((_) => BleAttendanceTokenSource(...))

import '../models/ble_models.dart';

/// Abstract token source — produces an [AttendanceSessionAdvertisement]
/// from any discovery mechanism (mock backend fetch, BLE scan, QR, etc.).
abstract class AttendanceTokenSource {
  /// Discover the nearest active attendance session.
  ///
  /// Returns an [AttendanceSessionAdvertisement] ready to feed into
  /// [AttendanceController.submitAttendance] — exactly as BLE would.
  ///
  /// Returns `null` when no active session is found.
  /// Throws on non-recoverable network/permission errors.
  Future<AttendanceSessionAdvertisement?> discoverSession();

  /// Release resources (timers, BLE subscriptions, etc.).
  void dispose();
}
