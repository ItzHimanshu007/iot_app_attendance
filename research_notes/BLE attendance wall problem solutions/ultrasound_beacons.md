# Acoustic (near-ultrasonic) proximity beacons to prove a phone is inside the staff room

Scope: should the ESP32 staff-room beacon also emit an inaudible or near-inaudible 17–20 kHz code that the Flutter app records, decodes and sends to the server? This would block someone outside the wall who can still receive BLE.

Research note: many primary-source domains (arxiv.org, source.android.com, help.webex.com, data.epo.org, nccgroup.com, sonitor.com, espressif docs) could not be fetched from this sandbox because the egress proxy denied them. Findings from those sources come from search-engine extracts of their abstracts and pages, and are marked "(abstract/extract)". GitHub and pub.dev were fetched directly, so ggwave source code and Flutter package metadata are verified first-hand.

Project context: the existing firmware already computes `token = HMAC-SHA256(BEACON_SECRET, "<beacon_id>:<unix_time / 30>")[0..7]` with a 30 s window and Wi-Fi time sync, and puts the token in the BLE advert — [firmware/staff_beacon/staff_beacon.ino](/home/user/iot_app_attendance/firmware/staff_beacon/staff_beacon.ino). An acoustic code could be derived from the same mechanism.

---

## Q1. How much do walls, doors and glass attenuate 17–22 kHz sound compared with 2.4 GHz radio? Does near-ultrasound stay inside a room?

### Takeaway
Solid walls block near-ultrasound far better than they block 2.4 GHz. Radio loses only about 3–12 dB through drywall, glass, wooden doors or brick, while sound insulation rises about 6 dB per doubling of frequency, so 18 kHz is blocked even better than the audible band. In practice, though, leakage paths decide containment: an open door, door gaps, open windows and ventilation. Vendors that use this commercially (Cisco, Shopkick, Google) state that it confines to a room only when doors are closed, and Cisco's own legal text says an open door can let it through.

