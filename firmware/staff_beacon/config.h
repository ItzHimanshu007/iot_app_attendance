// =============================================================================
// config.h — protocol constants (shared by every beacon, safe to commit)
// =============================================================================
#pragma once

#include <Arduino.h>

#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Missing secrets.h — copy secrets.example.h to secrets.h and fill it in."
#endif

#define FIRMWARE_VERSION "4.0.0"

// ── Protocol V3 manufacturer data (unchanged from the student system) ───────
//   Company ID 0xFFFF (little-endian), then 26 bytes:
//     [0]      0x03  protocol version
//     [1]      0x01  payload type: attendance beacon
//     [2..9]   8 token bytes  (first 8 bytes of the HMAC-SHA256)
//     [10..25] 16 beacon UUID bytes
#define BLE_PROTO_VERSION  0x03
#define BLE_PAYLOAD_TYPE   0x01
#define COMPANY_ID_LO      0xFF
#define COMPANY_ID_HI      0xFF
#define TOKEN_BYTES        8
#define UUID_BYTES         16
#define MFR_PAYLOAD_LEN    (2 + TOKEN_BYTES + UUID_BYTES)   // 26

// ── Radio ───────────────────────────────────────────────────────────────────
// 160 × 0.625 ms = 100 ms fixed interval (best detection at range).
#define BLE_ADV_INTERVAL   160
// Transmit power in dBm (ESP32 max is +9).
#define BLE_TX_POWER_DBM   9

// ── Time ────────────────────────────────────────────────────────────────────
#define NTP_SERVER_1       "pool.ntp.org"
#define NTP_SERVER_2       "time.google.com"
#define NTP_SERVER_3       "time.cloudflare.com"
// Any epoch earlier than this means "clock not set yet" (2024-01-01).
#define MIN_VALID_EPOCH    1704067200UL

// Status LED (GPIO 2 on most ESP32 dev boards). Set to -1 to disable.
#define STATUS_LED_PIN     2
