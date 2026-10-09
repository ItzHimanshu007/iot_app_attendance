# Transition plan: student BLE attendance ➜ staff attendance (PS 23 / SKIT023)

This document records how the old **student/teacher class-session** app was turned
into a **staff check-in / check-out** system, what was kept, what was removed,
and how the pieces fit together.

## 1. Goal

Staff stop queuing at the main gate. They mark attendance **from their own phone
after entering the campus**, and the system must make proxy attendance
impractical.

| PS 23 requirement | How it is met |
|---|---|
| 1. Live image capture | Front camera opened by the app (`camera` plugin, live preview only). |
| 2. No gallery uploads | The app has **no** image-picker / gallery code path at all. Frames are taken from the live camera and the temporary JPEG is deleted immediately. |
| 3. Facial recognition | On-device MobileFaceNet (TFLite) turns the face into a 192-number signature. Only that signature is sent; the **photo never leaves the phone**. The server compares it with the enrolled signature. |
| 4. Campus verification | **BLE beacon (ESP32) in range is mandatory**, with a rotating HMAC token that changes every 30 s, plus **GPS geofence** against the campus latitude/longitude/radius (mode `flag` or `enforce`) and fake-GPS detection. |
| 5. Proxy prevention | One phone per staff member (device binding), random liveness challenge (blink / smile / turn head), one-time server challenge, duplicate-face check at enrollment, admin approval, emulator block, and an audit log of every failed attempt. |

## 2. New user flow

```
Sign up (email, name, employee ID)  ──►  Supabase Auth  ──►  `staff` row created (status = pending)
        │
        ▼
Onboarding (first login)
  1. Bind this phone            POST /api/v1/devices/register
  2. Enroll face (live)         POST /api/v1/face/enroll      (3 face signatures, liveness first)
  3. Wait for admin approval    admin taps "Approve" in the Admin screen
        │
        ▼
Daily use
  Home screen scans for the campus beacon (ESP32, name "SCA-…")
  └─ beacon in range (RSSI ≥ threshold)  →  "Mark attendance" button unlocks
       1. POST /attendance/challenge   (server checks beacon token + device + state)
          ◄─ challenge_id + 2 random liveness steps (e.g. "blink", "turn_head")
       2. Camera opens → user performs the steps → one frame is captured
          → MobileFaceNet signature computed on the phone → JPEG deleted
       3. GPS fix (with mock-location flag)
       4. POST /attendance/submit       (face match, liveness, beacon, geofence, device)
          ◄─ present / late  (or a precise rejection reason)
  The same flow is used later in the day for check-out.
```

## 3. What was kept, changed or removed

| Area | Kept / reused | Removed |
|---|---|---|
| **ESP32 firmware** | NimBLE Protocol V3 advertiser (company ID 0xFFFF, `0x03 0x01`, 8-byte token, 16-byte UUID), Wi-Fi manager | MQTT/HiveMQ, session start/stop commands, heartbeat/telemetry. The ESP32 now **computes its own token** (HMAC-SHA256 of `beacon_id:window`, NTP time), so the backend no longer has to push tokens and Render's free-tier sleep can't break it. |
| **Flutter BLE** | V3 payload parser, scanner lessons (no `startScan(timeout)`, low-latency mode, cumulative `scanResults`, 10 s TTL, Android ≤ 30 location rule), `flutter_blue_plus` 1.36.8 (BSD-3) | V2 / name-only fallbacks, debug scanner screen |
| **Flutter app** | Theme (colours/typography), typed exception hierarchy, Dio API client pattern | All student/teacher screens, session discovery, timetable, reports for classes, `local_auth` fingerprint "biometrics" (it only proved *someone* unlocked the phone) |
| **Auth** | Supabase Auth (email + password) | Hand-rolled REST auth client → replaced by `supabase_flutter` (auto token refresh + persisted session) |
| **Device binding** | One active phone per account, fingerprint hash | Silent self-service device replacement (it let anyone move an account to a new phone). Changing phone now requires an admin reset. The fingerprint now uses the real `ANDROID_ID` (the old code used the *build ID*, which is identical for every phone of the same model/ROM). |
| **Backend** | FastAPI app skeleton, structured logging, request-ID middleware, error envelope, Supabase JWT verification (ES256 via JWKS + legacy HS256), repository base class, Excel export (openpyxl), Dockerfile / Render | Sessions, classrooms, subjects, enrollment, timetable, roster, notifications, MQTT publisher/subscriber, token-rotation loop, Alembic/SQLAlchemy models |
| **Database** | Supabase (new project recommended) | Every old table (`users`, `attendance_sessions`, `attendance_records`, `classrooms`, …). See `supabase/legacy/drop_student_schema.sql` if you reuse the old project. |
| **Repo hygiene** | – | Committed `.venv` (130 MB), committed `.env` with live keys, UTF-16 `.gitignore` that git could not read, helper scripts with demo passwords |

## 4. Architecture

```
┌──────────────┐  BLE adv (every 100 ms)   ┌──────────────────────┐
│ ESP32 beacon │ ─────────────────────────► │  Flutter staff app   │
│ token = HMAC │  0x03 0x01 [token][uuid]   │  (Android)           │
│ (NTP time)   │                            │  • BLE scan          │
└──────────────┘                            │  • camera + ML Kit   │
                                            │  • MobileFaceNet     │
                                            │  • GPS               │
                                            └─────────┬────────────┘
                     Supabase Auth (JWT) ◄────────────┤
                                                      │ HTTPS + Bearer JWT
                                            ┌─────────▼────────────┐
                                            │  FastAPI backend     │
                                            │  verifies everything │
                                            └─────────┬────────────┘
                                                      │ service-role key
                                            ┌─────────▼────────────┐
                                            │ Supabase Postgres    │
                                            │ (RLS on every table) │
                                            └──────────────────────┘
```

