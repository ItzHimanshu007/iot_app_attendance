/*
 * heartbeat_manager.cpp — Publishes heartbeat every 30 seconds.
 *
 * Heartbeat payload (published to TOPIC_HEARTBEAT):
 *   {
 *     "device_id":        "esp32-room-101",
 *     "room_id":          "43905a99-a513-5a9d-8cb5-e109b98166bb",  ← UUID (was "room-101")
 *     "classroom_id":     "43905a99-a513-5a9d-8cb5-e109b98166bb",  ← UUID
 *     "firmware_version": "3.0.0",
 *     "uptime_ms":        123456,
 *     "wifi_rssi":        -45,
 *     "free_heap":        120000,
 *     "ble_status":       "advertising",
 *     "mqtt_status":      "connected",
 *     "session_active":   true
 *   }
 *
 * MIGRATION NOTE (V2 → V3):
 *   "room_id" and "classroom_id" now carry CLASSROOM_UUID (the full UUID
 *   string) instead of the old "room-101" short identifier.
 *   The backend subscriber uses "room_id" for the esp32_devices lookup:
 *     Esp32Repository.update_heartbeat(mqtt_client_id=payload["room_id"])
 *   Ensure the esp32_devices row has mqtt_client_id = CLASSROOM_UUID.
 */

#include <ArduinoJson.h>
#include <WiFi.h>

#include "config.h"
#include "heartbeat_manager.h"
#include "ble_manager.h"
#include "command_handler.h"

// Forward declaration
namespace MQTTManager {
    bool publishMessage(const char* topic, const char* payload, bool retain);
    bool isConnected();
}

namespace HeartbeatManager {

// ── State ────────────────────────────────────────────────────────────────────

static unsigned long _lastHeartbeat = 0;

// ── Heartbeat construction ───────────────────────────────────────────────────

static void _publish() {
    JsonDocument doc;

    doc["device_id"]        = DEVICE_ID;
    doc["room_id"]          = CLASSROOM_UUID;   // V3: UUID string (was CLASSROOM_ID)
    doc["classroom_id"]     = CLASSROOM_UUID;   // V3: UUID string (was CLASSROOM_ID)
    doc["firmware_version"] = FIRMWARE_VERSION;
    doc["uptime_ms"]        = millis();
    doc["wifi_rssi"]        = WiFi.RSSI();
    doc["free_heap"]        = ESP.getFreeHeap();

    // BLE status string
    doc["ble_status"]       = BLEManager::isAdvertising() ? "advertising" : "idle";

    // MQTT status
    doc["mqtt_status"]      = MQTTManager::isConnected() ? "connected" : "disconnected";

    // Session state
    doc["session_active"]   = CommandHandler::isSessionActive();

    char buffer[320];
    serializeJson(doc, buffer, sizeof(buffer));

    MQTTManager::publishMessage(TOPIC_HEARTBEAT, buffer, false);

    #if FIRMWARE_DEBUG
    Serial.printf("[HEARTBEAT] RSSI: %d  Heap: %u  BLE: %s  Session: %s\n",
        WiFi.RSSI(), ESP.getFreeHeap(),
        BLEManager::isAdvertising() ? "ON" : "OFF",
        CommandHandler::isSessionActive() ? "active" : "inactive");
    #endif
}

// ── Public API ───────────────────────────────────────────────────────────────

void tick() {
    unsigned long now = millis();
    if (now - _lastHeartbeat >= HEARTBEAT_INTERVAL_MS) {
        _publish();
        _lastHeartbeat = now;
    }
}

void sendNow() {
    _publish();
    _lastHeartbeat = millis();
}

}  // namespace HeartbeatManager
