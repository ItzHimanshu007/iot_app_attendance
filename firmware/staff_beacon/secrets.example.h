// =============================================================================
// secrets.h — per-beacon configuration (NOT committed to git)
// =============================================================================
// 1. Copy this file to secrets.h (same folder).
// 2. In the app: Admin → Beacons → Add beacon (or open an existing one)
//    → "Firmware config" → copy the values here.
// =============================================================================
#pragma once

// Campus Wi-Fi — only used to get the correct time (NTP). The beacon keeps
// advertising if Wi-Fi drops later; the clock keeps running.
#define WIFI_SSID      "your-campus-wifi"
#define WIFI_PASSWORD  "your-wifi-password"

// From the backend (beacons.id) — lowercase UUID, exactly 36 characters.
#define BEACON_ID      "00000000-0000-0000-0000-000000000000"

// From the backend (beacons.secret) — 64 hex characters. Keep it private.
#define BEACON_SECRET  "0000000000000000000000000000000000000000000000000000000000000000"

// Name shown in BLE scanners. Must start with "SCA-" (max ~20 chars).
#define BEACON_NAME    "SCA-STAFFROOM"

// Must equal BEACON_WINDOW_SECONDS on the backend (default 30).
#define TOKEN_WINDOW_SECONDS 30
