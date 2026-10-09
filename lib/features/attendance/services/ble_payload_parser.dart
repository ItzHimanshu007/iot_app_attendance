import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/ble_models.dart';

/// BLE Payload Parser — supports Protocol V2 and V3.
///
/// ## Parse strategy (manufacturer-first)
///
/// **Step 1 — Manufacturer data (primary identification)**
/// If manufacturer data is present and byte[0] == 0x03 (V3):
///   → Parse V3 immediately. Device name is NOT required for this path.
///   → On success: return BleParseSuccess.
///   → On failure: return BleParseFailure (no fallback for V3 — UUID is mandatory).
///
/// **Step 2 — Device name filter (SCA prefix)**
/// If V3 was not found (no manufacturer data, or manufacturer data is not V3):
///   → Require device name to start with "SCA-" or "SCA_".
///   → This correctly rejects all non-SCA BLE devices at the name level.
///
/// **Step 3 — V2 manufacturer data**
/// If SCA name found and manufacturer data present with byte[0] == 0x02:
///   → Parse V2. On success return BleParseSuccess.
///   → On failure fall through to name-only.
///
/// **Step 4 — Name-only fallback (Path B)**
/// Legacy / validation mode. Token = device name suffix.
///
/// ## Manufacturer data lookup
///
/// Uses a safe lookup: `manufData[0xFFFF]` (ESP32 test company ID) is tried
/// first. If absent, falls back to `manufData.values.first`. This avoids
/// accidentally parsing a different company's data when multiple entries exist.
///
/// Accepts both SCA- and SCA_ prefixes.
/// Logs every parse decision with [BLE PROD] prefix via print().
class BlePayloadParser {
  const BlePayloadParser();

  /// Parse a [ScanResult] into an [AttendanceSessionAdvertisement].
  ///
  /// Returns [BleParseSuccess] on valid SCA beacon (path A-V3, A-V2, or B).
  /// Returns [BleParseFailure] with reason on any validation failure.
  BleParseResult parse(ScanResult scanResult) {
    final device = scanResult.device;
    final adv    = scanResult.advertisementData;
    final rssi   = scanResult.rssi;

    // ── 1. Manufacturer-data-first: try V3 before name check ─────────────────
    //
    // V3 packets carry the full classroom UUID in manufacturer data.
    // If the BLE stack delivers manufacturer data with version byte 0x03,
    // we parse it immediately without needing the device name.
    // This handles the case where the scan response (which carries the name)
    // is lost at range while the primary ADV_IND (which carries manufacturer
    // data) is received successfully.
    final manufData = adv.manufacturerData;
    if (manufData.isNotEmpty) {
      // Safe lookup: prefer 0xFFFF (ESP32 unregistered company ID).
      // Falls back to the first entry if 0xFFFF is absent.
      final bytes       = _safeManufBytes(manufData);
      final versionByte = bytes.isNotEmpty ? bytes[0] : -1;

      if (versionByte == BleProtocol.protocolVersionV3) {
        // Resolve device name for logging only — not required for V3 parsing.
        final logName = adv.advName.isNotEmpty ? adv.advName : device.platformName;
        final result  = _parseBinaryPathV3(
          deviceName: logName.isNotEmpty ? logName : '(no name)',
          bytes:      bytes,
          rssi:       rssi,
        );
        if (result is BleParseSuccess) return result;

        // V3 devices must NEVER fall back to name-only parsing.
        // A V3 parse failure means the UUID could not be extracted, so
        // classroomId would become the device-name suffix (e.g. "LAB101"),
        // which is not a UUID and causes a Postgres type error on the backend.
        print(
          '[BLE PROD] V3 binary parse FAILED for "$logName" '
          '- refusing name-only fallback: '
          '${(result as BleParseFailure).reason}',
        );
        return result; // BleParseFailure — scanner drops this device
      }
    }

    // ── 2. Resolve device name and apply SCA prefix filter ───────────────────
    // advName is the name from the advertisement packet itself.
    // platformName is the OS-cached name (can be stale).
    // Prefer advName; fall back to platformName.
    final deviceName = adv.advName.isNotEmpty
        ? adv.advName
        : device.platformName;

    if (!BleProtocol.isSCADevice(deviceName)) {
      // Silent — non-SCA devices are not logged (too noisy)
      return BleParseFailure('Not an SCA device: "$deviceName"');
    }

    final suffix = BleProtocol.extractSuffix(deviceName);
    if (suffix.isEmpty) {
      _log(deviceName: deviceName, rssi: rssi, accepted: false,
          reason: 'Empty suffix in device name');
      return BleParseFailure('Empty suffix in device name: "$deviceName"');
    }

    // ── 3. Try V2 manufacturer data ───────────────────────────────────────────
    if (manufData.isNotEmpty) {
      final bytes       = _safeManufBytes(manufData);
      final versionByte = bytes.isNotEmpty ? bytes[0] : -1;

      // Only attempt V2 parse. If versionByte is 0x03 it was already handled
      // above (and failed), so we skip it here. Unknown versions pass through
      // to _parseBinaryPath which will reject them with a clear message.
      if (versionByte != BleProtocol.protocolVersionV3) {
        final result = _parseBinaryPath(
          deviceName: deviceName,
          suffix:     suffix,
          bytes:      bytes,
          rssi:       rssi,
        );
        if (result is BleParseSuccess) return result;
        // V2 / unknown version — fall through to name-only (legacy behaviour).
        print('[BLE PROD] Binary parse (v${versionByte.toRadixString(16)}) '
            'failed for "$deviceName", trying name-only fallback: '
            '${(result as BleParseFailure).reason}');
      }
    }

    // ── 4. Name-only fallback (Path B) — validation mode ─────────────────────
    // Treat the full suffix as the token.
    // classroomId = suffix until binary protocol is live.
    // Example: SCA_SESSION_ABC123 → token = SESSION_ABC123
    final token = suffix;

    _log(
      deviceName: deviceName,
      rssi:       rssi,
      accepted:   true,
      reason:     manufData.isEmpty
          ? 'name-only fallback (no manufacturer data)'
          : 'name-only fallback (binary parse failed)',
      token: token,
    );

    return BleParseSuccess(
      AttendanceSessionAdvertisement(
        classroomId:     suffix,     // Use suffix as classroomId in validation
        token:           token,
        protocolVersion: 0,          // 0 = name-only, not binary protocol
        payloadType:     0,
        rssi:            rssi,
        deviceName:      deviceName,
        scannedAt:       DateTime.now(),
      ),
    );
  }

