# Non-BLE, non-acoustic ways to prove a phone is inside a specific room (Wi-Fi RTT/FTM, Wi-Fi BSSID/RSSI, UWB, NFC, light/camera, QR, magnetic/barometer/sensor fusion)

Scope note for the report writer: this covers technologies other than BLE and ultrasound/acoustic. Context is an ESP32 + Flutter + cheap Android staff-attendance system in India, where a BLE beacon leaks through the staff-room wall. Research date: Oct 2026. Several primary pages could not be fetched directly (docs.espressif.com, arxiv.org, esp32.com, MIT CSAIL, Wikipedia, and UEA ePrints all failed DNS from the research sandbox). Where a finding comes only from a search-engine summary of a page, it is marked "(via search summary)". USD to INR conversions use an assumed ~₹88/USD. That rate is my own and comes from no source.

---

## 1. Wi-Fi RTT / IEEE 802.11mc Fine Timing Measurement (FTM): accuracy, Android support on budget phones, ESP32 as responder, Flutter, walls

### Takeaway
Wi-Fi RTT measures distance (about 1–2 m at best with 3+ commercial APs). It does not measure which side of a wall you are on. An ESP32 SoftAP can act as an FTM responder, but Android-to-ESP32 interop has a history of bugs, and Espressif itself warned that accuracy against phones "will be very low". Support on budget phones is patchy: some Samsung Galaxy A and Redmi Note models are on Google's list, but no market-share figure exists. Treat RTT as a weak extra signal, not as proof of being inside the room.

