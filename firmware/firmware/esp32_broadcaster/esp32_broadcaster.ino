/*
 * esp32_broadcaster.ino — Smart Campus Attendance BLE Beacon  (Phase 1 · V3)
 * ============================================================================
 *
 * WHAT THIS FIRMWARE DOES
 *   The ESP32 is permanently installed in a classroom and acts as a
 *   passive BLE attendance beacon.  It broadcasts a Protocol V3 advertisement
 *   that the student Flutter app parses:
 *
 *     Primary ADV PDU → Manufacturer Data (Protocol V3, 26-byte payload):
 *       byte[0]      = 0x03  (BLE_PROTO_VERSION)
 *       byte[1]      = 0x01  (BLE_PAYLOAD_TYPE)
 *       byte[2..9]   = 8 raw token bytes   ("e1ede9723aacd6c4" decoded)
 *       byte[10..25] = 16 raw UUID bytes   ("e664f3af-8aec-5d5f-bf5d-b8754d6d93b2" decoded)
 *
 *     Scan Response PDU → Device Name: "SCA-LAB101"
 *       → Flutter isSCADevice("SCA-LAB101") → true  ✓
 *
 * FLUTTER PARSING FLOW (_parseBinaryPathV3)
 *   1. FlutterBluePlus scans, finds "SCA-LAB101"                      ✓
 *   2. isSCADevice("SCA-LAB101") → true                               ✓
 *   3. manufacturerData[0] == 0x03 → _parseBinaryPathV3()             ✓
 *   4. bytes.length (26) >= v3MinLength (26)                          ✓
 *   5. bytes[1] == 0x01 → attendance payload                          ✓
 *   6. bytes[2..9] → hex-encode each byte:
 *        E1→"e1" ED→"ed" ... C4→"c4" → "e1ede9723aacd6c4"            ✓
 *   7. bytes[10..25] → _formatUuid():
 *        → "e664f3af-8aec-5d5f-bf5d-b8754d6d93b2"                    ✓
 *   8. GET /sessions/active?classroom_id=e664f3af-8aec-5d5f-...
 *        Backend: WHERE classroom_id = 'e664f3af-...' (UUID)          ✓
 *   9. Session found → attendance can be submitted                    ✓
 *
 * SYSTEM FLOW
 *   [Teacher App] → [FastAPI Backend] → session created with UUID classroom_id
 *      (Phase 2) → [MQTT Broker] → ESP32 receives new token
 *                                  → updateBleToken(newToken)
 *   [ESP32 beacon] → BLE Protocol V3 advertisement
 *      ↓  (passive scan)
 *   [Student Flutter app] → POST /attendance → Backend verifies → mark present
 *
 * PHASE 2 UPGRADE (MQTT token rotation — zero BLE changes needed)
 *   1. Restore mqtt_handler.cpp and mqtt_handler.h.
 *   2. Uncomment the Phase 2 lines in setup() and loop() below.
 *   3. Flash.  updateBleToken(newToken) in the MQTT callback does the rest.
 *      Constraint: newToken must be exactly 16 hex chars.
 *
 * EXPECTED SERIAL OUTPUT (DEBUG=1)
 *   ─────────────────────────────────────────────────
 *   Smart Campus Attendance Beacon  [Phase 1 · V3]
 *   Device ID    : ESP_LAB101
 *   Device Name  : SCA-LAB101
 *   Classroom    : e664f3af-8aec-5d5f-bf5d-b8754d6d93b2
 *   Token        : e1ede9723aacd6c4
 *   Protocol     : V3 (binary UUID + token)
 *   ─────────────────────────────────────────────────
 *
 *   [BLE] Initialising NimBLE (Protocol V3)...
 *   [BLE] Advertising Started (Protocol V3)
 *   [BLE] Device Name    : SCA-LAB101
 *   [BLE] Token (hex)    : e1ede9723aacd6c4 
 *   [BLE] Token (bytes)  : E1 ED E9 72 3A AC D6 C4
 *   [BLE] Classroom UUID : e664f3af-8aec-5d5f-bf5d-b8754d6d93b2
 *   [BLE] UUID (bytes)   : E6 64 F3 AF 8A EC 5D 5F BF 5D B8 75 4D 6D 93 B2
 *   [BLE] Mfr Hex (full) : FF FF 03 01 E1 ED E9 72 3A AC D6 C4
 *                          E6 64 F3 AF 8A EC 5D 5F BF 5D B8 75 4D 6D 93 B2
 *
 * EXPECTED nRF CONNECT VIEW
 *   Device Name:       SCA-LAB101
 *   Manufacturer Data: 03 01
 *                      E1 ED E9 72 3A AC D6 C4
 *                      E6 64 F3 AF 8A EC 5D 5F
 *                      BF 5D B8 75 4D 6D 93 B2
 *   (nRF Connect strips the 2-byte Company ID 0xFF 0xFF from the display)
 *
 * HARDWARE
 *   Board   : ESP32 Dev Module (ESP32-WROOM / ESP32-ISM2)
 *   Library : NimBLE-Arduino 2.5.0 by h2zero
 *             Arduino IDE → Library Manager → "NimBLE-Arduino"
 *             Do NOT install "ESP32 BLE Arduino" alongside it.
 */