  // ── Safe manufacturer data lookup ─────────────────────────────────────────

  /// Returns the manufacturer payload bytes using a safe lookup strategy.
  ///
  /// Prefers company ID 0xFFFF (ESP32 unregistered/test ID).
  /// Falls back to the first entry in the map if 0xFFFF is absent.
  /// Returns an empty list if [manufData] is empty.
  static List<int> _safeManufBytes(Map<int, List<int>> manufData) {
    if (manufData.isEmpty) return const [];
    return manufData[0xFFFF] ?? manufData.values.first;
  }

  // ── Binary path V2 ────────────────────────────────────────────────────────

  BleParseResult _parseBinaryPath({
    required String      deviceName,
    required String      suffix,
    required List<int>   bytes,
    required int         rssi,
  }) {
    // Company ID 0xFFFF is the unregistered/test ID used by the ESP32.
    if (bytes.length < BleProtocol.minManufacturerDataLength) {
      return BleParseFailure(
        'Manufacturer data too short: ${bytes.length} bytes '
        '(need >= ${BleProtocol.minManufacturerDataLength})',
      );
    }

    final version = bytes[0];
    if (version != BleProtocol.protocolVersion) {
      return BleParseFailure(
        'Unknown protocol version: '
        '0x${version.toRadixString(16).padLeft(2, '0')} '
        '(expected 0x${BleProtocol.protocolVersion.toRadixString(16)})',
      );
    }

    final payloadType = bytes[1];
    if (payloadType != BleProtocol.payloadTypeAttendance) {
      return BleParseFailure(
        'Unsupported payload type: 0x${payloadType.toRadixString(16)} '
        '(expected 0x${BleProtocol.payloadTypeAttendance.toRadixString(16)})',
      );
    }

    final tokenBytes = bytes.sublist(
      BleProtocol.tokenStartOffset,
      BleProtocol.tokenEndOffset,
    );

    final tokenValid = tokenBytes.every(
      (b) =>
          (b >= 0x30 && b <= 0x39) || // 0-9
          (b >= 0x61 && b <= 0x66) || // a-f
          (b >= 0x41 && b <= 0x46),   // A-F
    );

    if (!tokenValid) {
      return BleParseFailure('Token contains non-hex ASCII characters');
    }

    final token = String.fromCharCodes(tokenBytes).toLowerCase();

    _log(
      deviceName: deviceName,
      rssi:       rssi,
      accepted:   true,
      reason:     'binary protocol V2',
      token:      token,
    );

    return BleParseSuccess(
      AttendanceSessionAdvertisement(
        classroomId:     suffix,
        token:           token,
        protocolVersion: version,
        payloadType:     payloadType,
        rssi:            rssi,
        deviceName:      deviceName,
        scannedAt:       DateTime.now(),
      ),
    );
  }