### Cited Findings
**How it works / accuracy**
- Android: "This class provides the primary API for measuring distance (range) to other devices using the IEEE 802.11mc Wi-Fi Round Trip Time (RTT) technology." Ranging targets are access points and Wi-Fi Aware peers — [Android WifiRttManager reference](https://developer.android.com/reference/android/net/wifi/rtt/WifiRttManager)
- With distances to **three or more APs** and multilateration, position is "typically accurate within 1-2 meters" — [Android Developers: Wi-Fi RTT](https://developer.android.com/develop/connectivity/wifi/wifi-rtt)
- A 2025 survey puts current Wi-Fi FTM accuracy at roughly 1–2 m (via search summary) — [arXiv 2509.03901, Indoor Positioning with Wi-Fi Location: A Survey of IEEE 802.11mc/az/bk FTM Research](https://arxiv.org/pdf/2509.03901)
- Android phones ranging to commercial APs: distance errors of about 0.5–1.7 m depending on phone, AP and burst size (via search summary) — [ScienceDirect: Assessing the Impact of the Burst Size in the FTM Ranging Procedure in COTS Wi-Fi Devices](https://www.sciencedirect.com/science/article/pii/S014036642400327X)
- With correction models, Orfanos et al. (Sensors 2023) report 1D mean absolute error of **0.85 m LOS vs 1.24 m NLOS** (for 80% of validation data) and about 1.1 m 2D RMSE. They note that raw measurements "suffer from instability… particularly in non-line-of-sight (NLOS) conditions" (via search summary) — [Orfanos et al. 2023, Sensors (TU Wien repository)](https://repositum.tuwien.at/bitstream/20.500.12708/175733/1/Orfanos-2023-Sensors-vor.pdf); [PMC10007519](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10007519/)
- Feng, Nguyen & Luo: RTT **trilateration "failed to deliver sub-metre accuracy as claimed"**, while RTT fingerprinting reached <0.75 m (a later version reports 0.6 m) (via search summary) — [Royal Holloway: WiFi RTT fingerprinting analysis](https://pure.royalholloway.ac.uk/en/publications/wifi-round-trip-time-rtt-fingerprinting-an-analysis-of-the-proper); [Brighton repository](https://research.brighton.ac.uk/en/publications/an-analysis-of-the-properties-and-the-performance-of-wifi-rtt-for/)
- NLOS/LOS condition is "the main factor that leads to inaccurate Wi-Fi RTT distance measurements" (via search summary) — [MDPI Algorithms 15(12):464](https://www.mdpi.com/1999-4893/15/12/464/htm)

**Android requirements / permissions**
- Wi-Fi RTT arrived in Android 9 (API 28). Android 10 added `ResponderLocation` (LCI/LCR). Android 15 (API 35) added IEEE 802.11az non-trigger-based ranging, which defaults to az when both sides support it and falls back to mc otherwise — [Android Developers: Wi-Fi RTT](https://developer.android.com/develop/connectivity/wifi/wifi-rtt)
- Permissions: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` (Android 13+), `ACCESS_FINE_LOCATION` (maxSdk 32). **Location services and Wi-Fi scanning must be ON.** Ranging works only from a foreground app or service ("Background location access is not permitted"). Foreground use is unlimited and background use is throttled — [Android Developers: Wi-Fi RTT](https://developer.android.com/develop/connectivity/wifi/wifi-rtt)
- Without one-sided RTT, only two-sided ranging works, and the responder must support 802.11mc. Apps check this with `ScanResult.is80211mcResponder()` (via search summary) — [Android WifiRttManager reference](https://developer.android.com/reference/android/net/wifi/rtt/WifiRttManager)

**Which phones support it (budget-phone relevance)**
- Google's supported-device list (described as "far from comprehensive") includes these phones. Android 14+ group: Pixel 7/7a/7 Pro/8/8a/8 Pro/9/9 Pro/9 Pro XL, Samsung **SM-A135F, SM-A127F, SM-A217F, SM-A515F, SM-A715F, SM-A528B, SM-A546E, SM-A556E**, SM-S911B, SM-S918B, SM-S928B, Xiaomi **21091116AI**. Android 9+ group: Pixel 1–6 incl. 3a/4a/5a, Xiaomi Mi 9/9T/10/10 Pro/Note 10/Note 10 Lite, **Redmi Note 5 Pro, Redmi Note 8, Note 8T, Note 9S, Note 9 Pro**, Redmi K20/K20 Pro/K30 Pro, **Poco X2**, LG G8X/V30/V50S/V60, Samsung Galaxy S20 family, Note 10 family, A9 Pro, Sharp Aquos R3 — [Android Developers: Wi-Fi RTT supported devices](https://developer.android.com/develop/connectivity/wifi/wifi-rtt)
- Support "depends on the individual manufacturer", so an Android 9+ phone may still lack it (Nov 2021 BANSHEE project snapshot) (via search summary) — [BANSHEE project Wi-Fi RTT PDF (UPC)](https://grxca.upc.edu/en/scientific-difussion/2021-banshee-project-wi-fi-rtt.pdf/@@download/file/2021-BANSHEE%20project-Wi-Fi%20RTT.pdf)
- An MIT page by B.K.P. Horn counts "at least 69" phones supporting FTM RTT (an earlier version said "over 50"). It also notes that many installed APs do not support FTM (via search summary; the page could not be fetched) — [MIT CSAIL: FTM RTT issues](https://people.csail.mit.edu/bkph/FTMRTT_issues)
- India market context: in 2025, **47%** of smartphones shipped in India used MediaTek chipsets and 29% Qualcomm. vivo led units with 20% share. Premium (₹30,000+) models were 22% of units — [GSMArena reporting Counterpoint](https://www.gsmarena.com/counterpoint_1_in_5_smartphones_shipped_in_india_in_2025_were_premium_models-news-71366.php)
- A search for MediaTek Dimensity or Redmi Note RTT confirmation found nothing. MediaTek's Dimensity page does not mention RTT/FTM — [MediaTek Dimensity](https://www.mediatek.com/products/smartphones/dimensity-5g)

**ESP32 as an FTM responder**
- Espressif docs: "ESP32-S3 as FTM Initiator in station mode. ESP32-S3 as FTM Responder in AP mode." The same pattern is documented for ESP32-S2, C2 and S31 (via search summary) — [ESP-IDF v6.0 ESP32-S3 Security and Roaming](https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32s3/api-guides/wifi-driver/security-and-roaming.html); [ESP-IDF v6.1 ESP32-S2](https://docs.espressif.com/projects/esp-idf/en/v6.1/esp32s2/api-guides/wifi-driver/security-and-roaming.html)
- ESP-IDF FTM example README lists supported targets **ESP32-C2, C3, C5, C6, C61, S2, S3, S31** (the original ESP32 is not listed). Supported configurations: "Station as Initiator and SoftAP as Responder on supported ESP devices" or station plus an external FTM AP. It says "ESP devices are self calibrated for high resolution measurement" and "The design requires line-of-sight with straightforward propagation path with no less than -70dBm RSSI for better results". For external initiators with large errors, it offers a zero-distance offset workaround (`ftm -R -o <cm0>`) — [esp-idf/examples/wifi/ftm/README.md](https://github.com/espressif/esp-idf/blob/master/examples/wifi/ftm/README.md)
- Conflict: the Arduino-ESP32 FTM example still says "THIS FEATURE IS SUPPORTED ONLY BY ESP32-S2 AND ESP32-C3" (older text) — [arduino-esp32 FTM_Responder.ino](https://github.com/espressif/arduino-esp32/blob/master/libraries/WiFi/examples/FTM/FTM_Responder/FTM_Responder.ino)
- An ESP32-C3 **pre-rev-3** in AP mode advertises FTM but never answers (it sends zero timestamps because the ROM code is missing). Android phones failed against it too. Espressif's fix was to use **rev 3 silicon** (issue closed Sep 2021) — [esp-idf issue #7578](https://github.com/espressif/esp-idf/issues/7578)
- **ESP32-S2 responder + Android phone** (issue #6810, Apr 2021 to Mar 2024): the phone saw FTM frames but got no RTT results. In Dec 2021 a Pixel 4a with Google's WifiRttScan got results only intermittently, and only while the phone was connected to some AP. A Mi 11X Pro did not show the problem. Espressif: "Also I must warn that the accuracy will be very low." In March 2024 Espressif "done more tests with Pixel devices and fixed some issues" and closed the issue via commit "Refactor and improve FTM code". **No commenter confirmed working Android-to-ESP32 ranging in a named release** — [esp-idf issue #6810](https://github.com/espressif/esp-idf/issues/6810)
- An older ESP32 forum thread said Google's WifiRttScan uses ASAP mode, which ESP32 did not support then. An older ESP-IDF example note listed "FTM Responder support for external Stations and ASAP mode" as future work (via search summary) — [esp32.com thread t=19919](https://esp32.com/viewtopic.php?t=19919)
- Another forum thread reportedly says ESP-IDF v4.3.1 made FTM work with Google's WifiRttScan on an Android phone, with "accuracy with third-party devices still being worked on" (via search summary; not directly fetched) — [esp32.com: Esp32C3 FTM](https://www.esp32.com/viewtopic.php?t=21183)
- No ESP-IDF release note mentioning FTM-responder ASAP support was found. v5.4 betas added "FTM calibration values for ESP32-C6" (via search summary) — [ESP-IDF v5.4-beta1 notes](https://newreleases.io/project/github/espressif/esp-idf/release/v5.4-beta1)
- ESP32-S2 to ESP32-S2 benchmark: good outdoors at longer range, but **poor at short indoor distances: about 1 m error at 0.5 m and 2–3 m error at 1.0–1.5 m**, attributed to HT20 bandwidth, first-arrival correction errors and hardware timestamp delays (via search summary) — [arXiv 2303.03766, Benchmarking and Security Considerations of Wi-Fi FTM for Ranging in IoT Devices](https://arxiv.org/html/2303.03766v1)
- Related paper (not fetched): [Fine Time Measurement for the Internet of Things: A Practical Approach Using ESP32 (arXiv 2401.16517)](https://arxiv.org/html/2401.16517v1)

**Flutter**
- `wifi_ftm` (publisher raylabz.com, v0.2.0, recently published, Android only, min SDK 24, compile SDK 35): capability detection, scanning for mc/az responders, multi-AP ranging, distance/RSSI/std-dev. It has about 375 downloads and 1 like, and it says nothing about ESP32 responders — [pub.dev wifi_ftm](https://pub.dev/packages/wifi_ftm); [GitHub RayLabz/wifi_ftm](https://github.com/RayLabz/wifi_ftm)
- `has_wifi_rtt` only checks support. `wifi_iot_rtt` is deprecated (via search summary) — [pub.dev has_wifi_rtt](https://pub.dev/packages/has_wifi_rtt); [depscope wifi_iot_rtt](https://depscope.dev/pkg/pub/wifi_iot_rtt)

### Inferences
- **Containment:** RTT gives a radius, not a room boundary. A phone just outside a wall that is 2 m from the ESP32 reads about 2 m, plus a small NLOS bias. That is indistinguishable from a phone 2 m inside, given ESP32-to-phone errors of ±1–3 m. RTT could only tighten the gate if the ESP32 sits far from every wall the public can reach (for example, centre of a large room with a "d < 2 m" rule). Even then a person pressed against the nearest wall may pass. Multilateration with 3+ ESP32 responders could in theory place the phone inside the room polygon, but the reported 1–3 m ESP32 errors are comparable to room dimensions.
- **Budget-phone support:** I read Google's model codes as Galaxy A13 (SM-A135F), A12 (SM-A127F), A21s (SM-A217F), A51, A71, A52s, A54, A55, and Xiaomi 11i HyperCharge (21091116AI; the "AI" suffix suggests the India variant). That reading comes from my own knowledge of model codes, not the source, so the writer should verify it. Some ₹10–20k phones therefore have RTT, but support is OEM-by-OEM, and the current best-sellers (vivo Y/T series, Realme, Redmi 13/14, Galaxy M) are not on the list. The safe approach is a runtime check (`FEATURE_WIFI_RTT`) with a fallback.
- **Security:** RTT measurements are produced by the phone's Wi-Fi stack and reported by the app. A modified app or rooted phone can report any distance, so the server cannot independently verify RTT unless the ESP32 is the measuring side.
- **Effort:** High. ESP32-S3/C3 rev3+/C6 SoftAP responder + Kotlin platform channel or `wifi_ftm` + per-phone calibration + Location-ON UX. Low cost (ESP32-S3 boards are cheap), but the interop risk is real and needs testing on the team's actual phones.

### Gaps
- No market-share figure (India or global) for Wi-Fi-RTT-capable Android phones was found. No confirmation for any vivo, Realme, Oppo, or MediaTek Dimensity/Helio budget model.
- No published measurement of Android-phone-to-ESP32-responder accuracy was found. Espressif's March 2024 fixes are not tied to a named release.
- No dedicated study of RTT error through specific Indian wall types (brick/RCC) was found.
- The security properties of 802.11mc FTM (unauthenticated frames) vs 802.11az secure ranging are addressed in arXiv 2303.03766, but the paper could not be fetched to quote specifics.

---

## 2. Wi-Fi based: requiring connection to the staff-room AP (BSSID check), RSSI fingerprinting, wall leakage, Android permissions

### Takeaway
Wi-Fi leaks through walls almost as much as BLE: 2.4 GHz loses only about 6–25 dB per brick or concrete wall. A BSSID or "connected to staff-room AP" check proves the phone is within Wi-Fi range of the AP, not inside the room. BSSIDs/SSIDs can be cloned, so this is spoofable without cryptographic AP signatures. RSSI fingerprinting gives metre-level accuracy at best, which is not enough to reliably separate the two sides of one wall.

### Cited Findings
- `WifiInfo.getBSSID()` returns **"02:00:00:00:00:00"** (and `getSSID()` returns `UNKNOWN_SSID`) when location-sensitive access is not allowed. Access "requires the same permissions as `WifiManager#getScanResults`" (via search summary) — [Android WifiInfo reference](https://developer.android.com/reference/android/net/wifi/WifiInfo)
- Apps targeting Android 10+ need `ACCESS_FINE_LOCATION` plus Location services ON to read SSID/BSSID (via search summary) — [pub.dev wifi_info_flutter docs](https://pub.dev/documentation/wifi_info_flutter/latest/); [network_info_plus](https://pub-web.flutter-io.cn/packages/network_info_plus/versions/2.3.0)
- Some Wi-Fi APIs still require `ACCESS_FINE_LOCATION` even when targeting Android 13. `NEARBY_WIFI_DEVICES` exists only from Android 13 (via search summary) — [Android Developers: Wi-Fi permissions](https://developer.android.com/develop/connectivity/wifi/wifi-permissions?hl=pl)
- **Wall attenuation at 2.4 GHz:**
  - Brick/concrete: 6–18 dB at 2.4 GHz and 10–30 dB at 5 GHz — [USPTO patent 11388680](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11388680)
  - CWNA study guide: brick, concrete and concrete block about −12 dB at 2.4 GHz — [Aruba community quoting CWNA](https://community.arubanetworks.com/viewthread?MID=17983)
  - Measured: about **8.9 dB** through a 10 cm concrete wall — [IEICE 2009](https://ken.ieice.org/ken/paper/20091217ZarQ/eng/)
  - 30.5 cm bearing wall or reinforced concrete slab: 20–25 dB — [Keenetic support](https://support.keenetic.com/titan/kn-1811/en/20207.html)
  - Moist/fresh concrete can exceed 20 dB — [MakeTechEasier](https://maketecheasier.com/mte-wi-fi-signals-struggle-through-walls-not-because-concrete-is-thick-but-because-water-in-the-plaster-absorbs-2-4-ghz-almost-exactly-the-frequency-a-microwave-oven-uses-to-heat-your-dinner/)
- **Spoofing:** a fraudulent user "can fool the system into reporting a false location by setting up wireless access points… with the proper SSIDs". The patent says this "may be avoided if a secure version is used in which each wireless access point broadcasts an encrypted time-dependent signature" — [USPTO patent 9883479](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9883479); [USPTO 10212689](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10212689)
- BSSID-based geolocation used by major vendors can be abused for tracking (Erik Rye, Black Hat USA 2024) — [SC Media](https://scmagazine.com/news/black-hat-usa-wi-fi-tracking-flaw-puts-the-bs-in-bssid)
- **Fingerprinting accuracy:** RTT fingerprinting reached 0.6 m in a complex indoor environment, reported as "107% better than traditional RSS fingerprinting" (via search summary) — [Royal Holloway](https://pure.royalholloway.ac.uk/en/publications/wifi-round-trip-time-rtt-fingerprinting-an-analysis-of-the-proper)
- IPIN 2023 on-site **smartphone** track winner (THWS): score **2.8 m** (third-quartile error). IPIN 2020 best smartphone-track third-quartile error was about 1 m. These systems typically fuse Wi-Fi, BLE, inertial sensors and so on (via search summary) — [EvAAL/IPIN 2023 results](https://evaal.isti.cnr.it/2023/results); [IPIN 2020 off-line evaluation](https://qmro.qmul.ac.uk/xmlui/handle/123456789/73992)

### Inferences
- An ESP32 SoftAP or college AP at about 15–20 dBm loses roughly 10 dB through one brick or RCC wall, which still leaves a strong, connectable signal a few metres outside. A "must be connected to SSID X / BSSID Y" rule therefore has the **same wall problem as BLE**. A coarse RSSI threshold (for example, connect only if RSSI > −45 dBm) shifts the boundary but cannot follow a wall, because phone-to-phone RSSI variation and body shadowing are of the same order (several dB).
- Making staff connect to an ESP32 SoftAP would also cut their internet unless the ESP32 bridges it, which hurts UX.
- **Spoof resistance:** if the ESP32 AP signs time-varying data (as the patent suggests), the check gains replay resistance but still not wall resistance. BSSID alone is trivially cloneable.
- **Effort:** Low (`network_info_plus` + location permission). Value against the wall problem is low.

### Gaps
- No measurement of RSSI separability across a single wall for budget Android phones was found.
- Android's Wi-Fi scan throttling, which limits how often a fingerprinting app can rescan, was not verified in this research.

---

## 3. UWB (ultra-wideband: Qorvo DW3000 / DWM3001C, Android UWB API)

### Takeaway
UWB is the only RF option here with real 10–30 cm ranging, plus cryptographic secure ranging (STS) that resists relay. With 3+ anchors it could geometrically decide inside or outside a room. But it needs a UWB phone: on Android that means Pixel Pro/8+, Galaxy S Ultra/Plus/Fold or Moto Edge 50 Ultra, all in the premium segment. It also needs FiRa-compliant anchors (about US$30 or ₹2,600 per Qorvo dev kit), and Android-to-Qorvo interop is not documented. **Not feasible for a cheap-Android-phone fleet in India in 2025–26.**

### Cited Findings
- Jetpack UWB (`androidx.core.uwb`): Android 12+, feature check `android.hardware.uwb`. IoT peers must be **FiRa MAC 1.3 compliant**. Out-of-band setup (e.g., BLE GATT) exchanges address, channel and session key. Roles are Controller and Controlee. Accuracy is described as "to an accuracy of 10 cm" — [Android Developers: UWB](https://developer.android.com/develop/connectivity/uwb)
- **Secure ranging:** provisioned STS (16-byte key) is "supported on all UWB-enabled devices running Android 14 or higher". Static STS (8-byte key) "is susceptible to replay/relay attacks", while provisioned STS mitigates them — [Android Developers: UWB](https://developer.android.com/develop/connectivity/uwb)
- Supported phones as of Jan 2025: **Pixel 6 Pro and newer, Pixel Fold, Pixel Tablet; Motorola Edge 50 Ultra; Samsung Galaxy Note 20, S21 and newer, Z Fold2 and newer**. Background ranging is unsupported on several of these. Jetpack-compatible partner kits (as of Apr 2023): Estimote UWB Development Kit and Mobile Knowledge MK UWB Kit Mobile Edition 2.0 — [Android Developers: UWB](https://developer.android.com/develop/connectivity/uwb)
- Google confirmed UWB precision finding is enabled only on **Pixel 8 series and later** (Oct 2025) — [Android Authority](https://www.androidauthority.com/older-pixel-phones-uwb-precision-finding-3610901)
- Android UWB phones are mainly the Samsung Galaxy S/Z lines and Pixel Pro, plus Motorola Edge/Razr. Xiaomi coverage is weak (Mix 4, 2021) (via search summary) — [Wikipedia: List of UWB-enabled mobile devices](https://en.wikipedia.org/wiki/List_of_UWB-enabled_mobile_devices); [NAOJ UWB devices list](https://prc.nao.ac.jp/freqras/EN_UWB_devices.html)
- **Penetration:**
  - ABI: UWB smartphone penetration grew from 21% (2022) to 25% (2023), "driven by Apple and Samsung", with "other large-scale smartphone vendors yet to adopt UWB" (via search summary) — [ABI Research insight](https://www.abiresearch.com/market-research/insight/7784160-nearly-5-years-after-the-first-uwb-smartph?hsLang=en)
  - A secondary source citing ABI gives 27% in 2025 — [ib-lenhardt UWB market](https://ib-lenhardt.com/market-insights/uwb-shipments)
  - Counterpoint: 19% global in Q2 2023 — [Counterpoint](https://counterpointresearch.com/?p=1031832)
  - ABI's 2020 forecast of about one-third by 2025 was optimistic — [ABI press release](https://abiresearch.com/press/apple-and-samsungs-early-uwb-smartphone-entry-spurs-adoption-to-nearly-one-third-of-all-smartphone-shipments-by-2025)
- India: premium (₹30k+) = 22% of 2025 shipments — [GSMArena/Counterpoint](https://www.gsmarena.com/counterpoint_1_in_5_smartphones_shipped_in_india_in_2025_were_premium_models-news-71366.php)
- **Anchor hardware:**
  - Qorvo DWM3001CDK is "interoperable with the Apple U1 & U2 chip" and FiRa PHY/MAC compliant. No Android/Jetpack claim was found. Price: **US$29.50** (qty 1–24) at RFMW; Farnell DE listing about €27.37 (shown as "27,370 €", German decimal format), out of stock; element14 KR ₩41,737 — [Qorvo DWM3001CDK](https://www.qorvo.com/products/p/DWM3001CDK); [RFMW](https://rfmw.com/products/detail/dwm3001cdk-qorvo/692466/); [Farnell](https://de.farnell.com/qorvo/dwm3001cdk/dev-kit-ultra-breitband-transceiver/dp/4683746); [FiRa product brief](https://www.firaconsortium.org/sites/default/files/2024-08/DWM3001CDK%20Product%20Brief.pdf)
  - Makerfabs ESP32 UWB (DW1000) listed at **US$39.80**. A hobbyist reported ±10 cm in a 10×10 m room, and another user saw ≤10 m indoor LOS range. The newer MaTouch ESP32-S3 MaUWB board is **US$59.80**. The DW3000 variant is advertised as able to talk to an Apple AirTag — [Hackster](https://hackster.io/news/makerfabs-arduino-compatible-esp32-usb-module-takes-aim-at-accurate-indoor-positioning-3f4b1a5967a3); [Arduino forum](https://forum.arduino.cc/t/affordable-indoor-positioning-using-esp32-uwb-modules/957727); [Notebookcheck](https://www.notebookcheck.net/Makerfabs-MaTouch-ESP32-S3-UWB-enables-sub-meter-indoor-positioning.1364946.0.html); [CNX Software 2026](https://cnx-software.com/2026/08/09/matouch-esp32-s3-mauwb-board-integrates-3-95-inch-touchscreen-and-uwb-module-for-indoor-positioning-and-ranging/)
- **Walls / NLOS:**
  - Through a concrete wall or human-body shadowing, Decawave/3db ranging errors were about **44–60 cm** (via search summary) — [arXiv 2104.11042](https://arxiv.org/pdf/2104.11042)
  - Two 10 cm concrete walls add about **1 ns** (about 30 cm) when the direct path survives. When the direct path is blocked, the receiver locks onto reflections, giving errors of "a few meters" (via search summary) — [arXiv 2404.15314](https://arxiv.org/pdf/2404.15314)
  - An older patent reports about 1 ft bias and about 10 in RMS through concrete — [US 7962150](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/7962150)
  - NLOS mitigation cut range RMSE from 0.77 m to 0.33 m — [EUSIPCO 2017](https://new.eurasip.org/Proceedings/Eusipco/Eusipco2017/papers/1570345025.pdf)
- **Flutter:** `flutter_uwb` 1.0.2 (verified publisher ahmedhamdan.com) lists Android↔Android stable and iPhone↔Apple-FiRa accessory (Qorvo/NXP) stable. **No Android↔accessory pairing is listed.** Android needs a Pixel 6 Pro+ or Galaxy S21 Ultra+ / `FEATURE_UWB`, with Android 14+ recommended. About 163 downloads — [pub.dev flutter_uwb](https://pub.dev/packages/flutter_uwb)

### Inferences
- **Containment:** with 3–4 anchors at the room's corners, 10–30 cm ranging plus multilateration can decide "inside polygon vs outside". This is the one RF technology here that can follow a wall. The wall's added delay (+30–60 cm) actually biases outside phones further away, which helps. Provisioned STS (Android 14+) gives cryptographic relay resistance that BLE, Wi-Fi and QR lack.
- **Feasibility for this project:** very low. (1) Almost no sub-₹30k Android phones in India have UWB. Given that premium is 22% of shipments and UWB within premium Android is a subset, I would guess well under 10% of a college staff's phones, but that is an estimate. (2) The DW1000 (Makerfabs ESP32 UWB) is the older pre-FiRa standard, which I believe cannot range with phones; this is my own understanding and was not verified. (3) DWM3001C/DW3000 anchors cost about ₹2,600 to ₹5,300 each (US$29.50–59.80), and 3–4 are needed. (4) No documented Jetpack interop with Qorvo kits. The documented partners are Estimote and MK. (5) A custom FiRa stack is a large firmware job for a student team.
- Possible niche: a "UWB fast path" for staff who own UWB flagships, with fallback to other methods.

### Gaps
- No India-specific UWB phone penetration figure was found.
- No public demo of Android Jetpack UWB ranging to a Qorvo DWM3001CDK or an ESP32+DW3000 board was found.
- Indian retail prices for DWM3001CDK or DW3000 modules were not found.

---

## 4. NFC tap points (ESP32 + PN532 reader with phone HCE, or dynamic NFC tag such as NTAG 424 DNA)

### Takeaway
NFC works only within a few centimetres, so a tag or reader mounted inside the room physically cannot be reached from outside the wall. This is the strongest cheap physics-based room proof. Remaining risks: phones without NFC (common in sub-₹15–20k Indian phones until about 2025), and relay attacks (NFCGate). A relay still needs an accomplice physically inside the room. Pair it with a server-verified dynamic code (NTAG 424 DNA SUN, or an ESP32 nonce plus a phone signature via HCE) and the existing face check.

### Cited Findings
**Android NFC / HCE**
- HCE is supported on **Android 4.4 (API 19)+**. Services extend `HostApduService`, and APDUs are routed by AID (ISO 7816-4) over ISO-DEP/NfcA. Only the OS can bind (`BIND_NFC_SERVICE`). **"HCE devices use random UIDs on each tap", so readers shouldn't use the UID for authentication.** Recommended exchange is about 1 KB (about 300 ms). Android 10+ "Secure NFC" disables card emulation when the screen is off. Feature check: `FEATURE_NFC_HOST_CARD_EMULATION` — [Android Developers: Host-based card emulation](https://developer.android.com/develop/connectivity/nfc/hce)

**NFC availability on Indian budget phones**
- Samsung Galaxy M16 5G (India, early 2025) brought Wallet Tap & Pay "to the budget segment for the first time". The Galaxy M06 5G "lacks NFC connectivity" — [SamMobile](https://www.sammobile.com/?p=16599540)
- A reader comment (anecdotal) says phones in India "rarely come with NFC at the sub 20k range… This is changing fast though, most of the 2025 releases have NFC" — [GSMArena Galaxy M36 reviews](https://www.gsmarena.com/samsung_galaxy_m36_5g-reviews-13967p3.php)
- The Indian Galaxy M56 has NFC (reviewer note) — [GSMArena M56 reviews](https://m.gsmarena.com/samsung_galaxy_m56_5g-reviews-13801p4.php)
- An older reader claim says the Poco X3's Indian variant dropped NFC — [GSMArena comments](https://www.gsmarena.com/newscomm-63664.php)
- No reliable NFC share figure for Indian phones was found. India NFC market revenue was US$879.2 M in 2025 (revenue, not device penetration) — [IMARC](https://www.imarcgroup.com/india-near-field-communication-market)

**Dynamic tags**
- NXP NTAG 424 DNA: "SUN authentication mechanism upon each read-out by an NFC enabled mobile device", i.e., a cryptographically fresh URL/CMAC per tap — [NXP NTAG 424 DNA](https://www.nxp.com/products/rfid-nfc/nfc-hf/NTAG424DNA)
- Chip prices: element14 Taiwan NT$11.28 at 30,000+ qty (about US$0.35) — [element14 TW](https://tw.element14.com/en-TW/nxp/nt4h2421g0da8-02j/nfc-rfid-tags-transponders-nfc/dp/4784260). Alibaba bare chip €0.20–0.23 at 5,000 MOQ — [Alibaba](https://spanish.alibaba.com/f/nxp_67.html). Finished-tag retail varies widely — [usmartcards NTAG 424 DNA](https://www.usmartcards.co.uk/ntag-424-dna)

**Relay attacks**
- **NFCGate** (TU Darmstadt, 2015) relays NFC between card and reader using "two rooted but otherwise unmodified Android phones", extending card–reader distance. It works on ISO 14443-3 systems "not hardened against relay attacks". An extended toolkit adds replay, modification, and latency measurement for countermeasures — [TU Darmstadt tuprints: NFCGate](https://tuprints.ulb.tu-darmstadt.de/5414); [NFCGate toolkit paper](https://astro.paperswithcode.com/paper/nfcgate-opening-the-door-for-nfc-security)
- ESET's "NGate" malware used NFCGate to relay victims' payment cards for ATM cash-outs — [Help Net Security](https://www.helpnetsecurity.com/?p=309780); [ID Stronghold](https://www.idstronghold.com/es/blogs/rfid-news/ngate-and-nfc-relay-threats)

**Flutter**
- `nfc_host_card_emulation` 1.1.0 (Android only, MIT): HCE with SELECT-AID APDU handling — [pub.dev nfc_host_card_emulation](https://pub.dev/documentation/nfc_host_card_emulation/latest/)
- `nfc_pro_manager` claims HCE plus ISO-DEP, min SDK 30, and says `nfc_manager` lacks HCE (self-claim) — [pub.dev nfc_pro_manager](https://pub.dev/documentation/nfc_pro_manager/latest/)
- `nfc_util` lists reader, NDEF and HCE — [pub.dev nfc_util](https://pub.dev/documentation/nfc_util/latest/)

### Inferences
- **Two designs:**
  - **(a) Phone reads a dynamic tag** (NTAG 424 DNA SUN, about ₹30–100 per chip, no ESP32 needed). The app sends the SUN URL (UID, counter, CMAC) to the server, which verifies the CMAC and that the counter is strictly increasing, then binds it to the face-verified session.
  - **(b) ESP32 + PN532 reads the phone (HCE).** The ESP32 sends a fresh nonce APDU, the phone signs it with a Keystore key enrolled to the staff member, and the ESP32 (or phone) uploads it for server verification. This fits the existing ESP32 token-generation firmware.
- **Containment:** 2–4 cm read range means the phone must be inside the room at the tap point; walls do not matter. This is far stronger than BLE.
- **Proxy/relay:** to fake a tap, an outsider needs an accomplice inside the room relaying the tag/reader exchange (NFCGate needs rooted phones). If the accomplice is already inside, the face-recognition step must stop them from marking for the absent person. Tightening the HCE response-time budget on the ESP32 raises the bar against relays, but needs testing. A dynamic tag also stops "photograph/copy the tag" attacks, which defeat static NDEF tags and static UIDs.
- **UX:** one tap is about 1 s. Staff need NFC turned ON (many Indian users keep it off). HCE needs the screen on, and unlocked when Secure NFC is enabled.
- **Coverage:** a fallback is required for staff phones without NFC (for example rotating QR, below).

### Gaps
- No reliable percentage of Indian smartphones (or of sub-₹15k models) with NFC was found.
- PN532 module retail price in India (Robu etc.) was not found in sources.
- No measured NFCGate relay latency figure was retrieved to set an ESP32 timeout.

---

## 5. Visible light / infrared: phone camera reading a blinking LED (optical camera communication), IR

### Takeaway
Light does not pass through opaque walls, so camera-based optical links are strong line-of-sight proofs. Phone cameras can decode LED blink codes via the rolling shutter at about 1–10 kb/s over about 3 m, but these are lab prototypes and Flutter implementation effort is high. A rotating QR on a screen (section 6) gets most of the same benefit far more easily. IR is not practical: I found no evidence of usable IR receivers on phones.

### Cited Findings
- Software-only rolling-shutter decoding with slow-motion video reached **up to 3 m and >1,200 b/s** (Schmid et al., 2016 ACM workshop) (via search summary) — [CPS-VO: Using Smartphones As Continuous Receivers in a VLC System](https://archive.cps-vo.org/node/38847)
- A single phosphor white LED gave **>5 kbit/s** net (Optics Express 2016) (via search summary) — [NYCU repository](https://ir.lib.nycu.edu.tw/handle/11536/134289)
- Record **10.32 kb/s** phone-based VLC (2017). Data rate is limited by sensor frame rate and rolling-shutter processing gaps (via search summary) — [NYCU repository](https://ir.lib.nycu.edu.tw/handle/11536/144048?mode=full)
- A 2022 TU Delft/ACM model estimates LED-to-camera range and data rate for binary and rolling-shutter modes — [TU Delft BodySys22](https://www.st.ewi.tudelft.nl/marco/files/BodySys22_Omer_.pdf)
- Phone-flash-to-photodiode link: 80 cm, extendable to 1.5 m — [ERJSH](https://erjsh.journals.ekb.eg/article_398949.html)

### Inferences
- **Design:** an ESP32 drives an LED (or LED strip) with a short TOTP-like code using on-off keying above the flicker-fusion rate. The app opens the camera (already used for face recognition) and decodes the stripes.
- **Containment:** excellent (opaque walls block it). Windows and open doors are the leak paths.
- **Replay/relay:** a phone video, or a live video call, of a slowly blinking LED could be replayed to a camera. Fast rolling-shutter-rate modulation (kHz) is unlikely to survive video compression at 30 fps, which gives it an edge over a QR code. That is my inference and has not been tested.
- **Effort:** high. The decoder depends on exposure control, which varies across cheap camera HALs. No Flutter package was found.
- **IR:** I found no sources showing budget phones have IR receivers, and IR blasters on some phones are transmit-only. I would not pursue it, but this was not researched in depth.

### Gaps
- No product or deployed attendance system using LED-to-phone-camera codes was found.
- Robustness of rolling-shutter decoding across Indian budget camera sensors was not studied.
- IR receivers on phones were not researched with sources.

---

## 6. QR / screen-based rotating code (dynamic QR shown inside the room) as a line-of-sight method

### Takeaway
Rotating QR codes (refreshing every 1–5 s) are widely used commercially for attendance and ticketing. They block forwarded screenshots but not a live relay (an accomplice video-calling the screen within the refresh window). Combined with the face check, the BLE/Wi-Fi presence check, and very short code validity, a QR shown on an ESP32-driven display inside the room is a cheap, practical line-of-sight factor that works on every phone with a camera.

### Cited Findings
- Commercial and academic rotating-code systems (via search summary):
  - Pathway MyPath: clock-in codes refresh **every 5 s** to stop screenshot sharing — [Pathway Labs](https://pathwaylabs.notion.site/QR-Code-Attendance-Class-Level-198932b1ac788088952fc29c243030a4)
  - Rutgers Qwickly: code changes every few seconds — [Rutgers ATS](https://ats-techdocs.rutgers.edu/m/98237/l/1971562-taking-attendance-check-in-with-qr-code)
  - Celebratix tickets: move every **3 s** — [Celebratix](https://help.celebratix.io/en/articles/12087457-why-can-t-i-take-a-screenshot-of-my-ticket)
  - Diobox: new code every second — [Diobox](https://help.d.io/en/articles/11638920-temporal-qr-codes)
  - Classter: admin-set refresh interval; old code invalid after refresh — [Classter KB](https://help.classter.com/kb/attendance-taking/interval-in-seconds-to-refresh-qr-code/)
  - Poll Everywhere: codes valid **20 s**, not reusable — [Poll Everywhere](https://support.polleverywhere.com/hc/en-us/articles/46711080694555-Checking-in-with-Rotating-Codes-For-Students)
  - SwipePoint: dynamic QR clock-in — [SwipePoint](https://en.swipepoint.app/function_clockin_dynamic_qrcode-en.php)
- Academic prototype: each QR invalid after **5 s**, screenshots disabled, **7,900 unique scans over 7 weeks** (via search summary) — [Maratto](https://www.maratto.africa/research/design-and-implementation-of-an-enhanced-qr-code-d783ffbc56)
- Nwabuwe et al. (IJACSA 2023, UEA): dynamic QR + **geofencing (venue polygon encoded in the QR)** + **device IMEI binding**. The authors report attacks were "effectively mitigated" (via search summary; PDF not fetchable) — [UEA research portal](https://research-portal.uea.ac.uk/en/publications/fraud-mitigation-in-attendance-monitoring-systems-using-dynamic-q/); [UEA ePrints PDF](https://ueaeprints.uea.ac.uk/93712/1/Paper_104_Fraud_Mitigation_in_Attendance_Monitoring_Systems.pdf)
- Indonesian prototype: expired tokens make a photographed QR unusable after the session. Tested with 12 scenarios and 20 respondents — [Garuda](https://garuda.kemdiktisaintek.go.id/journal/view/9601?page=22)
- The QR-forwarding weakness is named directly: classmates "can forward the URL" to absent students — [Overleaf attendance paper](https://nl.overleaf.com/articles/sleepers-attendance/mzdtppfkxmwh.pdf)
- PayPal patent **US 11,687,910**: splits a QR into interlaced frames synced to the display refresh rate, so a single photo or screen recording does not capture the full code (designed for payments) — [Google Patents US11687910](https://patents.google.com/patent/US11687910)

### Inferences
- **Fit:** an ESP32 + small TFT/OLED/e-paper display (or an old Android tablet) inside the staff room shows a QR of the same HMAC/TOTP token the ESP32 already generates. The app scans it with the camera already open for face recognition and submits token, face result and BLE observation together. This works on 100% of camera phones, unlike NFC, RTT or UWB.
- **Containment:** a solid wall blocks the view. Placement must avoid windows and the doorway sightline.
- **Attacks:** a screenshot or forward is defeated by 2–5 s validity plus single-use server checks. A **live relay** (accomplice inside streams the screen over WhatsApp video) is still possible within the window, so the defence must come from the face check plus binding the scan and the selfie into one continuous camera session. Shorter validity (1–2 s) and the frame-interlacing idea raise the cost of relay.
- **Effort:** low to moderate (ESP32 display firmware plus `mobile_scanner`-type QR scanning in Flutter, plus server validation). Hardware: ESP32 plus a small display, roughly a few hundred rupees (not sourced).

### Gaps
- No quantitative study of live video relay success against rotating attendance QR codes was found.
- No independent evaluation of the Nwabuwe et al. claims was found.

---

## 7. Magnetic field fingerprinting, barometer (floor detection), ambient light, and sensor fusion

### Takeaway
These on-phone sensors can tell floors apart (barometer about 0.5 m relative altitude; magnetic/barometric floor identification over 96%). They cannot reliably tell "inside the staff room" from "just outside its wall" on the same floor. Every reading is self-reported by the app, so a modified client can fake it. Useful only as a supporting signal: for example, if the staff room is on an upper floor and the attacker is at ground level outside the compound wall, a barometer delta against an ESP32 reference barometer could flag them.

### Cited Findings
- Barometer: a single phone detected **floor changes and their mode (elevator/escalator/stairs) with nearly 100% accuracy** across 3 devices in 7 buildings. **Absolute pressure is an unreliable floor indicator**, but pressure differences between floors vary much less across time and phone models (HotMobile 2014) — [Microsoft Research HotMobile14](https://microsoft.com/en-us/research/wp-content/uploads/2016/02/hotmobile14b.pdf)
- Crowdsourced 6-month study: always predicted the correct number of floors, with **average altitude error 0.5 m** — [PMC5855158: Dynamic Vertical Mapping with Crowdsourced Smartphone Sensor Data](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5855158/)
- Using **multiple (reference) barometers** to detect phone floor location — [PMC4431287](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4431287/)
- Magnetic-field floor identification outperformed barometric and Wi-Fi methods across Galaxy S8, LG G6 and LG G7 (Ashraf et al. 2019) — [PMC6603673](https://pmc.ncbi.nlm.nih.gov/articles/PMC6603673)
- FTrack: over 96% floor identification using only phone sensors in 3 buildings. Magnetic fingerprinting "requires more site-survey effort" than Wi-Fi. One cited study found it "difficult" to determine the actual floor from a phone barometer — [JCST FTrack paper](https://jcst.ict.ac.cn/cn/article/pdf/preview/10.1007/s11390-015-1597-z.pdf)
- MagicFinger (3D magnetic fingerprints): its authors note that a phone alone limits accuracy — [PMC4541928](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4541928/)
- Survey of magnetic indoor localization — [MDPI Electronics 11(6):864](https://0-www-mdpi-com.brum.beds.ac.uk/2079-9292/11/6/864)
- Best fused smartphone systems at IPIN 2023 had a third-quartile error of **2.8 m** — [EvAAL 2023 results](https://evaal.isti.cnr.it/2023/results)

### Inferences
- **Same-floor, same-wall containment:** not achievable with these sensors. Best smartphone fusion has third-quartile errors of 1–3 m, comparable to the wall-to-desk distance.
- **Barometer as a cheap extra factor:** a BMP280/BME280 on the ESP32 can publish a reference pressure, and the phone's pressure minus the reference can be checked against the known floor height (3–4 m per floor). This works only where an outsider would be on a different floor. Many budget phones may lack a barometer (unverified).
- **Magnetic "signature" at the tap/scan point:** possible in principle, but it needs site survey and per-phone calibration. Effort is high and gain is low.
- **Ambient light:** no evidence found. Any indoor-light pattern is easy for an outsider to imitate.
- **Security:** all of these are client-reported and spoofable with a modified APK or root. Unlike the ESP32-generated tokens (QR/NFC), they cannot be verified server-side.

### Gaps
- No room-level (same-floor) accuracy benchmark for smartphone magnetic fingerprinting was found.
- Barometer availability on Indian budget phones was not found.
- No ambient-light-based presence research was found.

---

## 8. Overall comparison for this project (ESP32 + Flutter + cheap Android, India)

### Takeaway
Ranked by **wall-proof containment × works on cheap phones × effort**: (1) **NFC tap point** (physics-limited to centimetres, server-verifiable, about ₹100–500 of hardware, needs an NFC phone). (2) **Rotating QR on an in-room ESP32 display** (line of sight, every phone, low effort, live-relay risk handled by the face check). (3) LED/camera optical code (wall-proof, but high effort). Wi-Fi BSSID/RSSI and Wi-Fi RTT do not solve the wall problem. UWB solves it technically but needs flagship phones. Barometer/magnetic work only as weak supporting signals.

### Cited Findings
- Wi-Fi leaks through walls at 6–25 dB loss — [USPTO 11388680](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11388680); [IEICE](https://ken.ieice.org/ken/paper/20091217ZarQ/eng/)
- RTT accuracy is about 1–2 m at best with commercial APs, and ESP32 responders are poor at short range and flagged as "very low" accuracy with phones — [Android Wi-Fi RTT](https://developer.android.com/develop/connectivity/wifi/wifi-rtt); [esp-idf #6810](https://github.com/espressif/esp-idf/issues/6810); [arXiv 2303.03766](https://arxiv.org/html/2303.03766v1)
- UWB is accurate to about 10 cm with STS secure ranging, but only on Pixel Pro/8+, Galaxy S/Fold and Moto Edge 50 Ultra — [Android UWB](https://developer.android.com/develop/connectivity/uwb)
- NFC HCE works on Android 4.4+. The relay toolkit needs two rooted phones and an accomplice at the reader — [Android HCE](https://developer.android.com/develop/connectivity/nfc/hce); [NFCGate](https://tuprints.ulb.tu-darmstadt.de/5414)
- Rotating QR is widely deployed with 1–5 s refresh — [Pathway](https://pathwaylabs.notion.site/QR-Code-Attendance-Class-Level-198932b1ac788088952fc29c243030a4); [Diobox](https://help.d.io/en/articles/11638920-temporal-qr-codes)

### Inferences
Summary table. Costs are approximate. Containment ratings are my synthesis of the sources above.

| Technology | Room containment (wall-proof?) | Typical accuracy | Cheap Indian Android support | Hardware cost | Effort (ESP32+Flutter) | Proxy/relay resistance |
|---|---|---|---|---|---|---|
| Wi-Fi BSSID / connect-to-AP | No: leaks through walls (6–25 dB loss) | Range only, tens of metres | ~100% (needs Location ON) | ₹0 (use ESP32 SoftAP or existing AP) | Low | Low: BSSID cloneable |
| Wi-Fi RSSI fingerprinting | No (metre-level, 1–3 m) | 1–3 m | ~100% | ₹0 to a few ESP32s | Medium (site survey) | Low: client-reported |
| Wi-Fi RTT (FTM) to ESP32 | Weak: distance radius, not a wall | 1–2 m with good APs; worse with ESP32 | Partial: some Galaxy A, older Redmi Note; unknown share | ESP32-S3/C3(rev3)/C6 board | High (interop bugs, calibration) | Low–medium: client-reported |
| UWB (FiRa, STS) | Yes, with 3+ anchors | 10–30 cm (+30–60 cm through concrete) | Very low (flagships only) | ~US$30–60 per anchor (₹2.6k–5.3k) | Very high | High (provisioned STS, Android 14+) |
| NFC tap (NTAG 424 DNA or ESP32+PN532 HCE) | Yes (cm range) | Binary at tap point | Many 2025 budget phones; older sub-₹20k often lack NFC | Tag <₹100; PN532 module (price not sourced) | Low–medium | Medium–high: dynamic crypto; relay needs accomplice in room + root |
| Rotating QR on in-room display | Yes (line of sight; watch windows/doors) | Binary | ~100% (camera) | ESP32 + small display | Low | Medium: screenshot-proof; live video relay possible |
| LED/camera optical code | Yes (line of sight) | Binary, ~3 m range | ~100% in theory; decoding varies by camera | LED + ESP32 | High | Medium–high (fast modulation hard to relay; untested) |
| Barometer / magnetic / light | No (floor-level only) | Floor ±0.5 m vertical; 1–3 m horizontal | Barometer often missing on budget phones (unverified) | BMP280 reference (cheap) | Medium | Low: client-reported |

- **Recommended combination (inference):** keep BLE as a coarse "nearby" signal. Add an **in-room line-of-sight or contact token generated by the ESP32**: NFC where the phone supports it, rotating QR otherwise. Verify it **server-side** and bind it to the **same camera session as the face match**. This turns "outside the wall" from easy into needing an accomplice inside the room, which face recognition then has to defeat.

### Gaps
- No single source compares these technologies head-to-head for attendance; the table is a synthesis.
- India-specific phone feature shares (NFC, RTT, barometer, UWB) remain unquantified in public sources found.
