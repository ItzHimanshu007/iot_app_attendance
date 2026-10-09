/*
 * wifi_manager.h — WiFi connection management with auto-reconnect.
 */

#pragma once

#include <Arduino.h>

namespace WiFiManager {

    /** Initialize and connect to WiFi. Restarts ESP32 on failure. */
    void begin();

    /** Check connection and reconnect if needed. Call from loop(). */
    void maintain();

    /** True if WiFi is currently connected. */
    bool isConnected();

    /** Current WiFi RSSI in dBm. Returns 0 if disconnected. */
    int getRSSI();

}  // namespace WiFiManager
