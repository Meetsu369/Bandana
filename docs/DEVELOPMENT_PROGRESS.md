# Bandana Dual-Band Development Progress

## Last Updated

2026-09-20

## Current Project State

**Dual-band ML pipeline implemented and hardened; real 60-feature model pending hardware data collection and training.**

IMPORTANT:
Do NOT say the 60-feature ML system is fully operational.
Do NOT claim a trained 60-feature model exists.

---

## Current Git State

**Repository:**
RS1ST-GPT/Bandana

**Personal fork:**
Meetsu369/Bandana

**Current branch:**
feature/dual-band-app-development

**Current commit:**
ba7b990

**Commit message:**
fix: harden dual-band ml and data pipeline

**Stable branch:**
feature/dual-band-bandana-update

**Stable commit:**
ef598b1

**origin:**
https://github.com/Meetsu369/Bandana.git

**upstream:**
https://github.com/RS1ST-GPT/Bandana.git

**Working tree:**
Clean

**Push status:**
Current development branch is pushed to origin.

---

## Completed Work

### Dual-Band BLE
- Independent Wrist and Ankle BLE connections
- Separate BandConnection instances
- Persistent device assignment
- Wrist/Ankle role separation
- BLE scan lifecycle cleanup
- Automatic reconnect/connection handling already implemented
- Packet count and last-packet health tracking

### BLE Protocol

**Service:**
0000ffe0-0000-1000-8000-00805f9b34fb

**Characteristic:**
0000ffe1-0000-1000-8000-00805f9b34fb

**Packet format:**
ax,ay,az,gx,gy,gz

**Sampling:**
10 Hz

**Important:**
ESP32 does not add timestamps to BLE packets.
Flutter captures one receive timestamp per BLE packet.

### ESP32 Firmware

**File:**
firmware/bandana_esp32/bandana_esp32.ino

**Features:**
- Single firmware codebase
- Compile-time role selection:
  - `#define BAND_ROLE_WRIST`
  - `#define BAND_ROLE_ANKLE`
- NimBLE-Arduino v2.x compatible advertising with device name
- Device names:
  - BANDANA-WRIST
  - BANDANA-ANKLE
- 10 Hz IMU streaming (CSV: ax,ay,az,gx,gy,gz)
- MTU 512
- Maximum TX power
- Automatic advertising/reconnect after disconnect
- Local SD card logging
- SD failure does not block BLE operation

**To configure as WRIST:**
```cpp
#define BAND_ROLE_WRIST
// #define BAND_ROLE_ANKLE
```

**To configure as ANKLE:**
```cpp
// #define BAND_ROLE_WRIST
#define BAND_ROLE_ANKLE
```

**Only one role may be enabled at a time.**

---

## BLE Protocol (Flutter-Compatible)

**Service UUID:**
0000ffe0-0000-1000-8000-00805f9b34fb

**Characteristic UUID:**
0000ffe1-0000-1000-8000-00805f9b34fb

**Properties:**
READ | NOTIFY

**MTU:**
512

**Packet Format:**
ax,ay,az,gx,gy,gz

**Example:**
0.1234,-0.4567,0.9876,1.2500,-0.3200,0.8700

- 6 numeric values
- comma separated
- 4 decimal places
- No timestamp
- No band name
- No JSON
- No brackets
- No extra text

---

## Flutter Application

### Key Files

| File | Purpose |
|------|---------|
| lib/src/core/constants/ble_constants.dart | BLE UUIDs, BandRole enum, constants |
| lib/src/core/di/service_locator.dart | GetIt DI + SharedPreferences + BandAssignmentManager init |
| lib/src/services/ble_service.dart | Dual BandConnection (wrist + ankle) management |
| lib/src/services/band_assignment_manager.dart | Persistent MAC-based role assignment |
| lib/src/services/database_service.dart | Drift v2 SQLite (raw IMU + feature windows) |
| lib/src/services/ml_service.dart | 30-feat single / 60-feat dual KNN |
| lib/src/models/imu_sample.dart | Typed IMU sample with bandRole, deviceId, timestamp |
| lib/src/features/settings/settings_screen.dart | Assignment scan, pair, connect UI |
| lib/src/features/record/record_screen.dart | Dual-band recording, charts, buffered DB writes |
| lib/src/features/live/live_screen.dart | Dual-band inference (single/dual features) |
| lib/src/features/dashboard/dashboard_screen.dart | Dual-band status + session history |

