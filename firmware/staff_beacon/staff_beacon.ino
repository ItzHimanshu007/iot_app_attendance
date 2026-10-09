/*
 * Staff Attendance — ESP32 BLE beacon  (firmware 4.x)
 * ====================================================
 *
 * Advertises a rotating token that proves a phone is physically near this
 * beacon right now. The token changes every TOKEN_WINDOW_SECONDS (30 s):
 *
 *     token = HMAC-SHA256(BEACON_SECRET, "<beacon_id>:<unix_time / 30>")[0..7]
 *
 * The backend recomputes the same value, so the beacon never needs to talk
 * to the server (no MQTT, no broker, works while the API is asleep).
 * Wi-Fi is only used to set the clock via NTP.
 *
 * Packet (Protocol V3, unchanged from the student system):
 *   company 0xFFFF | 0x03 | 0x01 | 8 token bytes | 16 beacon-UUID bytes
 *   scan response: complete local name = BEACON_NAME ("SCA-…")
 *
 * LED: fast blink = waiting for time sync, solid = advertising.
 */

#include <Arduino.h>

#include "ble_advertiser.h"
#include "config.h"
#include "time_sync.h"
#include "token_generator.h"

static uint32_t s_currentWindow = 0;
static unsigned long s_lastLog = 0;

static void setLed(bool on) {
#if STATUS_LED_PIN >= 0
    digitalWrite(STATUS_LED_PIN, on ? HIGH : LOW);
#endif
}

void setup() {
    Serial.begin(115200);
    delay(200);
#if STATUS_LED_PIN >= 0
    pinMode(STATUS_LED_PIN, OUTPUT);
#endif
    Serial.println();
    Serial.println("=============================================");
    Serial.printf(" Staff Attendance Beacon  v%s\n", FIRMWARE_VERSION);
    Serial.printf(" Beacon : %s (%s)\n", BEACON_NAME, BEACON_ID);
    Serial.printf(" Window : %d s\n", TOKEN_WINDOW_SECONDS);
    Serial.println("=============================================");

    BleAdvertiser::begin();
    TimeSync::begin();
}

void loop() {
    TimeSync::maintain();

    if (!TimeSync::isValid()) {
        // Never advertise a token computed from a wrong clock.
        BleAdvertiser::stop();
        setLed((millis() / 150) % 2);
        if (millis() - s_lastLog > 5000) {
            s_lastLog = millis();
            Serial.println("[MAIN] Waiting for NTP time sync…");
        }
        delay(50);
        return;
    }

    uint32_t window = TimeSync::epoch() / TOKEN_WINDOW_SECONDS;
    if (window != s_currentWindow || !BleAdvertiser::isAdvertising()) {
        uint8_t token[8];
        if (TokenGenerator::compute(window, token)) {
            BleAdvertiser::advertise(token);
            s_currentWindow = window;
            char hex[17];
            TokenGenerator::toHex(token, 8, hex);
            Serial.printf("[MAIN] window=%lu token=%s heap=%u\n",
                          (unsigned long)window, hex, ESP.getFreeHeap());
        } else {
            Serial.println("[MAIN] ERROR: HMAC failed");
        }
    }
    setLed(BleAdvertiser::isAdvertising());
    delay(200);
}
