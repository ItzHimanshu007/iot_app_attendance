# Staff Attendance — Flutter app (Android)

```bash
cp config/example.json config/dev.json   # fill in Supabase URL/key and API URL
flutter pub get
flutter run --dart-define-from-file=config/dev.json
flutter build apk --release --dart-define-from-file=config/dev.json
flutter test
```

Requires Flutter 3.47+ and a real Android phone (BLE, front camera). Emulators
are rejected by design.

## Structure

```
lib/
  main.dart, app.dart            Supabase init, router, app gate (login → onboarding → home)
  core/                          config, API client (Supabase JWT), theme, formatters
  shared/widgets.dart            badges, empty/error states, buttons
  features/
    auth/                        sign in / sign up / reset, /me provider
    onboarding/                  bind phone → enroll face → wait for approval
    device/                      ANDROID_ID-based device fingerprint
    beacon/                      BLE scan + Protocol V3 decoder (ESP32 beacon)
    face/                        camera screen, ML Kit liveness, MobileFaceNet (TFLite)
    location/                    GPS fix with mock-location flag
    attendance/                  home, check-in/out flow, history
    profile/                     profile + sign out
    admin/                       roster, staff approvals, alerts, beacons, settings/export
assets/models/mobilefacenet.tflite
```

## Privacy

* No gallery or storage permission. Faces are only captured from the live
  front camera.
* The single captured JPEG is deleted right after the face signature is computed.
* Only the 192-float signature is sent to the backend.

`assets/models/mobilefacenet.tflite` is MobileFaceNet from
[MCarlomagno/FaceRecognitionAuth](https://github.com/MCarlomagno/FaceRecognitionAuth)
(BSD-3-Clause), based on
[sirius-ai/MobileFaceNet_TF](https://github.com/sirius-ai/MobileFaceNet_TF)
(Apache-2.0). See `assets/models/NOTICE.md`.
