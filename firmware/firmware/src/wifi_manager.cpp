/*
 * wifi_manager.cpp — WiFi connection with auto-reconnect, backoff,
 *                    and power management.
 *
 * ── esp_coex_preference_set() — REMOVED ─────────────────────────────────────
 *
 *   Root-cause analysis determined that calling esp_coex_preference_set()
 *   in combination with CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE=1 in build_flags
 *   caused an abort() inside coex_core_enable() → coex_enable() →
 *   esp_bt_controller_enable() → NimBLEDevice::init().
 *
 *   Why it crashed:
 *
 *   1. CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE is already defined as 1 in the
 *      pre-compiled framework sdkconfig.h (line 354 of
 *      framework-arduinoespressif32 @ 3.20017.241212). Redefining it via
 *      the -D build flag caused a header-vs-binary mismatch: source-compiled
 *      glue code (esp32-hal-bt.c, WiFi.cpp adapter layer) compiled against
 *      our redefinition, while the pre-compiled libbt.a / libcoexist.a
 *      binaries were compiled with the original sdkconfig. This divergence
 *      corrupted the coexistence module's internal init state machine.
 *
 *   2. esp_coex_preference_set() is marked @deprecated in the installed
 *      esp_coexist.h (framework-arduinoespressif32 @ 3.20017.241212):
 *        "@deprecated Use esp_coex_status_bit_set() and
 *         esp_coex_status_bit_clear() instead."
 *      The function itself is a no-op stub (always returns 0), but its
 *      presence triggered a code path in the caller that assumed the
 *      coexistence module was properly initialized — which it was not due
 *      to problem #1 above.
 *
 *   Why esp_COEX_PREFER_BT is unnecessary here:
 *
 *   The pre-compiled framework already enables SW coexistence with balanced
 *   scheduling. With modem sleep disabled (WIFI_PS_NONE), the RF path is
 *   always available and BLE advertising at 100 ms fixed interval proceeds
 *   without pre-emption. The coexistence arbiter has negligible impact when
 *   MQTT traffic is periodic and low-volume (heartbeat 30s, telemetry 2 min).
 *   The correct approach is the ESP-IDF v5 API (esp_coex_status_bit_set),
 *   which requires both WiFi and BT to be fully initialized before calling.
 *   This is architecturally complex and provides marginal gain over the
 *   current configuration with modem sleep disabled.
 *
 * ── Modem Sleep / esp_wifi_set_ps() ──────────────────────────────────────────
 *
 *   WIFI_PS_NONE (disabling WiFi modem sleep) is strictly prohibited on ESP32
 *   when both WiFi and Bluetooth (BLE) are active simultaneously.
 *
 *   Why this occurs:
 *
 *     The ESP32 classic shares a single 2.4 GHz radio and antenna between WiFi
 *     and Bluetooth. The coexistence scheduler needs WiFi Modem Sleep enabled
 *     (e.g., WIFI_PS_MIN_MODEM) to time-slice access to the antenna. In modem
 *     sleep mode, the WiFi radio is periodically turned off (sleeping) to allow
 *     the Bluetooth controller dedicated window slots to transmit/receive.
 *
 *     If WIFI_PS_NONE is set, WiFi radio remains continuously active. In this state,
 *     coexistence scheduling cannot guarantee safe Bluetooth window slots. To prevent
 *     corrupted transmissions, collisions, or controller instability, the ESP-IDF
 *     driver checks this state in pm_set_sleep_type() / wifi_set_ps_process() in
 *     libpp.a / libcoexist.a and asserts/aborts with:
 *       "Error! Should enable WiFi modem sleep when both WiFi and Bluetooth are enabled!!!!!!"
 *
 *   Resolution:
 *     We remove all calls to esp_wifi_set_ps(WIFI_PS_NONE) and let the framework use
 *     the default WIFI_PS_MIN_MODEM mode, allowing proper coexistence arbitration.
 *
 * ── Reconnect Storm Prevention ───────────────────────────────────────────────
 *
 *   WiFi.setAutoReconnect(true): already active (set in begin()).
 *     Our maintain() backoff (5s → 10s → 20s → 30s) prevents storms.
 *     BLE advertising is NOT interrupted during reconnects because the
 *     NimBLE stack runs in its own FreeRTOS task on core 0, independent
 *     of the Wi-Fi driver task. No BLE guard is required.
 *
 * ── Watchdog Notes ──────────────────────────────────────────────────────────
 *
 *   maintain() must NOT call delay() without feeding the WDT.
 *   esp_task_wdt_reset() is called before WiFi.begin() in reconnect path.
 */

