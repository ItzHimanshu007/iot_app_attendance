# Industry and research approaches to room-level certainty and proxy-proof attendance

Research date: 2026-10-14. Method note: web fetches to most vendor and academic domains were blocked by the sandbox's egress proxy. Findings therefore come from search-result extracts of the cited pages, not full-text reads. Figures attributed to a page were present in that page's indexed text. Wherever a number comes only from a vendor, the notes say so.

## 1. Healthcare RTLS that claim "room-level certainty": what technologies they combine and why

### Takeaway
Every major clinical RTLS vendor that promises room-level or "certainty" location adds a signal that walls stop: infrared light (CenTrak, Midmark/Versus, Kontakt.io) or ultrasound (Sonitor, Stanley/AeroScout exciters). RF (BLE or Wi-Fi) is used for coverage and data backhaul. The vendors' own figures show BLE-only reaching only about 75–90% room accuracy, against a claimed 99.99–100% once IR or ultrasound is added. That gap is the main industry evidence the team can cite for its wall problem.

### Cited Findings

**Why RF alone fails at walls (industry statements)**
- Active Wi-Fi tags locate an item only to within about 10 feet, and "RF signals can transmit through walls," which makes exact room identification hard. The same deployment added ultrasound exciters because "ultrasound signals, on the other hand, are unable to penetrate walls, thus reducing the likelihood of tracking errors" (Dorset County Hospital, 2013). — [RFID Journal](https://www.rfidjournal.com/news/rtls-brings-efficiency-to-dorset-county-hospital/83706/)
- A BLE gateway "can often hear a beacon in the next room," and the RSSI gap between the correct room and the adjacent room can be "up to 20 dB." "Up to" means the gap is not guaranteed. — [Lansitec (vendor blog)](https://www.lansitec.com/blogs/rssi-indoor-positioning/)
- The same vendor attributes RSSI variability to wall materials. Citing NIST work, it says a person blocking the direct path can shift RSSI by about 11 dB. I could not verify this against the original NIST paper. — [Lansitec](https://www.lansitec.com/blogs/rssi-indoor-positioning/)
- Wi-Fi-only RTLS "can't always locate to room-level accuracy, particularly when the person or equipment being tracked is near a wall"; achieving consistent room-level accuracy can require tuning, calibration and ongoing maintenance. — [FitGap AeroScout listing (third-party aggregator)](https://us.fitgap.com/products/026076/aeroscout)

**Sonitor (ultrasound)**
- Sonitor's company profiles from 2007–2008 claim "100% room-level or sub-room-level accuracy" for its ultrasound (USID) system. These are vendor claims with no published test method. — [IDTechEx Sonitor profile](https://www.idtechex.com/en/timeline/sonitor-technologies-inc/c4092)
- Ascom's partner page for Sonitor Sense now says "proven room, bay, and chair level resolution," without the 100% figure. — [Ascom](https://www.ascom.com/about-us/why-ascom/interoperability-partners/sonitor/)
- Sonitor describes its ultrasound as room-bounded with sub-room identification, running as a hybrid "ULE + BLE + GPS + LF for reliability in all conditions." — [Sonitor](https://sonitor.com/?p=2340)
- SonitorMOBILE (2023) combines ultrasound (SonitorULE) and BLE on smartphones. The vendor claims "centimeter level accuracy with refresh rates of 1–2 seconds." SonitorBLU is a BLE-only option for zone-level use cases. — [BusinessWire 2023](https://businesswire.com/news/home/20230501005649/en/Sonitor-Introduces-SonitorBLU™-and-SonitorMOBILE™)
- Sonitor merged with Tagnos in August 2025. SonitorONE unifies ultrasound, BLE and Wi-Fi in one infrastructure. — [Dealroom](https://dealroom.co/companies/sonitor-technologies/)

**CenTrak (Gen2IR + RF)**
- CenTrak markets Gen2IR as "certainty-based" location: a tag reports the correct room or bay, or nothing. It claims "100% accurate" room, bed and bay locating. Low-frequency (LF) exciters handle chokepoint and chair-level detection. — [CenTrak](https://tours.centrak.com/answers/frost-sullivan-recognizes-centraks-rtls)
- Gen2IR "does not pass through walls," and CenTrak says it avoids the line-of-sight limits of older IR and ultrasound. It is paired with active RFID, Wi-Fi or BLE in "multi-mode" tags. — [CenTrak multi-mode](https://tours.centrak.com/answers/multi-mode-technology-gen2ir-and-wi-fi-rtls-for-healthcare)
- The Gen2IR update rate differs between CenTrak's own pages: "every 1500 milliseconds" on one, "every few seconds" on another. — [CenTrak BLE page](https://centrak.com/ble/); [CenTrak IoT devices](https://centrak.com/our-process/iot-devices)
- I found no third-party test of the "certainty" claim. An independent listing repeats CenTrak's description with a disclaimer. — [IntuitionLabs](https://intuitionlabs.ai/software/healthcare-provider-operations/asset-tracking-and-biomedical-equipment/centrak)

**Stanley Healthcare / AeroScout (Wi-Fi + ultrasound or LF exciters)**
- AeroScout's ultrasound exciter wakes the tag. The tag then reports its own ID plus the exciter's ID to the nearest Wi-Fi AP, and the engine maps the exciter ID to a room. — [RFID Journal](https://www.rfidjournal.com/news/rtls-brings-efficiency-to-dorset-county-hospital/83706/)
- The current AeroScout EX4330 product listing says it "transmits an ultrasound signal that does not pass through walls, enabling room-level detection." — [CDW listing](https://www.cdw.com/product/aeroscout-ex4330-ultrasound-exciter/5232297)
- Stanley Wi-Fi tags run on 2.4 GHz only, and Cisco warns that 2.4 GHz AP density and stability are critical to accuracy. — [Cisco design guide](https://cisco.com/c/en/us/solutions/collateral/enterprise-networks/dna-spaces/guide-c07-744957.html)

**Midmark RTLS (formerly Versus; IR + BLE)**
- Midmark's IR sensor covers a 15-foot radius at room level, or a 2-foot radius at chair level with a "focus kit": one small sensor per location. — [Midmark IR Sensory Network](https://www.midmark.com/medical/rtls/products/detail/ir-sensory-network)
- Midmark calls IR "the gold standard in room-certain location accuracy." — [Midmark](https://www.midmark.com/medical/rtls/our-approach/rtls-simplified)
- Midmark's newer BLE Sensory Network (Feb 2026) is quoted at "near-room location precision … with 3–5 meter accuracy." By the vendor's own framing, that is a lower tier than IR. — [Midmark press release Feb 2026](https://www.midmark.com/newsroom/news-releases/2026/02/17/midmark-rtls-launches-ble-sensory-network-for-smarter--scalable-rtls)
- The March 2026 hybrid offering uses BLE for facility-wide visibility and wireless IR for "room- or bed-level certainty." — [Midmark press release Mar 2026](https://www.midmark.com/newsroom/news-releases/2026/03/03/midmark-rtls-introduces-a-smarter-hybrid-approach-to-rtls-with-ble-and-wireless-ir)

**Kontakt.io (BLE + IR), the most useful published comparison**
- Kontakt.io's Beam Mini support table gives room-level accuracy by tag type (vendor-stated):
  - **99.99%** for BLE + IR tags (Smart Badge, Asset Tag 2) with a Beam Mini in the room.
  - **90%+** for BLE-only tags with a Beam Mini in the room.
  - **75%+** for BLE-only tags in rooms without one.
  - Latency is 1–5 minutes for the BLE-only tiers.
  — [Kontakt.io support: Beam Mini + Cisco Spaces](https://support.kontakt.io/hc/en-gb/articles/14512613170972-Intro-to-Beam-Mini-with-Cisco-Spaces)
- The Beam Mini contains an IR emitter array and IR receiver "for room-level certainty," plus BLE 5.0. — [Beam Mini tech specs](https://support.kontakt.io/hc/en-gb/articles/13957936100252-Beam-Mini-technical-specifications)
- Smart Badge 3 (staff badge) gets room-level precision from its built-in IR receiver combined with Kontakt.io Beams. — [Smart Badge 3](https://support.kontakt.io/hc/en-gb/articles/19676391233948-About-the-Smart-Badge-3)
- The Nano Tag IR patient wristband tag (BLE + IR) is marketed as locating patients "reliably … at the hospital room level." — [Kontakt.io press release](https://kontakt.io/press-releases/kontakt-io-launches-patient-flow-solution-featuring-the-worlds-smallest-wearable-tag-with-room-level-accuracy/)

**Cisco Spaces / HPE Aruba (enterprise Wi-Fi/BLE)**
- Cisco Spaces BLE asset tracking: "2–5 m under ideal conditions," varying with building and AP deployment. Another Cisco page says "up to 4 meters." — [Cisco Spaces](https://spaces.cisco.com/?p=18240)
- Cisco Hyperlocation (Wi-Fi angle-of-arrival module): 1–3 m average accuracy for associated clients. — [Cisco Hyperlocation datasheet](https://cisco.com/c/en/us/products/collateral/interfaces-modules/aironet-hyperlocation-module-advanced-security/datasheet-c78-734901.html)
- A competitor claims Wi-Fi positioning on Cisco Spaces typically gives 5–15 m. This is a competitor claim. — [Crowd Connected](https://www.crowdconnected.com/compare/cisco-meraki-alternative/)
- Cisco Spaces achieves room-level certainty by integrating Kontakt.io's IR-equipped Beam Mini (see the table above), not through Wi-Fi/BLE alone. — [Kontakt.io support](https://support.kontakt.io/hc/en-gb/articles/14512613170972-Intro-to-Beam-Mini-with-Cisco-Spaces)

**Cost**
- ECRI pricing for a 300-bed, hospital-wide, room-level system with 3,000 tags: **USD 100,000 to 2 million**, depending on technology. A Wi-Fi (RF) system is **USD 300,000–650,000**. These totals include software, installation and hardware. — [HFM Magazine citing ECRI](https://www.hfmmagazine.com/articles/398-working-in-real-time)
- A competitor estimates a CenTrak IR/BLE deployment at "USD 200K–500K+" per hospital. This is a competitor estimate. — [AirPinpoint comparison](https://airpinpoint.com/compare/airtags-vs-centrack)
- IR and ultrasound historically needed "dense ceiling-mounted equipment in every room and hallway," which "pushed the price-point beyond realistic viability." High installation cost is IR's major downside. — [Purple.ai Healthcare RTLS 101](https://purple.ai/blogs/healthcare-rtls-101/)
- A BLE RTLS vendor concedes that "to provide room-level accuracy, you still need a ton of devices throughout the hospital — this gets expensive very quickly." — [Cognosos (vendor blog)](https://cognosos.com/?p=10282)
- A patent filing describes IR and ultrasound as "non-standardized, costly to deploy and less energy efficient than BLE-only RTLS." — [US patent 12375877](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12375877)
- Tag price ranges from trade articles: USD 80–90+ RTLS tags for capital equipment, against USD 2–10 commodity BLE/iBeacon tags. These are vendor reprints, and which figure comes from which article was not confirmed. — [mfgrobots article 4168](https://www.mfgrobots.com/Article/iiot/iot/4168.html); [mfgrobots article 4133](https://www.mfgrobots.com/Article/iiot/iot/4133.html)

### Inferences
- The industry pattern is "RF for where-roughly, plus a wall-bounded modality for which-room." Vendors do not try to make BLE RSSI room-certain on its own. They add an in-room emitter whose physical carrier stops at walls (IR light, ultrasound) or has a tiny range (LF magnetic field). This is directly analogous to the team's problem and is the strongest framing for judges: "we follow the clinical RTLS architecture."
- Kontakt.io's own table is the best citable evidence that BLE-only room detection is about 90% at best even with a dedicated in-room gateway. It also shows a wall-bounded second signal is what moves the figure to "certainty."
- IR certainty depends on a dedicated IR receiver in the tag or badge. Ordinary Android phones generally do not have an IR receiver; some have IR blaster transmitters only. This is my own knowledge and was not sourced in this search. IR is therefore not practical for staff-phone attendance. Ultrasound is: every phone has a microphone, which is why Sonitor (SonitorMOBILE) and Microsoft (below) use ultrasound for phones.
- Hospital RTLS budgets (lakhs to crores of rupees) are irrelevant to a college. The architecture transfers, but the product does not.

### Gaps
- No independent or peer-reviewed validation was found for any vendor's 99.99% or 100% claim. Every certainty figure is vendor-stated.
- HPE Aruba location accuracy and room-level methods were not found in this search.
- No per-room installed cost was found for IR or ultrasound. Only whole-hospital ranges were available.
- The Sonitor current-generation spec sheet (ultrasound frequency, emitter cost) was not retrieved.

## 2. Classroom and workplace attendance products (BLE, geofence, Wi-Fi, QR, ultrasound): how they stop "standing outside", and known weaknesses

### Takeaway
Indian HR suites (Keka, Zoho People, greytHR, Darwinbox) mostly rely on GPS geofence plus selfie or face match. The geofence radii are tens to hundreds of metres, so none of them achieves room-level certainty. Classroom tools rely on short instructor-triggered windows plus proximity (Bluetooth, UWB) or inaudible sound: CourseKey, and Microsoft Teams Rooms, which explicitly uses ultrasound "because it does not pass through walls." Indian public deployments (Bihar e-Shikshakosh, NMC AEBAS) show what goes wrong with photo plus GPS: reused photos, old videos, stripped or faked GPS, and attendance marked from 100 km away.

### Cited Findings

**Indian HR-tech (staff attendance)**
- **Keka:** mobile clock-in geofencing is configured per capture scheme. The admin sets a location and a radius in metres under Time Attend > Settings > Geo Locations. — [Keka Help](https://help.keka.com/hc/en-us/articles/39946686482449)
- **Zoho People:**
  - The mobile check-in captures a photo and matches it against the employee's profile photo, so check-in succeeds only if they match. A manual-review option exists. — [Zoho People feature update](https://www.zoho.com/people/hrknowledgehive/November-feature-updates-Whats-new-in-Zoho-People.html)
  - Zoho People offers IP restriction and geofencing for mobile workers, and can make location sharing mandatory at check-in. — [Zoho People attendance](https://www.zoho.com/people/attendance-tracker.html); [Zoho People privacy policy](https://www.zoho.com/people/privacy-policy.html)
  - No Zoho documentation confirming fake-GPS detection was found.
- **greytHR:**
  - Combines geofence (admin-set lat/long) with selfie. The selfie is either sent to a manager or auto-matched against the stored photo with **liveness detection**. — [greytHR attendance marking methods](https://www.greythr.com/help-admin/attendance-management/employee-attendance-marking-methods/)
  - Employees can set their own geofence only if the admin enables it via an SMS access code, valid for 3 days. — [greytHR geofence configuration](https://www.greythr.com/help-ess-mobile/attendance-updates/configure-geofence-attendance)
- **Darwinbox:** geo-fencing and geo-tagging for "contactless attendance," with coordinates feeding payroll. — [Darwinbox Marketplace](https://marketplace.darwinbox.com/en-US/apps/405338/geo-fencing-geo-tagging/features)
- **What generic vendors admit:**
  - "GPS in a building is easily 30–50 m off," so set geofence radii generously. — [Offision help](https://offision.com/help/en/attendance/verify-clock-ins-with-gps-ip-and-selfies/)
  - A Wi-Fi/IP restriction "can verify whether the network source matches the rule, but it cannot determine the employee's precise physical location." Photos are "supporting material only." — [SwipePoint manual](https://swipepoint.blueeyes.tw/manual0907-en.php)

**Indian government deployments: real-world proxy evidence**
- **NMC (National Medical Commission):** moved medical-college faculty from fingerprint to Aadhaar face authentication from **1 May 2025**. The move followed cases of fake thumb impressions used by "ghost faculty" to meet the 75% attendance criterion. — [The South First](https://thesouthfirst.com/news/fingerprint-biometric-system-fails-in-medical-colleges-nmc-switches-to-face-based-attendance-for-faculty); [Tribune India](https://www.tribuneindia.com/news/facial-authentication-mandated-for-faculty-attendance-in-medical-colleges)
- **NMC geofence:** attendance can be marked only within a **100 m radius** of GPS points the college submits, signed by the dean or principal. — [The South First](https://thesouthfirst.com/news/fingerprint-biometric-system-fails-in-medical-colleges-nmc-switches-to-face-based-attendance-for-faculty)
- **NMC later notice:** a 26 Sep 2025 notice reportedly ended facial QR-code-based attendance devices by 1 Oct 2025 (single source). — [Mobile ID World](https://mobileidworld.com/indias-medical-colleges-switch-to-mandatory-face-based-aadhaar-authentication-for-faculty-attendance/)
- **Bihar e-Shikshakosh (teacher attendance app):** teachers upload a photo from campus between 8:30 and 9:00 am, and the app accepted attendance within **500 m** of the campus. A teacher was suspended for repeatedly marking attendance while sitting in her car. — [Scroll.in](https://scroll.in/article/1075292/bihar-is-using-an-app-to-track-teachers-attendance-much-to-their-anger)
- **Bihar fraud found in the Muzaffarpur probe (May 2025):**
  - Teachers reused the same photo in the same clothes for up to 10 days.
  - Photos were taken on another person's phone.
  - Old videos of school premises were uploaded.
  - GPS data was stripped from photos and doctored images were uploaded via other devices.
  - Hundreds of teachers came under scrutiny.
  — [Patna Press](https://patnapress.com/bihar-teacher-attendance-scam-photos-fake-locations-and-same-clothes-for-10-days-expose-e-shiksha-fraud/)
- **Kishanganj:** attendance was marked from about 100 km away, and seven teachers were asked to explain (headline only; body not read). — [Prabhat Khabar](https://www.prabhatkhabar.com/state/bihar/kishanganj/attendance-made-from-100-km-away-on-e-shikshakosh/amp)
- **Outcome:** the app reportedly curbed absenteeism, and over 1,000 teachers were penalised. Teachers want biometric attendance instead. — [Careers360, Oct 2025](https://news.careers360.com/bihar-e-shikshakosh-online-attendance-teachers-burden-curb-absenteeism-nitish-kumar-school-education-reform-assembly-election/amp)

**University classroom products**
- **Top Hat Secure Attendance:**
  - Requires a 4-digit code plus a location check, using geolocation for the device and Bluetooth for proximity to other responders. — [UW-Madison KB](https://kb.wisc.edu/helpdesk/121318); [Indiana CITL](https://citl.indiana.edu/teaching-resources/academic-integrity/tophat-attendance)
  - Oregon State warns that Secure Attendance "does NOT prevent students from responding remotely to questions asked in class." — [Oregon State](https://learn.prod.acquia.cws.oregonstate.edu/node/45701)
- **iClicker:**
  - The GPS check records only the student's distance from the instructor's check-in point against a radius. — [Ithaca College help](https://help.ithaca.edu/TDClient/34/Portal/KB/Article/1672/Using-iClicker-for-Attendance)
  - From **Fall 2026**, Bluetooth proximity check-in lets the instructor pick a room size (small, medium or large hall) to set the range, with no GPS needed. The class must be started from the iClicker Desktop app. — [UCLA DTS](https://dts.ucla.edu/news/iclicker-enhancement-bluetooth-attendance-tracking)
- **Acadly:**
  - Uses Bluetooth and UWB, described by the vendor as a "mesh-network technology that uses Bluetooth, WiFi, and UWB," to verify presence in the instructor's proximity. — [Columbia Business School](https://business.columbia.edu/acadly-students); [Acadly](https://pages.acadly.com/rfums-for-students)
  - Anti-proxy design claim: it is not practical to stand outside because the instructor starts attendance and the window lasts **only 2.5 minutes**. — [Acadly](https://pages.acadly.com/rfums-for-students)
  - Reliability: more than **95%** of present students are marked present when everyone has the app, rising to about **98%** after a first-lecture dry run. — [UIC help desk](https://help.uillinois.edu/TDClient/37/uic/KB/ArticleDet?ID=2353)
- **CourseKey (ultrasound):**
  - The instructor's device emits an inaudible tone carrying a unique "leader" code, and student phones that hear and match it log presence.
  - CourseKey says "the sound waves … can not travel through walls," so attendance is verified at classroom level.
  — [Campus Technology 2017](https://campustechnology.com/Articles/2017/10/02/New-CourseKey-Feature-Takes-Attendance-with-Sound.aspx)
  - The Portico admin guide, built on CourseKey, says the sound "cannot pass through doors or walls." — [Portico admin guide (PDF)](https://welcome.porticoedu.com/hubfs/MyPortico%20CS%20Documents/Admin%20Guide%20to%20Portico%20Attendance%20-%20Sound%20Technology.pdf)
  - A patent covers this "leader code in a sound signal" approach for attendance and exam presence. — [US 10551496](https://patents.justia.com/patent/10551496)

**Microsoft Teams Rooms Proximity Join (enterprise ultrasound + BLE)**
- Ultrasound beacons "are emitted only within the physical Teams Room." Because ultrasound "typically doesn't pass through walls," it is more precise than Bluetooth, which "can penetrate through walls."
- When both are on, they combine "to provide the most accuracy," and rooms found by ultrasound are listed first.
- Detection uses the laptop's microphone. Ultrasound was enabled by default on Teams Rooms on Windows, rolling out Aug–Nov 2024.
— [Microsoft Learn: Proximity Join](https://learn.microsoft.com/en-us/microsoftteams/rooms/proximity-join); [HANDS ON Teams admin summary](https://m365admin.handsontek.net/?p=10370); [Message Center MC808158](https://mc.merill.net/message/MC808158/v/2024-09-18T23-23-14-783Z); [i3-Connect guide](https://docs.i3-connect.com/how-to/enable-bluetooth-and-ultrasound-beaconing-for-teams-proximity-join-for-mtr-microsoft-teams-rooms)

**GPS spoofing on Android**
- A mock-location provider can feed fake coordinates to any app, so checking the GPS hardware is insufficient. Apps can check whether a location came from a mock provider. — [Giriton blog](https://giriton.com/en/blog/the-my-attendance-app-recognizes-a-fraudulent-location)
- Giriton's attendance app treats a simulated location as "GPS not detected," which blocks attendance. — [Giriton](https://giriton.com/en/blog/the-my-attendance-app-recognizes-a-fraudulent-location)
- Flutter `geolocator` exposes `Position.isMocked`, which wraps Android's `isFromMockProvider()` (API 18+). — [geolocator docs](https://pub-web.flutter-io.cn/documentation/geolocator/8.2.1/geolocator/Position/isMocked.html)
- The old global "Allow mock locations" setting check is deprecated from API 23 and always returns false. The per-fix check is recommended instead. — [MockLocationDetector README](https://github.com/smarques84/MockLocationDetector)
- A forum report says detection failed on Android 7.1 with a fake GPS app running. — [B4X forum](https://b4x.com/android/forum/threads/how-to-detect-mock-locations.83823)

### Inferences
- No mainstream Indian HR product claims room-level certainty. They operate at campus or building level, with radii of 100–500 m in government deployments, and treat the selfie or face as the main proof of identity rather than of room. A college system that adds a wall-bounded room signal would exceed what Keka, greytHR or Zoho offer. That is a credible differentiation claim for judges.
- The classroom products that claim to beat "standing outside" do it with three levers, often combined:
  1. A signal that stops at walls (CourseKey and Teams ultrasound).
  2. Short, unpredictable, instructor-triggered windows (Acadly 2.5 min, Top Hat code).
  3. Rotating codes carried in the signal ("leader codes").
- The Bihar evidence is a ready-made threat list: photo reuse, other-person capture, old video, GPS stripping or faking, remote marking. A defensible design needs:
  - in-app live capture with liveness, never a gallery upload;
  - server-side detection of duplicate or near-duplicate photos;
  - mock-location rejection;
  - a room-bound signal that cannot be satisfied from 500 m, or even 5 m, away.
- Bihar's fixed 8:30–9:00 window shows that predictable windows invite gaming. Random re-verification is the documented countermeasure pattern (see section 4).

### Gaps
- No primary Keka documentation was found on selfie or face matching, Wi-Fi restriction, or mock-GPS detection. No Darwinbox technical detail was found beyond the marketplace listing.
- No technical description was found of how iClicker's Bluetooth range is enforced: phone-to-instructor RSSI or something else.
- No independent tests were found of CourseKey or Teams ultrasound leakage through doors or open windows, or of relay attacks (e.g., re-playing the sound over a phone call).
- Official Android developer pages for `Location.isMock()` (API 31) were not returned in search; only third-party references were found.

## 3. Research: proxy-free attendance, BLE spoofing and relay attacks, proof-of-presence

### Takeaway
Peer-reviewed work shows that static BLE beacon attendance is trivially defeated: Kim, Lee and Paek (IEEE Access 2018) cloned a real university's commercial beacon and marked absent students present. Their proposed countermeasures were themselves circumvented. Research mitigations are rotating cryptographic tokens in the beacon (TOTP), biometric binding (face), tight per-room RSSI calibration with low TX power, and, for relays, latency or distance-bounding checks. Formal "proof-of-location" research shows that true relay resistance needs distance bounding, which BLE on commodity phones cannot provide.

### Cited Findings

**Attacks on BLE attendance**
- Kim, Lee and Paek, "Neutralizing BLE Beacon-Based Electronic Attendance System Using Signal Imitation Attack," *IEEE Access* 6:77921–77930 (2018), DOI 10.1109/ACCESS.2018.2884488:
  - They attacked a commercial beacon attendance system in use at a university and showed attendance could be marked without the student being present.
  - They analysed its vulnerabilities and proposed countermeasures, then showed "additional attack methods … to re-counteract those possible counter-measures."
  — [IEEE Xplore](https://ieeexplore.ieee.org/document/8555557/); [CAU ScholarWorks](https://scholarworks.bwise.kr/cau/handle/2019.sw.cau/3338)
- A student blog post (2018) describes bypassing a university e-attendance app by using a phone as a fake beacon, which enabled the "mark presence" button without attending class. — [Sungho Lee blog](https://sungho-lee.kr/2018/03/25/bypassing-university-attendance-system.html)
- On BLE relay attacks generally (NCC Group research, summarised): relay tooling adds detectable latency, so products defend with strict GATT response-time limits and/or link-layer encryption. — [Bournemouth CERT summary of NCC Group](https://cert.bournemouth.ac.uk/?p=17442)
- imec argues secure distance bounding (SDB) on BLE radios "can effectively prevent relay attacks." This is vendor and research-lab material. — [imec SDB white paper](https://www.imec-int.com/en/expertise/sensors-for-iot/secure-system-solutions/distance-bounding-white-paper)

**Defensive designs from the literature**
- **UGM thesis, 2020:**
  - The BLE beacon broadcasts a rotating TOTP code, and CNN face recognition runs in an Android app (server-side matching).
  - BLE verification takes about 10 s. Face recognition FAR is **0.0059** and FRR **0.168**.
  - The authors frame BLE TOTP as giving "fast and simultaneous attendance" while face recognition "ensures student honesty."
  — [UGM repository](https://etd.repository.ugm.ac.id/penelitian/detail/190222)
- **SMATCH (KMUTT, Thailand):** BLE beacons plus smartphone plus face recognition, with beacon signal strength used to infer seating position. A Random Forest reached about 98% on unseen data, but the face test used only 10 people from a public dataset. — [KMUTT](https://kirim.kmutt.ac.th/converis/portal/detail/Publication/1392443011?lang=en_GB)
- **Korean beacon + fingerprint/face system:** uses beacon intensity to exclude out-of-room attendance (publication year unconfirmed). — [earticle.net](https://www.earticle.net/Article/A331566)
- **Other BLE-only systems:** a modified iBeacon mechanism (2018), and BeaconDroid (2020), where student phones transmit and the instructor's device scans. — [SciTePress 2018](https://www.scitepress.org/Papers/2018/68302/); [BeaconDroid, UoD Journal](https://journal.uod.ac/index.php/uodjournal/article/view/945)
- **Seoul National University:**
  - Frames attendance as BLE geofencing, where beacon transmit power sets the fence range. BLE geofencing performed significantly better than Wi-Fi.
  - The ASEE version placed a class-2 beacon at the centre of a 9 m × 12 m classroom ceiling to limit body and fading effects, and notes that wall attenuation further weakens the signal.
  — [SNU paper](https://mmlab.snu.ac.kr/html/publications/docs/attendance_mckwak.pdf); [ASEE paper](https://peer.asee.org/26474.pdf)
- **Faculty-monitoring RSSI study (2019):** room layout and interiors change RSS behaviour, so thresholds must be set per room. Gaussian and average filters were used to reject outliers. — [REDI/CEDIA](https://redi.cedia.edu.ec/document/246610)
- **Door-sentinel layout:** a BLE study summary describes one beacon outside the door and one inside, and notes that RSSI varies with how the phone is held. This is a vendor blog summary. — [BeaconZone](https://www.beaconzone.co.uk/blog/page/28/)
- **Wi-Fi attendance error modes:** misclassification happens in both directions, outside-as-inside and inside-as-outside, due to layout and interference. — [ACM 2025 paper via Unpaywall](https://unpaywall.org/10.1145%2F3704522.3704523)
- **Wi-Fi fingerprinting (BUET seminar, 2026):** reports **94.74%** in/out classification accuracy. — [BUET CSE](https://cse.buet.ac.bd/home/news_detail/241)
- **Alternative cheap anti-proxy sensor:** a 2026 arXiv preprint does RFID-based classroom attendance with proxy detection via weight sensors on seats (title only reviewed). — [arXiv 2604.22697](https://arxiv.org/pdf/2604.22697)

**Ultrasound as a room-bounded channel (research)**
- A KAIST thesis notes that inaudible-frequency signals are "relatively suitable for room-based services because they pass through walls poorly compared with Wi-Fi and Bluetooth." — [KAIST](https://dspace.kaist.ac.kr/handle/10203/267084?mode=full)
- Google's near-ultrasonic protocol (Getreuer et al., IEEE Trans. Multimedia 2018) uses the 18.5–20 kHz band on commodity phones. Transmission is "reliable at 2 m" and "often works at 10 m" indoors. — [Ultrasonic Communication Using Consumer Hardware](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware)
- TU Berlin found 223 Android apps listening for 18–20 kHz ultrasonic beacons, and detected beacons in 4 of 35 stores. This shows phone mics can receive near-ultrasound in practice. — [Arp et al. 2016](https://mlsec.tu-berlin.de/docs/2016-batmobile.pdf); [EuroS&P 2017](https://vamos.mlsec.org/docs/2017a-eurosp.pdf)
- A patent document notes that many portable terminals have a detectable upper limit around **21 kHz**, due to microphone characteristics and low-pass filtering. — [US patent 9709655](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9709655)

**Proof-of-location / proof-of-presence protocols**
- In proof-of-location, users collect location-and-time tokens from a location authority and from nearby witnesses. Each witness runs distance bounding before endorsing. — ["Where Have You Been? Secure Location Provenance for Mobile Devices"](https://arxiv.org/pdf/1107.1821)
- Akand et al. (IEEE TDSC) implemented privacy-preserving PoL on an off-the-shelf Android phone. They identified a "geo-tampering" attack, where the issuer node is physically moved, and proposed a countermeasure. — [TDSC paper](https://perso.limos.fr/~palafour/PAPERS/PDF/TDSC-2020-10-0607.R1_Proof_hi%20(1).pdf)
- A 2025 taxonomy of PoL designs covers cryptographic guarantees, spatio-temporal sync, trust and witness models, and overhead. — [arXiv 2508.14230](https://arxiv.org/html/2508.14230v1)
- An ACM Computing Surveys paper (2019) on distance bounding covers relay, distance fraud and mafia-fraud threat models. — [Avoine et al.](https://research.sabanciuniv.edu/id/eprint/36919)

### Inferences
- The Kim et al. paper is the key citation for "why a static beacon is not enough." The team's existing ESP32 self-generated rotating token already addresses signal imitation (cloning or replay), in line with the UGM TOTP design. It does **not** address the wall or relay problem: a token received through a wall is still a valid token.
- Relay attacks, where an accomplice inside forwards the token to a colleague outside, can only be fully stopped by distance bounding, which commodity Android BLE does not expose. Practical mitigations are:
  - short token lifetimes (seconds), so a relay must be live;
  - binding the token to a face capture taken at the same moment;
  - requiring a second channel that does not pass through walls (ultrasound);
  - random re-checks, which make a standing relay operation costly.
- Per-room RSSI thresholds are endorsed by the literature but are fragile. Wall gaps are "up to" 20 dB, body shadowing is about 11 dB, and grip orientation matters. RSSI should be one factor, used with low TX power and a calibrated threshold, never the sole gate.
- An inside/outside dual-beacon (door sentinel) layout is cheap with two ESP32s and turns an absolute threshold into a relative comparison: is the inside beacon stronger than the outside one? This should be more robust to phone-to-phone RSSI offsets. It is inferred from the BeaconZone summary and general RSSI physics; I found no measured study.

### Gaps
- The full text of Kim et al. (the specific countermeasures and counter-attacks) could not be retrieved because the PDF host was blocked.
- I found no peer-reviewed 2024–2026 paper combining BLE, on-device face recognition and ultrasound for attendance, and none measuring BLE in-room versus behind-wall misclassification rates with a specific RSSI threshold.
- No cross-device study of near-ultrasound reception on low-cost Android phones (sub-INR 10,000 models) was found. The 21 kHz limit and the 2 m reliable / 10 m often figures are the closest.

## 4. Best cost/benefit combination for a hackathon prototype (ESP32 about INR 400–600, staff's own cheap Android phones)

### Takeaway
The credible, citable, demo-able answer is the clinical RTLS pattern scaled down:
- keep BLE with a rotating token for discovery and anti-cloning;
- add a wall-bounded second factor on the same ESP32: a near-ultrasound (about 18.5–20 kHz) rotating code from a small speaker, as CourseKey, Teams Rooms, Sonitor and AeroScout do;
- bind it to on-device face recognition with liveness and mock-GPS rejection, inside short or random check windows.

IR is what hospitals use for "certainty," but phones cannot receive it. RSSI tuning alone remains about 90% at best, per Kontakt.io's own figures.

### Cited Findings
- Wall-bounded modalities are what move room accuracy from about 75–90% (BLE-only) to a claimed 99.99% (BLE+IR). — [Kontakt.io Beam Mini table](https://support.kontakt.io/hc/en-gb/articles/14512613170972-Intro-to-Beam-Mini-with-Cisco-Spaces)
- Microsoft uses ultrasound plus BLE together on laptops and phones for exactly the "which room am I in" problem, citing that BLE penetrates walls and ultrasound does not. — [Microsoft Learn](https://learn.microsoft.com/en-us/microsoftteams/rooms/proximity-join)
- CourseKey uses a phone-receivable inaudible tone with a unique code for classroom-level attendance. — [Campus Technology](https://campustechnology.com/Articles/2017/10/02/New-CourseKey-Feature-Takes-Attendance-with-Sound.aspx)
- Near-ultrasound at 18.5–20 kHz on commodity phones is reliable at 2 m and often works at 10 m indoors. — [Getreuer et al.](https://www.academia.edu/164596957/Ultrasonic_Communication_Using_Consumer_Hardware)
- Phone microphones commonly cut off around 21 kHz. — [US 9709655](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/9709655)
- Short instructor-triggered windows (Acadly, 2.5 min) are the vendor-endorsed anti-"stand-outside" control. — [Acadly](https://pages.acadly.com/rfums-for-students)
- Face match with liveness is standard in Indian HR (greytHR). The national regulator NMC adopted face authentication after fingerprint fraud. — [greytHR](https://www.greythr.com/help-admin/attendance-management/employee-attendance-marking-methods/); [The South First](https://thesouthfirst.com/news/fingerprint-biometric-system-fails-in-medical-colleges-nmc-switches-to-face-based-attendance-for-faculty)
- GPS alone is 30–50 m off indoors, and real geofences are 100–500 m, so GPS only proves campus, not room. — [Offision](https://offision.com/help/en/attendance/verify-clock-ins-with-gps-ip-and-selfies/); [The South First](https://thesouthfirst.com/news/fingerprint-biometric-system-fails-in-medical-colleges-nmc-switches-to-face-based-attendance-for-faculty); [Scroll.in](https://scroll.in/article/1075292/bihar-is-using-an-app-to-track-teachers-attendance-much-to-their-anger)
- Bihar's photo-plus-GPS system was defeated by photo reuse, old video and GPS manipulation. — [Patna Press](https://patnapress.com/bihar-teacher-attendance-scam-photos-fake-locations-and-same-clothes-for-10-days-expose-e-shiksha-fraud/)
- Per-fix mock-location detection is available to Flutter apps via `Position.isMocked`. — [geolocator](https://pub-web.flutter-io.cn/documentation/geolocator/8.2.1/geolocator/Position/isMocked.html)

### Inferences
Option ranking, from my own synthesis. Costs beyond the ESP32 are rough estimates and were not sourced.

| Option | What it stops | Wall certainty | Extra hardware | Demo-ability | Industry precedent |
|---|---|---|---|---|---|
| A. BLE rotating token, low TX power + per-room RSSI threshold (calibrate mode) | cloning/replay (Kim et al.) | Weak (about 75–90%, Kontakt.io) | none | High | Kontakt.io BLE-only tier, SNU geofencing |
| B. A + second "outside/door" ESP32 sentinel; accept only if inside RSSI > outside RSSI by margin | standing just outside the door | Medium | +1 ESP32 (about INR 400–600) | High (walk through the door live) | Door-beacon layout (BeaconZone) |
| C. A + **near-ultrasound rotating code** from ESP32 (I2S DAC/amp + small tweeter or piezo), phone mic decodes; require both BLE token and ultrasound code within seconds | wall, corridor and neighbouring-room check-ins | Strong (sound does not pass walls well) | small amp + speaker (est. a few hundred INR) | High, and judges can "hear" nothing while it works | CourseKey, Teams Rooms, Sonitor, AeroScout |
| D. Face + liveness on device, bound to the same token window | proxy by another person, photo reuse | n/a (identity) | none | High | greytHR, Zoho, NMC, UGM thesis |
| E. Random re-verification ping during the day (push → re-scan BLE/ultrasound + quick face) | mark-and-leave, predictable-window gaming | n/a (temporal) | none | Medium | Acadly short window; Bihar fixed window shows the failure |
| F. Mock-GPS rejection + campus geofence | remote marking from home | n/a (campus) | none | High | Giriton, geolocator `isMocked` |
| G. IR (as in CenTrak/Kontakt.io) | wall | Strongest in hospitals | phones lack IR receivers | Low | CenTrak, Midmark, Kontakt.io |
| H. UWB (Acadly, Apple/Samsung) | wall/distance | Strong | UWB modules expensive; cheap Androids lack UWB | Low | Acadly |

- **Recommended stack for the hackathon:** A + C + D + F, with E as the stretch goal and B as a fallback if ultrasound proves flaky on the team's test phones.
  - It mirrors the Kontakt.io/Cisco and Teams Rooms architecture: RF for discovery, a wall-bounded signal for room certainty.
  - It uses only one ESP32 per room plus a small speaker.
  - It produces a crisp live demo: a phone on the other side of the wall gets the BLE token but not the ultrasound code, so it is rejected.
- **Risks to pre-empt with judges:**
  1. Cheap phone mics vary near 20 kHz. Calibrate per device, and consider 17.5–19 kHz, accepting slight audibility for some young listeners.
  2. Open doors leak sound, as BLE leaks through walls. Mitigate with low volume, a speaker aimed into the room, and requiring the code over several seconds.
  3. Live audio or BLE relay by an inside accomplice. Mitigate with a short token TTL bound to the face capture, and random re-checks. True relay-proofing needs distance bounding, which is out of scope.
  4. Android background-mic and Bluetooth permission prompts. Run the check only in the foreground during check-in.
- **Pitch line backed by sources:**
  - Hospitals don't trust Bluetooth for room location either.
  - Kontakt.io's own spec puts BLE-only at about 90% even with an in-room gateway. They add IR or ultrasound because walls stop it.
  - Microsoft does the same with ultrasound in Teams Rooms.
  - We do it with a INR 500 ESP32 and the phone's microphone.

### Gaps
- No sourced component prices were found for an ESP32 near-ultrasound transmitter (I2S amplifier such as MAX98357A plus tweeter) in India. The team should quote local prices (Robu.in, ElectronicsComp, etc.) themselves.
- No measured data was found on 18–20 kHz attenuation through typical Indian college walls (brick, plaster) versus doors and windows. The team should measure this in the staff room as part of calibration and show it as their own evidence.
- No study was found quantifying how much random re-verification reduces proxy attendance. The recommendation rests on vendor practice (Acadly) and the Bihar counter-example, not on measured outcomes.
