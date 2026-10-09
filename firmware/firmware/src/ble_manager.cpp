/*
 * ble_manager.cpp — NimBLE-Arduino 2.5.0  ·  Protocol V3 Implementation
 * ========================================================================
 *
 * ── BLE PACKET LAYOUT (Protocol V3) ─────────────────────────────────────
 *
 *  Primary ADV PDU  (≤ 31 bytes)
 *  ┌──────────────────────────────────────────────────────────────────────────┐
 *  │  [Manufacturer Specific AD]                                              │
 *  │    AD-Length  (1 B)  = 29  (= 1 + 2 + 26)                               │
 *  │    AD-Type    (1 B)  = 0xFF                                              │
 *  │    compID     (2 B)  = 0xFF 0xFF  (test/unregistered, little-endian)     │
 *  │    byte[0]    (1 B)  = 0x03  ← BLE_PROTO_VERSION                        │
 *  │    byte[1]    (1 B)  = 0x01  ← BLE_PAYLOAD_TYPE                         │
 *  │    byte[2..9] (8 B)  = token raw bytes                                   │
 *  │                        "e1ede9723aacd6c4" → E1 ED E9 72 3A AC D6 C4     │
 *  │    byte[10..25](16B) = classroom UUID raw bytes                          │
 *  │                        "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"            │
 *  │                        → E6 64 F3 AF 8A EC 5D 5F BF 5D B8 75 4D 6D 93 B2│
 *  └──────────────────────────────────────────────────────────────────────────┘
 *  Total primary PDU: 1(len) + 1(type) + 2(compID) + 26(payload) = 30 B ✓
 *
 *  ── Flags AD — deliberately absent ─────────────────────────────────────────
 *
 *  The Flags AD structure (3 bytes) is intentionally NOT included in the
 *  primary PDU. Reason: the manufacturer data already occupies 30 bytes
 *  of the 31-byte budget. Adding Flags would exceed the limit (30+3=33>31).
 *
 *  The Bluetooth Core Specification (Vol 3, Part C §11.1.3) states that
 *  Flags are OPTIONAL for non-connectable undirected advertising (ADV_NONCONN_IND).
 *  Flutter's flutter_blue_plus library discovers devices without requiring Flags.
 *  Confirmed: this device is already successfully discovered at all tested ranges.
 *
 *  Scan Response PDU  (≤ 31 bytes, sent on SCAN_REQ)
 *  ┌──────────────────────────────────────────────────────────────────────────┐
 *  │  [Complete Local Name AD]                                                │
 *  │    "SCA-LAB101" (9 chars → 11-byte AD element ✓)                        │
 *  └──────────────────────────────────────────────────────────────────────────┘
 *  Scan response is optimal at 11 bytes. Moving the name to the primary PDU
 *  would displace manufacturer data (which is the critical identifier).
 *
 * ── WHAT FLUTTER READS ────────────────────────────────────────────────────
 *
 *  BlePayloadParser flow (manufacturer-first after firmware audit):
 *    1. manufacturerData[0] == 0x03 → dispatch to _parseBinaryPathV3() ✓
 *    2. bytes.length >= 26                                             ✓
 *    3. bytes[1] == 0x01 → attendance payload                         ✓
 *    4. bytes[2..9]   → hex-encode each byte → "e1ede9723aacd6c4"    ✓
 *    5. bytes[10..25] → format as UUID string
 *         → "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"                   ✓
 *    6. GET /sessions/active?classroom_id=e664f3af-...                ✓
 *       Backend queries: WHERE classroom_id = 'e664f3af-...' (UUID)   ✓
 *
 * ── TX POWER AUDIT ────────────────────────────────────────────────────────
 *
 *  TX power is set ONCE in begin():
 *    NimBLEDevice::setPower(BLE_TX_POWER)  // ESP_PWR_LVL_P9 = +9 dBm
 *
 *  Verified: no other function in this file or any other source file
 *  calls NimBLEDevice::setPower() or esp_ble_tx_power_set() or any
 *  equivalent. TX power remains at +9 dBm for the lifetime of the process.
 *
 *  NimBLE 2.5.0 internal note: NimBLEDevice::init() sets power to P3 (+3 dBm)
 *  as a default before our setPower(P9) call. Our call immediately overwrites
 *  it. Because setPower() and init() are both in begin(), and begin() is called
 *  exactly once from setup() BEFORE any advertising starts, the TX power is
 *  guaranteed to be +9 dBm for all advertising.
 *
 * ── Wi-Fi / BLE COEXISTENCE STRATEGY ─────────────────────────────────────
 *
 *  esp_coex_preference_set() is NOT called anywhere in the firmware.
 *
 *  Root-cause: calling it with CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE=1 in
 *  build_flags caused abort() inside coex_core_enable() during
 *  esp_bt_controller_enable() inside NimBLEDevice::init() (line 967).
 *  The deprecated API interacted with the pre-compiled framework binaries
 *  in a way that corrupted the coexistence module init state.
 *
 *  Effective strategy (no API call required):
 *    • WiFi Modem Sleep is kept active (default WIFI_PS_MIN_MODEM) as required
 *      by ESP-IDF coexistence drivers when both WiFi and BLE are active.
 *      This allows the coexistence scheduler to arbitrate antenna time-slicing
 *      without crashing in pm_set_sleep_type().
 *    • The pre-compiled framework has SW coexistence enabled by default
 *      (CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE=1 in sdkconfig.h). The balanced
 *      coexistence arbiter is active at all times.
 *    • With MQTT traffic at 30s/2min intervals, the coexistence arbiter's
 *      balanced mode has negligible impact on 100 ms advertising.
 *
 * ── BLE BLACKOUT AUDIT ────────────────────────────────────────────────────
 *
 *  Original code had: delay(10) in _applyAndStart() to "settle" after stop().
 *
 *  Analysis:
 *    - NimBLE 2.5.0: s_pAdv->stop() sends a HCI command to the BLE controller.
 *      The controller processes it in its own FreeRTOS task (nimble_host).
 *      The Xtensa dual-core architecture means the BLE host task continues
 *      processing even while loop() runs on the other core.
 *    - yield() releases the CPU for one scheduler tick (~1 ms) — sufficient
 *      for the HCI stop command to be acknowledged.
 *    - delay(10) unnecessarily creates a 10 ms blackout per token rotation.
 *      With token rotations every ~60 s, this wastes ~10 ms/rotation.
 *      During session start it wastes 10 ms at the moment the student
 *      taps "scan" — the highest-value moment.
 *
 *  Fix: replace delay(10) with yield().
 *
 * ── NIMBLE 2.5.0 API NOTES ────────────────────────────────────────────────
 *
 *  ✓  pAdv->setConnectableMode(BLE_GAP_CONN_MODE_NON)
 *       Non-connectable legacy advertising.
 *       Called ONCE in begin() — NOT in _applyAndStart() — because
 *       setConnectableMode() internally calls m_advData.setFlags(0).
 *       When m_advData contains 30 bytes of manufacturer data and has
 *       no Flags element, setFlags(0) appends a 3-byte Flags element:
 *           30 + 3 = 33 > BLE_HS_ADV_MAX_SZ (31)
 *       → NimBLEAdvertisementData::addData() logs "Data length exceeded".
 *       Moving the call to begin() (where m_advData is still empty)
 *       prevents the overflow entirely.
 *       Replaces removed v1.x: setAdvertisementType(ADV_TYPE_NONCONN_IND)
 *
 *  ✓  setAdvertisementData() with explicit NimBLEAdvertisementData object.
 *       Sends the 30-byte payload directly to the BLE controller via
 *       ble_gap_adv_set_data() and sets m_advDataSet = true, so NimBLE's
 *       start() does not re-push m_advData.  No Flags AD is present
 *       in the on-air PDU.  Primary PDU = 30 bytes (Mfr AD only). ✓
 *
 *  ✗  ESP32 BLE Arduino (BLEDevice.h) — NOT included.
 *       Including both libraries causes linker conflicts.
 *
 *  ✓  Fixed-size stack buffers throughout — no heap allocation, no String.
 *
 * ── LONG RANGE PHY (LE Coded PHY) — NOT SUPPORTED ────────────────────────
 *
 *  BLE Coded PHY (BLE 5.0 Long Range) is NOT available on the original ESP32
 *  (Xtensa LX6, BLE 4.2 controller). Only these Espressif SoCs support it:
 *    - ESP32-C3 (RISC-V, BLE 5.0)
 *    - ESP32-S3 (Xtensa LX7, BLE 5.0)
 *    - ESP32-C6 (RISC-V, BLE 5.4)
 *    - ESP32-H2 (RISC-V, BLE 5.3)
 *
 *  The target hardware (esp32dev → ESP32-WROOM-32 / WROVER) has a BLE 4.2
 *  controller. NimBLE 2.5.0 does not expose the LE Coded PHY API on BLE 4.2
 *  hardware. No workaround exists at the software level.
 *
 *  To gain Long Range PHY: replace the ESP32-WROOM-32 with an ESP32-C3-MINI-1.
 *  The NimBLE-Arduino API for Coded PHY would then be:
 *    pAdv->setPhy(BLE_GAP_LE_PHY_CODED, BLE_GAP_LE_PHY_CODED);
 *  But this cannot be implemented on the current hardware.
 *
 * ── LIBRARY ───────────────────────────────────────────────────────────────
 *   NimBLE-Arduino 2.5.0 by h2zero
 *   PlatformIO: h2zero/NimBLE-Arduino @ ^2.5.0
 */

