# 50 Hz Stress Test - Hardware Validation Procedure

## PURPOSE

This document describes the procedure to stress-test the BANDANA dual-band pipeline at 50 Hz per band (100 Hz combined) to determine whether the hardware can reliably sustain this rate now that the SD card has been replaced.

**This is an EXPERIMENTAL configuration. 50 Hz is NOT considered validated until hardware testing is completed.**

## BASELINE

- **Validated baseline:** 40 Hz (commit `3915b9c`)
- **Hardware validation:** Session 125 (Walking, 4m18s, 20,632 total samples, 39.83 Hz per band)
- **Current branch:** `feature/dual-band-50hz-stress-test`

## TARGET CONFIGURATION

| Parameter | Value |
|-----------|-------|
| Target Sample Rate | 50 Hz |
| Target Interval | 20 ms |
| Window Size | 100 samples |
| Window Duration | 2 seconds |
| Combined Throughput Target | 100 Hz |

## CONFIGURATION CHANGES

### Firmware (`firmware/bandana_esp32/bandana_esp32.ino`)
- `SAMPLE_INTERVAL_MS = 20` (was 25)
- Diagnostics updated to show: `Target=50 Hz (20 ms) | Actual: ...`
- Startup banner shows: `Sample Rate: 50 Hz`
- Loop comment: `Read MPU6050 at fixed interval (50 Hz)`

### Firmware Build (`firmware/bandana_esp32/platformio.ini`)
- Build flag: `-D SAMPLE_INTERVAL_MS=20`

### Flutter (`lib/src/core/constants/ble_constants.dart`)
- `sampleRateHz = 50` (was 40)
- `windowSize = 100` (was 80)

### Flutter Diagnostics (`lib/src/features/record/record_screen.dart`)
- Diagnostics comment updated to "50 Hz stress test"
- Interval buffer comment: "~10 sec at 50 Hz"

## PRESERVED FROM 40 Hz BASELINE

- Elapsed-time scheduling mechanism (no `delay()`)
- MPU6050 reading, SD logging, BLE notification
- BLE packet format: `ax,ay,az,gx,gy,gz` (no timestamp)
- BLE UUIDs, MTU (512), connection parameters
- Wrist/Ankle role handling (compile-time `#define`)
- Diagnostics: average/min/max interval, actual measured Hz, sample count
- Real timestamps, SD failure handling
- Database schema, buffering, transactions
- CSV schema unchanged
- ML pipeline: 30 features/band, 60 combined (no interpolation)

## HARDWARE TEST PROCEDURE

### Test 1: Walking (2–3 minutes)

**DO NOT immediately collect final training data.**

1. Flash Wrist firmware with `BAND_ROLE_WRIST`
2. Flash Ankle firmware with `BAND_ROLE_ANKLE`
3. Start recording on Flutter app (Walking activity)
4. Walk for 2–3 minutes
5. Stop recording
6. Collect diagnostics from:
   - Wrist firmware Serial Monitor
   - Ankle firmware Serial Monitor
   - Flutter app debug console
   - Session database (sample counts, window counts)

### Expected Approximate Counts

| Duration | Samples per Band (Target) |
|----------|---------------------------|
| 2 minutes | ~6,000 |
| 3 minutes | ~9,000 |

### Expected Target Rates

- Wrist ≈ 50 Hz
- Ankle ≈ 50 Hz
- Combined ≈ 100 Hz

## VALIDATION CRITERIA

Investigate if actual rates fall substantially below target or if there is significant Wrist/Ankle imbalance.

### Inspect:
1. **Wrist actual Hz**
2. **Ankle actual Hz**
3. **Wrist/Ankle sample-count difference**
4. **Combined throughput**
5. **Interval stability (jitter)**
6. **Packet loss**
7. **Sample imbalance**
8. **Database write behavior**
9. **BLE stability**
10. **Session duration stability**
11. **Window generation**
12. **Long-session consistency**

**Report both average rate AND individual band behavior. Do not hide instability by averaging it away.**

## USER WILL PROVIDE

1. Wrist firmware diagnostics
2. Ankle firmware diagnostics
3. Mobile diagnostic rates
4. Session sample counts
5. Session window counts

## COMPARISON TARGET

| Metric | 40 Hz (Known-Good) | 50 Hz (Experimental) |
|--------|-------------------|---------------------|
| Wrist Hz | ~39.83 | Target: 50 |
| Ankle Hz | ~39.83 | Target: 50 |
| Sample Balance | Exactly equal | Must remain balanced |
| Interval | ~25 ms | Target: 20 ms |
| Windows (4m) | ~129/band | Target: ~161/band |

## ROLLBACK PROCEDURE

If 50 Hz proves unstable, return to validated baseline:

```bash
git checkout feature/dual-band-app-development
git reset --hard 3915b9c
# Re-flash firmware with 40 Hz configuration
```

The 40 Hz baseline (commit `3915b9c`) remains intact and available.

## DECISION

**Do not declare 50 Hz validated based only on compilation.**

The final decision between 40 Hz and 50 Hz will be made AFTER real hardware measurements are reviewed.

---

**Status:** Code prepared, hardware validation pending.
**Baseline:** 40 Hz — HARDWARE VALIDATED
**Test:** 50 Hz — CODE PREPARED, HARDWARE VALIDATION PENDING