The phone never decides "present". It only collects evidence. The backend checks
all of it and writes the record.

## 5. Database (Supabase)

File: `supabase/migrations/20261009000000_staff_attendance.sql`

| Table | Purpose |
|---|---|
| `staff` | Profile per auth user (`role` staff/admin, `status` pending/active/disabled). Created by a trigger on `auth.users`. |
| `devices` | Bound phone per staff member (partial unique index: one active device per staff, one active owner per fingerprint). |
| `face_templates` | Enrolled face signatures (JSON array of L2-normalised vectors) + approval status. **No photos are stored anywhere.** |
| `beacons` | ESP32 beacons: UUID (advertised), per-beacon HMAC secret, RSSI threshold. |
| `campus_settings` | Single row: campus lat/lng/radius, geofence mode, timezone, office start time, late grace, face-match threshold. |
| `attendance_challenges` | One-time challenges (nonce + liveness steps, 2-minute expiry, consumed once). |
| `attendance` | One row per staff per day: check-in/out times, beacon, RSSI, face score, location, flags, manual-override info. |
| `attendance_attempts` | Every success *and* failure with a reason code. This is the proxy-attempt log for admins. |
| `admin_audit_log` | Every admin action (approve, reset device, manual mark, settings change …). |

The mobile app only talks to Supabase for **authentication**; all data goes
through the backend, which uses the service-role key. RLS is enabled on every
table: staff can read their own profile/device/attendance, and sensitive tables
(face templates, beacon secrets, challenges, audit) have no client policies at all.

## 6. Backend API (`/api/v1`)

| Method | Path | Who | What |
|---|---|---|---|
| GET | `/me` | any signed-in | Profile + device + face status + `onboarding.next_step` |
| PATCH | `/me` | any signed-in | Update phone/department/designation (name/employee ID while pending) |
| POST | `/devices/register` | any signed-in | Bind this phone |
| GET | `/devices/me` | any signed-in | Current bound phone |
| POST | `/face/enroll` | bound phone | Store 3–10 face signatures (pending approval) |
| GET | `/face/status` | any signed-in | Enrollment status |
| GET | `/campus` | any signed-in | Public campus settings |
| POST | `/attendance/challenge` | active staff | Validate beacon/device/state → challenge + liveness steps |
| POST | `/attendance/submit` | active staff | Final verification → attendance record |
| GET | `/attendance/today` | active staff | Today's record |
| GET | `/attendance/history` | active staff | Own history |
| GET | `/admin/staff` | admin | List/search staff (filter by status) |
| POST | `/admin/staff/{id}/approve` | admin | Activate account + approve face |
| POST | `/admin/staff/{id}/reject-face` | admin | Ask staff to re-enroll |
| POST | `/admin/staff/{id}/reset-device` | admin | Allow binding a new phone |
| POST | `/admin/staff/{id}/reset-face` | admin | Delete face template |
| POST | `/admin/staff/{id}/status` | admin | Disable / re-enable |
| POST | `/admin/staff/{id}/role` | admin | Promote/demote admin |
| GET | `/admin/attendance?date=` | admin | Day roster + summary counts |
| POST | `/admin/attendance/manual` | admin | Manual mark with reason (audited) |
| GET | `/admin/attempts` | admin | Failed / suspicious attempts |
| GET | `/admin/reports/export?from=&to=` | admin | Excel report |
| GET/POST/PATCH | `/admin/beacons…` | admin | Manage beacons, view/rotate secret |
| GET/PUT | `/admin/campus` | admin | Campus settings |

## 7. Anti-proxy matrix

| Attempt | Blocked by |
|---|---|
| Marking from home / outside campus | No beacon in range → button locked; server re-checks the rotating token; GPS geofence |
| Friend forwards a screenshot of the beacon token | Token rotates every 30 s, is bound to the beacon ID, and the challenge expires in 2 minutes. Face + device are still required. |
| Fake GPS app | `isMocked` → rejected (`MOCK_LOCATION`) |
| Friend uses your phone | Face match fails |
| Holding up your photo/video | Random liveness steps chosen by the server, and the face tracking ID must stay the same through the whole challenge |
| Friend logs into your account on their phone | Device binding (one phone, admin reset needed to change) |
| Friend enrolls *their* face on your account | Admin approval + duplicate-face check against every other approved staff member |
| Replaying an old request | One-time challenge, consumed atomically |
| Emulator / virtual camera | `isPhysicalDevice` check on the phone and on the server |

**Honest limitation (say this to the judges):** a rooted phone running a modified
APK can still forge client-side signals. The production fix is Google's Play
Integrity API, plus server-side liveness models. That is listed as future work.

## 8. Five-day execution plan

| Day | Work |
|---|---|
| 1 | Rotate the leaked keys. Create a **new** Supabase project, run the migration, make yourself admin, deploy the backend (Render), flash one ESP32 with a beacon created in the admin screen. |
| 2 | Build the APK, enroll 3–4 team members, tune `face_match_threshold` with real scores from `attendance_attempts`. |
| 3 | Walk the campus: set campus lat/lng/radius, find a good beacon spot (staff room / parking), tune `rssi_threshold`. |
| 4 | Admin polish: approvals, roster, alerts, Excel export. Try every attack in §7 and screenshot the rejections. |
| 5 | Record a backup demo video. Slides: problem → flow → anti-proxy matrix → live demo. |

## 9. Future work

* Play Integrity API attestation on every submit.
* Server-side passive liveness (anti-spoof model) on top of the challenge.
* Campus Wi-Fi BSSID allowlist as an extra location signal.
* Background geofence notification ("You're on campus — mark attendance").
* Multiple campuses / shifts.
