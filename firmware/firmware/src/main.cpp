/*
 * main.cpp — Smart Campus Attendance ESP32 BLE Broadcaster  (v3.0.0)
 *
 * Architecture: Backend → MQTT → ESP32 (this device) → BLE → Flutter App
 *
 * This device is a "dumb broadcaster" with ZERO attendance logic.
 * It does exactly what the backend tells it via MQTT:
 *   1. Connects to WiFi and MQTT broker
 *   2. Subscribes to session control and token topics
 *   3. Starts/stops BLE advertising on command  ← Protocol V3 payload
 *   4. Rotates beacon tokens on command          ← V3 token bytes updated
 *   5. Sends heartbeat every 30 seconds
 *   6. Reports status and telemetry
 *   7. Recovers from WiFi/MQTT disconnections
 *   8. Uses hardware watchdog for hard fault recovery
 *
 * All intelligence lives in the FastAPI backend.
 *
 * Protocol V3 BLE Advertisement (emitted after START_SESSION command):
 *   Manufacturer Data payload (26 bytes after 2-byte Company ID):
 *     byte[0]      = 0x03  (BLE_PROTO_VERSION)
 *     byte[1]      = 0x01  (BLE_PAYLOAD_TYPE)
 *     byte[2..9]   = 8 raw token bytes   (16-char hex decoded to binary)
 *     byte[10..25] = 16 raw UUID bytes   (CLASSROOM_UUID decoded to binary)
 *
 * Firmware version: 3.0.0  (Protocol V3 + full MQTT)
 */

#include <Arduino.h>
#include <esp_task_wdt.h>

#include "config.h"
#include "wifi_manager.h"
#include "mqtt_manager.h"
#include "ble_manager.h"
#include "heartbeat_manager.h"
#include "status_reporter.h"
#include "command_handler.h"

// ── Telemetry timer ──────────────────────────────────────────────────────────

static unsigned long _lastTelemetry = 0;

// ── Setup ────────────────────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println();
    Serial.println("╔══════════════════════════════════════════════════╗");
    Serial.println("║  Smart Campus ESP32 BLE Broadcaster  v3.1.1     ║");
    Serial.println("║  Protocol V3 · MQTT · BLE Optimized             ║");
    Serial.println("╚══════════════════════════════════════════════════╝");
    Serial.printf ("Device ID      : %s\n", DEVICE_ID);
    Serial.printf ("Classroom UUID : %s\n", CLASSROOM_UUID);
    Serial.printf ("MQTT Broker    : %s:%d\n", MQTT_BROKER, MQTT_PORT);
    Serial.printf ("BLE Name       : %s\n", DEVICE_NAME);
    Serial.printf ("Free Heap      : %u bytes\n", ESP.getFreeHeap());
    Serial.println("──────────────────────────────────────────────────");

    // 1. Initialize hardware watchdog
    esp_task_wdt_init(WATCHDOG_TIMEOUT_S, true);  // true = panic on timeout
    esp_task_wdt_add(NULL);                        // Add current task to WDT

    // 2. Connect to WiFi (blocking — restarts on failure after WIFI_MAX_RETRIES)
    WiFiManager::begin();

    // 3. Initialize BLE stack with Protocol V3 (does NOT start advertising yet)
    //    Advertising begins only when a START_SESSION command arrives via MQTT.
    BLEManager::begin();

    // 4. Connect to MQTT and subscribe to command topics:
    //      campus/classroom/{CLASSROOM_UUID}/control/start
    //      campus/classroom/{CLASSROOM_UUID}/control/stop
    //      campus/classroom/{CLASSROOM_UUID}/token
    MQTTManager::begin();

    // 5. Send initial heartbeat and status
    HeartbeatManager::sendNow();
    StatusReporter::publishStatus("boot", FIRMWARE_VERSION);

    Serial.println("──────────────────────────────────────────────────");
    Serial.println("[MAIN] Setup complete. Waiting for MQTT commands...");
    Serial.printf ("[MAIN] INFO: Heartbeat interval : %d ms\n", HEARTBEAT_INTERVAL_MS);
    Serial.printf ("[MAIN] INFO: Watchdog timeout   : %d s\n",  WATCHDOG_TIMEOUT_S);
    Serial.printf ("[MAIN] INFO: Subscribe topic    : %s\n",    TOPIC_CONTROL_START);
    Serial.printf ("[MAIN] INFO: Adv interval       : %d ms fixed\n",
                   (int)(BLE_ADV_INTERVAL_MIN * 625 / 1000));
    Serial.printf ("[MAIN] INFO: TX power           : +9 dBm\n");
    Serial.printf ("[MAIN] INFO: PHY mode           : 1M PHY (BLE 4.2 hardware)\n");
    Serial.printf ("[MAIN] INFO: Wi-Fi coexistence  : SW coexist enabled (framework default)\n");
    Serial.printf ("[MAIN] INFO: Modem sleep        : Enabled (WIFI_PS_MIN_MODEM for coexistence)\n");
    Serial.printf ("[MAIN] INFO: Free heap          : %u bytes\n", ESP.getFreeHeap());
    Serial.printf ("[MAIN] INFO: Largest free block : %u bytes\n", ESP.getMaxAllocHeap());
    Serial.printf ("[MAIN] INFO: Min free heap      : %u bytes\n", ESP.getMinFreeHeap());
    Serial.println("──────────────────────────────────────────────────");
}

// ── Loop ─────────────────────────────────────────────────────────────────────

void loop() {
    // Feed the watchdog — if loop() hangs, ESP32 will restart
    esp_task_wdt_reset();

    // 1. Maintain WiFi (non-blocking reconnect with exponential backoff)
    WiFiManager::maintain();

    // 2. Maintain MQTT (non-blocking reconnect, processes incoming messages)
    //    Incoming messages → CommandHandler::handleMessage() →
    //      START_SESSION  → BLEManager::startAdvertising(token, sessionId)
    //      STOP_SESSION   → BLEManager::stopAdvertising()
    //      ROTATE_TOKEN   → BLEManager::updateToken(newToken)
    MQTTManager::maintain();

    // 3. Heartbeat every HEARTBEAT_INTERVAL_MS (30 s)
    HeartbeatManager::tick();

    // 4. Telemetry every TELEMETRY_INTERVAL_MS (2 min)
    unsigned long now = millis();
    if (now - _lastTelemetry >= TELEMETRY_INTERVAL_MS) {
        StatusReporter::publishTelemetry();
        _lastTelemetry = now;
    }

    // BLE advertising is entirely managed by MQTT commands — no polling needed.
    // The NimBLE stack runs in its own FreeRTOS task on the second core.
}
