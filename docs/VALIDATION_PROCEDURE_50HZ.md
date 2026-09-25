# 50 Hz Migration - Hardware Validation Procedure

## Overview
This document describes the procedure to validate that the complete BANDANA dual-band pipeline operates reliably at 50 Hz per band (100 Hz combined) before collecting the final dataset.

## Prerequisites
- Both ESP32-C3 SuperMini devices flashed with 50 Hz firmware
  - Wrist: `BAND_ROLE_WRIST` (device name: `BANDANA-WRIST`)
  - Ankle: `BAND_ROLE_ANKLE` (device name: `BANDANA-ANKLE`)
- Flutter app built and installed on Android device
- Both bands paired and assigned in the app (Settings → Band Assignment)
- SD cards inserted in both devices

## Expected Rates
| Metric | Target | Acceptable Range |
|--------|--------|------------------|
| Wrist sampling rate | 50 Hz | 45–55 Hz |
| Ankle sampling rate | 50 Hz | 45–55 Hz |
| Combined rate | 100 Hz | 90–110 Hz |
| Sample interval | 20 ms | 18–22 ms avg |
| 20-second test samples/band | 1,000 | 900–1,100 |
| 30-second test samples/band | 1,500 | 1,350–1,650 |

## Validation Steps

### 1. Firmware Verification
1. Connect both ESP32 devices via USB
2. Open Serial Monitor at 115200 baud for each device
3. Verify startup banner shows:
   ```
   Band Role: WRIST (or ANKLE)
   Sample Rate: 50 Hz
   ```
4. Verify periodic status output (every 5 seconds) includes:
   ```
   SAMPLING: avg=~20.00 ms (~50.00 Hz) min=~18 ms max=~22 ms count=~250
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
   - Wrist/Ankle sample rates should show ~50 Hz
   - Performance stats should show actual Hz rates
5. Press "Stop Recording"

### 4. Diagnostics Review
Check debug console (flutter logs / Android logcat) for periodic diagnostics (every 5 seconds):
```
DIAG Wrist: avg=20.1ms (49.8 Hz) min=18ms max=22ms samples=250
DIAG Ankle: avg=20.0ms (50.0 Hz) min=18ms max=23ms samples=250
DIAG Combined: 99.8 Hz total (500 samples in 5s)
```

Final diagnostics on stop:
```
DIAG Wrist: avg=20.0ms (50.0 Hz) min=18ms max=22ms samples=1000
DIAG Ankle: avg=20.1ms (49.8 Hz) min=18ms max=23ms samples=995
DIAG Combined: 99.8 Hz total (1995 samples in 20s)
```

### 5. Session Detail Verification
After stopping, the SessionDetailScreen should show:
- Wrist Samples: ~1,000 (for 20 sec) or ~1,500 (for 30 sec)
- Ankle Samples: ~1,000 / ~1,500
- Wrist Windows: ~10 (20 samples/window × 100 samples = 10 windows for 20 sec)
- Ankle Windows: ~10

### 6. CSV Export Verification
1. On SessionDetailScreen, tap "Export Raw CSV"
2. Share/open the CSV file
3. Verify:
   - Header: `sessionId,activity,timestamp,bandRole,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag`
   - Timestamps are ISO-8601 with millisecond precision
   - Both `wrist` and `ankle` bandRole values present
   - Sample count matches session detail
   - Time deltas between consecutive samples per band ~20 ms

### 7. SD Card Verification (Optional)
1. Remove SD cards from both devices
2. Open `/activity.csv` on computer
3. Verify:
   - Header: `timestamp_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z`
   - Timestamps are milliseconds since boot
   - ~1,000–1,500 rows per device
   - Intervals ~20 ms

## Acceptance Criteria
**PASS** if all of the following are true:
- [ ] Both firmware devices report ~50 Hz actual sampling rate
- [ ] Flutter app receives ~50 Hz per band (90+ Hz combined)
- [ ] Sample intervals average 20 ms with reasonable jitter (<±5 ms)
- [ ] No significant packet loss (>5% loss is failure)
- [ ] Database writes complete without errors
- [ ] Feature windows generated correctly (100 samples = 2 sec window)
- [ ] CSV export contains correct data with real timestamps
- [ ] No buffer overflow warnings in debug logs

**FAIL** if any:
- Actual rate < 45 Hz or > 55 Hz per band
- Packet loss > 5%
- Buffer overflow warnings
- Database errors
- Timestamp anomalies (duplicates, large gaps, non-monotonic)

## Next Steps After Validation
If validation PASSES:
1. Tag the commit: `git tag -a v50hz-validated -m "50 Hz pipeline validated"`
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

## Files Changed for 50 Hz Migration
- `firmware/bandana_esp32/bandana_esp32.ino` - Sampling interval, timing, diagnostics
- `firmware/bandana_esp32/platformio.ini` - Build flag for 20 ms interval
- `lib/src/core/constants/ble_constants.dart` - sampleRateHz=50, windowSize=100
- `lib/src/features/record/record_screen.dart` - Diagnostics, UI updates, interval tracking