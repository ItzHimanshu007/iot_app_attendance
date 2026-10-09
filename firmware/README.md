# ESP32 staff-attendance beacon

An ESP32 that advertises a **rotating token** over BLE. A phone can only get a
valid token by being physically near the beacon right now.

```
token = HMAC-SHA256(BEACON_SECRET, "<beacon_id>:<unix_time / 30>")[first 8 bytes]
```

The backend recomputes the same token, so the beacon **never talks to the
server**. There's no MQTT and no broker, and it keeps working while the API sleeps.
Wi-Fi is only used once at boot (and hourly afterwards) to set the clock via NTP.

## What changed from the student firmware

| Kept | Removed / changed |
|---|---|
| Protocol V3 packet: company `0xFFFF`, `0x03 0x01`, 8 token bytes, 16 UUID bytes | MQTT / HiveMQ client, session start/stop commands |
| NimBLE-Arduino, 100 ms non-connectable advertising, +9 dBm, name in scan response | Heartbeat / telemetry / status reporter |
| Wi-Fi reconnect with back-off | Tokens pushed by the backend → **computed locally** every 30 s |
| | Hard-coded Wi-Fi/MQTT passwords → `secrets.h` (git-ignored) |

## Flash a beacon (10 minutes)

1. **Create the beacon** in the app: *Admin → Beacons → Add beacon* (or
   `POST /api/v1/admin/beacons`). Tap **Firmware config** and copy the snippet.
2. Copy `staff_beacon/secrets.example.h` to `staff_beacon/secrets.h` and paste
   the values (also set your Wi-Fi SSID/password).
3. Build and flash:
   * **PlatformIO:** `cd firmware && pio run -t upload && pio device monitor`
   * **Arduino IDE:** open `staff_beacon/staff_beacon.ino`, install the
     *NimBLE-Arduino* library (2.x) from the Library Manager, select
     *ESP32 Dev Module*, and upload.
4. The serial monitor shows `window=… token=…` every 30 s. The on-board LED
   blinks fast until the clock is synced, then stays on.

## Placement tips

* Put the beacon where staff **already stop** (staff room, department office,
  parking), **not** at the main gate, or you recreate the gate crowd.
* Tune `rssi_threshold` per beacon in the admin screen. -85 dBm is roughly
  10–20 m indoors; use -75 to require being in the same room.
* Power it from a USB charger. It needs Wi-Fi only to get the time.

## Checking the token by hand

With `BEACON_ID = 43905a99-a513-5a9d-8cb5-e109b98166bb`,
`BEACON_SECRET = "a" × 64` and window `58000000`, the token must be
**`37a4820d05333aa1`**. The backend test `test_token_known_vector` checks the
same vector, and `token_generator.cpp` was host-compiled against it.
