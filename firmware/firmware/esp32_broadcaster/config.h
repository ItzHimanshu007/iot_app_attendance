/*
 * config.h — Smart Campus Attendance ESP32 BLE Beacon
 * =====================================================
 *
 * PURPOSE
 *   Single source of truth for all device-specific settings.
 *   Change DEVICE_ID, CLASSROOM_UUID, and ATTENDANCE_TOKEN before flashing.
 *   No other file needs editing.
 *
 * PROTOCOL V3 BLE ADVERTISEMENT
 *
 *   Device Name (GAP / Scan-Response):
 *     "SCA-LAB101"  — any label starting with "SCA-"
 *     Flutter isSCADevice() only checks the "SCA-" prefix.
 *     In V3 the suffix is IGNORED by the parser (classroomId comes from
 *     the embedded UUID in the manufacturer data).
 *
 *   Manufacturer Data payload (26 bytes, AFTER 2-byte Company ID):
 *
 *     byte[0]      = 0x03                    Protocol Version V3
 *     byte[1]      = 0x01                    Payload Type: Attendance Beacon
 *     byte[2..9]   = 8 raw token bytes       Token (hex string → binary)
 *     byte[10..25] = 16 raw UUID bytes       Classroom UUID (binary)
 *
 *   Flutter _parseBinaryPathV3() extracts:
 *     token       ← bytes[2..9]   → hex-encoded  → 16-char string
 *     classroomId ← bytes[10..25] → UUID formatted → "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
 *
 *   Token conversion example:
 *     "e1ede9723aacd6c4"  →  E1 ED E9 72 3A AC D6 C4  (8 bytes)
 *
 *   UUID conversion example:
 *     "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"
 *     →  E6 64 F3 AF  8A EC  5D 5F  BF 5D  B8 75 4D 6D 93 B2  (16 bytes)
 *
 * PDU BUDGET
 *   Primary ADV PDU (no auto-Flags when using setAdvertisementData):
 *     Mfr AD: 1(len) + 1(type 0xFF) + 2(compID) + 26(payload) = 30 bytes ✓
 *   Scan Response PDU:
 *     Name AD: 1(len) + 1(type 0x09) + N(name chars) ≤ 31 bytes ✓
 *
 * PHASE 2  (future — MQTT token rotation)
 *   Restore mqtt_handler.cpp and call updateBleToken(newToken) from the
 *   MQTT message callback.  Zero changes to ble_advertiser.cpp are needed.
 *
 * !! CHANGE DEVICE_ID, CLASSROOM_UUID, ATTENDANCE_TOKEN BEFORE FLASHING !!
 */

#pragma once

#include <Arduino.h>   // uint8_t, uint16_t — safe in all Arduino .h files

// ─────────────────────────────────────────────────────────────────────────────
// Debug
// ─────────────────────────────────────────────────────────────────────────────
//   1 → verbose Serial output (development / bench testing)
//   0 → silent production build
#define DEBUG 1

// ─────────────────────────────────────────────────────────────────────────────
// Device Identity
// ─────────────────────────────────────────────────────────────────────────────

/// Unique identifier for this ESP32 unit.
/// Used in Serial output and (Phase 2) MQTT client ID.
#define DEVICE_ID           "ESP_LAB101"

/// BLE GAP device name — MUST start with "SCA-" for Flutter to accept it.
///
/// In Protocol V3 the suffix ("LAB101") is IGNORED by the Flutter parser.
/// The classroomId is taken from the UUID embedded in the manufacturer data.
/// Choose any human-readable label after the "SCA-" prefix.
///
/// Max length: 27 chars (≤ 29-byte scan-response AD element).
#define DEVICE_NAME         "SCA-LAB101"