### Cited Findings
**Radio (BLE/Wi-Fi 2.4 GHz) through building materials**
- CWNA study-guide figures at 2.4 GHz: drywall ~3 dB, non-tinted glass ~3 dB, wood door ~3 dB, brick/concrete/block ~12 dB, foundation wall ~15 dB (second-hand forum reproduction) — [Aruba community / CWNA table](https://community.arubanetworks.com/viewthread?MID=17983)
- A 2025 practical design note gives plasterboard 2–4 dB, timber stud wall 4–6 dB, single clear glass 2–3 dB, 90–110 mm brick 8–12 dB, 150 mm concrete 12–20 dB, solid-core fire door 10–15 dB — [Zencontrol design note](https://support.zencontrol.com/hc/en-us/articles/13691317355919-Wireless-Thread-Signal-Strength-Path-Loss-Practical-Design-Note)
- A router vendor gives a 15 cm interior wall at 15–20 dB and a 30 cm bearing wall at 20–25 dB (approximate) — [Keenetic](https://help.keenetic.com/hc/en-us/articles/213968869)
- An empirical BLE room-level localization study got only 70–90% room accuracy in house and university settings, which illustrates how poorly BLE respects room boundaries — [Sensors/PMC 2021](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8197460/)

**Sound through walls (physics)**
- Mass law: sound reduction of a single wall rises about 6 dB per doubling of surface mass *or* of frequency. Above the coincidence dip it climbs faster, quoted as about 12 dB/octave (Ballagh) or about 9 dB/octave under damping control (COMSOL docs) — [Ballagh, NZ Acoustics 2003](https://www.acoustics.org.nz/sites/www.acoustics.org.nz/files/journal/pdfs/Ballagh,_K_NZA2003.pdf); [Insul tech info](https://www.insul.s05.system7.co.nz/tech-info/); [COMSOL TL model](https://doc.comsol.com/6.1/doc/com.comsol.help.models.aco.sound_transmission_loss_concrete/sound_transmission_loss_concrete.html)
- Standard lab ratings (ASTM E90/E413, ISO 10140) usually report only up to about 5 kHz, so no rated wall or door data exists at 16–20 kHz — [search synthesis of door-TL literature; see Trustile](https://www.trustile.com/technical-information/understanding-stc-ratings)

**Leakage through gaps and doors (dominant at high frequency)**
- 1/8-inch edge clearances cut an STC-52 door's effective rating to STC-21, and the loss is "especially serious at medium to high frequencies" (door vendor) — [Trustile STC guide](https://www.trustile.com/technical-information/understanding-stc-ratings)
- In a wooden-door study, leakage increased with both frequency and gap size and significantly degraded mid- and high-frequency insulation — [PMC 2025 wooden doors](https://pmc.ncbi.nlm.nih.gov/articles/PMC12307673/)
- A building-airtightness patent rests on the same principle: walls pass sound mainly near their resonance, but an opening lets other frequencies through — [EP3551985B1](https://patents.google.com/patent/EP3551985B1/en)
- A 40 kHz ultrasonic leak-finding case study found a single-pane glass window "offered little resistance" to the ultrasonic wave (note: 40 kHz, not 18 kHz, and probably leakage around the frame) — [Pico Technology app note](https://www.picotech.com/library/articles/application-note/soundproofing-a-room-using-a-picoscope)

**What deployed ultrasound-proximity systems say about containment**
- Google (Getreuer et al., IEEE Trans. Multimedia 2018): "high-frequency sound is largely reflected by walls," so devices identified this way are effectively limited to the same room (abstract/extract) — [Ultrasonic Communication Using Consumer Hardware](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware)
- Cisco Proximity help: Proximity "doesn't work outside the meeting room when doors to the room are closed" — [Webex Help: Cisco Proximity App](https://help.webex.com/en-us/article/b5c5rab/Install-and-Use-the-Cisco-Proximity-App)
- Cisco's legal privacy supplement: "If you can hear speech from outside a room, for instance through an open door, your Client may be able to detect the ultrasound audio pairing message and initiate a connection" — [Cisco Proximity privacy supplement](https://www3-realm.cisco.com/web/siteassets/legal/proximity-supplement.html)
- A Cisco employee on the Cisco community said to make sure the room "is not leaking ultrasound audio out of open cracks," to use a phone spectrum-analyzer app to find leaks, and that "not a lot of mass is needed" to stop ultrasonic audio — [Cisco Community thread](https://community.cisco.com/t5/cisco-proximity/security-of-content-sharing-with-proximity-feature/td-p/2882535)
- An EPO patent application (not Cisco) states that ultrasound is strongly attenuated by walls, doors, floors and ceilings, which keeps signals in the same room, and that 18–20 kHz works well (extract) — [EP3790280 A1](https://data.epo.org/publication-server/rest/v1.2/patents/EP3790280NWA1/document.html)
- Shopkick's in-store audio beacon: phones could pick up the signal "from up to 150 feet away," and "the nature of buildings" confined it to inside the store (2010) — [MIT Technology Review](https://www.technologyreview.com/s/420582/bringing-cell-phone-location-sensing-indoors/)
- An academic indoor-positioning paper states that ultrasonic systems suit room-level work "as walls confine acoustic waves inside" (a design claim, not a measurement) — [LOCATE-US, Sensors/PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8001629/)

### Inferences
- For a closed masonry room, the acoustic margin between "inside" and "outside the wall" should be tens of dB larger than the 3–12 dB a BLE signal loses. That is exactly the asymmetry the team needs.
- The weak points in a typical Indian college staff room are the **open door** (often propped open), **open windows / jaali vents**, gaps under doors, false ceilings, and glass partitions. Cisco's own wording ("open door → may be detected") means a person standing in the corridor near an open door must be assumed able to decode the signal at default volume.
- Mitigations within the team's control: (a) place the tweeter on the wall *opposite* the door, aimed into the room; (b) set the emission level per room (Cisco also tunes volume per room — see Q2) so decoding just covers the room; (c) reject decodes whose in-band SNR is below a threshold calibrated inside the room; (d) put the rule "attendance only counts with the door closed" in policy if possible.
- Mass-law arithmetic (inference, not measured): going from 4 kHz to 18 kHz is just over 2 octaves, so an ideal limp wall would gain about 13 dB of extra insulation. Real walls are stiff and leaky, so treat this as an upper bound.

### Gaps
- No measured transmission-loss values at 16–20 kHz were found for any specific wall, door or glass type. Lab standards stop near 5 kHz. The team should measure on site: put a phone spectrogram app outside the closed door, outside the open door and behind the wall, and log the SNR at 18–19 kHz.
- No independent study found that quantifies "open door vs closed door" decode probability for near-ultrasound.

---

## Q2. Existing products and research: what room-level accuracy do they report?

### Takeaway
Near-ultrasound co-presence is a proven, shipped technique: Google Nearby, Cisco Proximity/Webex, Zoom Rooms, Shopkick, LISNR and Chirp all used it. Most consumer data-over-sound SDKs have since been discontinued or acquired, though. No product publishes an independent "room-level accuracy %" for phone-based near-ultrasound. Sonitor claims "100% room-level," but that is vendor marketing for dedicated tags and infrastructure, not phones. No peer-reviewed ultrasound *attendance* evaluation with numbers was found. There is one 4-page APNOMS 2019 paper whose content could not be retrieved.

### Cited Findings
**Google Nearby (near-ultrasound "copresence" token)**
- 18.5–20 kHz band, "inaudible to most humans," direct-sequence spread spectrum with a 127-chip pseudorandom code per symbol (robust to multipath and narrowband noise), **raw rate 94.5 b/s**, transmission between phones **reliable at 2 m, often works at 10 m** in real indoor settings. It was part of Google's Nearby platform for sending a short token (abstract/extract) — [Getreuer, Gnegy, Lyon, Saurous, IEEE TMM 2018](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware)
- Nearby Messages is deprecated and "will stop working as of December 2023"; Google points to Nearby Connections instead — [Google Nearby developer page](https://developers.google.com/nearby)

**Cisco Proximity / Webex**
- Endpoint speakers must reliably produce sound in about the **20–22 kHz** range (Cisco employee) — [Cisco Community](https://community.cisco.com/t5/cisco-proximity/how-does-proximity-works-in-an-integrated-system-environment/m-p/3728389/highlight/true)
- Cisco's help says some rooms work better at lower ultrasound volume depending on size and acoustics, recommends per-room testing and a spectrogram app for troubleshooting (extract) — [Webex Proximity Troubleshooting Guide](https://help.webex.com/en-us/WBX9000031718/Webex-Meetings-Desktop-App-Proximity-Troubleshooting-Guide)
- Works only inside when doors are closed; an open door may leak (see Q1). The ultrasonic modem "is not designed to cater for multiple senders"; you normally pair with the closest device, and tuning volume helps — [Cisco Community: multiple endpoints](https://community.cisco.com/t5/cisco-proximity/any-plans-to-allow-multiple-proximity-endpoints-in-the-same-room/td-p/3024654)
- Cisco has discontinued development of the standalone Cisco Proximity app — [Webex Help](https://help.webex.com/en-us/article/b5c5rab/Install-and-Use-the-Cisco-Proximity-App)

**Zoom Rooms**
- The Zoom Room controller emits an ultrasonic signal that the desktop client detects with its selected microphone. The signal only broadcasts a sharing key, and there is a manual "Sharing Key" fallback — [Zoom dev forum](https://devforum.zoom.us/t/ultrasonic-connection/3318)
- Zoom's vendor test spec: at **5 m** the ultrasonic level should be **>30 dB** with a **98% success rate**, and the signal "should not be heard within 25 cm" — [Zoom ZRC vendor doc](https://gozdm-developer.zoom.us/docs/VendorOsZRC/SupportUltrasonicProximity.html)
- A blog post reports the frequencies are "slightly audible if you have good hearing" — [digitalseams blog](https://digitalseams.com/blog/the-dial-up-modem-lives-on-in-office-meeting-rooms)
- Zoom provides no ultrasonic library or signal specification — [Zoom dev forum](https://devforum.zoom.us/t/need-api-for-proximity-sharing-from-controller/5363)

**Shopkick / shopBeacon**
- In-store transmitter broadcasts an inaudible tone carrying a store code, detected only while the app was open; range up to 150 ft; confined by buildings — [MIT Technology Review 2010](https://www.technologyreview.com/s/420582/bringing-cell-phone-location-sensing-indoors/)
- shopBeacon (2013) later added Bluetooth LE to detect the app even when closed; trialled by Macy's and American Eagle — [Wikipedia: Shopkick](https://en.wikipedia.org/wiki/Shopkick)

**LISNR**
- "Smart Tones" in **18.7–19.2 kHz**, claimed inaudible to 49 of 50 people (press report; no official spec found) — [Digital Trends](https://www.digitaltrends.com/cool-tech/lisnr-transfer-files-audio/)

**Chirp.io**
- UK data-over-sound SDK company (audible or near-ultrasonic). Sonos acquired its IP and assets on 13 Feb 2020, and the SDKs stopped being publicly available on 1 Mar 2020 — [Wikipedia: Chirp](https://en.wikipedia.org/wiki/Chirp_(company)); [audioXpress](https://audioxpress.com/news/data-over-sound-pioneer-chirp-acquired-by-sonos)

**Sonitor (hospital RTLS)**
- Vendor material claims "100% room-level, or sub room-level (bed-level)" accuracy from its ultrasound IPS (IDTechEx-hosted presentations, 2008-era) — [IDTechEx](https://www.idtechex.com/ko/event-presentation/rtls-and-indoor-positioning-systems-using-ultrasound/1107)
- The current Sense platform is described as "Room, bay or chair level accuracy" and combines ultrasound with Wi-Fi and LF. A separate BLU product is BLE with "meter-level" accuracy — [Sonitor products](https://www.sonitor.com/products)
- One location transmitter can create up to 4 zones (press release) — [Securitas Healthcare / Sonitor](https://www.securitashealthcare.com/news/securitas-healthcare-and-sonitor-partner-transform-rtls-technology)

**Research systems**
- Dhwani (Microsoft Research India, SIGCOMM 2013): acoustic NFC using the phone's speaker and mic, **up to 2.4 kbps**, about **10 cm** range, "JamSecure" self-jamming against eavesdroppers — [MSR Dhwani project](https://www.microsoft.com/en-us/research/project/dhwani/); [Phys.org](https://phys.org/news/2013-08-microsoft-india-team-peer-to-peer-acoustic.html)
- Near-ultrasonic laptop link (EUSIPCO 2021): 18–20 kHz, **4 kbps up to 5 m**, notes that built-in hardware has a non-flat response in this band (abstract/extract) — [arXiv 2103.11261](https://arxiv.org/pdf/2103.11261)
- Smartphone social-distance ranging with 18–23 kHz chirps plus single-frequency tones (Sensors 2022) — [MDPI Sensors 22(19):7345](https://www.mdpi.com/1424-8220/22/19/7345)
- Putz et al. (TU Darmstadt, ACM Trans. IoT, Feb 2026) reviewed **31** acoustic-communication studies for commodity devices, found **none** had accessible source code, re-implemented schemes, and ran **>11,000** smartphone transmissions indoors and in an anechoic chamber. They conclude that real-world conditions (distance, device model, handling, background noise) cause problems rarely seen in simulation. The dataset is on Zenodo — [arXiv 2602.02249](https://arxiv.org/abs/2602.02249v1); [ACM DOI 10.1145/3779439](https://dl.acm.org/doi/10.1145/3779439)
- **Attendance-specific:** Kim, Mun, Lee, "A Data-Over-Sound Application: Attendance Book," APNOMS 2019, pp. 1–4, DOI 10.23919/APNOMS.2019.8892996 (cited in Putz et al.; abstract not retrievable) — [arXiv 2602.02249 references](https://arxiv.org/pdf/2602.02249)
- Patent: "Systems and methods for verifying participation in a meeting using sound signals" — [US10551496](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10551496)
- A 2026 pure-Dart package, `chirp_codec`, came out of a parking app's "sound check-in" feature: 4-FSK in **18–19.2 kHz**, **16-bit payload**, Goertzel decoding from raw mic PCM — [pub.dev chirp_codec 0.1.0](https://pub.dev/packages/chirp_codec)

### Inferences
- The closest real-world analogue to the team's idea is Cisco/Zoom room pairing. Both choose near-ultrasound *because* it roughly maps to the room, both tune volume per room, both admit leakage through open doors, and both keep a manual fallback.
- The discontinuation of Chirp's public SDK, Nearby Messages and Cisco Proximity points to a mature but niche technique. A student team should rely on open-source code (ggwave, or a small custom FSK decoder), not a commercial SDK.
- No source gives a phone-based near-ultrasound "room-level accuracy %". The team would have to produce its own numbers: inside vs corridor vs adjacent room, door open vs closed, across N phone models.

### Gaps
- Sonitor's actual carrier frequencies and independent validation of "100% room-level" were not found, and Sonitor uses dedicated tags, not phones.
- The content and results of the APNOMS 2019 "Attendance Book" paper were not found.
- Putz et al.'s per-scheme bit-error-rate vs distance numbers could not be retrieved (arxiv blocked here). They are worth reading for realistic smartphone reliability.

---

## Q3. Can cheap Android phones reliably record 17–20 kHz at 44.1/48 kHz? What about Android audio sources and Flutter packages?

### Takeaway
Usually yes in the 17–19.5 kHz range, but not guaranteed. Android's CDD only *strongly recommends* near-ultrasound recording support, while the VOICE_RECOGNITION path must run at 44.1/48 kHz with no band-pass or anti-aliasing filter. Responses fall off sharply toward 20 kHz and vary by model, and some OEM drivers still apply processing on "unprocessed." Design for **18–19.5 kHz**, use `VOICE_RECOGNITION` or `UNPROCESSED` with AGC, NS and AEC off, check each phone at enrolment, and keep a fallback. The Flutter `record` package supports all of this.

### Cited Findings
- The Android CDD added section **7.8.3 "Near-Ultrasound"** (commit "CDD: Near-ultrasound and mic resampling"). Devices with a microphone are "**strongly recommended**" (not required) to support near-ultrasound recording as described in 7.8.3 — [AOSP commit](https://android.googlesource.com/platform/docs/source.android.com/+/20cdbb7%5E%21); [CDD 7.8 mirror](https://os.unplugged.com/werunplugged/unplugged-vendor/src/branch/main/compatibility/cdd/7_hardware-compatibility/7_8_audio.md)
- AOSP audio pre-processing guidance: the `VOICE_RECOGNITION` source has extra tuning requirements, including 44100 or 48000 Hz capture "**with no band-pass or antialiasing filters**," and a near-ultrasound test tied to the `SUPPORT_PROPERTY_MIC_NEAR_ULTRASOUND` property. Pre-processing effects (NS, AGC) are off by default per source in the vendor `audio_effects.xml` (extract) — [AOSP: Implement pre-processing](https://source.android.com/docs/core/audio/implement-pre-processing)
- The CTS has a two-device near-ultrasound microphone test, so OEMs that declare support are tested — [AOSP CTS near-ultrasound tests](https://source.android.com/compatibility/cts/near-ultrasound)
- Real-world caveat: a Fairphone user found that recording via the "unprocessed" input still applied a voice filter and auto-gain (likely driver misconfiguration) — [Fairphone forum](https://forum.fairphone.com/t/very-low-quality-audio-recordings/54392?page=2)
- An IIT paper on Android near-ultrasonic data links found the usable band to be about **18–20 kHz, "with some variation existing among different devices"** (extract) — [Illinois Tech ECASP 2020](https://ecasp.ece.iit.edu/publications/2012-present/2020-10.pdf)
- iPhone 7/8 mic and speaker responses "drop sharply above 20 kHz" but pass 17–19 kHz. iPhone 8 "starts to significantly attenuate signals above 19 kHz," so the authors used an **18.5 kHz** carrier (extract) — [SonicPACT, arXiv 2012.04770](https://arxiv.org/pdf/2012.04770)
- Google's 18.5–20 kHz protocol works on "commodity smartphone speakers and microphones" (abstract) — [Getreuer et al. 2018](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware)
- Researchers (TU Braunschweig study, as reported) found ultrasonic tracking listeners at 18–20 kHz in 200+ / 230+ Android apps (the reports disagree on the count), showing that ordinary Android mics capture this band in the field — [CIO.de](https://www.cio.de/article/3685682/ueber-200-android-apps-verfolgen-anwender-mit-ultraschall.html); [PC-Welt](https://www.pcwelt.de/article/1164802/werbe-tracking-per-ultraschall-in-ueber-230-android-apps.html)
- An NCC Group whitepaper found that all near-ultrasound use cases it identified used **18–24 kHz** with ordinary speakers and microphones (extract) — [NCC Group ultrasound whitepaper](https://nccgroup.com/media/00rjhgp1/_ultrasound-whitepaper-v10.pdf)

**Flutter (verified on pub.dev / GitHub, Oct 2026)**
- `record` **7.1.2** (published 2026-10-09): stream or file recording with sample-rate options. `RecordConfig` defaults are `sampleRate = 44100`, `autoGain = false`, `echoCancel = false`, `noiseSuppress = false`. `AndroidRecordConfig.audioSource` accepts `AndroidAudioSource.voiceRecognition` and `AndroidAudioSource.unprocessed` among others, plus a `useLegacy` flag — [pub.dev record](https://pub.dev/packages/record); [record source: android_record_config.dart](https://github.com/llfbandit/record/blob/master/record_platform_interface/lib/src/types/android_record_config.dart)
- `mic_stream` **0.7.2** (2025-03): raw microphone byte stream (`Stream<Uint8List>`) — [pub.dev mic_stream](https://pub.dev/packages/mic_stream)
- `ggwave_flutter` **0.0.2** (2022-09, stale): Flutter plugin wrapping ggwave — [pub.dev ggwave_flutter](https://pub.dev/packages/ggwave_flutter)
- `chirp_codec` **0.1.0** (2026-08): pure-Dart 4-FSK 18–19.2 kHz, 16-bit payload, Goertzel decoding from raw PCM, no FFI — [pub.dev chirp_codec](https://pub.dev/packages/chirp_codec)
- `flutter_modem` **0.2.0** (2026-08): pure-Dart BFSK acoustic modem — [pub.dev flutter_modem](https://pub.dev/packages/flutter_modem)
- ggwave officially ships Android bindings (`ggwave-java`, `ggwave-kmm`) and iOS, Python, JS and WASM builds; Flutter is not listed — [ggwave README](https://github.com/ggerganov/ggwave)

### Inferences
- Recommended capture: `record` → `startStream(RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 48000, numChannels: 1, autoGain: false, echoCancel: false, noiseSuppress: false, androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.unprocessed)))`. If unprocessed yields nothing above 17 kHz on a model, retry with `voiceRecognition`, which per AOSP must be unfiltered at 44.1/48 kHz.
- Keep all tones between **≈18.0 and 19.5 kHz**. This stays below the steep roll-off near 20 kHz seen on phones, below the 22.05 kHz Nyquist limit of 44.1 kHz capture, and above most adults' hearing (see Q4).
- On first login, run a **device capability check**: play a reference tone from the beacon (or ask the user to stand near it), measure SNR at 18.5 kHz, and record the result server-side per device model. Optionally read `AudioManager.getProperty("android.media.property.SUPPORT_MIC_NEAR_ULTRASOUND")` through a platform channel as a hint. The property name is from the AOSP page above; the exact Java constant name should be verified.
- Expect a tail of budget models that fail. The policy needs a fallback (e.g., face plus BLE plus a manual approval by the HOD, or a QR code displayed inside the room) rather than blocking those staff.

### Gaps
- No measured frequency-response dataset for specific *budget* Android models (Redmi, Realme, Samsung Galaxy A/M, Vivo, Oppo) at 18–20 kHz was found. PhoneMicBench (IEEE DataPort) covers 8 phones from 200 Hz to 20 kHz, but its contents could not be checked.
- The exact CDD 7.8.3 numeric limits (mean response in the 18.5–20 kHz band relative to 2 kHz) could not be retrieved. Verify them on source.android.com before quoting them.

---

## Q4. Transmitter side: can an ESP32 generate 17–20 kHz? Speakers, cost in India, audibility and safety

### Takeaway
Yes. The simplest robust path is **ESP32 → I2S at 48 kHz → MAX98357A class-D amp (₹300–500) → small piezo or dome tweeter (₹30–100)**, for under ₹600 (about US$7) on top of the existing ESP32. The built-in 8-bit DAC or LEDC PWM into a piezo also works for FSK/OOK but is cruder. The main risk is **audibility**. 15–18 kHz is audible to many young people, ggwave's default "ultrasound" protocols start at 15 kHz, and Leighton's work documents complaints such as headaches from public near-ultrasound exposure. Use 18–19.5 kHz at the lowest level that covers the room.

### Cited Findings
**Electronics**
- MAX98357A I2S class-D amp: supports sample rates **8–96 kHz**, class-D switching at **330 kHz**, frequency response spec "±0.2 dB," datasheet measurements at LRCLK = 48 kHz — [DFRobot DFR0954 wiki](https://wiki.dfrobot.com/dfr0954); [MAX98357A datasheet (Farnell)](https://www.farnell.com/datasheets/4020607.pdf)
- ESP32 built-in DAC: two **8-bit** channels on GPIO25/26, which can be fed via I2S "built-in DAC mode" DMA — [ESP-IDF v4.4 DAC docs](https://docs.espressif.com/projects/esp-idf/en/v4.4/esp32/api-reference/peripherals/dac.html); [ESP-IDF I2S docs](https://my-esp-idf.readthedocs.io/en/latest/api-reference/peripherals/i2s.html)
- Forum reports of the I2S/DAC output frequency deviating from expected settings mean the actual tone should be verified with a scope or a phone spectrogram — [esp32.com thread](https://esp32.com/viewtopic.php?p=92411)
- ggwave's ESP32 example is **receive-only**, at a 24 kHz sample rate with 512-sample frames ("only MT protocols work" at 12 kHz). It uses an analog mic (MAX9814, KY-037/038) via the 12-bit ADC or an I2S MEMS mic (SPH0645). The only microcontroller TX example is `arduino-tx` — [ggwave esp32-rx example](https://github.com/ggerganov/ggwave/tree/master/examples/esp32-rx); [ggwave README](https://github.com/ggerganov/ggwave)
- ggwave's author: the microcontroller-friendly protocols reach about **5–10 B/s at 0.5–1.0 m** and run in the **1.0–2.5 kHz** band (audible), not ultrasound (HN mirror) — [HN post by ggerganov](https://hn.nuxtjs.org/item/31987674)
- Cisco requires endpoint speakers that reliably reproduce 20–22 kHz, so speaker choice matters — [Cisco Community](https://community.cisco.com/t5/cisco-proximity/how-does-proximity-works-in-an-integrated-system-environment/m-p/3728389/highlight/true)

**Cost (India)**
- MAX98357A + INMP441 bundle on Amazon.in: **₹499** (Jul 2026), all-time low ₹299 (Apr 2026), average about ₹453 — [price-history.in](https://price-history.in/product/max98357a-i2s-3w-class-d-amplifier-8KrHoqG5)
- DFRobot MAX98357A board ≈ €6–7 / about US$7 (TME) — [TME India catalogue](https://www.tme.com/in/en/katalog/audio-video-modules_113696/)
- Piezo tweeters: **₹30** (202 piezo tweeter, IndiaMART), **₹45–95** (Sunil Electronics Delhi), ₹280 (Ahuja PA tweeter); a 20 mm piezo buzzer costs about ₹8 — [IndiaMART Sunil Electronics](https://m.indiamart.com/sunilelectronics-delhi/buzzer.html); [IndiaMART piezo speakers](https://m.indiamart.com/impcat/piezo-speaker.html); [ExportersIndia tweeters](https://www.exportersindia.com/delhi/tweeter.htm)

**Audibility and safety**
- The **20 kHz one-third-octave band spans 17.8–22.4 kHz**, and most audible-sound guidelines also apply in that range — [Leighton, Acoustics Today 2020](https://acousticstoday.org/issues/2020AT/Fall2020/files/basic-html/page17.html)
- Leighton (Southampton): public complaints of "high-pitched" sounds causing headaches were often dismissed. Smartphone-spectrogram surveys found public exposure to VHF/ultrasound in occupied buildings. About **5% of 5–19-year-olds have a 20 kHz threshold 60 dB more sensitive than the median 30–39-year-old**. Existing guidelines are mostly occupational and rest on old data — [Leighton, Public Exposure to Airborne Ultrasound (Southampton eprint)](https://eprints.soton.ac.uk/444416/1/Public_Exposure_to_Airborne_Ultrasound_and_Very_High_Frequency_Sound_Timothy_G._Leighton.pdf); [Univ. of Southampton news 2016](https://www.southampton.ac.uk/engineering/news/2016/01/20-tim-leighton-ultrasound.page)
- Industry claims a maximum permissible level of **110 dB re 20 µPa** above the 20 kHz band; critics say this is not a consensus based on independent data — [Physics Today (PDF)](https://aip.brightspotcdn.com/PTO.v73.i12.38_1.online.pdf)
- Zoom's spec requires the tone to be inaudible beyond 25 cm, yet users with good hearing report it as slightly audible. ExpresSense's near-ultrasound chirps were "slightly audible" and caused "minor distractions for some participants" — [Zoom vendor doc](https://gozdm-developer.zoom.us/docs/VendorOsZRC/SupportUltrasonicProximity.html); [digitalseams blog](https://digitalseams.com/blog/the-dial-up-modem-lives-on-in-office-meeting-rooms); [ExpresSense arXiv 2301.06762](https://arxiv.org/pdf/2301.06762)
- LISNR markets 18.7–19.2 kHz as inaudible to 49 of 50 people (press) — [Digital Trends](https://www.digitaltrends.com/cool-tech/lisnr-transfer-files-audio/)
- ggwave ramps each tone frame's amplitude smoothly (`addAmplitudeSmooth`) instead of hard switching. Hard on/off keying creates audible broadband clicks — [ggwave.cpp source](https://github.com/ggerganov/ggwave/blob/master/src/ggwave.cpp)

### Inferences
- Bill of materials (inference from the prices above): existing ESP32 + MAX98357A (₹300–500) + piezo or small dome tweeter (₹30–100) + wiring ≈ **₹350–650**. Avoid the tiny 3 W "enclosed speakers" bundled with amp modules: such drivers usually roll off before 18 kHz (general audio knowledge, not verified here). A piezo tweeter is cheap and efficient at high frequencies.
- Generate tones by pre-computing a 48 kHz 16-bit sine table per FSK frequency (or synthesizing with a phase accumulator) and streaming it via I2S DMA. Ramp each symbol over about 2–5 ms with a raised-cosine envelope to avoid clicks.
- **Avoid ggwave's stock `[U]` protocols for a staff room.** They span 15.0–19.5 kHz (see Q5), and 15–17 kHz is plainly audible to many people. Either move `freqStart` to about 18 kHz with a narrow custom protocol or write a narrow 18–19.5 kHz FSK.
- Set emission level by measurement: the lowest level that gives reliable decoding at the far side of the room, checked with a phone SPL/spectrogram app. Keep it well below the contested 110 dB figure; something closer to normal speech levels at 1 m is likely enough (inference, to be measured).
- Run the tone only when needed, e.g., during office arrival hours or when the BLE beacon sees a scan request, to reduce continuous exposure and annoyance for occupants.

### Gaps
- No measured 18–20 kHz output curves were found for the specific cheap piezo tweeters and small speakers sold in India. The team must measure with a phone spectrogram at 1 m and 5 m.
- No source covered driving a piezo at 18 kHz with ESP32 LEDC PWM. This is feasible in principle (square wave; harmonics at 54 kHz+ are inaudible) but unverified.
- Robu.in and other Indian maker-store prices could not be fetched.

---

## Q5. Modulation and decoding: FSK/MFSK, chirps, OOK; data rate for a 16–32-bit code; FFT/Goertzel; noise, range, reverberation

### Takeaway
For a 32-bit rotating code, a simple **narrow-band MFSK (4–8 tones between 18.0 and 19.5 kHz) with a preamble, a CRC or Reed-Solomon check, and Goertzel detection** is enough. It sends one code in about 0.3–1.0 s, repeats it continuously, and decodes in a 2–3 s capture at 1–8 m. ggwave (MIT-licensed, MFSK + Reed-Solomon, 8–16 B/s) is a proven base if its frequency is moved up. DSSS, as in Google's 94.5 b/s protocol, is more robust to reverberation and narrowband noise but harder to build in a hackathon.

### Cited Findings
**ggwave (verified from source on GitHub)**
- Multi-frequency FSK: data split into 4-bit chunks; each frame sends 3 bytes as 6 simultaneous tones from 96 bins spaced **dF = 46.875 Hz** (4.5 kHz span). Reed-Solomon ECC. "Bandwidth rate is between **8–16 bytes/sec**." MIT licence — [ggwave README](https://github.com/ggerganov/ggwave)
- Protocol table (`{name, freqStart bin, framesPerTx, bytesPerTx, extra}`): `[U] Normal {320, 9, 3, 1}`, `[U] Fast {320, 6, 3, 1}`, `[U] Fastest {320, 3, 3, 1}`. `freqStart` 320 × 46.875 Hz = **15,000 Hz**. Audible protocols start at bin 40 (1875 Hz). DT/MT variants for microcontrollers start at bin 24. Ten `CUSTOM_0..9` protocol slots exist, and the API provides `ggwave_txProtocolSetFreqStart()` / `ggwave_rxProtocolSetFreqStart()` — [ggwave.h](https://github.com/ggerganov/ggwave/blob/master/include/ggwave/ggwave.h)
- Defaults: sample rate 48 kHz, 1024 samples per frame, 16 start/end marker frames, max data 256 bytes (140 in variable-length mode). ECC bytes = `len < 4 ? 2 : max(4, 2*(len/5))`. Fixed-length payload mode omits the markers — [ggwave.h](https://github.com/ggerganov/ggwave/blob/master/include/ggwave/ggwave.h); [ggwave.cpp](https://github.com/ggerganov/ggwave/blob/master/src/ggwave.cpp)

**Other schemes**
- Google Nearby: DSSS, 127-chip PN code per symbol, 94.5 b/s raw, robust to multipath and narrowband noise, 2 m reliable / 10 m often — [Getreuer et al. 2018](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware)
- `chirp_codec`: 4-FSK, 18–19.2 kHz, 16-bit payload, Goertzel filters — [pub.dev chirp_codec](https://pub.dev/packages/chirp_codec)
- Dhwani: about 2.4 kbps at about 10 cm (OFDM-style, very short range) — [MSR Dhwani](https://www.microsoft.com/en-us/research/project/dhwani/)
- Coherent modulation with adaptive equalization reaches 4 kbps at 5 m on laptops at 18–20 kHz, but needs an equalizer to handle non-flat hardware response — [arXiv 2103.11261](https://arxiv.org/pdf/2103.11261)
- Chirps at 18–23 kHz have been used on phones for ranging — [MDPI Sensors 2022](https://www.mdpi.com/1424-8220/22/19/7345)
- Real-world factors that hurt smartphone acoustic links: distance, device model, user handling, background noise — [Putz et al. 2026](https://arxiv.org/abs/2602.02249v1)
- A search extract reported that one proximity-detection paper finds acoustic approaches struggle with phones in pockets because of fabric noise. The extract did not say which paper; the DFKI paper is the likely source, but this attribution is unverified. Sound-Proof, by contrast, reports its *ambient* audio matching worked in pockets and purses — [DFKI: Sound-based proximity detection](https://www-live.dfki.de/fileadmin/user_upload/import/7857_Sound-based_proximity_detection_with_mobile_phones.pdf); [Sound-Proof arXiv 1503.03790](https://arxiv.org/pdf/1503.03790)

### Inferences
- **Payload design (inference):** `room_id` (4 bits) + `code` (32 bits) = `HMAC-SHA256(K_audio, beacon_id ‖ "AUD" ‖ floor(t/5))[0..3]` + CRC-8 = 44 bits. Use a separate key or domain-separation string from the BLE token so that leaking one doesn't reveal the other.
- **Airtime (computed from ggwave parameters at 48 kHz, 21.3 ms per 1024-sample frame):** a 4-byte fixed-length payload plus 4 ECC bytes = 8 bytes = 3 chunks. `[U] Fastest` (3 frames per chunk) takes about 0.19 s, `[U] Normal` (9 frames) about 0.58 s. Variable-length mode adds 2 × 16 marker frames (≈0.68 s) plus length bytes, for about 0.9–1.5 s total. In every case a 2–3 s capture contains ≥2 full repetitions, so the decoder can majority-vote.
- **A ggwave config that stays out of the audible band:** the stock `[U]` protocols span 15.0–19.5 kHz (6 tones × 16 bins × 46.875 Hz). A custom protocol with `bytesPerTx = 1` (2 tones → 32 bins = 1.5 kHz) and `freqStart = 384` (18.0 kHz) would occupy **18.0–19.5 kHz**, at the cost of a lower rate (still >1 B/s, fine for 5–8 bytes). This needs testing; ggwave's Android/iOS bindings would need the same custom protocol on the receive side.
- **DIY alternative:** 4-FSK or 8-FSK with tones spaced ≥150–250 Hz apart (e.g., 18.0/18.25/18.5/18.75 kHz) and 40–60 ms symbols with a 5–10 ms guard to let room reverberation decay. That gives about 30–50 b/s, so 44 bits plus a preamble take about 1–1.5 s. Decode with one Goertzel filter per tone per symbol window (O(N) per tone, trivially cheap in Dart). Use a known preamble pattern for symbol timing, and accept only if CRC passes *and* in-band SNR exceeds a calibrated threshold.
- Classroom chatter and ceiling fans put most of their energy well below 18 kHz, so the 18–19.5 kHz band should be relatively quiet. A 17 kHz high-pass before detection helps (typical acoustics knowledge; see Gaps). Range: Google's 2 m-reliable / 10 m-often and Zoom's 5 m/98% specs suggest a 6×8 m staff room is coverable with one well-placed tweeter.
- For the hackathon, adapt `chirp_codec`'s approach (pure Dart, Goertzel, 18–19.2 kHz) or port a minimal Goertzel decoder rather than depend on the stale `ggwave_flutter` plugin. It is new (v0.1.0) and unproven, so audit it before use.

### Gaps
- No measured classroom or staff-room noise spectra above 17 kHz were found in this session.
- No source gives reverberation times (RT60) at 18 kHz for typical Indian classrooms. High-frequency RT60 is usually short because air and surface absorption rise with frequency, but this is unverified here.
- Putz et al.'s quantitative comparison of schemes was not retrieved.

---

## Q6. Security: replay, relay, mitigations; is ultrasound + BLE stronger?

### Takeaway
A rotating, server-verified acoustic code defeats the **lone person outside a closed wall** and **later replay** of a recording. It does **not** defeat **real-time collusion**. Any phone inside the room can decode the code and forward it (as text or audio) to a colleague outside within a second or two, and an open door may leak the signal directly. Ultrasound + BLE + face + short freshness windows together are meaningfully stronger than BLE alone, but they raise the cost of cheating rather than prove presence. Stronger designs reverse the direction so the phone emits a server-issued per-session challenge that a mic on the ESP32 must hear, and can add acoustic time-of-flight.

### Cited Findings
- Ultrasonic beacon patent: an attacker "may capture and replay the beacon messages to impersonate the beacon device," gaining a proximity reward "even when they are not in proximity to the beacon." The countermeasure is **rolling, encrypted authorization values** checked by the server — [US9667352 Ultrasonic communications for wireless beacons](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9667352)
- Sound-Proof (USENIX Sec 2015) used ambient-audio similarity as a proximity second factor and reported it robust and usable — [arXiv 1503.03790](https://arxiv.org/pdf/1503.03790). Shrestha, Mahdad and Saxena ("Sound-Danger") showed it is "completely vulnerable" to passive environment-guessing and active environment-manipulating remote attackers. A same-room attacker can pass because ambient sound is similar over several metres. Their fix uses *active*, random, browser-generated sounds — [TAMU SPIES: Sound-Danger](https://spies.engr.tamu.edu/dangers-of-zero-effort-second-factor-login-based-on-ambient-audio/); [Saxena sound-based 2FA PDF](https://nsaxena.engr.tamu.edu/wp-content/uploads/sites/238/2025/08/sound-based-2FA.pdf)
- A 2020 survey covers the security mechanisms of short-range audio channels — [arXiv 2001.02877](https://arxiv.org/pdf/2001.02877)
- Cisco's privacy text: through an open door, the client "may be able to detect the ultrasound audio pairing message" — [Cisco Proximity supplement](https://www3-realm.cisco.com/web/siteassets/legal/proximity-supplement.html)
- Cisco suggests turning the feature off when "total security" is needed, which implicitly concedes that ultrasound proximity is a convenience-grade control — [Cisco Community](https://community.cisco.com/t5/cisco-proximity/security-of-content-sharing-with-proximity-feature/td-p/2882535)
- Dhwani notes NFC eavesdropping from 1 m with off-the-shelf gear and uses self-jamming to stop acoustic eavesdroppers. Acoustic signals are broadcast and capturable by anyone in range — [MSR Dhwani](https://www.microsoft.com/en-us/research/project/dhwani/)
- Analog physical-layer relay attacks on Bluetooth can relay over **90 m** and manipulate phase-based ranging, so BLE presence alone can be relayed — [CASA Bochum 2022](https://casa.rub.de/fileadmin/img/Publikationen_PDFs/2022_Analog_Physical-Layer_Relay_Attacks_with_Application_to_Bluetooth_and_Phase_Based_Ranging_Publication_ClusterofExcellence_CASA_Bochum.pdf)
- Car-entry patents add an ultrasonic exchange after the radio link because relaying sound over long distances distorts the position or timing estimate, making relay harder — [US10953851](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10953851); [US11528612](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11528612)
- Opus (used by many VoIP apps) has bandwidth modes capped at 4, 6, 8, 12 or 20 kHz (fullband only reaches 20 kHz), so a casual voice call may or may not carry 18–19 kHz depending on the mode the app picks — [Opus CTL values](https://opus-codec.org/docs/opus_api-1.5/group__opus__ctlvalues.html)

### Inferences
- **Threat model for this project:**
  1. *Lone outsider behind a wall or in the corridor with the door closed:* **blocked** by ultrasound (main win over BLE).
  2. *Outsider near an open door or window:* **may pass**. Mitigate with volume calibration, an SNR threshold, tweeter placement and a door-closed policy.
  3. *Recording played back later, or from home:* **blocked** by a 5–10 s code window plus server-side single-use checks per (staff, window).
  4. *Live collusion (insider decodes and sends the code over WhatsApp, or a modified app injects it):* **not blocked**. The code is just bits once decoded. A tight window (≤5–10 s) forces automated relaying instead of manual typing, but cannot stop it.
  5. *Insider holds the absent colleague's phone:* blocked by face recognition with liveness, not by ultrasound.
- **Server-side freshness rules (inference):** accept a code only for the current window ±1 (clock skew). Require the acoustic code and the BLE token to come from the same `beacon_id` and adjacent windows. Bind the submission to the face-match timestamp (all within one ≈10 s capture session). Reject a second use of the same code by the same staff ID. Rate-limit guesses (a 32-bit code makes guessing hopeless: 1 in 4.3 × 10⁹).
- **Is ultrasound + BLE stronger?** Yes, the two are complementary. BLE proves "within ~10–30 m and in radio range of this specific beacon now," and ultrasound adds "same acoustic space (closed room)." An attacker outside must defeat both at once. Neither factor resists a cooperating insider, so they raise the cost of cheating rather than prevent it.
- **Stronger option (reverse direction, per-phone challenge):** the server issues a random 32-bit nonce per attendance attempt, and the *phone* plays it as near-ultrasound while the ESP32 listens via an I2S MEMS mic (INMP441 ships in the same ₹299–499 bundle) and reports the heard nonce to the server over Wi-Fi. A relay then needs a *speaker physically inside the room* playing the outsider's audio in real time, which is much harder than forwarding a text code. Combined with a short deadline, this is the best collusion resistance achievable cheaply. Caveats: the ESP32 must sample at ≥40 kHz (ggwave's ESP32 RX example runs at only 24 kHz), and the INMP441's response at 18–19 kHz is unverified.
- **Acoustic distance-bounding (advanced, probably beyond the hackathon):** sound travels about 34 cm per ms. An ESP32 that emits a challenge and times the phone's acoustic reply could bound distance, and any network relay adds tens of ms (≈ several metres of apparent distance). This is the principle in the car-entry patents above. It needs tight timing on the phone, and Android audio latency is variable.

### Gaps
- No peer-reviewed security analysis of near-ultrasound *attendance or proximity tokens on smartphones* was found. The NCC Group whitepaper (blocked here) likely covers SDK weaknesses.
- Whether WhatsApp or Google Meet calls pass 18–19 kHz in practice is unverified, since their codec mode choice is not documented.

---

## Q7. Practical issues: battery and CPU, RECORD_AUDIO permission, UX (2–3 s capture), privacy

### Takeaway
Cost to battery and CPU is negligible: a 2–3 s mono 48 kHz capture is about 0.3 MB and Goertzel decoding is trivial. UX can be invisible if audio is captured **during the face scan the user already performs**. The real costs are (1) the RECORD_AUDIO permission and its privacy optics, (2) per-device reliability variance, and (3) audibility complaints. The privacy history of ultrasonic beacons (SilverPush, FTC 2016) means the app must listen only in the foreground, only during check-in, process audio on-device, never upload it, and say so clearly.

### Cited Findings
- FTC (Mar 2016) sent warning letters to 12 Android app developers using SilverPush code, which listened via the mic for inaudible TV "audio beacons." It flagged that the apps requested microphone access without apparent need and gave no notice of TV-viewing monitoring — [FTC press release](https://www.ftc.gov/news-events/press-releases/2016/03/ftc-issues-warning-letters-app-developers-using-silverpush-code)
- The Center for Democracy & Technology raised ultrasonic cross-device tracking concerns in Nov 2015. SilverPush later said it was ending its audio beacon service — [Wikipedia: SilverPush](https://en.wikipedia.org/wiki/SilverPush)
- Shopkick deliberately listened only while the app was open, to be "careful about privacy" — [MIT Technology Review](https://www.technologyreview.com/s/420582/bringing-cell-phone-location-sensing-indoors/)
- 200–230+ Android apps (TU Braunschweig study, as reported) embedded ultrasonic tracking, which is the source of public distrust of "apps that listen" — [PC-Welt](https://www.pcwelt.de/article/1164802/werbe-tracking-per-ultraschall-in-ueber-230-android-apps.html)
- Zoom keeps a manual sharing-key fallback when ultrasonic detection fails, a UX pattern worth copying — [Zoom dev forum](https://devforum.zoom.us/t/ultrasonic-connection/3318)
- The `record` Flutter plugin can stream PCM from a chosen Android audio source with AGC, AEC and NS off — [pub.dev record](https://pub.dev/packages/record)

### Inferences
- **Battery and CPU:** 2–3 s × 48,000 samples × 2 bytes ≈ 0.29 MB of PCM. A handful of Goertzel filters over it is microseconds-to-milliseconds of work in Dart. Running the mic concurrently with the camera for about 3 s is negligible next to the face-recognition model. Nothing runs in the background.
- **ESP32 side:** continuous I2S output and the amplifier draw extra current (tens of mA at modest volume; not measured). Mains-powered staff-room beacons make this a non-issue. Optionally gate emission to office hours.
- **UX flow:** open check-in → camera starts face capture *and* mic starts recording simultaneously (≈3 s) → decode on-device → send `{face_result, ble_token, audio_code, audio_snr, device_model}` to the server. If the audio fails, show "Move into the staff room and close the door," retry once, then fall back to the manual or HOD-approval path. The user perceives no extra step.
- **Permissions and privacy copy:** request RECORD_AUDIO at the moment of first check-in with a plain-language rationale ("We listen for 3 seconds for an inaudible room signal from the staff-room beacon. Audio never leaves your phone."). Do not upload raw audio, and store only the decoded code and SNR. Recent Android versions show a microphone-in-use indicator, so listening must coincide with the visible check-in screen (Android platform behaviour; verify per target API level).
- **Operational:** add an admin "calibrate room" screen that shows live SNR at 18–19.5 kHz, so whoever installs the beacon can walk inside, at the door and in the corridor and set the threshold. Log per-device-model success rates to spot phones that can't hear the band.

### Gaps
- No measured ESP32 + MAX98357A current draw for continuous near-ultrasound output was found.
- Current Google Play policy wording on microphone use for "ultrasonic beacon" detection was not checked. The app should still comply with the prominent-disclosure and user-data rules.
- Android version-specific behaviour (mic privacy indicator, concurrent capture rules, foreground-service type for microphone) was not verified against official docs in this session, because source.android.com and developer.android.com were blocked.

---

## Q8. Overall verdict: practical, reliable and secure enough? What would an implementation look like?

### Takeaway
**Practical:** yes. It needs about ₹350–650 of extra hardware and open-source code (ggwave or a small Goertzel FSK), and the technique is proven by Google, Cisco, Zoom and Shopkick. **Reliable:** good enough as a *factor*, not as the sole gate. Expect it to work on most phones at 18–19.5 kHz within about 5–8 m, with a tail of devices that fail and leakage through open doors. **Secure:** it solves the stated problem (a person outside a closed wall receiving BLE) and blocks replay, but not live insider collusion. It is the best cheap add-on for the "BLE goes through walls" problem, provided it is combined with BLE, face liveness and tight server-side freshness, and has a fallback path.

### Cited Findings
- Same-room confinement is the stated design rationale for near-ultrasound co-presence at Google — [Getreuer et al. 2018](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware) — and Cisco documents that it fails outside when doors are closed — [Webex Help](https://help.webex.com/en-us/article/b5c5rab/Install-and-Use-the-Cisco-Proximity-App)
- Range and reliability benchmarks: 2 m reliable / 10 m often (Google), 5 m at >30 dB with 98% success (Zoom spec) — [Getreuer et al.](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware); [Zoom vendor doc](https://gozdm-developer.zoom.us/docs/VendorOsZRC/SupportUltrasonicProximity.html)
- Phone support is recommended, not mandatory, under the Android CDD — [CDD 7.8 mirror](https://os.unplugged.com/werunplugged/unplugged-vendor/src/branch/main/compatibility/cdd/7_hardware-compatibility/7_8_audio.md)
- Open-source building blocks exist: ggwave (MIT, MFSK + RS, ultrasound protocols, ESP32/Android/iOS) — [ggwave](https://github.com/ggerganov/ggwave) — and Flutter capture via `record` 7.1.2 — [pub.dev record](https://pub.dev/packages/record)

### Inferences — reference implementation for the hackathon
1. **Hardware (per room):** existing ESP32 + MAX98357A (I2S BCLK/LRC/DIN on 3 GPIOs, 5 V) + piezo or small dome tweeter mounted high on the wall opposite the door, aimed into the room. Optional: INMP441 I2S mic on the same ESP32 for the reverse-direction mode later.
2. **Firmware:** reuse the existing time sync and HMAC token generator. Every 5 s compute `audio_code = HMAC-SHA256(AUDIO_SECRET, beacon_id + ":A:" + floor(t/5))[0..3]`, frame it as `[preamble][room_id:4b][code:32b][crc8]`, and synthesize 4-FSK at 18.00/18.25/18.50/18.75 kHz (or a ggwave custom protocol at freqStart ≈ 18 kHz) with 50 ms symbols, 5 ms raised-cosine ramps and a 48 kHz I2S stream, repeating continuously. Keep the existing BLE advert (30 s window) unchanged.
3. **App:** during the face-capture screen, stream 3 s of PCM16 mono at 48 kHz from `AndroidAudioSource.unprocessed` (fallback `voiceRecognition`) with AGC/NS/AEC off. Band-pass at 17.5–20 kHz, find the preamble, run Goertzel per symbol, check CRC, and compute the in-band SNR. Submit `{audio_code, snr, window_index}` together with the BLE token and face result.
4. **Server:** verify the HMAC for the current window ±1. Require the BLE token and audio code to come from the same beacon within ≤1 BLE window. Require SNR ≥ the room's calibrated threshold. Allow one use per staff per window, and log the device model. Store a "presence confidence" score instead of a hard pass/fail if the existing "Proxy Shield" confidence logic is used.
5. **Calibration and testing (to produce the evidence the judges will ask for):** measure decode rate and SNR at grid points inside the room, at the doorway, in the corridor with the door open and closed, and in the adjacent room. Use at least 5 phone models (budget Redmi/Realme/Samsung A/M). Report "inside success %" vs "outside false-accept %".
6. **Fallback:** if a device consistently fails the capability check, mark it "audio-incapable" and require an alternative (e.g., QR shown on a small display inside the room, or HOD approval) rather than silently trusting BLE.
7. **Stretch (stronger anti-collusion):** reverse direction. The server sends a per-attempt nonce, the phone plays it at 18–19.5 kHz, and the ESP32's INMP441 hears it and posts it to the server within a 3–5 s deadline.

### Gaps
- No field data exists for this exact setup (budget Android phones, Indian staff rooms with brick walls, open doors and ceiling fans). The calibration test in step 5 is required before claiming reliability numbers.
- Whether the INMP441 and ESP32 I2S path can capture 18–19.5 kHz cleanly at 44.1/48 kHz for the reverse-direction mode is unverified.
