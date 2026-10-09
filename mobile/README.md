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
* No photo is taken: the face is cut out of the live preview frame in memory
  and turned into a 192-float signature. Nothing is written to storage.
* Only that signature is sent to the backend.

## Face capture on low-end phones

* Works on 480p preview frames (`ResolutionPreset.medium`). It needs about 5 analysed frames per second, which cheap phones manage.
* NV21 frames are used directly. Phones that send 3-plane YUV_420_888 frames instead are converted.
* If no frame is analysed within 8 s, the screen explains why instead of waiting.
* **Dim light:** when the face is dark, the screen turns white at full brightness and acts as a fill light. Crops that are still too dark are refused with a "Too dark" prompt.
* **Brightness:** each crop is brightness-normalised before the signature is computed.
* **Liveness:** thresholds suit noisy eye and smile readings. If ML Kit briefly loses the face during a head turn, the steps don't restart.
* **Photo swap:** a signature taken while you do the liveness steps must match the final capture, so a photo held up at the end is caught.
* **Model version:** signatures carry `mobilefacenet-112-v2` (`AppConfig.faceModelVersion`). A face enrolled with an older version gets `FACE_REENROLL_REQUIRED` and must be reset by an admin.

`assets/models/mobilefacenet.tflite` is MobileFaceNet from
[MCarlomagno/FaceRecognitionAuth](https://github.com/MCarlomagno/FaceRecognitionAuth)
(BSD-3-Clause), based on
[sirius-ai/MobileFaceNet_TF](https://github.com/sirius-ai/MobileFaceNet_TF)
(Apache-2.0). See `assets/models/NOTICE.md`.