  // ── Binary path V3 ──────────────────────────────────────────────────────────

  /// Parse a V3 binary payload.
  ///
  /// Layout (after company ID stripped by BLE stack):
  ///   byte[0]     = 0x03 (protocol version)
  ///   byte[1]     = 0x01 (payload type — attendance)
  ///   byte[2..9]  = 8 raw token bytes  → 16-char lowercase hex string
  ///   byte[10..25]= 16 raw UUID bytes  → "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  ///
  /// [classroomId] is taken from the UUID field, NOT from the device name suffix.
  /// [deviceName] is used for logging only; V3 parsing does NOT require a valid name.
  BleParseResult _parseBinaryPathV3({
    required String    deviceName,
    required List<int> bytes,
    required int       rssi,
  }) {
    if (bytes.length < BleProtocol.minManufacturerDataLengthV3) {
      return BleParseFailure(
        'V3 payload too short: ${bytes.length} bytes '
        '(need >= ${BleProtocol.minManufacturerDataLengthV3})',
      );
    }

    final version = bytes[0];
    // Defensive check — dispatcher already verified this, but guard anyway.
    if (version != BleProtocol.protocolVersionV3) {
      return BleParseFailure(
        'V3 parser received unexpected version byte: '
        '0x${version.toRadixString(16).padLeft(2, '0')}',
      );
    }

    final payloadType = bytes[1];
    if (payloadType != BleProtocol.payloadTypeAttendance) {
      return BleParseFailure(
        'V3 unsupported payload type: 0x${payloadType.toRadixString(16)} '
        '(expected 0x${BleProtocol.payloadTypeAttendance.toRadixString(16)})',
      );
    }

    // ── Token: bytes[2..9] — 8 raw binary bytes → 16-char lowercase hex ──────
    final tokenBytes = bytes.sublist(
      BleProtocol.tokenStartOffset,                               // 2
      BleProtocol.tokenStartOffset + BleProtocol.tokenLengthV3,  // 10
    );
    final token = tokenBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(); // 16-char lowercase hex string

    // ── Classroom UUID: bytes[10..25] — 16 raw binary bytes → UUID string ────
    final uuidBytes = bytes.sublist(
      BleProtocol.uuidStartOffset,                          // 10
      BleProtocol.uuidStartOffset + BleProtocol.uuidLength, // 26
    );
    final String classroomId;
    try {
      classroomId = BleProtocol.formatUuid(uuidBytes);
    } on ArgumentError catch (e) {
      return BleParseFailure('V3 UUID extraction failed: $e');
    }

    _log(
      deviceName:  deviceName,
      rssi:        rssi,
      accepted:    true,
      reason:      'binary protocol V3 (manufacturer-first)',
      token:       token,
      classroomId: classroomId,
    );

    return BleParseSuccess(
      AttendanceSessionAdvertisement(
        classroomId:     classroomId,
        token:           token,
        protocolVersion: version,    // 0x03
        payloadType:     payloadType, // 0x01
        rssi:            rssi,
        deviceName:      deviceName,
        scannedAt:       DateTime.now(),
      ),
    );
  }

  // ── Logging ───────────────────────────────────────────────────────────────

