# Bandana 50 Hz Production Validation & Offline BLE Sync Specification

## Overview
This specification details the production 50 Hz data pipeline for the Bandana wearable HAR system (ESP32-C3 SuperMini + MPU-6050 + HW-125 MicroSD).

---

## 1. 50 Hz Acquisition Engine
- **Sampling Interval**: $20,000\ \mu\text{s}$ ($50\ \text{Hz}$).
- **Hardware Timer**: Monotonic microsecond hardware timer (`esp_timer_get_time()`) using additive clock tracking:
  ```cpp
  if (now_us - last_sample_us >= SAMPLING_INTERVAL_US) {
    last_sample_us += SAMPLING_INTERVAL_US;
    // Sample MPU-6050
  }
  ```
- **Throughput**:
  - Single Band: 50 samples/second (1,000 bytes/sec).
  - Dual Band (Wrist + Ankle): 100 samples/second (2,000 bytes/sec).

---

## 2. Binary Transport Protocol (Choice B: 20-Byte Packed Binary)
- **GATT Service UUID**: `0000ffe0-0000-1000-8000-00805f9b34fb`
- **Data Characteristic UUID (Notify)**: `0000ffe1-0000-1000-8000-00805f9b34fb`
- **Control Characteristic UUID (Write / Write Without Response)**: `0000ffe2-0000-1000-8000-00805f9b34fb`

### Binary Frame Layout (20 Bytes Little-Endian)
| Byte Offset | Type | Field | Description |
|:---|:---|:---|:---|
| `[0..3]` | `uint32_t` | `sensor_tick_ms` | Monotonic hardware timestamp since boot |
| `[4..5]` | `uint16_t` | `seq` | Monotonic packet sequence counter |
| `[6..7]` | `int16_t` | `ax` | Accelerometer X ($\pm 8\text{g}$, $4096\ \text{LSB/g}$) |
| `[8..9]` | `int16_t` | `ay` | Accelerometer Y ($\pm 8\text{g}$, $4096\ \text{LSB/g}$) |
| `[10..11]` | `int16_t` | `az` | Accelerometer Z ($\pm 8\text{g}$, $4096\ \text{LSB/g}$) |
| `[12..13]` | `int16_t` | `gx` | Gyroscope X ($\pm 1000^\circ/\text{s}$, $32.8\ \text{LSB}/(^\circ/\text{s})$) |
| `[14..15]` | `int16_t` | `gy` | Gyroscope Y ($\pm 1000^\circ/\text{s}$, $32.8\ \text{LSB}/(^\circ/\text{s})$) |
| `[16..17]` | `int16_t` | `gz` | Gyroscope Z ($\pm 1000^\circ/\text{s}$, $32.8\ \text{LSB}/(^\circ/\text{s})$) |
| `[18..19]` | `uint16_t` | `status_flags` | Bit 0: Role (`0`=Wrist, `1`=Ankle); Bit 1: SD Ready |

---

## 3. Session Control & Ground-Truth Protocol
Written from the mobile app to `0000ffe2-0000-1000-8000-00805f9b34fb`:

| Opcode | Command | Payload | Description |
|:---|:---|:---|:---|
| `0x01` | `OP_START_RECORDING` | `[0x01, UTF-8 Label...]` | Marks active recording, resets sequence counter (`seq = 0`), and flushes SD sync marker |
| `0x02` | `OP_STOP_RECORDING` | `[0x02]` | Flushes and seals SD log buffer |
| `0x03` | `OP_START_OFFLINE_SYNC` | `[0x03]` | Requests offline `/raw_imu.bin` batch transfer |
| `0x04` | `OP_CLEAR_OFFLINE_STORAGE` | `[0x04]` | Erases `/raw_imu.bin` on SD card after successful download |

---

## 4. Offline BLE Catch-Up Sync
1. When disconnected from phone, bands log all 50 Hz binary packets to `/raw_imu.bin` on the local MicroSD card.
2. Upon reconnection, the user taps **Sync Offline** in the mobile app.
3. The app sends opcode `0x03`.
4. Firmware pauses live BLE notifications, opens `/raw_imu.bin`, and reads batches of 10 packets (200 bytes), sending them via notifications.
5. Sensor acquisition at 50 Hz retains top priority during sync.
6. When EOF is reached, firmware sends a 4-byte marker: `[0xFF, 0xFF, 0xFF, 0xFF]`.
7. Mobile app detects the EOF marker, finalizes the offline session in SQLite, and sends opcode `0x04` (`CLEAR_OFFLINE_STORAGE`) to erase `/raw_imu.bin`.

---

## 5. Synchronized 16-Column Export Format
Exports from `DatabaseService.exportSessionCsv()` follow the synchronized schema:
```csv
timestamp_phone_ms,sensor_tick_ms,seq,wrist_ax,wrist_ay,wrist_az,wrist_gx,wrist_gy,wrist_gz,ankle_ax,ankle_ay,ankle_az,ankle_gx,ankle_gy,ankle_gz,activity
```
- Missing band readings in a slot are set to `0.0`.
- All accelerations are normalized to $\text{m/s}^2$ and angular rates to $\text{rad/s}$.