// ─────────────────────────────────────────────────────────────────────────────
// Protocol V3 — Classroom UUID
// ─────────────────────────────────────────────────────────────────────────────
//
//  The classroom UUID is the PRIMARY KEY of the classrooms row in Supabase.
//  It is embedded as 16 raw bytes in the manufacturer data (bytes[10..25]).
//  Flutter formats it back to "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" and
//  passes it as classroom_id to GET /sessions/active?classroom_id=<UUID>.
//
//  !! MUST MATCH the id column of the classrooms table row for this room !!
//
//  Example:
//    UUID string: "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"
//    Raw bytes:    E6 64 F3 AF  8A EC  5D 5F  BF 5D  B8 75 4D 6D 93 B2
//
#define CLASSROOM_UUID      "43905a99-a513-5a9d-8cb5-e109b98166bb"

// ─────────────────────────────────────────────────────────────────────────────
// Protocol V3 — Attendance Token
// ─────────────────────────────────────────────────────────────────────────────
//
//  The token is a 16-character lowercase hex string (= 8 raw bytes).
//  It is an HMAC-SHA256 of (classroom_uuid : time_window), truncated to
//  16 hex chars.  The backend generates it; the ESP32 embeds it as raw bytes.
//
//  V3 encoding: each pair of hex chars becomes one raw byte.
//    "e1ede9723aacd6c4" → E1 ED E9 72 3A AC D6 C4  (bytes[2..9])
//
//  !! MUST be exactly 16 lowercase hex characters !!
//
#define ATTENDANCE_TOKEN    "c81669ef4b12a473"

/// Token length in hex characters (= 16).  Encodes to V3_TOKEN_BYTES raw bytes.
#define TOKEN_HEX_LEN       16

/// Number of raw bytes the token occupies in the manufacturer payload (= 8).
#define V3_TOKEN_BYTES      8

/// Number of raw bytes the classroom UUID occupies in the payload (= 16).
#define V3_UUID_BYTES       16

// ─────────────────────────────────────────────────────────────────────────────
// Protocol V3 — Manufacturer Data Constants
// ─────────────────────────────────────────────────────────────────────────────
//
//  Full layout of the 26-byte manufacturer payload (after Company ID):
//
//    byte[0]      = BLE_PROTO_VERSION  (0x03)
//    byte[1]      = BLE_PAYLOAD_TYPE   (0x01)
//    byte[2..9]   = 8 raw token bytes
//    byte[10..25] = 16 raw UUID bytes
//
//  On air (including Company ID, AD-Length, and AD-Type):
//    [0x1D]   AD Length  = 29   (1 + 2 + 26)
//    [0xFF]   AD Type    = Manufacturer Specific
//    [0xFF]   Company ID low  (0xFFFF = test/unregistered)
//    [0xFF]   Company ID high
//    [0x03]   Protocol Version V3
//    [0x01]   Payload Type: Attendance Beacon
//    [8 B]    Token raw bytes
//    [16 B]   UUID  raw bytes
//
//  Total mfr AD value bytes passed to NimBLE (including company ID): 28
//  Primary ADV PDU:  1(AD-len) + 1(AD-type) + 28(value) = 30 bytes ✓

/// Protocol V3 version byte.
#define BLE_PROTO_VERSION   0x03

/// Attendance beacon payload type byte.
#define BLE_PAYLOAD_TYPE    0x01

/// Total manufacturer payload length (after Company ID stripped):
///   1 (version) + 1 (type) + 8 (token) + 16 (UUID) = 26 bytes.
#define MFR_PAYLOAD_LEN     26

/// Bluetooth SIG test/unregistered company identifier (little-endian).
#define COMPANY_ID_LO       0xFF
#define COMPANY_ID_HI       0xFF

// ─────────────────────────────────────────────────────────────────────────────
// BLE Advertising Intervals
// ─────────────────────────────────────────────────────────────────────────────
//   Unit: 0.625 ms per count (Bluetooth Core Specification vol 6, part B).
//   160 × 0.625 ms = 100 ms  |  320 × 0.625 ms = 200 ms
//
//   The Flutter BleScanner uses a 5-second scan window and a 5-second
//   advertisement TTL.  Advertising at ≤ 200 ms guarantees multiple
//   packets within each TTL window, ensuring reliable detection.
#define ADV_INTERVAL_MIN    160   // ~100 ms
#define ADV_INTERVAL_MAX    320   // ~200 ms
