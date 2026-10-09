#include "time_sync.h"

#include <WiFi.h>
#include <time.h>

#include "config.h"

namespace TimeSync {

static unsigned long s_lastAttempt = 0;
static unsigned long s_backoffMs = 5000;

void begin() {
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.printf("[TIME] Connecting to Wi-Fi \"%s\"", WIFI_SSID);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) {
        delay(250);
        Serial.print(".");
    }
    Serial.println(WiFi.status() == WL_CONNECTED ? " connected" : " not yet (will retry)");

    // UTC — the token uses Unix time, so no timezone is needed.
    configTime(0, 0, NTP_SERVER_1, NTP_SERVER_2, NTP_SERVER_3);
}

void maintain() {
    if (WiFi.status() == WL_CONNECTED) {
        s_backoffMs = 5000;
        return;
    }
    unsigned long now = millis();
    if (now - s_lastAttempt < s_backoffMs) return;
    s_lastAttempt = now;
    Serial.println("[TIME] Wi-Fi down — reconnecting (BLE keeps advertising)");
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    s_backoffMs = min(s_backoffMs * 2, 60000UL);
}

bool isValid() {
    return (uint32_t)time(nullptr) >= MIN_VALID_EPOCH;
}

uint32_t epoch() {
    return (uint32_t)time(nullptr);
}

}  // namespace TimeSync
