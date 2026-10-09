// BLE attendance models — strongly typed payloads from ESP32 beacons.
//
// Spec: docs/ble_payload_spec.md
// Payload layout (after BLE stack strips 2-byte company ID):
//   byte[0]    = Protocol Version (0x02)
//   byte[1]    = Payload Type    (0x01 = attendance beacon)
//   byte[2..17]= Token           (16 ASCII hex chars)
//   byte[18..21]= Reserved       (0x00)

import '../../../core/config.dart';

/// Protocol constants matching ESP32 firmware config.h
class BleProtocol {
  BleProtocol._();

  /// Final binary-protocol prefix (dash) — used in Phase 3+
  static const String deviceNamePrefix = 'SCA-';

  /// Validation-mode prefix (underscore) — used by current ESP32 firmware.
  /// The ESP32 advertises `SCA_<TOKEN>` instead of `SCA-<classroomId>`.
  /// Accepted during validation until firmware is updated.
  static const String deviceNamePrefixAlt = 'SCA_';

  // ── Protocol V2 constants ─────────────────────────────────────────────────

  /// V2 protocol version byte (byte[0] == 0x02).
  static const int protocolVersion = 0x02;

  static const int payloadTypeAttendance = 0x01;

  /// Minimum manufacturer data length for V2 (after company ID stripped).
  /// Layout: 1 (version) + 1 (type) + 16 (ASCII hex token) + 2 (reserved) = 20
  static const int minManufacturerDataLength = 20;

  /// V2 token starts at byte index 2.
  static const int tokenStartOffset = 2;

  /// V2 token is 16 ASCII hex characters.
  static const int tokenLength = 16;

  /// V2 token ends at byte index 18 (exclusive).
  static const int tokenEndOffset = tokenStartOffset + tokenLength; // 18

  // ── Protocol V3 constants ─────────────────────────────────────────────────

  /// V3 protocol version byte (byte[0] == 0x03).
  /// Matches ESP32 firmware BLE_PROTO_VERSION = 0x03.
  static const int protocolVersionV3 = 0x03;

  /// V3 token is 8 raw binary bytes (byte[2..9]).
  /// Encoded to a 16-char lowercase hex string by the parser.
  static const int tokenLengthV3 = 8;

  /// V3 classroom UUID starts at byte index 10 (byte[10..25]).
  static const int uuidStartOffset = 10;

  /// V3 classroom UUID is 16 raw binary bytes.
  static const int uuidLength = 16;

  /// Minimum manufacturer data length for V3 (after company ID stripped).
  /// Layout: 1 (version) + 1 (type) + 8 (raw token) + 16 (UUID) = 26
  static const int minManufacturerDataLengthV3 = 26;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns true if [name] starts with either accepted SCA prefix.
  static bool isSCADevice(String name) =>
      name.startsWith(deviceNamePrefix) ||
      name.startsWith(deviceNamePrefixAlt);

  /// Extracts the token/classroomId segment from a validated SCA device name.
  static String extractSuffix(String name) {
    if (name.startsWith(deviceNamePrefix)) {
      return name.substring(deviceNamePrefix.length);
    }
    if (name.startsWith(deviceNamePrefixAlt)) {
      return name.substring(deviceNamePrefixAlt.length);
    }
    return name;
  }

  /// Formats 16 raw bytes as a canonical UUID string.
  ///
  /// Used by the V3 parser to convert the classroom UUID bytes from the BLE
  /// manufacturer data payload into the string form expected by the backend:
  ///   `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
  ///
  /// [bytes] must be exactly 16 bytes (indices 0..15).
  /// Throws [ArgumentError] if [bytes].length != 16.
  static String formatUuid(List<int> bytes) {
    if (bytes.length != uuidLength) {
      throw ArgumentError(
        'formatUuid expects exactly $uuidLength bytes, got ${bytes.length}',
      );
    }
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    // xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}

/// Strongly-typed model for a parsed ESP32 BLE beacon advertisement.
///
/// Extracted from manufacturer data per docs/ble_payload_spec.md.
class AttendanceSessionAdvertisement {
  const AttendanceSessionAdvertisement({
    required this.classroomId,
    required this.token,
    required this.protocolVersion,
    required this.payloadType,
    required this.rssi,
    required this.deviceName,
    required this.scannedAt,
  });

  /// Classroom ID — extracted from device name: `SCA-{classroomId}`
  final String classroomId;

  /// 16 ASCII hex chars — HMAC-SHA256 time-window token set by backend
  final String token;

  /// Must be 0x02 for this parser version
  final int protocolVersion;

  /// Must be 0x01 (attendance beacon)
  final int payloadType;

  /// Received Signal Strength Indicator (dBm) — negative value
  final int rssi;

  /// Raw BLE device name (e.g., `SCA-room-101`)
  final String deviceName;

  /// When this advertisement was received
  final DateTime scannedAt;

  /// Human-readable signal strength label.
  SignalStrength get signalStrength {
    if (rssi >= -50) return SignalStrength.excellent;
    if (rssi >= -65) return SignalStrength.good;
    if (rssi >= AppConfig.bleRssiThreshold) return SignalStrength.fair;
    return SignalStrength.weak;
  }

  /// Whether RSSI meets the proximity threshold.
  bool get isInRange => rssi >= AppConfig.bleRssiThreshold;

  /// Age of this advertisement object in milliseconds — for diagnostics only.
  ///
  /// **NOT used for attendance admission decisions.**
  /// Attendance validity is determined by [AttendanceController] via a live
  /// backend session lookup ([AttendanceRepository.getActiveSessionForClassroom]).
  /// A beacon is valid as long as the backend reports an active session,
  /// regardless of how long ago this object was created.
  int get ageMs => DateTime.now().difference(scannedAt).inMilliseconds;

  /// Diagnostic freshness flag — true while the object is younger than
  /// [AppConfig.bleAdvertisementMaxAgeDebugSeconds].
  ///
  /// Used only for logging inside [RealBleScanner] and [BleController].
  /// **Do NOT use this to gate attendance submission.**
  bool get isFresh =>
      ageMs < AppConfig.bleAdvertisementMaxAgeDebugSeconds * 1000;

  @override
  String toString() =>
      'AttendanceSessionAdvertisement('
      'classroom=$classroomId, rssi=$rssi, '
      'token=${token.substring(0, 6)}..., ageMs=$ageMs)'; 
}

/// Signal strength quality levels.
enum SignalStrength {
  excellent, // >= -50 dBm
  good,      // >= -65 dBm
  fair,      // >= threshold (default -70)
  weak,      // < threshold — below proximity cutoff
}

extension SignalStrengthX on SignalStrength {
  String get label {
    switch (this) {
      case SignalStrength.excellent: return 'Excellent';
      case SignalStrength.good:      return 'Good';
      case SignalStrength.fair:      return 'Fair';
      case SignalStrength.weak:      return 'Weak';
    }
  }

  int get bars {
    switch (this) {
      case SignalStrength.excellent: return 4;
      case SignalStrength.good:      return 3;
      case SignalStrength.fair:      return 2;
      case SignalStrength.weak:      return 1;
    }
  }
}

/// Parse result — either success with payload or a typed failure.
sealed class BleParseResult {}

class BleParseSuccess extends BleParseResult {
  BleParseSuccess(this.advertisement);
  final AttendanceSessionAdvertisement advertisement;
}

class BleParseFailure extends BleParseResult {
  BleParseFailure(this.reason);
  final String reason;
}
