// time_sync.h — Wi-Fi + NTP so the beacon knows the current 30-second window.
#pragma once

#include <Arduino.h>

namespace TimeSync {

/// Connect to Wi-Fi and start SNTP. Non-fatal: call maintain() from loop().
void begin();

/// Reconnect Wi-Fi with back-off (SNTP re-syncs automatically, hourly).
void maintain();

/// True once the clock holds a plausible real time.
bool isValid();

/// Current Unix time in seconds.
uint32_t epoch();

}  // namespace TimeSync
