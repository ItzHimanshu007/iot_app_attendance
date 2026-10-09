/*
 * ble_advertiser.cpp — NimBLE-Arduino 2.5.0  ·  Protocol V3 Implementation
 * ==========================================================================
 *
 * ── BLE PACKET LAYOUT (Protocol V3) ─────────────────────────────────────────
 *
 *  Primary ADV PDU  (≤ 31 bytes, no auto-Flags when using setAdvertisementData)
 *  ┌────────────────────────────────────────────────────────────────────────┐
 *  │  [Manufacturer Specific AD]                                            │
 *  │    AD-Length  (1 B)  = 29  (= 1 + 2 + 26)                             │
 *  │    AD-Type    (1 B)  = 0xFF                                            │
 *  │    compID     (2 B)  = 0xFF 0xFF  (test/unregistered, little-endian)   │
 *  │    byte[0]    (1 B)  = 0x03  ← BLE_PROTO_VERSION                      │
 *  │    byte[1]    (1 B)  = 0x01  ← BLE_PAYLOAD_TYPE                       │
 *  │    byte[2..9] (8 B)  = token raw bytes                                 │
 *  │                        "e1ede9723aacd6c4" → E1 ED E9 72 3A AC D6 C4   │
 *  │    byte[10..25](16B) = classroom UUID raw bytes                        │
 *  │                        "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"          │
 *  │                        → E6 64 F3 AF 8A EC 5D 5F BF 5D B8 75 4D 6D 93 B2│
 *  └────────────────────────────────────────────────────────────────────────┘
 *  Total primary PDU: 1(len) + 1(type) + 2(compID) + 26(payload) = 30 B ✓
 *
 *  Scan Response PDU  (≤ 31 bytes, sent on SCAN_REQ)
 *  ┌────────────────────────────────────────────────────────────────────────┐
 *  │  [Complete Local Name AD]                                              │
 *  │    "SCA-LAB101" (9 chars → 11-byte AD element ✓)                      │
 *  └────────────────────────────────────────────────────────────────────────┘
 *
 * ── WHAT FLUTTER READS ───────────────────────────────────────────────────────
 *
 *  BlePayloadParser flow:
 *    1. isSCADevice(name) → name.startsWith("SCA-") → true          ✓
 *    2. manufacturerData[0] == 0x03 → dispatch to _parseBinaryPathV3()
 *    3. bytes.length >= 26                                           ✓
 *    4. bytes[1] == 0x01 → attendance payload                        ✓
 *    5. bytes[2..9]   → hex-encode each byte → "e1ede9723aacd6c4"   ✓
 *    6. bytes[10..25] → format as UUID string
 *         → "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"                  ✓
 *    7. GET /sessions/active?classroom_id=e664f3af-...               ✓
 *       Backend queries: WHERE classroom_id = 'e664f3af-...' (UUID)  ✓
 *
 * ── EXPECTED nRF CONNECT VIEW ────────────────────────────────────────────────
 *
 *  Device Name:       SCA-LAB101
 *  Manufacturer Data (nRF strips the 2-byte Company ID from display):
 *    03 01
 *    E1 ED E9 72 3A AC D6 C4
 *    E6 64 F3 AF 8A EC 5D 5F
 *    BF 5D B8 75 4D 6D 93 B2
 *
 * ── HELPER FUNCTIONS ─────────────────────────────────────────────────────────
 *
 *  _hexCharToNibble(c)    → 0..15 or -1 on error
 *  _hexStringToBytes()    → decodes 16-char hex string to 8 raw bytes
 *  _uuidStringToBytes()   → decodes "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
 *                           to 16 raw bytes
 *  _isHexChar(c)          → validates a single hex character
 *  _isValidToken(token)   → validates 16-char hex token string
 *
 * ── NIMBLE 2.5.0 API NOTES ───────────────────────────────────────────────────
 *
 *  ✓  pAdv->setConnectableMode(BLE_GAP_CONN_MODE_NON)
 *       Non-connectable legacy advertising.
 *       Replaces the removed v1.x: setAdvertisementType(BLE_GAP_CONN_MODE_NON)
 *
 *  ✓  setAdvertisementData() with explicit NimBLEAdvertisementData object.
 *       When this is called, NimBLE does NOT auto-add Flags — allowing the
 *       30-byte V3 manufacturer AD to fit exactly within the 31-byte budget.
 *
 *  ✗  ESP32 BLE Arduino (BLEDevice.h) — NOT included.
 *       Including both libraries causes linker conflicts.
 *
 *  ✓  Fixed-size stack buffers throughout — no heap allocation, no String.
 *
 * ── LIBRARY ──────────────────────────────────────────────────────────────────
 *   NimBLE-Arduino 2.5.0 by h2zero
 *   Arduino IDE → Library Manager → "NimBLE-Arduino"
 *   Board: ESP32 Dev Module (ESP32 Arduino core ≥ 2.x)
 */

