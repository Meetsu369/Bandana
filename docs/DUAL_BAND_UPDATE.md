# Dual-Band Bandana System Update

**Date:** 2026-09-19  
**Branch:** `feature/dual-band-bandana-update`  
**Commit:** `feat: add dual-band bandana system update`

---

## 1. Project Overview

This update implements a complete dual-band Bandana Human Activity Recognition (HAR) system with two ESP32-C3 SuperMini wearables (Wrist + Ankle) communicating simultaneously with a Flutter mobile application via Bluetooth Low Energy (BLE).

---

## 2. Hardware Architecture

### ESP32-C3 SuperMini (×2)

| Band | Device Name | Role |
|------|-------------|------|
| Board 1 | `BANDANA-WRIST` | Wrist-worn IMU |
| Board 2 | `BANDANA-ANKLE` | Ankle/leg-worn IMU |

### Peripheral Connections

| Peripheral | Pins | Notes |
|------------|------|-------|
| **MPU6050 (I2C)** | SDA=GPIO8, SCL=GPIO9 | Address 0x68, VCC=3.3V |
| **HW-125 MicroSD (SPI)** | SCK=GPIO4, MISO=GPIO5, MOSI=GPIO6, CS=GPIO10 | VCC=5V (confirmed working) |

---

## 3. Firmware Architecture

**File:** `firmware/bandana_esp32/bandana_esp32.ino`

### Key Features

- **Single firmware codebase** — compile-time role selection:
  ```cpp
  #define BAND_ROLE_WRIST
  // #define BAND_ROLE_ANKLE
  ```

- **BLE Peripheral/Server** using NimBLE-Arduino v2.x:
  - Service UUID: `0000ffe0-0000-1000-8000-00805f9b34fb`
  - Characteristic UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
  - Properties: READ | NOTIFY
  - MTU: 512
  - TX Power: ESP_PWR_LVL_P9 (maximum)

- **Device Names:**
  - Wrist: `BANDANA-WRIST`
  - Ankle: `BANDANA-ANKLE`

- **IMU Streaming:**
  - Rate: 10 Hz (100 ms interval, non-blocking `millis()`)
  - Format: CSV `ax,ay,az,gx,gy,gz` (4 decimal places)
  - No timestamp in BLE packet (Flutter assigns receive timestamp)

- **Conversions:**
  - Accelerometer: raw / 16384.0 → g
  - Gyroscope: raw / 131.0 → deg/s

- **SD Logging:**
  - File: `/activity.csv`
  - Header: `timestamp_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z`
  - Append mode (never overwrites)
  - 4 MHz SPI
  - Non-blocking: SD failure does not stop BLE

- **Reliability:**
  - Automatic advertising restart (500 ms after disconnect)
  - No blocking `delay()` in main loop
  - Global `SPIClass sdSPI(FSPI)` object

---

## 4. BLE Protocol (Flutter-Compatible)

### Service / Characteristic UUIDs
| Type | UUID |
|------|------|
| Service | `0000ffe0-0000-1000-8000-00805f9b34fb` |
| Characteristic (Notify) | `0000ffe1-0000-1000-8000-00805f9b34fb` |

### Packet Format
```
ax,ay,az,gx,gy,gz
```
Example: `0.1234,-0.4567,0.9876,1.2500,-0.3200,0.8700`

- 6 comma-separated float values
- 4 decimal places
- No timestamp, no band identifier, no JSON, no brackets

---

## 5. Flutter Application Architecture

### Core Files

| File | Purpose |
|------|---------|
| `lib/src/core/constants/ble_constants.dart` | BLE UUIDs, BandRole enum, constants |
| `lib/src/core/di/service_locator.dart` | GetIt DI + SharedPreferences + BandAssignmentManager init |
| `lib/src/services/ble_service.dart` | Dual `BandConnection` (wrist + ankle) management |
| `lib/src/services/band_assignment_manager.dart` | Persistent MAC-based role assignment |
| `lib/src/services/database_service.dart` | Drift v2 SQLite (raw IMU + feature windows) |
| `lib/src/services/ml_service.dart` | 30-feat single / 60-feat dual KNN |
| `lib/src/models/imu_sample.dart` | Typed IMU sample with bandRole, deviceId, timestamp |
| `lib/src/features/settings/settings_screen.dart` | Assignment scan, pair, connect UI |
| `lib/src/features/record/record_screen.dart` | Dual-band recording, charts, buffered DB writes |
| `lib/src/features/live/live_screen.dart` | Dual-band inference (single/dual features) |
| `lib/src/features/dashboard/dashboard_screen.dart` | Dual-band status + session history |

