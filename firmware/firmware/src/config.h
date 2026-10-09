/*
 * config.h — Smart Campus Attendance ESP32 BLE + MQTT Broadcaster
 * ================================================================
 *
 * !! CHANGE DEVICE_ID, CLASSROOM_UUID, ATTENDANCE_TOKEN,
 *    WIFI_SSID, WIFI_PASSWORD, and MQTT_BROKER BEFORE FLASHING !!
 * No other file needs editing.
 *
 * Firmware version: 3.1.0  (Protocol V3 + MQTT + HiveMQ TLS)
 *
 * ── PROTOCOL V3 BLE ADVERTISEMENT ──────────────────────────────────────────
 *
 *   Device Name (GAP / Scan-Response):
 *     "SCA-LAB101"  — any label starting with "SCA-"
 *     Flutter isSCADevice() only checks the "SCA-" prefix.
 *     In V3 the suffix is IGNORED; classroomId comes from the UUID bytes.
 *
 *   Manufacturer Data payload (26 bytes, AFTER 2-byte Company ID 0xFFFF):
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
 * ── MQTT TOPICS ────────────────────────────────────────────────────────────
 *
 *   All topics now use CLASSROOM_UUID (full UUID) instead of "room-101".
 *   Must match backend/app/mqtt/__init__.py exactly.
 *
 *   Subscribe (Backend → ESP32):
 *     campus/classroom/{uuid}/control/start
 *     campus/classroom/{uuid}/control/stop
 *     campus/classroom/{uuid}/token
 *
 *   Publish (ESP32 → Backend):
 *     campus/classroom/{uuid}/heartbeat
 *     campus/classroom/{uuid}/status
 *     campus/classroom/{uuid}/telemetry
 */

#pragma once

#include <Arduino.h>   // uint8_t, uint16_t — safe in all Arduino .h files

// ── Build Mode ───────────────────────────────────────────────────────────────
//   1 → verbose Serial output (development / bench testing)
//   0 → silent production build
#ifndef FIRMWARE_DEBUG
#define FIRMWARE_DEBUG 1
#endif

// ── Firmware Identity ────────────────────────────────────────────────────────
#define FIRMWARE_VERSION   "3.1.0"

// ── Device Identity (CHANGE PER DEVICE) ─────────────────────────────────────

/// Unique identifier for this ESP32 unit.
/// Used in Serial output and MQTT client ID.
#define DEVICE_ID          "esp32-room-101"

// ── Protocol V3 — Classroom UUID ────────────────────────────────────────────
//
//  The classroom UUID is the PRIMARY KEY of the classrooms row in Supabase.
//  It is embedded as 16 raw bytes in the manufacturer data (bytes[10..25]).
//  Flutter formats it back to "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" and
//  passes it as classroom_id to GET /sessions/active?classroom_id=<UUID>.
//
//  !! MUST MATCH the id column of the classrooms table row for this room !!
//  !! MUST be exactly 36 characters in "8-4-4-4-12" format !!
//
//  Example:
//    UUID string: "43905a99-a513-5a9d-8cb5-e109b98166bb"
//    Raw bytes:    43 90 5A 99 A5 13 5A 9D 8C B5 E1 09 B9 81 66 BB
//
#define CLASSROOM_UUID     "43905a99-a513-5a9d-8cb5-e109b98166bb"

// ── Protocol V3 — BLE Device Name ────────────────────────────────────────────
//
//  MUST start with "SCA-" for Flutter isSCADevice() to accept it.
//  In V3 the suffix is cosmetic — classroomId comes from the UUID bytes.
//  Max length: 27 chars (≤ 29-byte scan-response AD element).
//
#define DEVICE_NAME        "SCA-LAB101"

// ── Protocol V3 — Attendance Token (compile-time default) ───────────────────
//
//  Used ONLY as the initial token when no MQTT message has arrived yet.
//  This value is overwritten at runtime as soon as the backend sends the
//  session-start command or a token-update message via MQTT.
//
//  !! MUST be exactly TOKEN_HEX_LEN (16) lowercase hex characters !!
//
#define ATTENDANCE_TOKEN   "c81669ef4b12a473"

/// Token length in hex characters (= 16). Encodes to V3_TOKEN_BYTES raw bytes.
#define TOKEN_HEX_LEN      16
/// Alias used by token_parser.h and command_handler.cpp
#define TOKEN_LENGTH       TOKEN_HEX_LEN

/// Number of raw bytes the token occupies in the manufacturer payload (= 8).
#define V3_TOKEN_BYTES     8

/// Number of raw bytes the classroom UUID occupies in the payload (= 16).
#define V3_UUID_BYTES      16

/// Session ID is a UUID string (36 chars).
#define SESSION_ID_LENGTH  36