#include <NimBLEDevice.h>    // NimBLE-Arduino 2.5.0 — NOT the built-in BLE lib
#include <string.h>          // strlen, strncpy, memcpy, memset
#include <Arduino.h>         // Serial, delay, uint8_t

#include "config.h"
#include "ble_advertiser.h"

// ─────────────────────────────────────────────────────────────────────────────
// Module-level state
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton pointer from NimBLEDevice::getAdvertising().
/// Set once in setupBle(); never freed during normal operation.
static NimBLEAdvertising* s_pAdv = nullptr;

/// True while the BLE controller is actively sending advertisement PDUs.
static bool s_advertising = false;

/// Current token stored as 8 raw bytes (decoded from 16-char hex string).
/// Updated by updateBleToken(); initialised in setupBle().
static uint8_t s_tokenBytes[V3_TOKEN_BYTES];

/// Classroom UUID stored as 16 raw bytes (decoded from CLASSROOM_UUID string).
/// Set once in setupBle(); does not change at runtime.
static uint8_t s_uuidBytes[V3_UUID_BYTES];

/// Human-readable copy of the current token for Serial debug output.
static char s_tokenHex[TOKEN_HEX_LEN + 1];

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers — character / byte conversions
// ─────────────────────────────────────────────────────────────────────────────

/**
 * _isHexChar(c)
 *
 * Returns true if [c] is a valid ASCII hexadecimal digit.
 * Accepts: '0'–'9' (0x30–0x39), 'a'–'f' (0x61–0x66), 'A'–'F' (0x41–0x46).
 */
static inline bool _isHexChar(char c) {
    return (c >= '0' && c <= '9') ||
           (c >= 'a' && c <= 'f') ||
           (c >= 'A' && c <= 'F');
}

/**
 * _hexCharToNibble(c)
 *
 * Converts a single ASCII hex character to its 4-bit value (0–15).
 *
 * @return  0–15 on success, -1 if [c] is not a valid hex character.
 */
static int _hexCharToNibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/**
 * _hexStringToBytes(hexStr, out, outLen)
 *
 * Decodes a hex string of length [outLen * 2] into [outLen] raw bytes.
 *
 * Example:
 *   "e1ede9723aacd6c4" (16 chars) → { 0xE1, 0xED, 0xE9, 0x72, 0x3A, 0xAC, 0xD6, 0xC4 }
 *
 * @param hexStr   Null-terminated hex string.  Must be exactly outLen*2 chars.
 * @param out      Destination buffer of at least [outLen] bytes.
 * @param outLen   Number of raw bytes to decode.
 * @return         true on success, false if any character is invalid.
 */
