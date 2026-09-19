# Bandana ESP32-C3 SuperMini Firmware

Dual-band IMU firmware for ESP32-C3 SuperMini with MPU6050 and HW-125 MicroSD.
Supports **WRIST** and **ANKLE** configurations from a single codebase.

---

## Hardware Connections

| Component | Pin | ESP32-C3 GPIO | Notes |
|-----------|-----|---------------|-------|
| **MPU6050** | VCC | 3.3V | |
| | GND | GND | |
| | SDA | GPIO 8 | I2C |
| | SCL | GPIO 9 | I2C |
| | AD0 | GND | Address 0x68 |
| **HW-125 SD** | VCC | **5V** | Confirmed working at 5V |
| | GND | GND | |
| | SCK | GPIO 4 | SPI |
| | MISO | GPIO 5 | SPI |
| | MOSI | GPIO 6 | SPI |
| | CS | GPIO 10 | SPI |

---

## Configuration

### WRIST Band
```cpp
#define BAND_ROLE_WRIST
// #define BAND_ROLE_ANKLE
```
- Device name: `BANDANA-WRIST`
- Role string: `WRIST`

### ANKLE Band
```cpp
// #define BAND_ROLE_WRIST
#define BAND_ROLE_ANKLE
```
- Device name: `BANDANA-ANKLE`
- Role string: `ANKLE`

**Only one role may be uncommented at a time.**

---

## Required Libraries (Arduino Library Manager)

| Library | Version |
|---------|---------|
| **NimBLE-Arduino** (by h2zero) | Latest (tested with v2.x) |
| **Wire** | Built-in |
| **SPI** | Built-in |
| **SD** | Built-in (ESP32 core) |

---

## Arduino IDE Settings

| Setting | Value |
|---------|-------|
| **Board** | ESP32C3 Dev Module (or ESP32-C3 SuperMini) |
| **USB CDC On Boot** | Enabled |
| **CPU Frequency** | 160 MHz |
| **Flash Frequency** | 80 MHz |
| **Flash Mode** | QIO |
| **Flash Size** | 4MB |
| **Partition Scheme** | Default 4MB with spiffs |
| **PSRAM** | Disabled |
| **Upload Speed** | 921600 |
| **Serial Monitor** | 115200 baud |

---

## BLE Protocol (Must Match Flutter App)

| Parameter | Value |
|-----------|-------|
| **Service UUID** | `0000ffe0-0000-1000-8000-00805f9b34fb` |
| **Characteristic UUID** | `0000ffe1-0000-1000-8000-00805f9b34fb` |
| **Properties** | READ \| NOTIFY |
| **MTU** | 512 |
| **Packet Format** | `ax,ay,az,gx,gy,gz` (CSV, 4 decimal places) |
| **Sample Rate** | 10 Hz (100ms interval) |

**Example BLE notification:**
```
0.1234,-0.4567,0.9876,1.2500,-0.3200,0.8700
```

---

## SD Card Logging

- **File:** `/activity.csv`
- **Header:** `timestamp_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z`
- **Format:** Millisecond timestamp + 6 sensor values
- **Mode:** Append (never overwrites existing data)
- **SPI Speed:** 4 MHz
- **VCC:** 5V (confirmed for HW-125)

**Example row:**
```
12345,0.0123,-0.0345,0.9876,1.2345,-0.4567,0.1234
```

---

## Key Behaviors

| Behavior | Implementation |
|----------|----------------|
| **BLE reconnect** | Automatic advertising restart 500ms after disconnect |
| **SD failure** | BLE continues operating; only SD logging disabled |
| **No blocking delays** | All timing via `millis()`; no `delay()` in loop |
| **Memory** | Fixed 128-byte buffer; no String/JSON in loop |
| **Clock sync** | None - Flutter assigns receive timestamp |
| **Role detection** | Compile-time flag; Flutter assigns by MAC |

---

## Compilation

Test with Arduino IDE:

1. Open `bandana_esp32.ino`
2. Select board: **ESP32C3 Dev Module**
3. Uncomment desired role (`BAND_ROLE_WRIST` or `BAND_ROLE_ANKLE`)
4. Click **Verify** (compile)
5. Click **Upload**

**Expected compile result:** Success for both configurations.

---

## Expected Serial Output (115200 baud)

```
================================
BANDANA ESP32-C3
================================
Band Role: WRIST
Device Name: BANDANA-WRIST
Sample Rate: 10 Hz

MPU6050: OK
SD Card: OK
BLE: OK
Advertising: YES
===============================

BLE: CONNECTED | Samples: 120 | Rate: 10 Hz
ACC:  0.1234, -0.4567, 0.9876
GYRO: 1.2500, -0.3200, 0.8700
SD: OK
---
```

---