  void _log({
    required String deviceName,
    required int    rssi,
    required bool   accepted,
    required String reason,
    String?         token,
    String?         classroomId,
  }) {
    // Uses print() — NOT dart:developer. print() is visible in release builds
    // via: adb logcat | Select-String "flutter"
    print(
      '[BLE PROD]\n'
      '  deviceName=$deviceName\n'
      '  token=${token ?? "(none)"}\n'
      '  classroomId=${classroomId ?? "(from name)"}\n'
      '  rssi=$rssi\n'
      '  accepted=$accepted\n'
      '  reason=$reason',
    );
  }

  // ── Raw bytes (unit test path) ─────────────────────────────────────────────

  /// Parse a raw byte array — primary path for unit tests without BLE hardware.
  ///
  /// Supports both Protocol V2 (0x02) and Protocol V3 (0x03).
  /// Dispatches on [bytes][0] the same way the live scanner does.
  BleParseResult parseRawBytes({
    required List<int> bytes,
    required String    deviceName,
    required int       rssi,
  }) {
    if (!BleProtocol.isSCADevice(deviceName)) {
      return BleParseFailure('Not an SCA device');
    }
    final suffix = BleProtocol.extractSuffix(deviceName);

    if (bytes.isEmpty) {
      return BleParseFailure('Empty payload');
    }

    final version = bytes[0];

    // ── Protocol V3 ──────────────────────────────────────────────────────────
    if (version == BleProtocol.protocolVersionV3) {
      if (bytes.length < BleProtocol.minManufacturerDataLengthV3) {
        return BleParseFailure(
          'V3 payload too short: ${bytes.length} '
          '(need >= ${BleProtocol.minManufacturerDataLengthV3})',
        );
      }

      final payloadType = bytes[1];
      if (payloadType != BleProtocol.payloadTypeAttendance) {
        return BleParseFailure(
          'V3 unsupported payload type: 0x${payloadType.toRadixString(16)}',
        );
      }

      // Token: bytes[2..9] → 16-char lowercase hex
      final tokenBytes = bytes.sublist(
        BleProtocol.tokenStartOffset,
        BleProtocol.tokenStartOffset + BleProtocol.tokenLengthV3,
      );
      final token = tokenBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Classroom UUID: bytes[10..25] → UUID string
      final uuidBytes = bytes.sublist(
        BleProtocol.uuidStartOffset,
        BleProtocol.uuidStartOffset + BleProtocol.uuidLength,
      );
      final String classroomId;
      try {
        classroomId = BleProtocol.formatUuid(uuidBytes);
      } on ArgumentError catch (e) {
        return BleParseFailure('V3 UUID extraction failed: $e');
      }

      return BleParseSuccess(
        AttendanceSessionAdvertisement(
          classroomId:     classroomId,
          token:           token,
          protocolVersion: version,
          payloadType:     payloadType,
          rssi:            rssi,
          deviceName:      deviceName,
          scannedAt:       DateTime.now(),
        ),
      );
    }

    // ── Protocol V2 ──────────────────────────────────────────────────────────
    if (version == BleProtocol.protocolVersion) {
      if (bytes.length < BleProtocol.minManufacturerDataLength) {
        return BleParseFailure(
          'V2 payload too short: ${bytes.length} '
          '(need >= ${BleProtocol.minManufacturerDataLength})',
        );
      }

      final payloadType = bytes[1];
      if (payloadType != BleProtocol.payloadTypeAttendance) {
        return BleParseFailure(
          'V2 unsupported payload type: 0x${payloadType.toRadixString(16)}',
        );
      }

      final tokenBytes = bytes.sublist(
        BleProtocol.tokenStartOffset,
        BleProtocol.tokenEndOffset,
      );
      final token = String.fromCharCodes(tokenBytes).toLowerCase();

      return BleParseSuccess(
        AttendanceSessionAdvertisement(
          classroomId:     suffix,
          token:           token,
          protocolVersion: version,
          payloadType:     payloadType,
          rssi:            rssi,
          deviceName:      deviceName,
          scannedAt:       DateTime.now(),
        ),
      );
    }

    // ── Unknown version ───────────────────────────────────────────────────────
    return BleParseFailure(
      'Unknown protocol version: '
      '0x${version.toRadixString(16).padLeft(2, '0')} '
      '(supported: V2=0x02, V3=0x03)',
    );
  }
}
