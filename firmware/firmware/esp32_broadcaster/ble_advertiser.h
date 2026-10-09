/*
 * ble_advertiser.h — NimBLE-Arduino 2.5.0  ·  Protocol V3 Public API
 * =====================================================================
 *
 * PURPOSE
 *   Declares the four public functions that control the Protocol V3
 *   BLE attendance beacon.
 *
 *   All NimBLE types are fully hidden — the .ino sketch and any future
 *   Phase 2 MQTT handler need only include this header.
 *
 * PROTOCOL V3 ADVERTISEMENT FORMAT
 *
 *   GAP Device Name (Scan-Response):
 *     Any name starting with "SCA-"  e.g. "SCA-LAB101"
 *     Flutter isSCADevice() only checks the "SCA-" prefix.
 *     The suffix is IGNORED in V3; classroomId comes from the UUID bytes.
 *
 *   Manufacturer Data payload (26 bytes after 2-byte Company ID 0xFFFF):
 *     byte[0]      = 0x03                    BLE_PROTO_VERSION
 *     byte[1]      = 0x01                    BLE_PAYLOAD_TYPE
 *     byte[2..9]   = 8 raw bytes             Token (hex string decoded to binary)
 *     byte[10..25] = 16 raw bytes            Classroom UUID (binary)
 *
 *   Example for token="e1ede9723aacd6c4", UUID="e664f3af-8aec-5d5f-bf5d-b8754d6d93b2":
 *
 *     nRF Connect raw hex (28 bytes including company ID):
 *     FF FF 03 01 E1 ED E9 72 3A AC D6 C4
 *                 E6 64 F3 AF 8A EC 5D 5F BF 5D B8 75 4D 6D 93 B2
 *
 *     Flutter extracts:
 *       token       = "e1ede9723aacd6c4"  (bytes[2..9] hex-encoded)
 *       classroomId = "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"  (bytes[10..25] as UUID)
 *
 * TOKEN REQUIREMENTS
 *   - Exactly TOKEN_HEX_LEN (16) lowercase hex characters.
 *   - Valid characters: [0-9a-fA-F].
 *   - updateBleToken() decodes the hex string to 8 raw bytes in-place.
 *
 * CLASSROOM UUID REQUIREMENTS
 *   - Standard "8-4-4-4-12" UUID string, exactly 36 characters.
 *   - Set in config.h as CLASSROOM_UUID.  Embedded as binary at setup().
 *   - Firmware restart required to change the classroom UUID.
 *
 * PHASE 2 INTEGRATION (future — one call is all that is needed)
 *
 *   Inside your MQTT message callback:
 *
 *       #include "ble_advertiser.h"
 *       updateBleToken(receivedToken);   // stops, rebuilds, restarts — no reboot
 *
 *   For session gating via MQTT start/end commands:
 *
 *       startBleAdvertising();           // MQTT session-start handler
 *       stopBleAdvertising();            // MQTT session-end handler
 *
 * LIBRARY
 *   NimBLE-Arduino 2.5.0 by h2zero
 *   Arduino IDE → Library Manager → search "NimBLE-Arduino" → Install
 *   Do NOT install the built-in "ESP32 BLE Arduino" library alongside it.
 */

#pragma once

#include <Arduino.h>   // uint8_t, size_t — always explicit in headers

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

/**
 * setupBle()
 *
 * Initialises the NimBLE 2.5.0 stack, sets the GAP device name (DEVICE_NAME),
 * TX power to +9 dBm, decodes CLASSROOM_UUID and ATTENDANCE_TOKEN from
 * config.h into raw bytes, builds the first Protocol V3 manufacturer-data
 * advertisement, and starts non-connectable advertising.
 *
 * Protocol V3 payload built here (26 bytes):
 *   byte[0]      = 0x03  (BLE_PROTO_VERSION)
 *   byte[1]      = 0x01  (BLE_PAYLOAD_TYPE)
 *   byte[2..9]   = 8 raw token bytes  (decoded from ATTENDANCE_TOKEN hex string)
 *   byte[10..25] = 16 raw UUID bytes  (decoded from CLASSROOM_UUID string)
 *
 * Uses setConnectableMode(BLE_GAP_CONN_MODE_NON) — the NimBLE 2.5.0 API.
 *
 * Call exactly once from Arduino setup().
 */
void setupBle();

// ─────────────────────────────────────────────────────────────────────────────
// Runtime control
// ─────────────────────────────────────────────────────────────────────────────

/**
 * updateBleToken(token)
 *
 * Replaces the attendance token in the Protocol V3 manufacturer-data payload
 * and restarts advertising — without rebooting the ESP32.
 *
 * Internally:
 *   1. Validates: length == 16 and all characters are hex digits.
 *   2. Decodes the 16-char hex string to 8 raw bytes.
 *   3. Rebuilds the 26-byte V3 manufacturer payload.
 *   4. Stops and restarts advertising.
 *
 * The classroom UUID (bytes[10..25]) is NOT changed by this call.
 * Only the token bytes (bytes[2..9]) are updated.
 *
 * Validation rules (both must pass or the update is rejected):
 *   1. Length must be exactly TOKEN_HEX_LEN (16) characters.
 *   2. Every character must be a valid hex digit [0-9a-fA-F].
 *
 * @param token  Null-terminated string, exactly 16 hex chars.
 *               Example: "e1ede9723aacd6c4"
 *
 * Phase 2 usage (inside MQTT message callback):
 *   updateBleToken(receivedToken);
 */
void updateBleToken(const char* token);

/**
 * startBleAdvertising()
 *
 * Resumes BLE advertising using the current token and UUID.
 * No-op if advertising is already active.
 *
 * Phase 2 usage: call from the MQTT session-start command handler.
 */
void startBleAdvertising();

/**
 * stopBleAdvertising()
 *
 * Halts BLE advertising.  The NimBLE stack remains initialised; calling
 * startBleAdvertising() or updateBleToken() will resume it.
 *
 * Phase 2 usage: call from the MQTT session-end command handler.
 */
void stopBleAdvertising();