static bool _hexStringToBytes(const char* hexStr, uint8_t* out, size_t outLen) {
    for (size_t i = 0; i < outLen; i++) {
        int hi = _hexCharToNibble(hexStr[i * 2]);
        int lo = _hexCharToNibble(hexStr[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            Serial.printf("[BLE] _hexStringToBytes: invalid hex at position %u\n",
                          (unsigned)(i * 2));
            return false;
        }
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return true;
}

/**
 * _uuidStringToBytes(uuidStr, out)
 *
 * Parses a standard UUID string "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
 * (36 chars: 32 hex digits + 4 dashes) into 16 raw bytes.
 *
 * The dashes at positions 8, 13, 18, 23 are skipped.
 * All remaining 32 hex characters are decoded in order.
 *
 * Example:
 *   "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"
 *   →  { 0xE6, 0x64, 0xF3, 0xAF, 0x8A, 0xEC, 0x5D, 0x5F,
 *         0xBF, 0x5D, 0xB8, 0x75, 0x4D, 0x6D, 0x93, 0xB2 }
 *
 * Flutter _formatUuid() reverses this exactly:
 *   raw[0..3]   → group 1 (8 chars)
 *   raw[4..5]   → group 2 (4 chars)
 *   raw[6..7]   → group 3 (4 chars)
 *   raw[8..9]   → group 4 (4 chars)
 *   raw[10..15] → group 5 (12 chars)
 *
 * @param uuidStr  Null-terminated UUID string, exactly 36 characters.
 * @param out      Destination buffer of at least 16 bytes.
 * @return         true on success, false if the format is wrong.
 */
static bool _uuidStringToBytes(const char* uuidStr, uint8_t* out) {
    // Validate total length
    if (strlen(uuidStr) != 36) {
        Serial.printf("[BLE] _uuidStringToBytes: UUID length %u != 36\n",
                      (unsigned)strlen(uuidStr));
        return false;
    }

    // Validate dashes at positions 8, 13, 18, 23
    if (uuidStr[8]  != '-' || uuidStr[13] != '-' ||
        uuidStr[18] != '-' || uuidStr[23] != '-') {
        Serial.println("[BLE] _uuidStringToBytes: missing dash in UUID");
        return false;
    }

    // Collect the 32 hex characters by skipping dashes
    char hexOnly[33];   // 32 hex chars + null
    size_t hi = 0;
    for (size_t i = 0; i < 36 && hi < 32; i++) {
        if (uuidStr[i] == '-') continue;
        if (!_isHexChar(uuidStr[i])) {
            Serial.printf("[BLE] _uuidStringToBytes: non-hex char '%c' at pos %u\n",
                          uuidStr[i], (unsigned)i);
            return false;
        }
        hexOnly[hi++] = uuidStr[i];
    }
    hexOnly[32] = '\0';

    // Decode 32 hex chars → 16 bytes
    return _hexStringToBytes(hexOnly, out, V3_UUID_BYTES);
}

/**
 * _isValidToken(token)
 *
 * Validates that [token] satisfies Protocol V3 token requirements:
 *   1. Not null.
 *   2. Length == TOKEN_HEX_LEN (16).
 *   3. Every character is a valid hex digit [0-9a-fA-F].
 *
 * @return  true if valid, false if rejected (rejection reason logged to Serial).
 */
static bool _isValidToken(const char* token) {
    if (token == nullptr) {
        Serial.println("[BLE] Token rejected: null pointer");
        return false;
    }
    size_t len = strlen(token);
    if (len != TOKEN_HEX_LEN) {
        Serial.printf("[BLE] Token rejected: length %u != %d\n",
                      (unsigned)len, TOKEN_HEX_LEN);
        return false;
    }
    for (size_t i = 0; i < TOKEN_HEX_LEN; i++) {
        if (!_isHexChar(token[i])) {
            Serial.printf("[BLE] Token rejected: non-hex char '%c' at index %u\n",
                          token[i], (unsigned)i);
            return false;
        }
    }
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers — payload building
// ─────────────────────────────────────────────────────────────────────────────

/**
 * _buildV3MfrValue(buf)
 *
 * Writes the complete Manufacturer Data AD value into [buf].
 *
 * Layout (2-byte Company ID + 26-byte V3 payload = 28 bytes total):
 *
 *   buf[0]      = COMPANY_ID_LO   (0xFF)
 *   buf[1]      = COMPANY_ID_HI   (0xFF)
 *   buf[2]      = BLE_PROTO_VERSION (0x03)
 *   buf[3]      = BLE_PAYLOAD_TYPE  (0x01)
 *   buf[4..11]  = s_tokenBytes[0..7]  (8 raw token bytes)
 *   buf[12..27] = s_uuidBytes[0..15] (16 raw UUID bytes)
 *
 * As Flutter sees it (after stripping the Company ID automatically):
 *   bytes[0]      = 0x03
 *   bytes[1]      = 0x01
 *   bytes[2..9]   = token raw bytes  → hex-encoded → "e1ede9723aacd6c4"
 *   bytes[10..25] = UUID  raw bytes  → formatted   → "e664f3af-8aec-..."
 *
 * @param buf   Caller-supplied buffer of at least 2 + MFR_PAYLOAD_LEN (= 28) bytes.
 * @return      Total bytes written (= 28).
 */
static int _buildV3MfrValue(uint8_t* buf) {
    // Company ID (little-endian, 2 bytes)
    buf[0] = COMPANY_ID_LO;           // 0xFF
    buf[1] = COMPANY_ID_HI;           // 0xFF

    // Protocol V3 header
    buf[2] = BLE_PROTO_VERSION;       // 0x03
    buf[3] = BLE_PAYLOAD_TYPE;        // 0x01

    // Token: 8 raw bytes at buf[4..11]
    //   (Flutter reads these as bytes[2..9] after stripping Company ID)
    memcpy(buf + 4, s_tokenBytes, V3_TOKEN_BYTES);

    // Classroom UUID: 16 raw bytes at buf[12..27]
    //   (Flutter reads these as bytes[10..25])
    memcpy(buf + 4 + V3_TOKEN_BYTES, s_uuidBytes, V3_UUID_BYTES);

    return 2 + MFR_PAYLOAD_LEN;       // 28 bytes total
}

/**
 * _applyAndStart()
 *
 * Core internal routine:
 *   1. Stops advertising if currently active (+ 10 ms settle).
 *   2. Builds the 28-byte Protocol V3 manufacturer-data AD value on the stack.
 *   3. Rebuilds NimBLEAdvertisementData (advertisement + scan-response).
 *   4. Sets non-connectable mode via setConnectableMode() [NimBLE 2.5.0 API].
 *   5. Sets advertising intervals (100–200 ms).
 *   6. Restarts advertising.
 *
 * All objects are stack-allocated; no heap allocation occurs.
 * Precondition: s_pAdv != nullptr  (i.e., setupBle() was called).
 */
static void _applyAndStart() {
    if (s_pAdv == nullptr) {
        Serial.println("[BLE] ERROR: setupBle() must be called before advertising");
        return;
    }

    // ── Stop if currently active ──────────────────────────────────────────
    if (s_advertising) {
        s_pAdv->stop();
        s_advertising = false;
        // NimBLE processes stop() asynchronously inside the host task.
        // 10 ms is sufficient for the controller to quiesce.
        delay(10);
    }

    // ── Build Protocol V3 manufacturer data value on the stack ────────────
    //
    //   mfrValue layout (28 bytes):
    //     [0..1]   Company ID    (0xFF 0xFF)
    //     [2]      0x03          (BLE_PROTO_VERSION)
    //     [3]      0x01          (BLE_PAYLOAD_TYPE)
    //     [4..11]  token bytes   (8 raw bytes, e.g. E1 ED E9 72 3A AC D6 C4)
    //     [12..27] UUID bytes    (16 raw bytes)
    //
    uint8_t mfrValue[2 + MFR_PAYLOAD_LEN];   // 28 bytes
    int mfrLen = _buildV3MfrValue(mfrValue);

    // ── Advertisement data (primary PDU) ──────────────────────────────────
    //   When setAdvertisementData() is called with an explicit object,
    //   NimBLE does NOT auto-add the Flags AD, so the full 30-byte mfr
    //   AD fits within the 31-byte PDU budget:
    //     1(AD-len) + 1(AD-type 0xFF) + 28(mfrValue) = 30 bytes ✓
    //   Device name goes in scan-response.
    NimBLEAdvertisementData advData;
    advData.setManufacturerData(
        std::string(reinterpret_cast<char*>(mfrValue), (size_t)mfrLen));
    s_pAdv->setAdvertisementData(advData);

    // ── Scan response data ────────────────────────────────────────────────
    //   Contains: Complete Local Name = "SCA-LAB101".
    //   AD element = 1(len) + 1(type 0x09) + 9(name) = 11 bytes ✓
    //   Flutter isSCADevice() only checks the "SCA-" prefix.
    NimBLEAdvertisementData scanData;
    scanData.setName(DEVICE_NAME);
    s_pAdv->setScanResponseData(scanData);

    // ── Non-connectable mode ──────────────────────────────────────────────
    //   NimBLE-Arduino 2.5.0 API.
    //   Replaces the removed v1.x: setAdvertisementType(BLE_GAP_CONN_MODE_NON)
    s_pAdv->setConnectableMode(BLE_GAP_CONN_MODE_NON);

    // ── Advertising intervals ─────────────────────────────────────────────
    //   160 × 0.625 ms = 100 ms,  320 × 0.625 ms = 200 ms.
    s_pAdv->setMinInterval(ADV_INTERVAL_MIN);
    s_pAdv->setMaxInterval(ADV_INTERVAL_MAX);

    // ── Start ─────────────────────────────────────────────────────────────
    s_pAdv->start();
    s_advertising = true;

    // ── Debug output ──────────────────────────────────────────────────────
    #if DEBUG
    Serial.println("[BLE] Advertising Started (Protocol V3)");
    Serial.printf ("[BLE] Device Name    : %s\n", DEVICE_NAME);
    Serial.printf ("[BLE] Token (hex)    : %s\n", s_tokenHex);
    Serial.print  ("[BLE] Token (bytes)  : ");
    for (int i = 0; i < V3_TOKEN_BYTES; i++) {
        Serial.printf("%02X ", s_tokenBytes[i]);
    }
    Serial.println();
    Serial.printf ("[BLE] Classroom UUID : %s\n", CLASSROOM_UUID);
    Serial.print  ("[BLE] UUID (bytes)   : ");
    for (int i = 0; i < V3_UUID_BYTES; i++) {
        Serial.printf("%02X ", s_uuidBytes[i]);
    }
    Serial.println();
    Serial.print  ("[BLE] Mfr Hex (full) : ");
    for (int i = 0; i < mfrLen; i++) {
        Serial.printf("%02X ", mfrValue[i]);
    }
    Serial.println();
    #endif
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

void setupBle() {
    // ── Decode classroom UUID from config.h → 16 raw bytes ────────────────
    //   Runs once; UUID does not change at runtime.
    if (!_uuidStringToBytes(CLASSROOM_UUID, s_uuidBytes)) {
        Serial.println("[BLE] FATAL: CLASSROOM_UUID in config.h is invalid.");
        Serial.println("[BLE] Cannot build V3 advertisement. Halting.");
        while (true) { delay(1000); }   // halt — misconfiguration
    }

    // ── Decode attendance token from config.h → 8 raw bytes ──────────────
    if (!_isValidToken(ATTENDANCE_TOKEN)) {
        Serial.println("[BLE] FATAL: ATTENDANCE_TOKEN in config.h is invalid.");
        Serial.println("[BLE] Must be exactly 16 lowercase hex characters. Halting.");
        while (true) { delay(1000); }   // halt — misconfiguration
    }
    if (!_hexStringToBytes(ATTENDANCE_TOKEN, s_tokenBytes, V3_TOKEN_BYTES)) {
        Serial.println("[BLE] FATAL: ATTENDANCE_TOKEN decode failed. Halting.");
        while (true) { delay(1000); }
    }
    strncpy(s_tokenHex, ATTENDANCE_TOKEN, TOKEN_HEX_LEN);
    s_tokenHex[TOKEN_HEX_LEN] = '\0';

    // ── Compile-time sanity check ─────────────────────────────────────────
    //   Catches accidental config.h edits before they reach the hardware.
    static_assert(
        sizeof(ATTENDANCE_TOKEN) - 1 == TOKEN_HEX_LEN,
        "ATTENDANCE_TOKEN in config.h must be exactly TOKEN_HEX_LEN (16) chars"
    );
    static_assert(
        sizeof(CLASSROOM_UUID) - 1 == 36,
        "CLASSROOM_UUID in config.h must be exactly 36 characters"
    );

    // ── Initialise NimBLE stack ───────────────────────────────────────────
    #if DEBUG
    Serial.println("[BLE] Initialising NimBLE (Protocol V3)...");
    #endif

    NimBLEDevice::init(DEVICE_NAME);

    // ── TX power ──────────────────────────────────────────────────────────
    //   ESP_PWR_LVL_P9 = +9 dBm (maximum transmit power).
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);

    // ── Obtain singleton advertising handle ───────────────────────────────
    s_pAdv = NimBLEDevice::getAdvertising();

    // ── Build and start the first Protocol V3 advertisement ──────────────
    _applyAndStart();
}

// ─────────────────────────────────────────────────────────────────────────────

void updateBleToken(const char* token) {
    // ── Guard: stack must be initialised ─────────────────────────────────
    if (s_pAdv == nullptr) {
        Serial.println("[BLE] updateBleToken: ignored — call setupBle() first");
        return;
    }

    // ── Validate: exactly 16 hex chars ───────────────────────────────────
    if (!_isValidToken(token)) {
        // _isValidToken() already printed the rejection reason.
        return;
    }

    // ── Decode hex string → 8 raw token bytes ────────────────────────────
    uint8_t newTokenBytes[V3_TOKEN_BYTES];
    if (!_hexStringToBytes(token, newTokenBytes, V3_TOKEN_BYTES)) {
        Serial.println("[BLE] updateBleToken: hex decode failed — token unchanged");
        return;
    }

    // ── Apply new token bytes and update debug buffer ─────────────────────
    memcpy(s_tokenBytes, newTokenBytes, V3_TOKEN_BYTES);
    strncpy(s_tokenHex, token, TOKEN_HEX_LEN);
    s_tokenHex[TOKEN_HEX_LEN] = '\0';

    // ── Rebuild V3 payload and restart advertising ─────────────────────
    //   Note: s_uuidBytes is unchanged — only the token bytes change.
    _applyAndStart();

    #if DEBUG
    Serial.printf("[BLE] Token updated → \"%s\"\n", s_tokenHex);
    Serial.print ("[BLE] Token bytes   : ");
    for (int i = 0; i < V3_TOKEN_BYTES; i++) {
        Serial.printf("%02X ", s_tokenBytes[i]);
    }
    Serial.println();
    #endif
}

// ─────────────────────────────────────────────────────────────────────────────

void startBleAdvertising() {
    if (s_pAdv == nullptr) {
        Serial.println("[BLE] startBleAdvertising: ignored — call setupBle() first");
        return;
    }
    if (s_advertising) {
        #if DEBUG
        Serial.println("[BLE] startBleAdvertising: already active — no-op");
        #endif
        return;
    }
    _applyAndStart();
}

// ─────────────────────────────────────────────────────────────────────────────

void stopBleAdvertising() {
    if (s_pAdv == nullptr || !s_advertising) {
        #if DEBUG
        Serial.println("[BLE] stopBleAdvertising: not active — no-op");
        #endif
        return;
    }
    s_pAdv->stop();
    s_advertising = false;

    #if DEBUG
    Serial.println("[BLE] Advertising Stopped");
    #endif
}
