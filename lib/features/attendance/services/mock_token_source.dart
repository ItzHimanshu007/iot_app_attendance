/// Mock token source — fetches an active session from the backend.
///
/// Builds a synthetic [AttendanceSessionAdvertisement] exactly as the
/// BLE scanner would, using rssi = -55 dBm (strong signal, passes
/// every proximity check).
///
/// Retained as a test/fallback class. The active [tokenSourceProvider]
/// now returns [BleAttendanceTokenSource] for real ESP32 scanning.
/// To revert to mock during debugging, swap back in the provider below.

import 'dart:developer' as dev;

import '../../../services/api_client.dart';
import '../models/ble_models.dart';
import 'attendance_token_source.dart';

/// Mock implementation of [AttendanceTokenSource].
///
/// Calls [GET /sessions/current-active] to find any running session, then
/// wraps the response into an [AttendanceSessionAdvertisement] indistinguishable
/// from one produced by the BLE scanner.
class MockAttendanceTokenSource implements AttendanceTokenSource {
  MockAttendanceTokenSource({required ApiClient apiClient})
      : _api = apiClient;

  final ApiClient _api;

  /// Simulated RSSI that always passes the proximity threshold (-70 dBm).
  static const int _simulatedRssi = -55;

  @override
  Future<AttendanceSessionAdvertisement?> discoverSession() async {
    dev.log('[MOCK TOKEN] discoverSession() called', name: 'MockTokenSource');

    try {
      final session = await _api.get<Map<String, dynamic>?>(
        '/sessions/current-active',
        fromJson: (data) =>
            data == null ? null : data as Map<String, dynamic>,
      );

      if (session == null) {
        dev.log('[MOCK TOKEN] No active session found', name: 'MockTokenSource');
        return null;
      }

      final classroomId = session['classroom_id'] as String? ?? 'unknown';
      final token = session['current_token'] as String? ?? '';

      dev.log(
        '[MOCK TOKEN] Session found  sessionId=${session['id']}  '
        'classroomId=$classroomId  token=${token.length > 6 ? '${token.substring(0, 6)}…' : token}',
        name: 'MockTokenSource',
      );

      // Build advertisement exactly as BlePayloadParser would.
      return AttendanceSessionAdvertisement(
        classroomId: classroomId,
        token: token,
        protocolVersion: BleProtocol.protocolVersion,
        payloadType: BleProtocol.payloadTypeAttendance,
        rssi: _simulatedRssi,
        deviceName: 'MOCK-$classroomId',
        scannedAt: DateTime.now(),
      );
    } catch (e) {
      dev.log('[MOCK TOKEN] Error: $e', name: 'MockTokenSource');
      rethrow;
    }
  }

  @override
  void dispose() {
    // Nothing to release — stateless HTTP call.
    dev.log('[MOCK TOKEN] dispose()', name: 'MockTokenSource');
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
//
// [tokenSourceProvider] has moved to ble_token_source.dart.
//
// To temporarily revert to mock discovery during debugging:
//   1. Open lib/features/attendance/services/ble_token_source.dart.
//   2. Change the provider body to:
//        return MockAttendanceTokenSource(apiClient: ref.watch(apiClientProvider));
//   3. Revert before merging.
