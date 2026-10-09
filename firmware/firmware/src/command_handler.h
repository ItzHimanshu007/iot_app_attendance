/*
 * command_handler.h — Parse and execute backend MQTT commands.
 */

#pragma once

#include <Arduino.h>

namespace CommandHandler {

    /**
     * Process an incoming MQTT message on a subscribed topic.
     * Routes to the appropriate handler based on topic.
     *
     * @param topic  MQTT topic string
     * @param payload  Raw message bytes
     * @param length  Payload length in bytes
     */
    void handleMessage(const char* topic, const uint8_t* payload, unsigned int length);

    /** True if a session is currently active. */
    bool isSessionActive();

    /** Get the current session ID (empty if no session). */
    const char* getSessionId();

}  // namespace CommandHandler
