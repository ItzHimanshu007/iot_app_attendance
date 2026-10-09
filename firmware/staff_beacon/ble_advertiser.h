// ble_advertiser.h — Protocol V3 BLE advertiser (NimBLE-Arduino 2.x)
//
// Kept from the student system: same packet layout, same 100 ms interval,
// non-connectable advertising, name in the scan response. Only the token
// source changed — it is now computed locally every window.
#pragma once

#include <Arduino.h>

namespace BleAdvertiser {

/// Initialise NimBLE and decode BEACON_ID. Halts on a malformed BEACON_ID.
void begin();

/// Put [token] (8 bytes) in the payload and (re)start advertising.
void advertise(const uint8_t token[8]);

/// Stop advertising (e.g. while the clock is not set).
void stop();

bool isAdvertising();

}  // namespace BleAdvertiser