### Key Architectural Changes

1. **Dual BLE Connections:** `BleService` now holds two independent `BandConnection` instances (`wrist` + `ankle`), each with its own scan/connect/notify lifecycle.

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

## 6. Verified Results (Software/Integration)

| Test | Status | Evidence |
|------|--------|----------|
| BANDANA-WRIST discovered | ✅ VERIFIED | `BLE: Found device: BANDANA-WRIST` |
| BANDANA-ANKLE discovered | ✅ VERIFIED | `BLE: Found device: BANDANA-ANKLE` |
| Simultaneous connection | ✅ VERIFIED | Both `onConnectionStateChange:connected` |
| MTU 512 negotiated | ✅ VERIFIED | `mtu=512 status=0` |
| Service/Char discovered | ✅ VERIFIED | `count: 3` services, `ffe1` found |
| Notifications enabled | ✅ VERIFIED | `setNotifyValue ffe1 SUCCESS` |
| IMU CSV streaming | ✅ VERIFIED | Continuous `onCharacteristicChanged: chr: ffe1` |
| RSSI quality | ✅ VERIFIED | ~ -60 dBm |
| Flutter analyze | ✅ PASS | Only pre-existing style warnings |
| Flutter test | ✅ PASS | 1/1 widget test |

---

## 7. Test Status Summary

| Test | Status |
|------|--------|
| 1. Flash Wrist → visible in nRF | ✅ VERIFIED |
| 2. Flash Ankle → visible in nRF | ✅ VERIFIED |
| 3. Connect Wrist to Flutter | ✅ VERIFIED |
| 4. Connect Ankle (Wrist connected) | ✅ VERIFIED |
| 5. Move Wrist only → Wrist data changes | ✅ VERIFIED |
| 6. Move Ankle only → Ankle data changes | ✅ VERIFIED |
| 7. Record 30–60s both bands | ⏳ PENDING |
| 8. Power off Wrist → Ankle continues | ⏳ PENDING |
| 9. Power on Wrist → auto-reconnect | ⏳ PENDING |
| 10. Repeat for Ankle | ⏳ PENDING |

> **Note:** Tests 1–6 verified via live device logs. Tests 7–10 require dedicated hardware session.

---

## 8. Remaining Hardware Validation Checklist

- [ ] **Test 7:** Record 30–60 seconds from both bands simultaneously
- [ ] **Test 8:** Power off Wrist → Ankle continues operating
- [ ] **Test 9:** Power on Wrist → verify auto-reconnect
- [ ] **Test 10:** Repeat disconnect/reconnect test for Ankle

---

## 8. Limitations & Next Steps

| Area | Limitation | Next Step |
|------|------------|-----------|
| Clock Sync | No cross-device timestamp sync | Implement NTP/time sync or hardware timestamp |
| Wi-Fi | Not implemented | Add Wi-Fi for high-bandwidth / OTA |
| ML | KNN only | Evaluate lightweight neural nets (TFLite Micro) |
| Battery | No voltage monitoring | Add ADC-based battery level reporting |
| SD | Single file append | Session-separated files, rotation |
| Clock | No cross-device sync | Implement synchronized timestamps |

---

## 9. Important File Paths

```
flutter/
├── lib/
│   ├── src/
│   │   ├── core/constants/ble_constants.dart
│   │   ├── core/di/service_locator.dart
│   │   ├── services/
│   │   │   ├── ble_service.dart
│   │   │   ├── band_assignment_manager.dart
│   │   │   ├── database_service.dart
│   │   │   └── ml_service.dart
│   │   ├── features/
│   │   │   ├── settings/settings_screen.dart
│   │   │   ├── record/record_screen.dart
│   │   │   ├── live/live_screen.dart
│   │   │   └── dashboard/dashboard_screen.dart
│   │   └── models/imu_sample.dart
├── firmware/bandana_esp32/
│   ├── bandana_esp32.ino
│   ├── platformio.ini
│   └── README.md
└── docs/DUAL_BAND_UPDATE.md
```

---

## 10. Git Metadata

| Field | Value |
|-------|-------|
| Branch | `feature/dual-band-bandana-update` |
| Base Branch | `feature/dual-band-mobile` → `main` |
| Remote | `origin` → `https://github.com/RS1ST-GPT/Bandana.git` |
| Commit Message | `feat: add dual-band bandana system update` |
| Documentation | `docs/DUAL_BAND_UPDATE.md` |

---

## 11. Verification Commands

```bash
flutter analyze    # PASS (style warnings only)
flutter test       # PASS (1/1 widget test)
```