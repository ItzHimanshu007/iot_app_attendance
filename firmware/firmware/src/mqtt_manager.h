/*
 * mqtt_manager.h — MQTT connection, subscription, and message dispatch.
 */

#pragma once

#include <Arduino.h>

namespace MQTTManager {

    /** Initialize MQTT client and connect to broker. */
    void begin();

    /** Maintain connection and process incoming messages. Call from loop(). */
    void maintain();

    /** Publish a message to a topic. Returns true on success. */
    bool publishMessage(const char* topic, const char* payload, bool retain = false);

    /** True if MQTT is currently connected. */
    bool isConnected();

    /** Disconnect cleanly (for shutdown). */
    void disconnect();

}  // namespace MQTTManager