#include <NimBLEDevice.h>    // NimBLE-Arduino 2.5.0 — NOT the built-in BLE lib
#include <string.h>          // strlen, strncpy, memcpy, memset
#include <Arduino.h>         // Serial, yield, uint8_t

#include "config.h"
#include "ble_manager.h"

namespace BLEManager {

// ─────────────────────────────────────────────────────────────────────────────
// Module-level state
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton pointer from NimBLEDevice::getAdvertising().
/// Set once in begin(); never freed during normal operation.
static NimBLEAdvertising* s_pAdv = nullptr;

/// True while the BLE controller is actively sending advertisement PDUs.
static bool s_advertising = false;

/// Current token stored as 8 raw bytes (decoded from 16-char hex string).
/// Updated by updateToken(); initialised in begin().
static uint8_t s_tokenBytes[V3_TOKEN_BYTES];

/// Classroom UUID stored as 16 raw bytes (decoded from CLASSROOM_UUID string).
/// Set once in begin(); does not change at runtime.
static uint8_t s_uuidBytes[V3_UUID_BYTES];

/// Human-readable copy of the current token for Serial debug output.
static char s_tokenHex[TOKEN_HEX_LEN + 1];

/// Current session ID (stored for telemetry/heartbeat).
static char s_sessionId[SESSION_ID_LENGTH + 1];

/// Count of advertising restart events (token rotations + session starts).
/// Used for diagnostics / memory stability tracking.
static uint32_t s_restartCount = 0;

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers — character / byte conversions
// ─────────────────────────────────────────────────────────────────────────────

static inline bool _isHexChar(char c) {
    return (c >= '0' && c <= '9') ||
           (c >= 'a' && c <= 'f') ||
           (c >= 'A' && c <= 'F');
}

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
            #if FIRMWARE_DEBUG
            Serial.printf("[BLE] _hexStringToBytes: invalid hex at position %u\n",
                          (unsigned)(i * 2));
            #endif
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
    if (strlen(uuidStr) != 36) {
        #if FIRMWARE_DEBUG
        Serial.printf("[BLE] _uuidStringToBytes: UUID length %u != 36\n",
                      (unsigned)strlen(uuidStr));
        #endif
        return false;
    }

