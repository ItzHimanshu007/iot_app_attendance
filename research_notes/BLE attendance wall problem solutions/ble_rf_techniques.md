# BLE / RF-only techniques for room-level containment ("inside the staff room" vs "just outside the wall")

Scope note for the report writer: the research environment's network blocked direct page fetches of PMC, arXiv, docs.espressif.com and espressif.com (HTTP 403 at the egress proxy). Figures below come from search-engine extracts of those pages (quoted figures), from vendor pages, and from the cited papers' abstracts. Where an extract could not be tied to one exact paper, this is flagged. Numbers labelled "model calculation" are my own log-distance path-loss arithmetic and are illustrations, not measurements.

Project context checked in the repo: the beacon firmware currently advertises at `BLE_TX_POWER_DBM 9` (+9 dBm, the ESP32 maximum) with `BLE_ADV_INTERVAL 160` (160 x 0.625 ms = 100 ms) (`/home/user/iot_app_attendance/firmware/staff_beacon/config.h`, lines 32-34).

## 1. Wall attenuation at 2.4 GHz, phone RSSI noise, and whether one RSSI threshold can separate inside from outside

### Takeaway
A typical interior wall costs only about 2-12 dB at 2.4 GHz (glass and drywall 2-5 dB, a single brick leaf about 8-12 dB, thick concrete 12-30 dB). Phone RSSI error from orientation, body shadowing and handset model is the same size or larger: about 6 dB between models, up to 8 dB from small angle changes, and 10-20 dB from a body in the path. So one absolute RSSI threshold on one beacon cannot reliably separate "inside" from "just outside the wall". This holds most strongly when the beacon is within a few metres of the wall, which it nearly always is in a small staff room.