## Hardware Test Checklist

### TEST 1: Wrist Firmware
1. Configure: `#define BAND_ROLE_WRIST`
2. Upload to ESP32 #1
3. Open Serial Monitor at 115200
4. **Expected:** `BANDANA-WRIST` appears in BLE scan

### TEST 2: Ankle Firmware
1. Configure: `#define BAND_ROLE_ANKLE`
2. Upload to ESP32 #2
3. Open Serial Monitor at 115200
4. **Expected:** `BANDANA-ANKLE` appears in BLE scan

### TEST 3: Connect Wrist to Flutter
1. Open Bandana Flutter app
2. Settings → Assign Wrist → Scan
3. Select `BANDANA-WRIST` → Assign
4. Tap Connect
4. **Expected:** IMU notifications arrive (Live/Record tabs show data)

### TEST 4: Connect Ankle (Wrist Remains Connected)
1. Settings → Assign Ankle → Scan
2. Select `BANDANA-ANKLE` → Assign
3. Tap Connect
4. **Expected:** Both Wrist and Ankle show Connected simultaneously

### TEST 5: Wrist Data Independence
1. Move **only Wrist** band
2. **Expected:** Wrist data changes; Ankle data remains stable

### TEST 6: Ankle Data Independence
1. Move **only Ankle** band
2. **Expected:** Ankle data changes; Wrist data remains stable

### TEST 7: Record Session
1. Record tab → Select label → Start Recording
2. Move both bands for 30-60 seconds
3. Stop Recording
4. **Expected:** Session saved with both bands' data

### TEST 8: Wrist Power Off
1. Turn off Wrist ESP32 (disconnect USB/battery)
2. **Expected:** Ankle remains connected and streaming

### TEST 9: Wrist Reconnect
1. Turn Wrist ESP32 back on
2. **Expected:** Wrist advertises → Flutter auto-reconnects

### TEST 10: Ankle Power Cycle
1. Repeat TEST 8-9 with Ankle turned off/on
2. **Expected:** Wrist continues; Ankle reconnects

---

## Known Limitations

| Limitation | Details |
|------------|---------|
| **No cross-device clock sync** | Each ESP32 uses local `millis()`; Flutter timestamps on receive |
| **No Wi-Fi** | BLE only; Wi-Fi reserved for future |
| **No on-device ML** | Raw streaming only; KNN runs on phone |
| **Single CSV file** | All sessions append to `/activity.csv` |
| **10 Hz fixed** | Configurable via `SAMPLE_INTERVAL_MS` |
| **No battery monitor** | Li-Po voltage not reported |
| **Flutter scan filter** | App currently scans for `BANDANA_HAR`; may need update to accept `BANDANA-WRIST`/`BANDANA-ANKLE` |

---

## Verification Checklist

Before flashing, verify:

- [ ] MPU6050 GPIO8/GPIO9 I2C pins
- [ ] MPU6050 address 0x68
- [ ] MPU6050 VCC → 3.3V
- [ ] HW-125 GPIO4/5/6/10 SPI pins
- [ ] HW-125 VCC → **5V** (not 3.3V)
- [ ] Global `SPIClass sdSPI(FSPI)` declaration
- [ ] SD SPI 4 MHz
- [ ] `/activity.csv` with correct header
- [ ] Append mode (no overwrite)
- [ ] BLE Service UUID: `0000ffe0-0000-1000-8000-00805f9b34fb`
- [ ] BLE Char UUID: `0000ffe1-0000-1000-8000-00805f9b34fb`
- [ ] Characteristic READ \| NOTIFY
- [ ] MTU 512
- [ ] BLE packet: exactly `ax,ay,az,gx,gy,gz` (6 values, 4 decimals)
- [ ] Wrist device name: `BANDANA-WRIST`
- [ ] Ankle device name: `BANDANA-ANKLE`
- [ ] 10 Hz sampling (100ms interval)
- [ ] No Wi-Fi code
- [ ] No ML code
- [ ] No blocking `delay()` in `loop()`
- [ ] Automatic BLE advertising restart on disconnect
- [ ] SD failure does not stop BLE
- [ ] Both `BAND_ROLE_WRIST` and `BAND_ROLE_ANKLE` compile

---

## Flutter App Compatibility Note

The Flutter app's assignment scan currently filters for `BANDANA_HAR` (see `BleConstants.deviceName`). To discover `BANDANA-WRIST` and `BANDANA-ANKLE`, update the scan filter in `settings_screen.dart` line 147 to accept both names, e.g.:

```dart
_discoveredDevices.addAll(results.where(
  (r) => r.device.platformName.startsWith("BANDANA-"),
));
```

This is a one-line change in the Flutter app. The firmware uses the exact BLE UUIDs and packet format expected by the existing Flutter code.