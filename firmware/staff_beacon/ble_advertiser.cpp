#include "ble_advertiser.h"

#include <NimBLEDevice.h>
#include <string.h>

#include "config.h"

namespace BleAdvertiser {

static NimBLEAdvertising* s_adv = nullptr;
static bool s_advertising = false;
static uint8_t s_uuid[UUID_BYTES];

static int nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/// "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" → 16 bytes.
static bool parseUuid(const char* text, uint8_t out[UUID_BYTES]) {
    if (strlen(text) != 36) return false;
    size_t o = 0;
    for (size_t i = 0; i < 36; i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (text[i] != '-') return false;
            continue;
        }
        int hi = nibble(text[i]);
        int lo = nibble(text[++i]);
        if (hi < 0 || lo < 0 || o >= UUID_BYTES) return false;
        out[o++] = (uint8_t)((hi << 4) | lo);
    }
    return o == UUID_BYTES;
}

void begin() {
    if (!parseUuid(BEACON_ID, s_uuid)) {
        Serial.println("[BLE] FATAL: BEACON_ID in secrets.h is not a valid UUID. Halting.");
        while (true) delay(1000);
    }

    NimBLEDevice::init(BEACON_NAME);
    NimBLEDevice::setPower(BLE_TX_POWER_DBM);
    s_adv = NimBLEDevice::getAdvertising();

    // Must be called while the advertisement data is still empty: it adds a
    // 3-byte Flags element, and our 30-byte payload leaves no room for it later.
    s_adv->setConnectableMode(BLE_GAP_CONN_MODE_NON);
    s_adv->setMinInterval(BLE_ADV_INTERVAL);
    s_adv->setMaxInterval(BLE_ADV_INTERVAL);

    Serial.printf("[BLE] Ready: name=%s id=%s tx=+%d dBm interval=%d ms\n",
                  BEACON_NAME, BEACON_ID, BLE_TX_POWER_DBM, BLE_ADV_INTERVAL * 625 / 1000);
}

void advertise(const uint8_t token[8]) {
    if (s_adv == nullptr) return;
    if (s_advertising) {
        s_adv->stop();
        s_advertising = false;
        yield();  // ~1 ms for the controller to acknowledge the stop
    }

    // Company ID (LE) + V3 payload = 28 bytes → 30-byte AD element (≤ 31).
    uint8_t mfr[2 + MFR_PAYLOAD_LEN];
    mfr[0] = COMPANY_ID_LO;
    mfr[1] = COMPANY_ID_HI;
    mfr[2] = BLE_PROTO_VERSION;
    mfr[3] = BLE_PAYLOAD_TYPE;
    memcpy(mfr + 4, token, TOKEN_BYTES);
    memcpy(mfr + 4 + TOKEN_BYTES, s_uuid, UUID_BYTES);

    NimBLEAdvertisementData advData;
    advData.setManufacturerData(std::string(reinterpret_cast<char*>(mfr), sizeof(mfr)));
    s_adv->setAdvertisementData(advData);

    NimBLEAdvertisementData scanData;
    scanData.setName(BEACON_NAME);
    s_adv->setScanResponseData(scanData);

    s_adv->setMinInterval(BLE_ADV_INTERVAL);
    s_adv->setMaxInterval(BLE_ADV_INTERVAL);
    s_advertising = s_adv->start();
}

void stop() {
    if (s_adv != nullptr && s_advertising) {
        s_adv->stop();
        s_advertising = false;
    }
}

bool isAdvertising() {
    return s_advertising;
}

}  // namespace BleAdvertiser