### Cited Findings
**Wall and material attenuation at 2.4 GHz (vendor and rule-of-thumb tables; values vary with thickness and construction):**
- Plasterboard/drywall 2-4 dB. Brick (90-110 mm) 8-12 dB. Concrete 150 mm 12-20 dB. Reinforced concrete 200-240 mm 20-30 dB. Single clear glass 2-3 dB. Low-E/tinted glass 10-25 dB. — [zencontrol design note (2025)](https://support.zencontrol.com/hc/en-us/articles/13691317355919-Wireless-Thread-Signal-Strength-Path-Loss-Practical-Design-Note)
- CWNA study-guide values at 2.4 GHz: drywall/sheetrock about 3 dB, "brick, concrete, concrete blocks" about 12 dB, untinted window about 3 dB. — [Aruba community thread quoting CWNA guide](https://community.arubanetworks.com/viewthread?MID=17983)
- iBwave material table at 2.4 GHz: dry-wall partition 5.4 dB, lime brick 4.3 dB, heavy concrete 22.8 dB. Attenuation is substantially higher at 5 GHz. — [iBwave blog](https://blog.ibwave.com/?p=3095)
- Interior wall (15.2 cm) 15-20 dB, bearing wall (30.5 cm) 20-25 dB, metallised tinted window 5-8 dB. — [Keenetic Wi-Fi attenuation table](https://help.keenetic.com/hc/en-us/articles/213968869)
- Sources disagree for brick in particular: iBwave 4.3 dB for lime brick vs 8-12 dB (zencontrol) vs about 12 dB (CWNA). — [iBwave](https://blog.ibwave.com/?p=3095); contradicted by [zencontrol](https://support.zencontrol.com/hc/en-us/articles/13691317355919-Wireless-Thread-Signal-Strength-Path-Loss-Practical-Design-Note) and [CWNA via Aruba](https://community.arubanetworks.com/viewthread?MID=17983)

**Phone RSSI noise, body and orientation effects:**
- Trinity College Dublin's measurements of BLE between phones found that RSSI varies strongly with handset model, relative handset orientation, and absorption by human bodies and bags. The effect is "comparable with that caused by moving 2m", and RSSI "need not decrease with increasing distance". — [Leith & Farrell, arXiv 2006.06822](https://arxiv.org/abs/2006.06822v1); [CONNECT/TCD summary](https://connectcentre.ie/news/trinity-study-confirms-accuracy-concerns-on-contact-tracing-apps)
- In that work, people sitting with the phone in a pocket received low signal strength even within 1 m. — [Leith & Farrell (as summarised in search results)](https://arxiv.org/abs/2006.06822v1)
- Static, unobstructed RSSI noise can be under 1 dB standard deviation. Small changes in receiver angle can shift per-channel levels by up to 8 dB. With a phone held in hand, line-of-sight vs body-obstructed readings differ by 10-20 dB. — reported in smartphone BLE measurement papers [arXiv 2006.15711](https://arxiv.org/pdf/2006.15711) / [arXiv 2006.09099](https://arxiv.org/pdf/2006.09099). The search extract did not let me pin each number to one of these two papers.
- On Google Pixel phones, the three BLE advertising channels differed by up to 15 dB at the same distance, because of channel-specific multipath fading. — [Gentner et al., arXiv 2006.09099](https://arxiv.org/pdf/2006.09099)
- One evaluation found that at least one Pixel model recorded RSSI only from one of the three advertising channels. — [Leith & Farrell bus study, arXiv 2006.08543](https://arxiv.org/pdf/2006.08543)
- A vendor (Lansitec) cites NIST work showing that one person in the direct path can shift RSSI by about 11 dB. It also says the RSSI gap between the correct room and the adjacent room can be "up to about 20 dB", and so can also be much smaller. This is a secondary, vendor source. — [Lansitec BLE presence detection guide](https://www.lansitec.com/blogs/ble-presence-detection/); [Lansitec RSSI guide](https://www.lansitec.com/blogs/rssi-indoor-positioning/)

**Device-to-device RSSI offsets (Android heterogeneity):**
- Different phone types measured RSSI values up to 6 dB apart at the same position and orientation, including different models from the same vendor. — [ResearchGate figure from a phone-comparison study](https://www.researchgate.net/figure/Comparison-of-BLE-RSSI-values-for-different-phones-at-the-same-position-and-orientation_fig1_317423547)
- Google/Apple Exposure Notifications had to maintain a per-model calibration CSV of TX power and RX correction. Confidence tiers ran from 1 to 3: tier 1 is a manufacturer average, tier 2 one measured antenna orientation, tier 3 a measured range of orientations. — [beaconzone blog](https://beaconzone.co.uk/blog/?p=5616); [PersonalData wiki on BLE calibration](https://wiki.personaldata.io/wiki/Item:Q4792)
- Example calibration entry: Samsung XCover P_TX = -24 dBm, RX correction Δ_RX = 5 dB. Galaxy S7 had a different TX value. — [Distance Estimation for BLE-based Contact Tracing, arXiv 2101.09075](https://arxiv.org/pdf/2101.09075)
- Google later updated calibration values for hundreds of devices. — [9to5Google](https://9to5google.com/?p=370257)
- A vehicle-access calibration patent gives an illustrative offset of +8 for a Galaxy S7 relative to an iPhone 6 reference. This is a patent example, not measured data. — [US 11122389](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11122389)

**Direct evidence on single-threshold room detection:**
- WPI's iBeacon in-room presence study used a -60 dBm threshold plus a 3 dB inside/outside difference to decide entry vs exit. The -60 dBm threshold only worked when the beacon was mounted outside the entrance door, so it did not transfer to other placements. — [WPI CWINS, "Using iBeacon for Intelligent In-Room Presence Detection"](https://www.cwins.wpi.edu/publications/conference%20paper/Sushi.pdf)
- A vendor recommends not assuming "strongest RSSI = correct room". It suggests rolling-window repeated detections, top-vs-second-best comparison, hysteresis, and a "near boundary" state for near-ties. — [Lansitec](https://www.lansitec.com/blogs/ble-presence-detection/)

### Inferences
- Model calculation (log-distance, FSPL at 1 m = 40.2 dB at 2.44 GHz, TX +9 dBm, 8 m x 6 m room, beacon on the ceiling at the centre, 1.8 m above the phone). The farthest in-room corner reads about -46 dBm (n=2) to -53 dBm (n=3). A phone 0.3 m outside the nearest long wall (3.3 m from the beacon) reads -46/-51 dBm through a 3 dB glass or drywall wall, -51/-56 dBm through an 8 dB wall, and -55/-60 dBm through a 12 dB brick wall. The inside-worst vs outside-best margin is therefore -1 to +9 dB for common walls, and only about 16 dB for 20 dB concrete. That margin is smaller than the 6 dB model offset plus 10-20 dB body shadowing. A single threshold on one beacon will both admit proxies and reject honest staff (phone in a bag or pocket).
- If the beacon sits near a wall (for example on a desk against the wall), a person 0.8 m outside that wall reads about -38 dBm through 10 dB. That is stronger than an honest user 7.5 m away inside the room (-49 to -57 dBm). The wall is worth "moving 2-3x farther away", no more.
- The attacker and the honest user are asymmetric. The proxy outside the wall is motivated: they hold the phone up, press it to the wall, and pick the best orientation. Honest staff carry phones in pockets and bags. Any threshold low enough to accept honest pocket readings will accept a motivated outsider.
- Indian college buildings commonly use 230 mm (9-inch) external and 115 mm (4.5-inch) internal plastered burnt-clay brick walls. This is general construction knowledge, not sourced here. By the tables above, a 115 mm partition is about 8-12 dB, roughly the "brick" row. Doors, windows, ventilators and glass panes in that wall are 2-3 dB holes. Leakage through a door or window, not through the brick, sets the worst case.

### Gaps
- I found no peer-reviewed measurement of BLE (rather than Wi-Fi) attenuation through Indian-style 115 mm or 230 mm plastered brick walls. The team should measure it: walk a phone along both sides of the actual wall at several TX powers.
- I found no single study tabulating RSSI offsets across many cheap Android models (Redmi, Realme, Samsung M/A series). The Google EN calibration CSV would have that data, but I could not retrieve it.
- The NIST "11 dB per person" figure comes only from a vendor's citation. The original NIST report was not retrieved.

## 2. Lowering ESP32 TX power and beacon placement or shielding

### Takeaway
On the original ESP32 the BLE TX power can be set from -12 dBm to +9 dBm (`ESP_PWR_LVL_N12` to `ESP_PWR_LVL_P9`). Lowering it shrinks how far the beacon is heard at all, but it shifts inside and outside RSSI by the same number of dB, so it does not widen the inside/outside margin. Placement changes geometry and does help: centre of room, ceiling, at least 3 m from any wall facing an accessible area. The biggest win comes from a "tap/near-field zone": very low TX power plus a requirement that the phone be within about 10-30 cm of the beacon. That opens a margin of more than 20 dB, which swamps device offsets. Metal backplates or reflectors can make an antenna directional, but no measured BLE room-containment study was found, and metal near the ESP32 PCB antenna detunes it.

### Cited Findings
- On ESP32, the BLE power level range is `ESP_PWR_LVL_N12` to `ESP_PWR_LVL_P9`, where P9 = +9 dBm is the maximum. It is set with `esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, ESP_PWR_LVL_P9)`, with separate power types for advertising, scanning and each connection. Newer chips (ESP32-C2, C5, C6, H2) should use `esp_ble_tx_power_set_enhanced`. — [Espressif ESP-Techpedia: Wireless TX power configuration](https://docs.espressif.com/projects/esp-techpedia/en/latest/esp-friends/advanced-development/performance/modify-tx-power.html)
- Forum users report that calling `esp_ble_tx_power_set` sometimes had no visible effect on the advertised TX level, or stuck at about +3 dBm. Verify actual output with a phone before trusting the setting. — [esp32.com thread "esp_ble_tx_power_set has no effect"](https://esp32.com/viewtopic.php?p=29260); [esp32.com "how to set BLE transmit power above 3dB?"](https://esp32.com/viewtopic.php?p=56871)
- A hobby site claims ESP32 output power runs from -20 to +4 dBm and quotes typical indoor beacon range of 10-30 m. The first figure conflicts with Espressif's -12 to +9 dBm and is probably generic beacon data, so it should not be relied on. — [Zbotic](https://zbotic.in/esp32-ble-beacon-indoor-location-tracking-with-ibeacon/); contradicted by [Espressif ESP-Techpedia](https://docs.espressif.com/projects/esp-techpedia/en/latest/esp-friends/advanced-development/performance/modify-tx-power.html)
- The WPI in-room presence study found that its threshold only worked with the beacon mounted outside the entrance door. Placement determined whether threshold detection worked at all. — [WPI CWINS paper](https://www.cwins.wpi.edu/publications/conference%20paper/Sushi.pdf)
- An academic BLE positioning demonstrator used ESP32 beacons with external antennas and "self-made, colored reflectors for directing the Bluetooth signal", with a beacon in a room corner. No confinement measurements appeared in the extract. — [arXiv 2110.06832](https://arxiv.org/pdf/2110.06832)
- Patent literature notes that a conductive metal element placed near an omnidirectional radiator makes it directional. — [USPTO 10390183 (light-fixture beacon patent; attribution per search extract)](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10390183)
- Espressif antenna guidance (as summarised by NextPCB) calls for at least 15 mm clearance from metal around the PCB antenna. Enclosure or metal detuning is a common cause of range loss, and the fix is an external U.FL antenna. — [NextPCB ESP32 antenna design guide](https://www.nextpcb.com/blog/esp32-antenna-design-guide)

### Inferences
- Model calculation for TX power. Every dB of TX reduction lowers inside and outside RSSI equally, so the inside-vs-outside margin from section 1 is unchanged; you only re-tune the threshold. TX reduction helps against far-away proxies (outside the campus wall tens of metres away), whose signal drops below the phone's sensitivity, but not against someone standing 0.5-1 m outside the staff-room wall.
- Model calculation for the "tap zone" (n=2 inside, n=2-2.5 outside, any TX power):
  - At 10 cm the phone reads TX - 20 dB (e.g. -32 dBm at -12 dBm TX).
  - At 30 cm it reads TX - 30 dB (-42 dBm at -12 dBm TX).
  - At 3 m behind a 3 dB glass or drywall wall it reads TX - 53 dB (-65 dBm). Behind a 10 dB brick wall it reads TX - 62 dB (-74 dBm).
  - The 30 cm-vs-outside margin is therefore about 23-32 dB. That exceeds the 6 dB device offset and 10-20 dB body shadowing, and body shadowing barely applies when the phone is held at the beacon.
  - At -12 dBm the beacon is effectively inaudible beyond a few metres. This also shrinks the window in which a nearby attacker can sniff the rotating token.
  - The cost: staff must walk to a "check-in point" (like an NFC tap) rather than being detected anywhere in the room.
- Ceiling mounting at room centre helps in two ways. It maximises the distance to the nearest wall, and it gives a stable line-of-sight path to phones held in hand. It also makes the outside phone's path more oblique through the wall, which increases effective wall loss. This last point is a physical argument, not measured here.
- A metal backplate or reflector (e.g. a beacon in a small metal box open towards the room interior, antenna at least 15 mm from the metal) could add several dB of front-to-back ratio towards walls. Without a measurement it should be treated as an experiment. A cheaper, more predictable alternative is an ESP32 module with a U.FL connector and a small directional (patch) antenna aimed downward from the ceiling.

### Gaps
- No measured study was found of ESP32 BLE with a metal reflector or shield confining coverage to a room. Front-to-back ratios for DIY reflectors at 2.4 GHz are unknown.
- I did not confirm BLE TX power ranges for ESP32-C3/S3/C6 (some sources suggest up to about +18-21 dBm on newer chips, but this was not verified). The team should check `esp_power_level_t` in the ESP-IDF headers for their exact chip.
- I found no measured sensitivity floor for cheap Android phones, so the exact "inaudible" radius at -12 dBm is not known.

## 3. Multi-beacon approaches: require-all, differential (inside vs corridor) RSSI, trilateration, and room-level presence studies

### Takeaway
Published BLE room-level classification typically reaches about 70-90% accuracy with a few beacons, and above 95% only with dense beacons or favourable layouts. That is not good enough on its own for an anti-proxy decision. The most promising cheap RF approach for this project is differential RSSI. Measure an inside beacon and a guard beacon on the far side of the wall with the same phone, and require that the inside beacon is stronger by X dB. This cancels each phone model's receiver offset, and the wall loss counts in favour of the correct answer from both sides. That roughly doubles the useful margin.

### Cited Findings
- An empirical room-level BLE study used a kNN classifier with each room as a class. It reported 70-90% accuracy for house and university scenarios with a few beacons. In a 10-room residential test it reached 97.6% (laptop receiver) and 87.7% (Raspberry Pi) with all beacons, and 85-88% (laptop) and 74-76% (Pi) with only three beacons. — [Empirical Study of a Room-Level Localization System Based on BLE Beacons, Sensors 2021 (PMC8197460)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8197460/)
- In hospital patient rooms with one to four beacons, extremely randomized trees gave the best results: 81% accuracy for binary and 71% for multiclass zone classification. — [Development and Evaluation of BLE-Based Room-Level Localization ... Hand Hygiene (PMC9904895)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9904895/)
- An energy-harvesting BLE tag system combining Dempster-Shafer theory with fingerprinting reported room-level accuracy above 99% over about 2000 m² with many rooms, under standard test conditions. Note that the tag transmits and fixed gateways receive, which removes phone heterogeneity. — [Electronics 2024, 13(22), 4493](http://dx.doi.org/10.3390/electronics13224493)
- BLE fused with inertial (IMU) data reached 87.1% room-level accuracy, measured as the share of time each room was predicted correctly. — [arXiv 2305.19342](https://arxiv.org/pdf/2305.19342)
- A University of Geneva study in a three-room office and a six-room house reported better room detection with its algorithm than with raw RSSI. The extract gave no specific numbers. — [UNIGE paper](https://tam.unige.ch/index.php/download_file/view/123/151)
- Heterogeneous devices bias RSS, which mismatches pre-built radio maps. — [Reference Device-Assisted Adaptive Location Fingerprinting (PMC4934228)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4934228/)
- Signal-strength-difference (SSD) radio maps use RSS differences between transmitters to minimise device-dependent effects. — [Yang et al., Remote Sensing 2019 (DOAJ)](https://doaj.org/article/11a87ca35dcd4a189754bc8575e89206)
- Rank or relation-based metrics are more stable across devices than raw values. — [arXiv 2106.02777](https://arxiv.org/pdf/2106.02777)
- Difference-based approaches lose some information and can be incompatible with algorithms needing absolute RSSI. — [He, Hu & Chan, HKUST](https://cse.hkust.edu.hk/~gchan/papers/PC17_PracD.pdf)
- A refined RSSD with compressive sensing improved accuracy by 20.5% vs plain SSD and 15.6% vs CS alone. — [EURASIP JWCN 2020](https://jwcn-eurasipjournals.springeropen.com/track/pdf/10.1186/s13638-020-01683-8)
- A vendor recommends comparing the strongest receiver to the second-best rather than using an absolute threshold. — [Lansitec](https://www.lansitec.com/blogs/ble-presence-detection/)

### Inferences
- **Why differential works (model calculation).** Setup: wall at y=0, room 8 m x 6 m, inside beacon at room centre, guard beacon 1.5 m beyond the wall in the corridor, 10 dB wall, n=2.5, both at +9 dBm.
  - "Inside minus guard" reads +7.6 dB for the worst inside point (0.5 m from the shared wall), +9.4 dB in the inside corner by the wall, and +15.8 dB in the far corner.
  - It reads -23.6 dB for a person 0.5 m outside the wall, -12.8 dB at the corridor end, and -25.1 dB 3 m out.
  - The worst-inside vs best-outside separation is therefore about 20 dB. With a single centre beacon the same layout gives about 6 dB (section 1).
  - Any per-phone constant RX offset (about 6 dB between models) cancels exactly in the difference, because the same radio measures both.
  - Body shadowing does not cancel, because it depends on direction. With about 20 dB of separation, a 10-20 dB one-sided body loss can still occasionally flip a borderline reading. Temporal averaging (section 5) mitigates this.
- "Require all inside beacons to be heard above threshold" (beacons at both ends of the room) mainly trims false accepts at the room's ends and corners. A person outside the middle of a long wall still hears both. It still depends on absolute thresholds and therefore on phone offsets, so it is weaker than differential for the same hardware.
- Guard beacon placement matters. A guard placed inside the room near the wall fails, because honest users near that wall also hear the guard strongly. Guards must sit on the far side of each wall that faces an accessible area (corridor, verandah, outside the campus wall). A wall shared with another staff-controlled room may need no guard. Most rooms need 1-3 guards plus 1 inside beacon, i.e. 2-4 ESP32 boards.
- The guard beacons do not need to rotate secrets. They only need to be recognised (static ID) and to advertise at the same TX power as the inside beacon, or at a known power. If an attacker can spoof the guard with lower power, they bias the difference in their favour, so the guard should also be authenticated (rotating token or signed payload). Otherwise, treat "guard heard weakly or not at all" conservatively (see section 8).
- Indoor trilateration from phone RSSI typically has metre-scale errors. Room-level work therefore frames the problem as classification rather than geometry. For a wall-adjacent proxy at 0.5-1 m from the wall, trilateration error is larger than the distance to be resolved, so it is not recommended.

### Gaps
- I found no published study that tested exactly the "inside beacon minus corridor beacon" decision with smartphones and reported in-room vs out-of-room error rates. The 20 dB figure above is a model calculation. The team should measure it.
- I found no metre-level trilateration accuracy figures in the retrieved extracts (the Ivanov 2021 "Accuracy analysis of BLE beacon-based localization in smart buildings" paper was found but its numbers were not retrieved: [SAGE](https://journals.sagepub.com/doi/10.3233/AIS-210607)).
- Kontakt.io and Estimote room-level presence product documentation was not retrieved, so vendor-claimed room-level accuracy figures are missing.

## 4. RSSI fingerprinting / machine-learning classifiers (kNN, SVM, random forest) for in-room vs out-of-room

### Takeaway
ML on multi-beacon RSSI vectors gives about 80-91% room-level accuracy in realistic multi-room deployments and about 99% only in small or controlled setups. Random-forest-type models usually beat SVM and kNN. Calibration needs a site survey, which device heterogeneity and furniture or people changes erode. For a student team, a hand-tuned differential rule (section 3) with temporal smoothing is likely as accurate and far easier to maintain. ML is an optional later layer.

### Cited Findings
- An RSS fingerprinting study on a small grid compared kNN, SVM and Random Forest. Random Forest scored about 99.95% on its test set vs about 99.16% for SVM, with smaller worst-case error. — [Sensors 2021, 21(13), 4605](https://doi.org/10.3390/s21134605)
- A whole-floor BLE deployment with 30 beacons (rooms of different sizes plus a hall) reported 91% accuracy detecting multiple users with Random Forest. Attribution per search extract; most likely this deployment study. — [Fingerprint-based indoor positioning system using BLE: real deployment study (ResearchGate)](https://www.researchgate.net/publication/367762231_Fingerprint-based_indoor_positioning_system_using_BLE_real_deployment_study)
- Extremely randomized trees: 81% binary, 71% multiclass, 1-4 beacons per patient room. — [PMC9904895](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9904895/)
- kNN room classification: 70-90% typical. 97.6% with all beacons in a residential test, falling to 85-88% with three beacons. Accuracy also depends on the receiver hardware (laptop vs Raspberry Pi differed by about 10 points). — [PMC8197460](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8197460/)
- BLE occupancy estimation with SVM reached very high accuracy at 200 Hz sampling, but only 86.35% at 20 Hz. Sample rate strongly affects classifier accuracy. — [Estimating indoor occupancy through low-cost BLE devices, arXiv 2102.03351](https://arxiv.org/pdf/2102.03351)
- Heterogeneous devices bias RSS against the radio map, which motivates SSD and rank features. — [PMC4934228](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4934228/); [Yang et al. 2019](https://doaj.org/article/11a87ca35dcd4a189754bc8575e89206)

### Inferences
- The receiver-hardware effect in PMC8197460 (laptop vs Pi, about 10 percentage points) is a direct analogue of the cheap-Android heterogeneity problem. A model trained on one team member's phone will degrade on staff phones unless the features are differential (inside minus guard) or rank-based.
- If ML is attempted, use features that cancel device offsets: pairwise differences, ranks, and the windowed median or variance of each beacon. Train a small random forest or gradient-boosted tree on labelled walks (inside spots, outside-wall spots, corridor, door) collected with 3-5 different phone models. Ship it as a threshold table or tree in the Flutter app. Calibration effort is roughly a few hundred labelled windows per room. This is an estimate; no source gave a number.
- With only 2-4 beacons and a binary label, a hand-set rule (median of diff over N seconds > X dB) is a one-feature classifier. Most of the ML gain would come from the differential feature itself.

### Gaps
- No study found reports the exact binary "inside room vs immediately outside the wall" accuracy with smartphones and wall attenuation as the main variable.
- No retrieved source quantifies calibration effort (samples per room, survey time) or model drift over weeks for BLE fingerprints.

## 5. Temporal approaches: stable RSSI over N seconds, dwell time, entry trend

### Takeaway
Windowed decisions (median or percentile over 10-30 s, with hysteresis) are standard and cheap. They suppress multipath fades and momentary body shadowing for honest users. They do not stop a stationary proxy standing still outside the wall, because that person's RSSI is also stable. Entry or "walk-in" signatures (RSSI rising past a door beacon, then the inside beacon dominating) add some evidence but are easy to fake and are not well studied for phones. Android scan-rate limits constrain how many samples per second a cheap phone delivers.

### Cited Findings
- Vendor guidance recommends repeated detections in a short rolling window, hysteresis against flip-flopping between rooms, and a "near boundary" state when readings are near-tied. Some BLE receivers (TI is cited) report only the RSSI of the last received packet, which makes single readings noisy. — [Lansitec presence guide](https://www.lansitec.com/blogs/ble-presence-detection/); [Lansitec RSSI guide](https://www.lansitec.com/blogs/rssi-indoor-positioning/)
- A patent describes declaring presence or absence from a window of RSSI samples rather than a single reading, with window width as a design parameter and sliding windows analysed one sample at a time. — [US 10057723](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10057723)
- The WPI iBeacon study used an entry/exit decision (3 dB inside/outside difference and a -60 dBm threshold) with a door-mounted beacon. — [WPI CWINS](https://www.cwins.wpi.edu/publications/conference%20paper/Sushi.pdf)
- BLE classification accuracy fell to 86.35% at 20 Hz sampling vs much higher at 200 Hz. — [arXiv 2102.03351](https://arxiv.org/pdf/2102.03351)
- Since Android 7.0, an app may start or stop BLE scans at most 5 times per 30 s. Exceeding this silently returns no results for about 30 s. Scans running more than 30 minutes are downgraded to opportunistic. `SCAN_MODE_LOW_LATENCY` scans continuously, while `SCAN_MODE_LOW_POWER` can miss intermittent advertisers. — [Punch Through](https://punchthrough.com/ble-scan-returns-no-results-on-android/); [Punch Through scan errors](https://punchthrough.com/android-ble-scan-errors/); [ProAndroidDev](https://proandroiddev.com/to-find-a-beacon-without-losing-it-my-journey-into-a-realm-of-bluetooth-low-energy-on-android-aa3e2c2923aa)

### Inferences
- With the current 100 ms advertising interval and a single continuous `SCAN_MODE_LOW_LATENCY` scan (not restarted more than 5 times in 30 s), a phone should log many advertisements per beacon in a 10-20 s window. Exact reception rates on cheap phones were not found. A median over that window, rather than the max, removes the upward fades that a proxy would otherwise get lucky with. Requiring the condition (e.g. diff > X dB) to hold for at least 80% of the windowed samples gives hysteresis.
- Temporal smoothing mainly fixes false rejects (honest users with momentary body shadowing). It does little against a patient proxy who stands still at the best spot outside the wall. It must be combined with geometry (tap zone or differential) to stop proxies.
- An "entry signature" (door/guard beacon peaks, then the inside beacon rises above the guard and stays there for at least 20 s) is optional extra evidence. An outsider can mimic it by walking along the wall. It is most useful as an anomaly signal, e.g. a proxy who never shows a door-crossing pattern.

### Gaps
- No smartphone study found that quantifies dwell-time or hysteresis parameter choices against room-level error rates.
- Official Android documentation for the 5-scans/30-s limit was not retrieved; the sources are developer blogs.
- Advertisement reception rates for budget Android phones (packets per second at 100 ms advertising interval) were not found.

## 6. BLE direction finding (Bluetooth 5.1 AoA/AoD with Constant Tone Extension)

### Takeaway
Not feasible for this project in 2025-2026. Android phones expose no public API to transmit or receive CTE or IQ samples, so a phone can act neither as an AoA tag nor as an AoD receiver. Among Espressif chips, only the new ESP32-H4 (samples announced March 2026) lists AoA/AoD in marketing; no ESP-IDF direction-finding API was confirmed. The ESP32, C3, S3, C6, H2 and C5 have no documented CTE support. Commercial AoA antenna-array kits cost about USD 149-299 (Silicon Labs) or about ₹36,800 (u-blox XPLR-AOA-3) per locator.

### Cited Findings
- Espressif's ESP32-H4 announcement (April 2024) lists Direction Finding using AoA and AoD among Bluetooth 5.4 LE features. The product page repeats "Direction Finding (AoA/AoD)". — [Espressif ESP32-H4 news](https://www.espressif.com/en/news/ESP32-H4); [ESP32-H4 product page](https://www.espressif.com/en/products/socs/esp32-h4); [CNX Software](https://www.cnx-software.com/2024/04/15/esp32-h4-low-power-risc-v-soc-802-15-4-bluetooth-5-4-le/)
- In March 2026 Espressif announced ESP32-H4 samples, listing Direction Finding (AoA/AoD) for indoor positioning and stating the chip passed Bluetooth 6.0 certification. No mass-production date or ESP-IDF direction-finding API/example was found. — [Espressif ESP32-H4 sample announcement](https://www.espressif.com/en/news/ESP32_H4_Sample)
- An ESP-IDF GitHub issue asking for CTE on ESP32-C6 (certified BLE 5.3) reports finding no CTE implementation in the libraries. — [espressif/esp-idf issue #13531 (IDFGH-12525)](https://github.com/espressif/esp-idf/issues/13531)
- ESP32-H2 is described as Bluetooth LE 5.0-supported and certified to 5.3, with no direction-finding mention. — [ESP-IDF ESP32-H2 BLE overview](https://docs.espressif.com/projects/esp-idf/en/stable/esp32h2/api-guides/ble/overview.html)
- Nordic: "At this time smartphones do not support Bluetooth Direction Finding, but it is expected they will at some point." — [Nordic Bluetooth Direction Finding page](https://www.nordicsemi.com/Products/Wireless/Bluetooth-Direction-Finding)
- Phone SoCs may contain BT 5.1 hardware, but the software stack (drivers, firmware, angle calculation) was not exposed. — [Abalta Technologies (2021)](https://abaltatech.com/blog/2021/01/microlocation3/); [Nordic DevZone thread](https://devzone.nordicsemi.com/f/nordic-q-a/96452/android-bluetooth-5-1-direction-finding-aoa-aod-in-android-app)
- By design, AoD lets a single-antenna receiver such as a phone compute direction from IQ samples. AoA needs a multi-antenna array at the locator. CTE types are AoA, AoD 1 µs, and AoD 2 µs slots. — [Bluetooth SIG blog](https://www.bluetooth.com/blog/new-aoa-aod-bluetooth-capabilities/); [Bluetooth SIG RDF Technical Overview (Woolley)](https://www.bluetooth.com/wp-content/uploads/Files/developer/RDF_Technical_Overview.pdf)
- Kit costs:
  - Silicon Labs BG22-RB4191A 4x4 dual-polarised antenna array radio board kit: MSRP USD 149. — [Silicon Labs](https://silabs.com/development-tools/wireless/bluetooth/bg22-rb4191a-bg22-bluetooth-dual-polarized-antenna-array-radio-board)
  - Silicon Labs BG22-PK6022A Pro Kit (array plus mainboard): MSRP USD 299, listed at NOK 3,276 ex-VAT at Farnell. — [Silicon Labs BG22 Pro Kit](https://silabs.com/development-tools/wireless/bluetooth/bgm22-pro-kit); [Farnell Norway](https://no.farnell.com/en-NO/silicon-labs/bg22-pk6022a/pro-kit-bluetooth-low-energy-soc/dp/4011828)
  - u-blox XPLR-AOA-3 (NINA-B4, ANT-B10 antenna board): about ₹36,806 at Mouser India, about €353 in the EU. — [Mouser India](https://www.mouser.in/en/c/embedded-solutions/engineering-tools/sensor-development-tools/?m=u-blox); [Digi-Key XPLR-AOA](https://www.digikey.com/en/product-highlight/u/u-blox/xplr-aoa-direction-finding-and-indoor-positioning-explorer-kit)
- Nordic's nRF Connect SDK ships direction-finding central and locator samples, a reference for a full implementation on non-Espressif silicon. — [nRF Connect SDK direction finding central](https://docs.nordicsemi.com/bundle/ncs-3.0.0/page/nrf/samples/bluetooth/direction_finding_central/README.html)

### Inferences
- AoA (array in the room, phone transmits) fails because phones cannot append a CTE to their advertisements through any public Android API, and ordinary advertisements carry no CTE. AoD (beacon array transmits, phone computes angle) fails because Android exposes no IQ samples or AoD API. Neither works with cheap Android phones in 2026.
- Even with working AoA, a ceiling array gives an angle (a cone), not wall containment. It would still need a geometry rule plus anti-spoofing. Given costs of USD 149-299 or about ₹37k per locator, plus non-ESP32 toolchains, this is out of scope for a hackathon budget.
- ESP32-H4 may enable experimental AoD/AoA between two ESP32-H4 boards later, but that does not help phone-based attendance.

### Gaps
- I could not open the ESP-IDF "Major Feature Support Status" tables for ESP32-C6, H2, C5 or H4 to confirm the exact "Direction Finding" row. GitHub and Espressif marketing are the evidence used.
- I found no 2025-2026 Android release notes mentioning CTE or direction-finding APIs. The absence is inferred from Nordic's statement and from no such API appearing in Android's ranging docs, which list only BLE CS, BLE RSSI, UWB and Wi-Fi RTT.

## 7. Bluetooth Channel Sounding (Core 6.0) for distance measurement

### Takeaway
Channel Sounding (CS) is the first Bluetooth feature giving secure, roughly sub-metre distance between a phone and a tag. Android 16 exposes it through `RangingManager`/`android.ranging.ble.cs`. However, as of 2025-2026 it needs flagship phones (Pixel 10 confirmed; some 2026 flagships rumoured) and a non-Espressif CS-capable chip on the beacon (Nordic nRF54L, Silicon Labs BG24/BG2B, NXP MCX W). ESP-IDF lists CS as unsupported on ESP32-S3 and ESP32-C2. It is not usable with cheap Indian Android phones or the team's ESP32 boards today. It is a future upgrade path only.

### Cited Findings
- Android 16 introduced a Ranging module giving one interface for Bluetooth Channel Sounding, UWB and Wi-Fi NAN RTT. It is obtained via `Context.getSystemService(RangingManager.class)`, with BLE CS parameters in `android.ranging.ble.cs` and the `BLE_CS` technology constant. — [Android Developers: Range between devices](https://developer.android.com/develop/connectivity/ranging); [RangingManager reference](https://developer.android.com/reference/android/ranging/RangingManager); [android.ranging.ble.cs](https://developer.android.com/reference/android/ranging/ble/cs/package-summary); [Android 16 features](https://developer.android.com/about/versions/16/features)
- Google Pixel 10 (released 28 August 2025) was the first phone with CS hardware. Nordic's nRF54L15 reflector sample works with it via Android 16's `RangingManager`, and was confirmed with Android 17 Beta 4 (June 2026). — [Nordic DevZone blog: CS on Pixel 10](https://devzone.nordicsemi.com/nordic/nordic-blog/b/blog/posts/evaluating-bluetooth-channel-sounding-with-our-open_2d00_source-android-app-on-google-pixel-10); [Android Police](https://www.androidpolice.com/pixel-10-family-bluetooth-6-channel-sounding/)
- Developer forum posts suggest Samsung S26+/S26 Ultra add CS support and OnePlus 13 "should" support it, untested. "You can't have Channel Sounding on phones not being Bluetooth 6". These are unconfirmed forum claims. — [Nordic DevZone Q&A: which smartphones are supported](https://devzone.nordicsemi.com/f/nordic-q-a/127111/ble-channel-sounding-with-nrf54l15-which-smartphones-are-actually-supported)
- A Substack analysis claims CS hardware readiness is "widespread" in early-2026 Android flagships and upper mid-range phones. It was paywalled and could not be verified. — [Technotrend](https://technotrend.substack.com/p/bluetooth-channel-sounding-device)
- Both ends of the ranging exchange must support CS. CS hardware named: Nordic nRF54L series, Silicon Labs EFR32BG24/BG2B, NXP MCX W. — [Nordic CS page](https://www.nordicsemi.com/Products/Wireless/Bluetooth-Low-Energy/Channel-Sounding); [Silicon Labs CS](https://www.silabs.com/wireless/bluetooth/channel-sounding); [NXP MCX W CS](https://www.nxp.com/company/about-nxp/smarter-world-videos/CHANNEL-SOUNDING-MCXW-VID)
- ESP-IDF v6.0 lists Channel Sounding as unsupported on ESP32-S3 (controller, Bluedroid, NimBLE). ESP-IDF v6.1 lists it as unsupported on ESP32-C2. — [ESP-IDF v6.0 ESP32-S3 feature status](https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32s3/api-guides/ble/ble-feature-support-status.html); [ESP-IDF ESP32-C2 feature status](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c2/api-guides/ble/ble-feature-support-status.html)
- ESP32-H4 marketing mentions Bluetooth 6.0 certification but does not mention Channel Sounding. — [Espressif ESP32-H4 sample news](https://www.espressif.com/en/news/ESP32_H4_Sample)
- Accuracy: the Bluetooth SIG targets sub-metre performance where RSSI is inadequate. One developer reported a demo "hovered around 1 m" rather than 30 cm. Press "centimetre-level" claims are promotional. — [Bluetooth SIG blog](https://www.bluetooth.com/blog/true-distance-awareness-with-bluetooth-channel-sounding/); [Hacker News discussion](https://news.ycombinator.com/item?id=45913870)

### Inferences
- In 2026, CS needs Android 16+ and BT 6.0 controller hardware on the phone (flagships), plus a Nordic/SiLabs/NXP beacon instead of ESP32. Budget phones common among Indian college staff are very unlikely to have it. Requiring CS would exclude most staff, so it cannot be the primary check.
- Even ideal CS gives distance, not "which side of the wall". A 1 m-accurate distance helps only if the check-in spot is at least 2-3 m from every wall, i.e. the same geometry as the tap zone in section 2. The value of CS here is mainly resistance to relay or amplification attacks that fool RSSI. That claim needs verification (see Gaps).
- A reasonable framing for the report: an optional "CS-verified" tier for phones that support it, with a non-ESP32 beacon (e.g. an nRF54L15 board), while everyone else uses the RSSI-based checks.

### Gaps
- No authoritative list of CS-capable Android phones as of October 2026 was found. Mid-range or budget models sold in India with CS were not identified.
- I did not confirm whether ESP32-C5, C6, H2 or H4 list CS in ESP-IDF; only the S3 and C2 tables were seen (both unsupported).
- I did not retrieve Bluetooth SIG documentation on CS security properties (resistance to relay or distance-reduction attacks), so that advantage is stated as likely but unverified.
- Prices of nRF54L15 or BG24 boards in India were not retrieved.

## 8. Security: can a proxy attacker boost reception or relay the beacon, and what mitigates it?

### Takeaway
Yes. BLE advertisements can be recorded and replayed (signed or rotating payloads are indistinguishable from the real beacon within their validity window). They can be relayed in real time over the internet to a second location ("wormhole"), with tools as simple as a phone or Raspberry Pi plus an MQTT server. They can be re-transmitted at high power to beat any RSSI threshold. The 30 s rotating token stops offline replay after 30 s but not live relay. A friend inside the room (or a cheap ESP32 left in the room) could stream the token to an outsider whose app sees a spoofed local "beacon" at excellent RSSI. RF geometry checks (tap zone, differential) stop the passive "standing outside the wall" proxy. Stopping an active relay requires binding the proof to the phone itself (beacon-side or two-way checks), plus face recognition and server-side anomaly checks.

### Cited Findings
- Wormhole attacks on BLE contact tracing: an attacker places BLE devices at two or more locations, records advertisements, forwards them over the internet, and rebroadcasts them so they "seem to come from a local 1-hop neighbor". This produces many false contacts. — [Baumgärtner et al., "Mind the GAP", arXiv 2006.05914](https://arxiv.org/pdf/2006.05914)
- Wormholes were demonstrated with basic tools (mobile device or Raspberry Pi). One multi-location wormhole used a Raspberry Pi and an MQTT server and rebroadcast beacons within the 10-minute ID validity period. Attribution per search extract. — [Wormhole attack setup to relay BLE beacons (ResearchGate figure)](https://www.researchgate.net/figure/Wormhole-attack-setup-to-relay-BLE-beacons_fig3_350861000)
- In beacon systems, recorded beacon messages and their signatures are indistinguishable from those of a real beacon, so replay needs no key cracking. "Silencing" attacks flood spoofed beacons with a higher advertised TX-power value to manipulate perceived distance. — [Security and Privacy of Wireless Beacon Systems, arXiv 2107.05868](https://arxiv.org/pdf/2107.05868)
- NCC Group showed BLE proximity authentication is vulnerable to link-layer relay attacks. Their tooling adds as little as about 8 ms round-trip latency, defeating latency-bound checks and even link-layer encryption-based proximity assumptions. — [NCC Group technical advisory](https://www.nccgroup.com/research-blog/technical-advisory-ble-proximity-authentication-vulnerable-to-relay-attacks/)
- Google's ephemeral-identifier scheme (Eddystone-EID style, rotating cloud-resolvable IDs) mitigates tracking and spoofing. It does not on its own stop live relay. — [Google Research: Ephemeral Identifiers](https://research.google/pubs/ephemeral-identifiers-mitigating-tracking-spoofing-threats-to-ble-beacons/)
- A security analysis of the COVID-19 contact-tracing proposals discusses the same relay and replay class. — [IACR ePrint 2020/428](https://eprint.iacr.org/2020/428.pdf)

### Inferences
- **Boosting reception passively.** A phone's internal antenna cannot be upgraded. But an attacker can put an ESP32 with an external high-gain 2.4 GHz antenna against the outside wall to receive the beacon, then rebroadcast it at full power right next to their own phone. RSSI-only checks of any kind (single threshold, differential, ML) are then beaten for that beacon, because the attacker controls the received power. So RF geometry alone stops lazy proxies, not equipped ones.
- **Raising the bar for relays.**
  - (a) Multi-beacon differential checks force the attacker to relay all beacons and reproduce a plausible inside-vs-guard RSSI pattern, which is harder but possible.
  - (b) Authenticate the guard beacons too, so they cannot be suppressed or faked.
  - (c) Shorten token rotation (e.g. 5-10 s) and have the phone report a sequence of tokens with arrival times. A relay adds latency, and missing or duplicate tokens become anomalies. This is weak against a good relay, given NCC's 8 ms.
  - (d) Make the ESP32 also scan. The phone advertises a one-time nonce (Android `BluetoothLeAdvertiser`, supported on many phones). The in-room ESP32 reports, over Wi-Fi to the server, that it heard that nonce at a given RSSI. A relay then has to work in both directions, and the RSSI is measured by one fixed, known receiver, which removes RX heterogeneity (phone TX power still varies by model). This requires the beacon to have network connectivity.
  - (e) Cross-check with face recognition (already in the system) and server-side anomaly detection: the same beacon session used by people far apart, impossible timing, or the same "relay" MAC patterns.
- **Effect on the security story.** The tap zone (section 2) and differential RSSI (section 3) are the right RF answer to the stated problem: someone standing just outside the wall with an ordinary phone. Against a deliberate relay with extra hardware, no RSSI technique is sufficient. Only distance-bounding-style ranging (Channel Sounding, which needs flagship phones) or a non-RF proof (face check plus a physical tap) closes the gap.

**Cross-cutting summary for the report writer (inference, ranking by value per rupee for this team):**
1. Tap or near-field check-in zone. Lower TX to about -12 dBm, place the beacon at least 3 m from walls facing accessible areas (centre or ceiling), and require median RSSI over 3-5 s above a high threshold calibrated per phone at about 20-30 cm. Model margin about 23-32 dB. No extra hardware. Inconvenient but robust against passive wall-proxies.
2. Differential "presence sandwich". One inside beacon plus 1-3 authenticated guard beacons beyond accessible walls; accept only if median(inside − guard) > X dB over 10-20 s. Model margin about 20 dB vs about 6 dB single-beacon. Cancels phone model offsets. Costs 1-3 more ESP32 boards per room.
3. Temporal windowing and hysteresis on top of 1 or 2 (reduces false rejects; respect Android's 5-scan-starts/30 s limit).
4. Optional: beacon-side scanning of a phone nonce (two-way RF) for relay resistance, if the beacon can get Wi-Fi.
5. Not practical now: single-threshold tuning or TX-power-only fixes (do not widen the margin), ML fingerprinting (80-91% in the literature, heavy calibration), AoA/AoD (no Android support, USD 149-299 or about ₹37k arrays, no confirmed ESP32 API), Channel Sounding (flagship phones only, no ESP32 support).

### Gaps
- I found no attendance-system-specific studies of BLE relay or proxy attacks; the evidence comes from contact tracing and access control.
- I did not source gain figures for commercially available 2.4 GHz Yagi or patch antennas or the record BLE reception range with them, so "how far away an equipped attacker can be" is not quantified.
- I did not confirm what share of cheap Android phones in India support BLE peripheral advertising (`BluetoothLeAdvertiser`, needed for the two-way nonce idea). The team should test their target phones.
- ESP32 dev-board prices in India were not sourced. The team should check local electronics retailers for current per-board cost when budgeting guard beacons.