#include <Arduino.h>        // Explicit — required for modular Arduino builds

#include "config.h"         // DEVICE_ID, DEVICE_NAME, CLASSROOM_UUID, ATTENDANCE_TOKEN
#include "ble_advertiser.h" // setupBle(), updateBleToken(), start/stopBleAdvertising()

// Phase 2 — uncomment when mqtt_handler.cpp is restored:
// #include "mqtt_handler.h"

// ─────────────────────────────────────────────────────────────────────────────
// setup()
// ─────────────────────────────────────────────────────────────────────────────

void setup() {
    // ── Serial ────────────────────────────────────────────────────────────
    Serial.begin(115200);

    // 500 ms: gives the USB-serial bridge time to enumerate before the first
    // Serial.print so the banner is not lost on slow hosts.
    delay(500);

    // ── Startup banner ────────────────────────────────────────────────────
    //   Printed unconditionally (regardless of DEBUG) so the operator always
    //   gets essential identity information after flashing a device.
    Serial.println();
    Serial.println("─────────────────────────────────────────────────");
    Serial.println("Smart Campus Attendance Beacon  [Phase 1 · V3]");
    Serial.println("─────────────────────────────────────────────────");
    Serial.printf ("Device ID    : %s\n", DEVICE_ID);
    Serial.printf ("Device Name  : %s\n", DEVICE_NAME);
    Serial.printf ("Classroom    : %s\n", CLASSROOM_UUID);
    Serial.printf ("Token        : %s\n", ATTENDANCE_TOKEN);
    Serial.println("Protocol     : V3 (binary UUID + token)");
    Serial.println("─────────────────────────────────────────────────");
    Serial.println();

    // ── BLE initialisation ────────────────────────────────────────────────
    //   setupBle() (see ble_advertiser.cpp):
    //     1. Decode CLASSROOM_UUID → 16 raw bytes (fatal halt if invalid)
    //     2. Decode ATTENDANCE_TOKEN → 8 raw bytes (fatal halt if invalid)
    //     3. NimBLEDevice::init("SCA-LAB101")
    //     4. TX power → +9 dBm (ESP_PWR_LVL_P9)
    //     5. Build Protocol V3 manufacturer data:
    //          byte[0]      = 0x03  (BLE_PROTO_VERSION)
    //          byte[1]      = 0x01  (BLE_PAYLOAD_TYPE)
    //          byte[2..9]   = 8 raw token bytes
    //          byte[10..25] = 16 raw UUID bytes
    //     6. Set scan-response name → "SCA-LAB101"
    //     7. setConnectableMode(BLE_GAP_CONN_MODE_NON)  [NimBLE 2.5.0 API]
    //     8. Start advertising at 100–200 ms intervals
    setupBle();

    // ── Phase 2 stubs (WiFi + MQTT) ───────────────────────────────────────
    //   Restore mqtt_handler.cpp, then uncomment:
    //
    //   connectWifi();   // wifi_handler.cpp — connect before MQTT
    //   setupMqtt();     // mqtt_handler.cpp — registers MQTT callback
    //                    //   callback calls: updateBleToken(newToken)
    //                    //   newToken must be exactly 16 hex chars
}

// ─────────────────────────────────────────────────────────────────────────────
// loop()
// ─────────────────────────────────────────────────────────────────────────────

void loop() {
    /*
     * NimBLE runs in its own FreeRTOS task on the ESP32 dual-core processor.
     * BLE advertising requires no polling from loop() — it continues
     * independently at 100–200 ms intervals set in _applyAndStart().
     *
     * Phase 2 additions (drop-in — no BLE changes required):
     *
     *   loopMqtt();   // non-blocking MQTT keepalive + reconnect
     *
     *   // Optional heartbeat:
     *   if (millis() - lastHeartbeat >= 30000UL) {
     *       sendHeartbeat();
     *       lastHeartbeat = millis();
     *   }
     */

    // Yield to FreeRTOS / watchdog.  Without a delay or portYIELD_FROM_ISR,
    // the idle task can starve on single-core builds and trip the task WDT.
    delay(1000);
}
