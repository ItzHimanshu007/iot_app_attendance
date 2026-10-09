/*
 * mqtt_manager.cpp — MQTT connection, subscriptions, and message dispatch.
 *
 * Transport: TLS / SSL over WiFiClientSecure (port 8883, HiveMQ Cloud).
 *   _wifiClient.setInsecure() skips CA cert validation for dev/testing.
 *   Replace with _wifiClient.setCACert(hivemq_root_ca) for production.
 *
 * Subscribes to:
 *   campus/classroom/{classroom_uuid}/control/start   (QoS 1)
 *   campus/classroom/{classroom_uuid}/control/stop    (QoS 1)
 *   campus/classroom/{classroom_uuid}/token           (QoS 1)
 *
 * Features:
 *   - Exponential backoff reconnect (1s → 30s)
 *   - Auto-resubscribe after reconnect
 *   - Message dispatch to CommandHandler
 *   - LWT (Last Will and Testament) for offline detection
 *
 * WATCHDOG NOTES
 *   _mqtt.connect() is blocking: it calls WiFiClientSecure::connect() for the
 *   TLS handshake (up to MQTT_SOCKET_TIMEOUT seconds), then busy-waits for
 *   CONNACK (another up to MQTT_SOCKET_TIMEOUT seconds).  Neither path feeds
 *   the hardware watchdog.  With WATCHDOG_TIMEOUT_S = 30 and the default
 *   MQTT_SOCKET_TIMEOUT = 15, two sequential slow/failed calls can starve the
 *   WDT and trigger a panic reset.
 *
 *   Fix: call esp_task_wdt_reset() immediately before every blocking operation
 *   so the watchdog timer is refreshed just before we might block.
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <esp_task_wdt.h>   // esp_task_wdt_reset()

#include "config.h"
#include "mqtt_manager.h"
#include "command_handler.h"

namespace MQTTManager {

// ── State ────────────────────────────────────────────────────────────────────

static WiFiClientSecure _wifiClient;
static PubSubClient _mqtt(_wifiClient);
static unsigned long _reconnectDelay = MQTT_RECONNECT_MIN_MS;
static unsigned long _lastReconnectAttempt = 0;
static uint32_t _reconnectCount = 0;

// ── MQTT callback ────────────────────────────────────────────────────────────

static void _onMessage(char* topic, byte* payload, unsigned int length) {
    CommandHandler::handleMessage(topic, payload, length);
}

// ── Subscribe to all command topics ──────────────────────────────────────────

static void _subscribeAll() {
    _mqtt.subscribe(TOPIC_CONTROL_START, 1);
    _mqtt.subscribe(TOPIC_CONTROL_STOP, 1);
    _mqtt.subscribe(TOPIC_TOKEN, 1);

    #if FIRMWARE_DEBUG
    Serial.println("[MQTT] Subscribed to:");
    Serial.printf("  %s\n", TOPIC_CONTROL_START);
    Serial.printf("  %s\n", TOPIC_CONTROL_STOP);
    Serial.printf("  %s\n", TOPIC_TOKEN);
    #endif
}

// ── Connect with LWT ─────────────────────────────────────────────────────────

static bool _connect() {
    #if FIRMWARE_DEBUG
    Serial.printf("[MQTT] Connecting to %s:%d as %s...\n",
        MQTT_BROKER, MQTT_PORT, MQTT_CLIENT_ID);
    #endif

    // Last Will and Testament — backend detects this as device going offline
    // Published to status topic automatically by broker if connection drops
    char lwtPayload[128];
    snprintf(lwtPayload, sizeof(lwtPayload),
        "{\"device_id\":\"%s\",\"classroom_id\":\"%s\",\"event\":\"offline\",\"detail\":\"LWT triggered\"}",
        DEVICE_ID, CLASSROOM_UUID);

    // ── Feed WDT before the blocking TLS + MQTT handshake ─────────────────
    //
    //   _mqtt.connect() is a two-phase blocking call:
    //     Phase 1 — WiFiClientSecure::connect(host, 8883):
    //               TCP connect + TLS handshake.  Blocks up to ~15 s on a
    //               slow/unreachable broker with no yield() calls.
    //     Phase 2 — PubSubClient waits for CONNACK (inner busy-wait in
    //               PubSubClient.cpp line ~257):  blocks up to socketTimeout
    //               (15 s default) without yielding.
    //
    //   Total worst-case blocking: up to 30 s — exactly WATCHDOG_TIMEOUT_S.
    //   With any added latency the WDT fires before connect() returns.
    //
    //   Resetting the WDT here gives the full timeout budget to the connect
    //   sequence so it can complete before the next watchdog deadline.
    esp_task_wdt_reset();

    bool connected;
    if (strlen(MQTT_USERNAME) > 0) {
        connected = _mqtt.connect(
            MQTT_CLIENT_ID,
            MQTT_USERNAME, MQTT_PASSWORD,
            TOPIC_STATUS,   // LWT topic
            0,              // LWT QoS
            true,           // LWT retain
            lwtPayload      // LWT message
        );
    } else {
        connected = _mqtt.connect(
            MQTT_CLIENT_ID,
            nullptr, nullptr,
            TOPIC_STATUS,
            0,
            true,
            lwtPayload
        );
    }

    // Feed WDT again — connect() may have spent close to the timeout
    esp_task_wdt_reset();

    if (connected) {
        _reconnectDelay = MQTT_RECONNECT_MIN_MS;  // Reset backoff
        _reconnectCount = 0;
        _subscribeAll();

        #if FIRMWARE_DEBUG
        Serial.println("[MQTT] Connected and subscribed");
        #endif
        return true;
    }

    #if FIRMWARE_DEBUG
    Serial.printf("[MQTT] Connection failed, rc=%d\n", _mqtt.state());
    #endif
    return false;
}

// ── Public API ───────────────────────────────────────────────────────────────

void begin() {
    // TLS: skip CA cert validation (dev/testing only).
    // For production, replace with: _wifiClient.setCACert(hivemq_root_ca);
    _wifiClient.setInsecure();

    // Cap the TCP/TLS socket timeout to 10 s.
    // Default MQTT_SOCKET_TIMEOUT is 15 s; combined with the TLS handshake
    // time, two blocked phases can hit WATCHDOG_TIMEOUT_S (30 s).
    // 10 s gives a comfortable margin: 10 s (TLS) + 10 s (CONNACK) = 20 s
    // worst-case, well under the 30 s watchdog with room for the WDT reset.
    _wifiClient.setTimeout(10000);      // WiFiClientSecure TCP timeout (ms)
    _mqtt.setSocketTimeout(10);         // PubSubClient CONNACK wait (s)

    _mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    _mqtt.setCallback(_onMessage);
    _mqtt.setBufferSize(MQTT_BUFFER_SIZE);
    _mqtt.setKeepAlive(MQTT_KEEPALIVE);
    _connect();
}

void maintain() {
    if (_mqtt.connected()) {
        _mqtt.loop();
        return;
    }

    // Not connected — exponential backoff reconnect
    unsigned long now = millis();
    if (now - _lastReconnectAttempt < _reconnectDelay) {
        return;
    }

    _lastReconnectAttempt = now;
    _reconnectCount++;

    #if FIRMWARE_DEBUG
    Serial.printf("[MQTT] Reconnecting (attempt %u, backoff %lums)...\n",
        _reconnectCount, _reconnectDelay);
    #endif

    if (_connect()) {
        // Reconnected — send immediate heartbeat
        return;
    }

    // Exponential backoff: 1s → 2s → 4s → 8s → 16s → 30s
    _reconnectDelay = min(_reconnectDelay * 2, (unsigned long)MQTT_RECONNECT_MAX_MS);

    // After many failures, restart ESP32
    if (_reconnectCount > 50) {
        #if FIRMWARE_DEBUG
        Serial.println("[MQTT] Too many reconnect failures — restarting ESP32");
        #endif
        ESP.restart();
    }
}

bool publishMessage(const char* topic, const char* payload, bool retain) {
    if (!_mqtt.connected()) {
        #if FIRMWARE_DEBUG
        Serial.printf("[MQTT] Cannot publish — not connected (topic: %s)\n", topic);
        #endif
        return false;
    }
    return _mqtt.publish(topic, payload, retain);
}

bool isConnected() {
    return _mqtt.connected();
}

void disconnect() {
    if (_mqtt.connected()) {
        _mqtt.disconnect();
        #if FIRMWARE_DEBUG
        Serial.println("[MQTT] Disconnected");
        #endif
    }
}

}  // namespace MQTTManager