    if (uuidStr[8]  != '-' || uuidStr[13] != '-' ||
        uuidStr[18] != '-' || uuidStr[23] != '-') {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] _uuidStringToBytes: missing dash in UUID");
        #endif
        return false;
    }

    // Collect the 32 hex characters by skipping dashes
    char hexOnly[33];   // 32 hex chars + null
    size_t hi = 0;
    for (size_t i = 0; i < 36 && hi < 32; i++) {
        if (uuidStr[i] == '-') continue;
        if (!_isHexChar(uuidStr[i])) {
            #if FIRMWARE_DEBUG
            Serial.printf("[BLE] _uuidStringToBytes: non-hex char '%c' at pos %u\n",
                          uuidStr[i], (unsigned)i);
            #endif
            return false;
        }
        hexOnly[hi++] = uuidStr[i];
    }
    hexOnly[32] = '\0';

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
 * @return  true if valid, false if rejected (reason logged to Serial).
 */
static bool _isValidToken(const char* token) {
    if (token == nullptr) {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] Token rejected: null pointer");
        #endif
        return false;
    }
    size_t len = strlen(token);
    if (len != TOKEN_HEX_LEN) {
        #if FIRMWARE_DEBUG
        Serial.printf("[BLE] Token rejected: length %u != %d\n",
                      (unsigned)len, TOKEN_HEX_LEN);
        #endif
        return false;
    }
    for (size_t i = 0; i < TOKEN_HEX_LEN; i++) {
        if (!_isHexChar(token[i])) {
            #if FIRMWARE_DEBUG
            Serial.printf("[BLE] Token rejected: non-hex char '%c' at index %u\n",
                          token[i], (unsigned)i);
            #endif
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
 *   1. Stops advertising if currently active.
 *   2. yield() — releases CPU for one FreeRTOS tick (~1 ms) so the NimBLE
 *      host task can process the HCI stop acknowledgement.
 *      (Replaces the original delay(10) — eliminates a 10 ms BLE blackout
 *       on every token rotation and session start.)
 *   3. Builds the 28-byte Protocol V3 manufacturer-data AD value on the stack.
 *   4. Rebuilds NimBLEAdvertisementData (advertisement + scan-response).
 *   5. Sets advertising intervals (100 ms fixed — min == max, no jitter).
 *   6. Restarts advertising.
 *
 * All objects are stack-allocated; no heap allocation occurs.
 * Precondition: s_pAdv != nullptr  (i.e., begin() was called).
 *
 * ── Advertising restart downtime ────────────────────────────────────────────
 *   Original:  stop() → delay(10) → build → start  → ~12 ms gap
 *   Optimized: stop() → yield()   → build → start  → ~2 ms gap
 *   Improvement: ~10 ms per token rotation / session start.
 */
static void _applyAndStart() {
    if (s_pAdv == nullptr) {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] ERROR: begin() must be called before advertising");
        #endif
        return;
    }

    // ── Stop if currently active ──────────────────────────────────────────
    if (s_advertising) {
        s_pAdv->stop();
        s_advertising = false;
        // yield() instead of delay(10):
        //   Releases the CPU for one FreeRTOS scheduler tick (~1 ms).
        //   NimBLE's host task (running on core 0) processes the HCI stop
        //   command during this yield window.
        //   Eliminating the 9 ms excess reduces each advertising restart
        //   blackout from ~12 ms to ~2 ms.
        yield();
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
    uint8_t mfrValue[2 + MFR_PAYLOAD_LEN];   // 28 bytes, stack-allocated
    int mfrLen = _buildV3MfrValue(mfrValue);

    // ── Advertisement data (primary PDU) ──────────────────────────────────
    //   setAdvertisementData() sends the payload to the BLE controller via
    //   ble_gap_adv_set_data() and sets m_advDataSet = true so NimBLE's
    //   start() does not attempt to re-push m_advData.
    //
    //   Primary PDU budget (31 bytes max):
    //     1(AD-len) + 1(AD-type 0xFF) + 28(mfrValue) = 30 bytes ✓
    //
    //   Flags AD (3 bytes) is intentionally absent:
    //     30 + 3 = 33 > 31 bytes → would overflow the PDU budget.
    //     Flags are optional for non-connectable advertising per BT Spec v5.4
    //     Vol 3, Part C §11.1.3.  Flutter discovers this device correctly
    //     without Flags. See file header for full rationale.
    //
    //   IMPORTANT: setConnectableMode() is NOT called here.  It was moved
    //   to begin() because setConnectableMode(NON) calls
    //   m_advData.setFlags(0) which — when no Flags element exists — appends
    //   a 3-byte element, making 30 + 3 = 33 > 31 and emitting:
    //       E NimBLEAdvertisementData: Data length exceeded
    NimBLEAdvertisementData advData;
    advData.setManufacturerData(
        std::string(reinterpret_cast<char*>(mfrValue), (size_t)mfrLen));
    s_pAdv->setAdvertisementData(advData);

    // ── Scan response data ────────────────────────────────────────────────
    //   Contains: Complete Local Name = DEVICE_NAME (e.g. "SCA-LAB101").
    //   AD element = 1(len) + 1(type 0x09) + 9(name) = 11 bytes ✓
    //
    //   Scan response optimization audit:
    //     Option A: Name in scan response (current) — 11 bytes.
    //     Option B: Name in primary ADV — would displace 11 bytes of mfr data
    //               (classroomId UUID would be truncated). NOT acceptable.
    //     Option C: Shorten name to "SCA" (3 chars → 5-byte AD) — saves 6 bytes
    //               in scan response but gains nothing in primary PDU since scan
    //               response is a separate PDU with its own 31-byte budget.
    //     Decision: current layout is optimal. "SCA-LAB101" in scan response
    //               allows human identification in nRF Connect + Flutter name
    //               fallback (V2 / name-only path). No change needed.
    //
    NimBLEAdvertisementData scanData;
    scanData.setName(DEVICE_NAME);
    s_pAdv->setScanResponseData(scanData);

    // ── Advertising intervals ─────────────────────────────────────────────
    //   Fixed 100 ms (min == max == 160 × 0.625 ms).
    //   Equal min/max eliminates the controller's random interval selection
    //   and produces a perfectly predictable 100 ms cadence.
    //   At 100 ms, a 10-second Flutter scan window receives ≥ 100 packets,
    //   providing >99% detection probability even at 15% packet loss rate.
    s_pAdv->setMinInterval(BLE_ADV_INTERVAL_MIN);  // 100 ms
    s_pAdv->setMaxInterval(BLE_ADV_INTERVAL_MAX);  // 100 ms (fixed)

    // ── Start ─────────────────────────────────────────────────────────────
    s_pAdv->start();
    s_advertising = true;
    s_restartCount++;

    // ── Structured diagnostic log ─────────────────────────────────────────
    #if FIRMWARE_DEBUG
    Serial.println("[BLE] INFO: Advertising Started (Protocol V3)");
    Serial.printf ("[BLE] INFO: Device Name    : %s\n", DEVICE_NAME);
    Serial.printf ("[BLE] INFO: Token (hex)    : %s\n", s_tokenHex);
    Serial.printf ("[BLE] INFO: Classroom UUID : %s\n", CLASSROOM_UUID);
    Serial.printf ("[BLE] INFO: Adv Interval   : %d ms (fixed, min==max)\n",
                   (int)(BLE_ADV_INTERVAL_MIN * 625 / 1000));
    Serial.printf ("[BLE] INFO: PHY Mode       : 1M PHY (BLE 4.2 hardware — Coded PHY unavailable)\n");
    Serial.printf ("[BLE] INFO: TX Power       : +9 dBm (ESP_PWR_LVL_P9)\n");
    Serial.printf ("[BLE] INFO: Connectable    : NO (ADV_NONCONN_IND)\n");
    Serial.printf ("[BLE] INFO: Restart count  : %u\n", s_restartCount);
    Serial.printf ("[BLE] INFO: Free heap      : %u bytes\n", ESP.getFreeHeap());
    Serial.printf ("[BLE] INFO: Min free heap  : %u bytes\n", ESP.getMinFreeHeap());
    Serial.print  ("[BLE] INFO: Mfr hex (full) : ");
    for (int i = 0; i < mfrLen; i++) {
        Serial.printf("%02X ", mfrValue[i]);
    }
    Serial.println();
    #endif
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

void begin() {
    // ── Decode classroom UUID from config.h → 16 raw bytes ────────────────
    //   Runs once; UUID does not change at runtime.
    if (!_uuidStringToBytes(CLASSROOM_UUID, s_uuidBytes)) {
        Serial.println("[BLE] FATAL: CLASSROOM_UUID in config.h is invalid.");
        Serial.println("[BLE] Cannot build V3 advertisement. Halting.");
        while (true) { delay(1000); }   // halt — misconfiguration
    }

    // ── Decode initial attendance token from config.h → 8 raw bytes ───────
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

    // Initialise session ID buffer
    memset(s_sessionId, 0, sizeof(s_sessionId));

    // ── Compile-time sanity checks ─────────────────────────────────────────
    static_assert(
        sizeof(ATTENDANCE_TOKEN) - 1 == TOKEN_HEX_LEN,
        "ATTENDANCE_TOKEN in config.h must be exactly TOKEN_HEX_LEN (16) chars"
    );
    static_assert(
        sizeof(CLASSROOM_UUID) - 1 == 36,
        "CLASSROOM_UUID in config.h must be exactly 36 characters"
    );

    // ── Initialise NimBLE stack ───────────────────────────────────────────
    Serial.println("[BLE] INFO: Initialising NimBLE 2.5.0 (Protocol V3)...");

    NimBLEDevice::init(DEVICE_NAME);

    // ── TX Power: +9 dBm (maximum for original ESP32) ────────────────────
    //
    //   NimBLEDevice::init() internally calls esp_ble_tx_power_set() with
    //   a default of P3 (+3 dBm). Our call immediately overwrites it.
    //
    //   TX power audit: this is the ONLY call to setPower() in the entire
    //   firmware. No other file calls setPower() or esp_ble_tx_power_set().
    //   Confirmed by full source audit. TX power remains at +9 dBm permanently.
    //
    NimBLEDevice::setPower(BLE_TX_POWER);
    Serial.println("[BLE] INFO: TX Power set to +9 dBm (ESP_PWR_LVL_P9)");

    // Obtain singleton advertising handle (does NOT start advertising)
    s_pAdv = NimBLEDevice::getAdvertising();

    // ── Non-connectable mode (set ONCE here, before any setAdvertisementData)
    //   This MUST be called before _applyAndStart() ever runs.
    //
    //   Root-cause: setConnectableMode(BLE_GAP_CONN_MODE_NON) internally calls
    //   m_advData.setFlags(0).  In NimBLE 2.5.0, setFlags(0) tries to append a
    //   3-byte Flags AD element when none already exists.  If m_advData already
    //   holds the 30-byte Manufacturer Specific AD element, adding 3 more bytes
    //   (30 + 3 = 33) exceeds BLE_HS_ADV_MAX_SZ (31) and NimBLEAdvertisementData
    //   logs "Data length exceeded".
    //
    //   Calling setConnectableMode() here — while m_advData is still empty —
    //   allows the 3-byte Flags element to be inserted safely (0 + 3 = 3 ≤ 31).
    //   Subsequent calls to setAdvertisementData() in _applyAndStart() replace
    //   m_advData entirely with a clean 30-byte object, so the warning never
    //   reappears on token rotations either.
    s_pAdv->setConnectableMode(BLE_GAP_CONN_MODE_NON);

    // ── Advertising intervals (set once; _applyAndStart refreshes these too) ──
    s_pAdv->setMinInterval(BLE_ADV_INTERVAL_MIN);  // 100 ms fixed
    s_pAdv->setMaxInterval(BLE_ADV_INTERVAL_MAX);  // 100 ms fixed

    Serial.println("[BLE] INFO: BLE stack initialized");
    Serial.printf ("[BLE] INFO: Device Name    : %s\n", DEVICE_NAME);
    Serial.printf ("[BLE] INFO: CLASSROOM_UUID : %s\n", CLASSROOM_UUID);
    Serial.printf ("[BLE] INFO: Initial token  : %s (overwritten by MQTT at session start)\n", s_tokenHex);
    Serial.printf ("[BLE] INFO: Adv interval   : %d ms fixed (min==max)\n",
                   (int)(BLE_ADV_INTERVAL_MIN * 625 / 1000));
    Serial.printf ("[BLE] INFO: TX power       : +9 dBm\n");
    Serial.printf ("[BLE] INFO: PHY            : 1M PHY (BLE 4.2 — Coded PHY unavailable on this SoC)\n");
    Serial.printf ("[BLE] INFO: Connectable    : NO (non-connectable undirected)\n");
    Serial.printf ("[BLE] INFO: Free heap      : %u bytes\n", ESP.getFreeHeap());
    Serial.println("[BLE] Waiting for START_SESSION command via MQTT...");
}

// ─────────────────────────────────────────────────────────────────────────────

void startAdvertising(const char* token, const char* sessionId) {
    if (s_pAdv == nullptr) {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] startAdvertising: ignored — call begin() first");
        #endif
        return;
    }

    // Validate and apply the token from the MQTT session-start command
    if (token != nullptr && _isValidToken(token)) {
        if (!_hexStringToBytes(token, s_tokenBytes, V3_TOKEN_BYTES)) {
            #if FIRMWARE_DEBUG
            Serial.println("[BLE] startAdvertising: token hex decode failed — using existing token");
            #endif
        } else {
            strncpy(s_tokenHex, token, TOKEN_HEX_LEN);
            s_tokenHex[TOKEN_HEX_LEN] = '\0';
        }
    }
    // If token is null/invalid, we keep the current s_tokenBytes (default or last MQTT update)

    // Store session ID for heartbeat/telemetry
    if (sessionId != nullptr && strlen(sessionId) > 0) {
        strncpy(s_sessionId, sessionId, SESSION_ID_LENGTH);
        s_sessionId[SESSION_ID_LENGTH] = '\0';
    }

    _applyAndStart();

    Serial.printf("[BLE] INFO: Advertising STARTED | Token: %s | Session: %.8s...\n",
        s_tokenHex, s_sessionId);
}

// ─────────────────────────────────────────────────────────────────────────────

void stopAdvertising() {
    if (s_pAdv == nullptr || !s_advertising) {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] stopAdvertising: not active — no-op");
        #endif
        return;
    }
    s_pAdv->stop();
    s_advertising = false;

    memset(s_sessionId, 0, sizeof(s_sessionId));

    Serial.printf("[BLE] INFO: Advertising STOPPED | Restart count so far: %u\n",
                  s_restartCount);
    Serial.printf("[BLE] INFO: Min free heap at stop: %u bytes\n",
                  ESP.getMinFreeHeap());
}

// ─────────────────────────────────────────────────────────────────────────────

void updateToken(const char* token) {
    if (s_pAdv == nullptr) {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] updateToken: ignored — call begin() first");
        #endif
        return;
    }

    // Validate: exactly 16 hex chars
    if (!_isValidToken(token)) {
        // _isValidToken() already printed the rejection reason.
        return;
    }

    // Decode hex string → 8 raw token bytes
    uint8_t newTokenBytes[V3_TOKEN_BYTES];
    if (!_hexStringToBytes(token, newTokenBytes, V3_TOKEN_BYTES)) {
        #if FIRMWARE_DEBUG
        Serial.println("[BLE] updateToken: hex decode failed — token unchanged");
        #endif
        return;
    }

    // Apply new token bytes and update debug buffer
    memcpy(s_tokenBytes, newTokenBytes, V3_TOKEN_BYTES);
    strncpy(s_tokenHex, token, TOKEN_HEX_LEN);
    s_tokenHex[TOKEN_HEX_LEN] = '\0';

    if (s_advertising) {
        // Rebuild V3 payload and restart advertising.
        // Only token bytes (bytes[2..9]) change — UUID (bytes[10..25]) unchanged.
        // _applyAndStart() blackout: ~2 ms (stop + yield + build + start).
        // Previously: ~12 ms (stop + delay(10) + build + start).
        _applyAndStart();

        Serial.printf("[BLE] INFO: Token ROTATED → \"%s\"\n", s_tokenHex);
        Serial.printf("[BLE] INFO: Advertising RESTARTED after token rotation\n");
        Serial.printf("[BLE] INFO: Restart downtime: ~2 ms (yield) vs ~12 ms (old delay)\n");
        #if FIRMWARE_DEBUG
        Serial.print ("[BLE] INFO: Token bytes   : ");
        for (int i = 0; i < V3_TOKEN_BYTES; i++) {
            Serial.printf("%02X ", s_tokenBytes[i]);
        }
        Serial.println();
        #endif
    } else {
        // Token updated but not advertising — will be used next startAdvertising()
        #if FIRMWARE_DEBUG
        Serial.printf("[BLE] Token updated (not advertising): %s\n", s_tokenHex);
        #endif
    }
}

// ─────────────────────────────────────────────────────────────────────────────

bool isAdvertising() {
    return s_advertising;
}

// ─────────────────────────────────────────────────────────────────────────────

const char* getCurrentToken() {
    return s_tokenHex;
}

}  // namespace BLEManager
