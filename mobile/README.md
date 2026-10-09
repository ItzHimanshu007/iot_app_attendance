# Staff Attendance — Flutter app (Android)

```bash
cp config/example.json config/dev.json   # Supabase URL/key, API URL, college name
flutter pub get
flutter run --dart-define-from-file=config/dev.json
flutter build apk --release --dart-define-from-file=config/dev.json
flutter test
```

Requires Flutter 3.47+ and a real Android phone (BLE, front camera). Emulators
are rejected by design.

## Branding

| Setting | Where |
|---|---|
| College name on the sign-in and splash screens | `COLLEGE_NAME` in `config/dev.json` |
| "Need help? Contact …" text | `SUPPORT_CONTACT` in `config/dev.json` |
| Campus name after sign-in | Admin → Settings → Campus name (from the backend) |
| Colours | `lib/core/theme/colors.dart` (navy + gold palette) |
| App icon / logo | `android/app/src/main/res/mipmap-*`, `assets/branding/logo.png` |
| Fonts | Poppins (headings, bundled, SIL OFL; see `assets/fonts/OFL.txt`) + Roboto (body, system font) |

## Screens

* **Staff:** Sign in · Sign up · Onboarding (phone → face → approval) · Home ·
  Face verification · Result · Attendance history · Profile
* **Admin** (extra tab for administrators): Overview (attendance rate, roster,
  manual marks) · Staff approvals · Proxy alerts · Beacons · Settings and Excel export

Regenerate the screenshots in `../docs/screenshots` after UI changes:

```bash
flutter test --tags screenshots --run-skipped --update-goldens
```

## Structure

```
lib/
  main.dart, app.dart            Supabase init, router, app gate (login → onboarding → shell)
  core/                          config, API client, error texts, formatters, theme
  shared/widgets.dart            design-system components (cards, chips, stat tiles, banners…)
  features/
    shell/                       bottom navigation: Home · Attendance · Profile · Admin
    auth/                        sign in / sign up / reset, /me provider
    onboarding/                  phone → face → approval checklist
    device/                      ANDROID_ID-based device fingerprint
    beacon/                      BLE scan + Protocol V3 decoder (ESP32 beacon)
    face/                        camera screen, ML Kit liveness, MobileFaceNet (TFLite)
    location/                    GPS fix with mock-location flag
    attendance/                  home dashboard, check-in/out flow + result screens, history
    profile/                     profile, security info, sign out
    admin/                       overview, staff, alerts, beacons, settings/export
assets/models/mobilefacenet.tflite
assets/fonts/                    Poppins
assets/branding/logo.png
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