### Key Architectural Changes

1. **Dual BLE Connections:** `BleService` holds two independent `BandConnection` instances (wrist + ankle), each with its own scan/connect/notify lifecycle.

2. **Device Assignment:** Persistent MAC-based assignment via `SharedPreferences`:
   - `bandana_wrist_device_id` / `bandana_wrist_device_name`
   - `bandana_ankle_device_id` / `bandana_ankle_device_name`
   - Prevents same device assigned to both roles

3. **Runtime Permissions:** Android 12+ requires `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `LOCATION` — requested before scan.

4. **Database (Drift v2):**
   - `ImuSampleRecords` — raw IMU samples with `bandRole`, `deviceId`, timestamp
   - `SensorWindows` — feature windows with `bandRole` for ML training
   - Migration strategy v1→v2

5. **ML Pipeline:**
   - Single-band: 30 features (6 axes × 5 stats)
   - Dual-band: 60 features (30 wrist + 30 ankle concatenated)
   - KNN classifier (`ml_algo` + `ml_dataframe`)

---

## ML Model Status

| Component | Status |
|-----------|--------|
| 30-feature extraction | Complete |
| 30-feature training | Complete |
| 30-feature prediction | Complete |
| 60-feature extraction | Complete |
| 60-feature training API | Complete |
| 60-feature prediction API | Complete |
| 60-feature feature validation | Complete |
| Real dual-band training dataset | NOT AVAILABLE |
| Real trained 60-feature model | NOT AVAILABLE |
| Production-ready dual-band 60-feature inference | NOT AVAILABLE |

**Explicit explanation:**

The 60-feature infrastructure is implemented, but no real 60-feature model exists yet because real dual-band training data has not been collected.

When both bands are connected and the 60-feature model is unavailable, the application must not pretend to perform dual-band ML inference.

---

## Current Live Inference Behavior

| Scenario | Behavior |
|----------|----------|
| Both bands + 60-feature model trained | → 60-feature prediction |
| Both bands + 60-feature model NOT trained | → No dual-band prediction → Show that dual-band model is unavailable/not trained |
| Single band + 30-feature model trained | → 30-feature prediction |

The UI must distinguish:
- 30-feature single-band inference
- 60-feature dual-band inference
- Unavailable dual-band model

---

## Hardening Completed

1. **60-feature model separated from 30-feature model** — separate `_classifier30` and `_classifier60` with independent training counters
2. **Feature vector validation** — `predictFromFeatures30()` validates exactly 30 features; `predictFromFeatures60()` validates exactly 60 features
3. **Dual-band snapshot/copy-then-clear** — LiveScreen uses `.take().toList()` snapshots then `removeRange()` to clear consumed samples
4. **Recording buffer limit** — `_maxPendingWrites = 5000` with overflow logging, drops oldest on overflow
4. **DB flush lifecycle safety** — flush timer cancelled in dispose; `_recordingStopped` flag prevents writes after stop; final flush on stop
5. **BLE scan subscription cleanup** — `PopScope.onPopInvokedWithResult` cancels scan on bottom sheet dismiss
6. **Single timestamp per BLE packet** — one `DateTime.now()` per packet, passed to all lines
7. **Connection health tracking** — `lastPacketTime`, `packetCount`, `isStale` getter (5s threshold)
8. **Deprecated onPopInvoked migration** — uses `onPopInvokedWithResult`
9. **Training validation handling** — `_validateTrainingData` returns `false` with debug log instead of throwing
9. **Removed misleading hardcoded confidence** — confidence now `null` with documentation
10. **Prevented misleading Wrist-only fallback** — `predictAdaptive()` returns `null` when both bands connected but 60-model missing

---

## Verification Results

| Check | Result |
|-------|--------|
| flutter analyze | PASS (8 pre-existing warnings in settings_screen.dart) |
| flutter test | PASS (1/1 widget test) |
| Git status | Clean |
| Git branch | feature/dual-band-app-development |
| Current commit | ba7b990 |

**No new warnings introduced by the current changes.**

---

## Remaining Hardware Validation

1. Flash Wrist ESP32 firmware
2. Flash Ankle ESP32 firmware
3. Verify Wrist BLE discovery
4. Verify Ankle BLE discovery
5. Connect Wrist to Flutter
5. Connect Ankle while Wrist remains connected
6. Move Wrist only → Wrist data changes
7. Move Ankle only → Ankle data changes
7. Record 30–60 seconds from both bands
8. Power off Wrist → Ankle continues
8. Power on Wrist → verify auto-reconnect
9. Repeat disconnect/reconnect test for Ankle

---

## Remaining ML Work

After hardware validation:

1. Collect labeled dual-band training sessions.
2. Ensure every training sample contains:
   - 30 Wrist features
   - 30 Ankle features
   - total 60 features
   - correct activity label
3. Use Dashboard "Train 60-Feat".
4. Confirm `trainCombined()` succeeds.
5. Confirm `isCombinedTrained` becomes true.
6. Validate 60-feature Live inference.
7. Evaluate predictions on held-out real dual-band data.
8. Compare behavior against the existing 30-feature single-band model.
9. Do not claim production readiness until real validation is completed.

---

## Known Remaining Technical Considerations

- Monitor `_maxPendingWrites` overflow.
- Monitor BLE connection health (`isStale`, `lastPacketTime`, `packetCount`).
- No cross-device clock synchronization (each ESP32 uses local `millis()`).
- No Wi-Fi (BLE only, per requirements).
- No on-device ML (raw streaming only; KNN runs on phone).
- Single CSV file `/activity.csv` (all sessions append).
- 10 Hz fixed (configurable via `SAMPLE_INTERVAL_MS`).
- No battery voltage monitoring.

---

## Tomorrow Morning — Exact Starting Point

**Resume from branch feature/dual-band-app-development at commit ba7b990.**

### Phase 1 — Hardware
Flash and test:
- Wrist ESP32
- Ankle ESP32

### Phase 2 — BLE
Verify:
- discovery
- simultaneous connection
- notifications
- independent Wrist/Ankle streams
- reconnect

### Phase 3 — Recording
Perform:
- 30–60 second dual-band recording
- database inspection
- Wrist/Ankle data separation check
- buffer/flush check

### Phase 4 — Dataset
Collect labeled dual-band activities.

### Phase 5 — 60-Feature Training
Use:
Dashboard → Train 60-Feat

### Phase 6 — Live Inference
Verify:
60 features → _classifier60 → prediction

### Phase 7 — Evaluation
Measure real performance on held-out dual-band data.

---

## Important Do-Not-Do List

- Do not fabricate a 60-feature model.
- Do not generate fake training data just to mark the model as trained.
- Do not change the BLE UUIDs without a concrete reason.
- Do not change the BLE packet format.
- Do not mix Wrist and Ankle samples.
- Do not pass 60 features into the 30-feature classifier.
- Do not pass 30 features into the 60-feature classifier.
- Do not silently call a Wrist-only prediction a dual-band prediction.
- Do not push to upstream.
- Do not modify the stable branch unnecessarily.
- Do not rewrite Git history.

---

## Current Branch Strategy

```
main
  ↓
feature/dual-band-bandana-update
  ↓
feature/dual-band-app-development
```

- `feature/dual-band-bandana-update` is the stable dual-band implementation snapshot.
- `feature/dual-band-app-development` contains subsequent hardening.
- The development branch should remain separate until hardware validation is complete.

---

## Final Status

**SOFTWARE STATUS:**
Dual-band application pipeline implemented and hardened.

**ML STATUS:**
60-feature infrastructure implemented, but real 60-feature model pending.

**HARDWARE STATUS:**
Physical end-to-end validation pending.

**NEXT ACTION:**
Hardware validation followed by real dual-band data collection and 60-feature model training.