# 40 Hz Migration - Hardware Validation Procedure

## Overview
This document describes the procedure to validate that the complete BANDANA dual-band pipeline operates reliably at 40 Hz per band (80 Hz combined) before collecting the final dataset.

## Prerequisites
- Both ESP32-C3 SuperMini devices flashed with 40 Hz firmware
  - Wrist: `BAND_ROLE_WRIST` (device name: `BANDANA-WRIST`)
  - Ankle: `BAND_ROLE_ANKLE` (device name: `BANDANA-ANKLE`)
- Flutter app built and installed on Android device
- Both bands paired and assigned in the app (Settings → Band Assignment)
- SD cards inserted in both devices

## Expected Rates
| Metric | Target | Acceptable Range |
|--------|--------|------------------|
| Wrist sampling rate | 40 Hz | 36–44 Hz |
| Ankle sampling rate | 40 Hz | 36–44 Hz |
| Combined rate | 80 Hz | 72–88 Hz |
| Sample interval | 25 ms | 22–28 ms avg |
| 20-second test samples/band | 800 | 720–880 |
| 30-second test samples/band | 1,200 | 1,080–1,320 |

## Validation Steps

### 1. Firmware Verification
1. Connect both ESP32 devices via USB
2. Open Serial Monitor at 115200 baud for each device
3. Verify startup banner shows:
   ```
   Band Role: WRIST (or ANKLE)
   Sample Rate: 40 Hz
   ```
4. Verify periodic status output (every 5 seconds) includes:
   ```
   SAMPLING: avg=~25.00 ms (~40.00 Hz) min=~22 ms max=~28 ms count=~200
   ```

### 2. BLE Connection Verification
1. Launch Flutter app
2. Go to Settings → Band Assignment
3. Scan and assign both BANDANA-WRIST and BANDANA-ANKLE
4. Return to Record screen
5. Verify both bands show "Connected" status chips

### 3. Short Recording Test (20–30 seconds)
1. On Record screen, select an activity label (e.g., "Sitting")
2. Press "Start Recording"
3. Keep still for 20–30 seconds
4. Observe real-time stats:
   - Wrist/Ankle sample rates should show ~40 Hz
   - Performance stats should show actual Hz rates
5. Press "Stop Recording"

### 4. Diagnostics Review
Check debug console (flutter logs / Android logcat) for periodic diagnostics (every 5 seconds):
```
DIAG Wrist: avg=25.1ms (39.8 Hz) min=22ms max=28ms samples=200
DIAG Ankle: avg=25.0ms (40.0 Hz) min=22ms max=29ms samples=200
DIAG Combined: 79.8 Hz total (400 samples in 5s)
```

Final diagnostics on stop:
```
DIAG Wrist: avg=25.0ms (40.0 Hz) min=22ms max=28ms samples=800
DIAG Ankle: avg=25.1ms (39.8 Hz) min=22ms max=29ms samples=795
DIAG Combined: 79.8 Hz total (1595 samples in 20s)
```

### 5. Session Detail Verification
After stopping, the SessionDetailScreen should show:
- Wrist Samples: ~800 (for 20 sec) or ~1,200 (for 30 sec)
- Ankle Samples: ~800 / ~1,200
- Wrist Windows: ~10 (80 samples/window = 10 windows for 20 sec)
- Ankle Windows: ~10

### 6. CSV Export Verification
1. On SessionDetailScreen, tap "Export Raw CSV"
2. Share/open the CSV file
3. Verify:
   - Header: `sessionId,activity,timestamp,bandRole,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag`
   - Timestamps are ISO-8601 with millisecond precision
   - Both `wrist` and `ankle` bandRole values present
   - Sample count matches session detail
   - Time deltas between consecutive samples per band ~25 ms

### 7. SD Card Verification (Optional)
1. Remove SD cards from both devices
2. Open `/activity.csv` on computer
3. Verify:
   - Header: `timestamp_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z`
   - Timestamps are milliseconds since boot
   - ~800–1,200 rows per device
   - Intervals ~25 ms

## Acceptance Criteria
**PASS** if all of the following are true:
- [ ] Both firmware devices report ~40 Hz actual sampling rate
- [ ] Flutter app receives ~40 Hz per band (72+ Hz combined)
- [ ] Sample intervals average 25 ms with reasonable jitter (<±5 ms)
- [ ] No significant packet loss (>5% loss is failure)
- [ ] Database writes complete without errors
- [ ] Feature windows generated correctly (80 samples = 2 sec window)
- [ ] CSV export contains correct data with real timestamps
- [ ] No buffer overflow warnings in debug logs

**FAIL** if any:
- Actual rate < 36 Hz or > 44 Hz per band
- Packet loss > 5%
- Buffer overflow warnings
- Database errors
- Timestamp anomalies (duplicates, large gaps, non-monotonic)

## Next Steps After Validation
If validation PASSES:
1. Tag the commit: `git tag -a v40hz-validated -m "40 Hz pipeline validated"`
2. Begin final dataset collection per `DATASET_COLLECTION_PLAN.md`

If validation FAILS:
1. Diagnose bottleneck (BLE, DB, CPU)
2. Apply fixes
3. Re-run validation

## Diagnostic Commands
```bash
# View Flutter debug logs
flutter logs

# Filter for diagnostics
flutter logs | grep DIAG

# View firmware serial output (if using platformio)
pio device monitor -e wrist
pio device monitor -e ankle
```

## Files Changed for 40 Hz Migration
- `firmware/bandana_esp32/bandana_esp32.ino` — Sampling interval, timing, diagnostics
- `firmware/bandana_esp32/platformio.ini` — Build flag for 25 ms interval
- `lib/src/core/constants/ble_constants.dart` — sampleRateHz=40, windowSize=80
- `lib/src/features/record/record_screen.dart` — Diagnostics, UI updates, interval tracking