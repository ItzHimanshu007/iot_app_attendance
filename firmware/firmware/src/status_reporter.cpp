/*
 * status_reporter.cpp — Publishes status and telemetry to MQTT.
 *
 * Status topic   : campus/classroom/{uuid}/status
 * Telemetry topic: campus/classroom/{uuid}/telemetry
 *
 * Uses a forward-declared MQTT publish function to avoid circular
 * dependency with mqtt_manager.
 *
 * MIGRATION NOTE (V2 → V3):
 *   "classroom_id" in all payloads now carries CLASSROOM_UUID (full UUID
 *   string) instead of the old "room-101" short identifier.
 *   Buffer sizes increased to accommodate the 36-char UUID.
 */

#include <ArduinoJson.h>
#include <WiFi.h>

#include "config.h"
#include "status_reporter.h"
#include "ble_manager.h"
#include "command_handler.h"

// Forward declaration — implemented in mqtt_manager.cpp
namespace MQTTManager {
    bool publishMessage(const char* topic, const char* payload, bool retain);
}

namespace StatusReporter {

void publishStatus(const char* event, const char* detail) {
    JsonDocument doc;
    doc["device_id"]        = DEVICE_ID;
    doc["classroom_id"]     = CLASSROOM_UUID;   // V3: UUID string
    doc["event"]            = event;
    doc["detail"]           = detail;
    doc["firmware_version"] = FIRMWARE_VERSION;
    doc["uptime_ms"]        = millis();

    char buffer[320];
    serializeJson(doc, buffer, sizeof(buffer));

    MQTTManager::publishMessage(TOPIC_STATUS, buffer, false);

    #if FIRMWARE_DEBUG
    Serial.printf("[STATUS] %s: %s\n", event, detail);
    #endif
}

void publishTelemetry() {
    JsonDocument doc;
    doc["device_id"]              = DEVICE_ID;
    doc["classroom_id"]           = CLASSROOM_UUID;   // V3: UUID string
    doc["firmware_version"]       = FIRMWARE_VERSION;
    doc["uptime_ms"]              = millis();
    doc["free_heap"]              = ESP.getFreeHeap();
    doc["min_free_heap"]          = ESP.getMinFreeHeap();
    doc["wifi_rssi"]              = WiFi.RSSI();
    doc["ble_advertising"]        = BLEManager::isAdvertising();
    doc["session_active"]         = CommandHandler::isSessionActive();

    const char* sid = CommandHandler::getSessionId();
    if (strlen(sid) > 0) {
        doc["session_id"] = sid;
    }

    const char* tok = BLEManager::getCurrentToken();
    if (strlen(tok) > 0) {
        // Publish only first 4 chars for security
        char tokenPrefix[8];
        strncpy(tokenPrefix, tok, 4);
        strncpy(tokenPrefix + 4, "...", 4);
        doc["current_token_prefix"] = tokenPrefix;
    }

    char buffer[448];
    serializeJson(doc, buffer, sizeof(buffer));

    MQTTManager::publishMessage(TOPIC_TELEMETRY, buffer, false);

    #if FIRMWARE_DEBUG
    Serial.printf("[TELEMETRY] Heap: %u  RSSI: %d  BLE: %s\n",
        ESP.getFreeHeap(), WiFi.RSSI(),
        BLEManager::isAdvertising() ? "ON" : "OFF");
    #endif
}

}  // namespace StatusReporter