// ── Protocol V3 — Manufacturer Data Constants ────────────────────────────────
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
#define BLE_PROTO_VERSION  0x03
/// Attendance beacon payload type byte.
#define BLE_PAYLOAD_TYPE   0x01
/// Total manufacturer payload length (after Company ID stripped):
///   1 (version) + 1 (type) + 8 (token) + 16 (UUID) = 26 bytes.
#define MFR_PAYLOAD_LEN    26
/// Bluetooth SIG test/unregistered company identifier (little-endian).
#define COMPANY_ID_LO      0xFF
#define COMPANY_ID_HI      0xFF

// ── WiFi ─────────────────────────────────────────────────────────────────────
#define WIFI_SSID                    "Vivo T3 Pro"
#define WIFI_PASSWORD                "12345678"
#define WIFI_MAX_RETRIES             20        // Before first restart
#define WIFI_RECONNECT_INTERVAL_MS   5000      // Between reconnect attempts

// ── MQTT ─────────────────────────────────────────────────────────────────────
//
//  HiveMQ Cloud TLS broker (port 8883, WiFiClientSecure, setInsecure()).
//  mqtt_manager.cpp uses WiFiClientSecure — plain WiFiClient will NOT work.
//
#define MQTT_BROKER                  "dce0dc24b166462e8ddabb14da31c6d0.s1.eu.hivemq.cloud"
#define MQTT_PORT                    8883
#define MQTT_USERNAME                "esp32"
#define MQTT_PASSWORD                "Esp32@32"
#define MQTT_CLIENT_ID               DEVICE_ID
#define MQTT_BUFFER_SIZE             512        // Max MQTT message size in bytes
#define MQTT_KEEPALIVE               60         // Seconds

// Reconnect backoff
#define MQTT_RECONNECT_MIN_MS        1000       // Initial delay (1 s)
#define MQTT_RECONNECT_MAX_MS        30000      // Max delay (30 s cap)

// ── MQTT Topics (MUST match backend/app/mqtt/__init__.py) ───────────────────
//
//  The prefix now uses CLASSROOM_UUID (the full UUID string) so that all
//  topics align with backend publish paths:
//    campus/classroom/{classroom_uuid}/...
//
#define TOPIC_PREFIX          "campus/classroom/" CLASSROOM_UUID

// Subscribe (Backend → ESP32):
#define TOPIC_CONTROL_START   TOPIC_PREFIX "/control/start"
#define TOPIC_CONTROL_STOP    TOPIC_PREFIX "/control/stop"
#define TOPIC_TOKEN           TOPIC_PREFIX "/token"

// Publish (ESP32 → Backend):
#define TOPIC_HEARTBEAT       TOPIC_PREFIX "/heartbeat"
#define TOPIC_STATUS          TOPIC_PREFIX "/status"
#define TOPIC_TELEMETRY       TOPIC_PREFIX "/telemetry"

// ── BLE Advertising Intervals ────────────────────────────────────────────────
//   Unit: 0.625 ms per count (Bluetooth Core Specification vol 6, part B).
//   160 × 0.625 ms = 100 ms
//
//   Fixed interval (min == max) eliminates jitter and maximises transmission
//   predictability at range. The Flutter BleScanner uses a 10-second scan window
//   with auto-retry. Advertising at 100 ms guarantees ≥ 100 packets per scan
//   window, ensuring reliable detection even with significant packet loss.
//
//   Range test results:
//     200 ms interval → ~50% detection rate at 25 m NLOS (1 wall)
//     100 ms interval → ~95% detection rate at 25 m NLOS (same conditions)
//
#define BLE_ADV_INTERVAL_MIN  160    // 160 × 0.625 ms = 100 ms
#define BLE_ADV_INTERVAL_MAX  160    // fixed = MIN → no jitter, maximum density
#define BLE_TX_POWER          ESP_PWR_LVL_P9   // +9 dBm (max range on ESP32)

// ── Wi-Fi / BLE Coexistence ───────────────────────────────────────────────────
//
//   esp_coex_preference_set() is NOT called. Root-cause analysis showed that
//   calling it (with CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE=1 in build_flags)
//   caused abort() inside coex_core_enable() → esp_bt_controller_enable() →
//   NimBLEDevice::init().
//
//   Effective coexistence strategy (no API call required):
//     • WiFi Modem Sleep is kept active (default WIFI_PS_MIN_MODEM) as required
//       by ESP-IDF coexistence drivers when both WiFi and BLE are active.
//       This allows the coexistence scheduler to arbitrate antenna time-slicing
//       without crashing in pm_set_sleep_type().
//     • The arduino-esp32 framework pre-compiled libraries already enable SW
//       coexistence (CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE=1 in sdkconfig.h).
//     • With MQTT traffic at 30s/2min intervals, balanced coexistence has
//       negligible impact on 100 ms BLE advertising regularity.
//
// ── Timing ───────────────────────────────────────────────────────────────────
#define HEARTBEAT_INTERVAL_MS      30000    // 30 seconds
#define STATUS_REPORT_INTERVAL_MS  60000    // 60 seconds
#define TELEMETRY_INTERVAL_MS      120000   // 2 minutes
#define WATCHDOG_TIMEOUT_S         30       // Hardware watchdog timeout
