/*
 * ble_manager.h — BLE advertising management for Protocol V3 attendance beacons.
 *
 * PURPOSE
 *   Declares the BLEManager namespace public API.
 *   All NimBLE types are fully hidden — main.cpp, command_handler.cpp,
 *   heartbeat_manager.cpp, and status_reporter.cpp only need this header.
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
 * LIBRARY
 *   NimBLE-Arduino 2.5.0 by h2zero
 *   PlatformIO: h2zero/NimBLE-Arduino @ ^2.5.0
 *   Do NOT mix with the built-in "ESP32 BLE Arduino" (BLEDevice.h) library.
 */

#pragma once

#include <Arduino.h>

namespace BLEManager {

    /**
     * begin()
     *
     * Initialises the NimBLE 2.5.0 stack, sets the GAP device name (DEVICE_NAME),
     * TX power to +9 dBm, decodes CLASSROOM_UUID and ATTENDANCE_TOKEN from
     * config.h into raw bytes.
     *
     * Does NOT start advertising — BLE advertising begins only when the backend
     * sends a START_SESSION command via MQTT.
     *
     * Call exactly once from Arduino setup(), after Serial.begin().
     */
    void begin();

    /**
     * startAdvertising(token, sessionId)
     *
     * Begins BLE advertising with a Protocol V3 payload built from [token]
     * and the fixed CLASSROOM_UUID.
     *
     * Replaces any currently active session (stop → rebuild → start).
     *
     * @param token      16-char lowercase hex string (e.g. "e1ede9723aacd6c4").
     *                   Must be exactly TOKEN_HEX_LEN characters.
     * @param sessionId  UUID string of the session (stored for telemetry/heartbeat).
     *                   Null or empty is accepted; advertising still starts.
     */
    void startAdvertising(const char* token, const char* sessionId);

    /**
     * stopAdvertising()
     *
     * Halts BLE advertising. The NimBLE stack remains initialised.
     * Calling startAdvertising() or updateToken() will resume it.
     *
     * No-op if not currently advertising.
     */
    void stopAdvertising();

    /**
     * updateToken(token)
     *
     * Replaces the attendance token in the Protocol V3 payload and restarts
     * advertising without rebooting the ESP32.
     *
     * Only the token bytes (bytes[2..9]) are updated.
     * The classroom UUID (bytes[10..25]) does not change.
     *
     * Internally: validates → decodes hex → rebuilds V3 payload → stop → start.
     *
     * Validation rules (both must pass, or the update is rejected silently):
     *   1. Length must be exactly TOKEN_HEX_LEN (16) characters.
     *   2. Every character must be a valid hex digit [0-9a-fA-F].
     *
     * @param token  Null-terminated string, exactly 16 hex chars.
     */
    void updateToken(const char* token);

    /**
     * isAdvertising()
     *
     * Returns true while BLE PDUs are actively being sent.
     */
    bool isAdvertising();

    /**
     * getCurrentToken()
     *
     * Returns the 16-char hex token currently embedded in the advertisement.
     * Returns an empty string if advertising has never started.
     */
    const char* getCurrentToken();

}  // namespace BLEManager