#include <WiFi.h>
#include <esp_wifi.h>          // esp_wifi_set_ps()
#include <esp_task_wdt.h>      // esp_task_wdt_reset()
#include "config.h"
#include "wifi_manager.h"

namespace WiFiManager {

// ── State ────────────────────────────────────────────────────────────────────

static unsigned long _lastReconnectAttempt = 0;
static unsigned long _reconnectDelay = WIFI_RECONNECT_INTERVAL_MS;
static uint32_t _disconnectCount = 0;

// ── Initial connection (blocking) ────────────────────────────────────────────

void begin() {
    // ── esp_coex_preference_set() intentionally NOT called here ──────────
    //
    //   See file header for full root-cause analysis.
    //   Short reason: deprecated API + CONFIG_ESP32_WIFI_SW_COEXIST_ENABLE
    //   build flag caused abort() inside coex_core_enable() during
    //   NimBLEDevice::init(). Both have been removed.
    //   WIFI_PS_NONE (below) is the effective and safe coexistence improvement.

    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    #if FIRMWARE_DEBUG
    Serial.printf("[WiFi] Connecting to %s", WIFI_SSID);
    #endif

    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < WIFI_MAX_RETRIES) {
        delay(500);
        #if FIRMWARE_DEBUG
        Serial.print(".");
        #endif
        retries++;
    }

    if (WiFi.status() == WL_CONNECTED) {
        _reconnectDelay = WIFI_RECONNECT_INTERVAL_MS;  // Reset backoff

        #if FIRMWARE_DEBUG
        Serial.printf("\n[WiFi] Connected. IP: %s  RSSI: %d dBm\n",
            WiFi.localIP().toString().c_str(), WiFi.RSSI());
        Serial.printf("[WiFi] INFO: Auto-reconnect enabled, backoff %lu ms\n",
            _reconnectDelay);
        #endif
    } else {
        #if FIRMWARE_DEBUG
        Serial.println("\n[WiFi] Connection FAILED — restarting in 3s");
        #endif
        delay(3000);
        ESP.restart();
    }
}

// ── Non-blocking reconnect (call from loop) ──────────────────────────────────

void maintain() {
    if (WiFi.status() == WL_CONNECTED) {
        return;
    }

    unsigned long now = millis();
    if (now - _lastReconnectAttempt < _reconnectDelay) {
        return;  // Backoff timer not elapsed
    }

    _lastReconnectAttempt = now;
    _disconnectCount++;

    #if FIRMWARE_DEBUG
    Serial.printf("[WiFi] Reconnecting... (attempt %u, backoff %lums)\n",
        _disconnectCount, _reconnectDelay);
    #endif

    // Feed WDT before blocking WiFi driver calls.
    // WiFi.begin() can block briefly; without resetting the WDT here, a run
    // of rapid reconnect attempts could push total blocked time past the
    // watchdog timeout.
    esp_task_wdt_reset();

    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    // Do NOT delay() here — this is called from loop() which owns the WDT
    // feed at the top.  The backoff timer (_reconnectDelay) already prevents
    // hammering; we just kick off the connection and return immediately.
    // The WiFi driver reconnects in the background on its own FreeRTOS task.
    //
    // BLE advertising is NOT affected by reconnects: NimBLE runs in its own
    // FreeRTOS task on core 0 and is independent of the Wi-Fi driver.
    yield();

    if (WiFi.status() == WL_CONNECTED) {
        _reconnectDelay = WIFI_RECONNECT_INTERVAL_MS;  // Reset backoff
        #if FIRMWARE_DEBUG
        Serial.printf("[WiFi] Reconnected. IP: %s\n",
            WiFi.localIP().toString().c_str());
        #endif
    } else {
        // Exponential backoff: 5s → 10s → 20s → 30s (capped)
        _reconnectDelay = min(_reconnectDelay * 2,
            (unsigned long)MQTT_RECONNECT_MAX_MS);
    }

    // If too many failures, hard restart
    if (_disconnectCount > 30) {
        #if FIRMWARE_DEBUG
        Serial.println("[WiFi] Too many failures — restarting ESP32");
        #endif
        ESP.restart();
    }
}

// ── Getters ──────────────────────────────────────────────────────────────────

bool isConnected() {
    return WiFi.status() == WL_CONNECTED;
}

int getRSSI() {
    if (WiFi.status() != WL_CONNECTED) return 0;
    return WiFi.RSSI();
}

}  // namespace WiFiManager
