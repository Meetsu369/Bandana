/*
 * BANDANA HARDENED PRODUCTION FIRMWARE (ESP32-C3 SuperMini)
 * Dual-Band 6-Axis IMU Streamer & Local Logger
 * 
 * Hardware Role Auto-Detection:
 *   - GPIO 3 OPEN / HIGH  -> BANDANA-WRIST
 *   - GPIO 3 TIED TO GND  -> BANDANA-ANKLE
 * 
 * Hardware Wiring:
 *   - MPU6050: SDA=GPIO8, SCL=GPIO9, ADDR=0x68, VCC=3.3V, GND=GND
 *   - HW-125 MicroSD: SCK=GPIO4, MISO=GPIO5, MOSI=GPIO6, CS=GPIO10, VCC=5V, GND=GND
 *   - Role Detect: GPIO 3 (Internal Pull-Up enabled)
 *   - USB CDC Serial: Native USB (GPIO18 D-, GPIO19 D+)
 * 
 * BLE Protocol (Choice B: 20-Byte Packed Binary):
 *   - Service UUID: 0000ffe0-0000-1000-8000-00805f9b34fb
 *   - Char UUID:    0000ffe1-0000-1000-8000-00805f9b34fb
 *   - Properties:   READ | NOTIFY
 *   - Payload:      20 bytes packed binary (little-endian)
 *                   [0..3] uint32_t sensor_tick_ms
 *                   [4..5] uint16_t seq
 *                   [6..11] int16_t ax, ay, az (±8g, 4096 LSB/g)
 *                   [12..17] int16_t gx, gy, gz (±1000 dps, 32.8 LSB/dps)
 *                   [18..19] uint16_t status_flags (bit 0: 0=wrist, 1=ankle; bit 1: SD ready)
 * 
 * MicroSD Storage:
 *   - File:         /raw_imu.bin (Binary append, persistent handle)
 *   - Frequency:    16 MHz SPI
 */

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <NimBLEDevice.h>

// ============================================================
// HARDWARE PIN DEFINITIONS & CONSTANTS
// ============================================================
static const uint8_t PIN_ROLE_SELECT = 3;   // OPEN = Wrist, GND = Ankle
static const uint8_t MPU_SDA         = 8;
static const uint8_t MPU_SCL         = 9;
static const uint8_t MPU_ADDR        = 0x68;

static const uint8_t SD_SCK          = 4;
static const uint8_t SD_MISO         = 5;
static const uint8_t SD_MOSI         = 6;
static const uint8_t SD_CS           = 10;

// Sampling Interval (20,000 us = 50 Hz | 25,000 us = 40 Hz)
#ifndef SAMPLE_INTERVAL_US
#define SAMPLE_INTERVAL_US 20000ULL  // Default 50 Hz = 20,000 microseconds
#endif
static const uint64_t SAMPLING_INTERVAL_US = SAMPLE_INTERVAL_US;

// BLE UUIDs
static const char* SERVICE_UUID                = "0000ffe0-0000-1000-8000-00805f9b34fb";
static const char* CHARACTERISTIC_UUID         = "0000ffe1-0000-1000-8000-00805f9b34fb";
static const char* CONTROL_CHARACTERISTIC_UUID = "0000ffe2-0000-1000-8000-00805f9b34fb";

// Control Opcodes
static const uint8_t OP_START_RECORDING       = 0x01;
static const uint8_t OP_STOP_RECORDING        = 0x02;
static const uint8_t OP_START_OFFLINE_SYNC    = 0x03;
static const uint8_t OP_CLEAR_OFFLINE_STORAGE = 0x04;

// ============================================================
// 20-BYTE PACKED BINARY PAYLOAD (CHOICE B)
// ============================================================
struct __attribute__((packed)) ImuBinaryPacket {
  uint32_t sensor_tick_ms; // 4 Bytes: Monotonic hardware timer
  uint16_t seq;            // 2 Bytes: Packet loss & drop detector
  int16_t  ax, ay, az;     // 6 Bytes: Raw Accelerometer (+/- 8g, 4096 LSB/g)
  int16_t  gx, gy, gz;     // 6 Bytes: Raw Gyroscope (+/- 1000 dps, 32.8 LSB/dps)
  uint16_t status_flags;   // 2 Bytes: Bit 0 = Role (0:Wrist, 1:Ankle), Bit 1 = SD OK
}; // Exactly 20 Bytes

// ============================================================
// BROADCAST RING BUFFER (DUAL TAIL POINTERS)
// ============================================================
static const size_t RING_CAPACITY = 256;
ImuBinaryPacket ring_buffer[RING_CAPACITY];
volatile size_t ring_head = 0;
volatile size_t ble_tail  = 0;
volatile size_t sd_tail   = 0;

inline void ring_push(const ImuBinaryPacket& pkt) {
  size_t next_head = (ring_head + 1) % RING_CAPACITY;
  ring_buffer[ring_head] = pkt;
  ring_head = next_head;
  // If buffer overflows unread packets, advance lagging tails
  if (next_head == ble_tail) ble_tail = (ble_tail + 1) % RING_CAPACITY;
  if (next_head == sd_tail)  sd_tail  = (sd_tail + 1) % RING_CAPACITY;
}

// ============================================================
// GLOBAL STATE
// ============================================================
NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pCharacteristic = nullptr;
NimBLECharacteristic* pControlCharacteristic = nullptr;
bool deviceConnected = false;

SPIClass sdSPI(FSPI);
File sdLogFile;
File sdSyncFile;
bool sdReady = false;
bool is_recording_active = false;
bool offline_sync_active = false;

const char* device_name = "BANDANA-WRIST";
bool is_wrist = true;
uint16_t global_seq = 0;
uint32_t session_start_ms = 0;

// Diagnostics
volatile uint32_t samplesCaptured = 0;
volatile uint32_t blePacketsSent = 0;
volatile uint32_t sdPacketsWritten = 0;
volatile uint32_t i2cErrors = 0;

// ============================================================
// I2C 9-PULSE BUS CLEAR RECOVERY
// ============================================================
void i2c_bus_recovery() {
  Wire.end();
  pinMode(MPU_SCL, OUTPUT_OPEN_DRAIN);
  pinMode(MPU_SDA, INPUT_PULLUP);

  // Send 9 clock pulses on SCL to clear stuck slave
  for (int i = 0; i < 9; i++) {
    digitalWrite(MPU_SCL, LOW);
    delayMicroseconds(5);
    digitalWrite(MPU_SCL, HIGH);
    delayMicroseconds(5);
  }

  // Issue manual STOP condition
  pinMode(MPU_SDA, OUTPUT_OPEN_DRAIN);
  digitalWrite(MPU_SDA, LOW);
  delayMicroseconds(5);
  digitalWrite(MPU_SCL, HIGH);
  delayMicroseconds(5);
  digitalWrite(MPU_SDA, HIGH);
  delayMicroseconds(5);

  Wire.begin(MPU_SDA, MPU_SCL);
  Wire.setClock(400000);
  Wire.setTimeOut(25);
}

bool initMPU() {
  Serial.println("[BOOT] Initializing I2C bus (SDA=GPIO8, SCL=GPIO9, 400kHz)...");
  Wire.begin(MPU_SDA, MPU_SCL);
  Wire.setClock(400000);
  Wire.setTimeOut(25);

  Serial.println("[BOOT] Probing MPU6050 at address 0x68...");
  Wire.beginTransmission(MPU_ADDR);
  if (Wire.endTransmission() != 0) {
    Serial.println("[BOOT] MPU6050 not responding. Executing 9-pulse bus recovery sequence...");
    i2c_bus_recovery();
    Wire.beginTransmission(MPU_ADDR);
    if (Wire.endTransmission() != 0) {
      Serial.println("[BOOT] MPU6050: NOT DETECTED at 0x68 (Check wiring/power: SDA=8, SCL=9, 3.3V, GND)");
      return false;
    }
  }
  Serial.println("[BOOT] MPU6050 ACK received! Configuring registers...");

  // Wake up MPU-6050 (clear SLEEP bit)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x00);
  if (Wire.endTransmission() != 0) {
    Serial.println("[BOOT] Failed to wake MPU6050 (PWR_MGMT_1 write error)");
    return false;
  }
  delay(10);

  // Accelerometer: +/- 8g (4096 LSB/g) -> AFS_SEL = 2 (0x10)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);
  Wire.write(0x10);
  if (Wire.endTransmission() != 0) {
    Serial.println("[BOOT] Failed to configure MPU6050 accelerometer scale");
    return false;
  }

  // Gyroscope: +/- 1000 deg/s (32.8 LSB/dps) -> FS_SEL = 2 (0x10)
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1B);
  Wire.write(0x10);
  if (Wire.endTransmission() != 0) {
    Serial.println("[BOOT] Failed to configure MPU6050 gyroscope scale");
    return false;
  }

  Serial.println("[BOOT] MPU6050 configured successfully (Acc: +/-8g, Gyro: +/-1000 dps)");
  return true;
}

inline bool readMPU(ImuBinaryPacket& pkt) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0) {
    i2cErrors++;
    i2c_bus_recovery();
    return false;
  }

  if (Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)14) < 14) {
    i2cErrors++;
    return false;
  }

  pkt.ax = (Wire.read() << 8) | Wire.read();
  pkt.ay = (Wire.read() << 8) | Wire.read();
  pkt.az = (Wire.read() << 8) | Wire.read();
  Wire.read(); Wire.read(); // Discard temperature
  pkt.gx = (Wire.read() << 8) | Wire.read();
  pkt.gy = (Wire.read() << 8) | Wire.read();
  pkt.gz = (Wire.read() << 8) | Wire.read();

  pkt.sensor_tick_ms = millis() - session_start_ms;
  pkt.seq = global_seq++;
  pkt.status_flags = (is_wrist ? 0x0000 : 0x0001) | (sdReady ? 0x0002 : 0x0000);

  samplesCaptured++;
  return true;
}

// Forward declarations for offline sync and control
void startOfflineSync();
void clearOfflineStorage();
void handleControlCommand(const uint8_t* data, size_t len);

// ============================================================
// BLE CALLBACKS
// ============================================================
class BleServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    Serial.println("BLE: CLIENT CONNECTED");
    pServer->updateConnParams(connInfo.getConnHandle(), 12, 16, 0, 300);
  }
  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
    deviceConnected = false;
    if (offline_sync_active) {
      sdSyncFile.close();
      offline_sync_active = false;
      if (!sdLogFile) {
        sdLogFile = SD.open("/raw_imu.bin", FILE_APPEND);
      }
    }
    Serial.printf("BLE: DISCONNECTED (reason=%d), Restarting Advertising\n", reason);
    NimBLEDevice::startAdvertising();
  }
};

class ControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
    std::string val = pChar->getValue();
    if (val.length() > 0) {
      handleControlCommand((const uint8_t*)val.data(), val.length());
    }
  }
};

void startOfflineSync() {
  if (offline_sync_active) return;

  if (sdLogFile) {
    sdLogFile.flush();
    sdLogFile.close();
  }

  if (SD.exists("/raw_imu.bin")) {
    sdSyncFile = SD.open("/raw_imu.bin", FILE_READ);
    if (sdSyncFile && sdSyncFile.size() > 0) {
      offline_sync_active = true;
      Serial.printf("[SYNC] Offline sync started. File size: %u bytes (%u packets)\n",
                    (unsigned int)sdSyncFile.size(), (unsigned int)(sdSyncFile.size() / sizeof(ImuBinaryPacket)));
      return;
    }
  }

  Serial.println("[SYNC] No offline data to sync or file empty. Sending EOF marker.");
  if (pCharacteristic) {
    uint32_t eof_marker = 0xFFFFFFFF;
    pCharacteristic->setValue((uint8_t*)&eof_marker, 4);
    pCharacteristic->notify();
  }
  sdLogFile = SD.open("/raw_imu.bin", FILE_APPEND);
}

void clearOfflineStorage() {
  if (offline_sync_active) {
    sdSyncFile.close();
    offline_sync_active = false;
  }
  if (sdLogFile) {
    sdLogFile.close();
  }
  if (SD.exists("/raw_imu.bin")) {
    SD.remove("/raw_imu.bin");
    Serial.println("[SYNC] /raw_imu.bin erased from SD card.");
  }
  sdLogFile = SD.open("/raw_imu.bin", FILE_APPEND);
}

void handleControlCommand(const uint8_t* data, size_t len) {
  if (len == 0) return;
  uint8_t opcode = data[0];

  if (opcode == OP_START_RECORDING) {
    is_recording_active = true;
    global_seq = 0;
    String label = "";
    if (len > 1) {
      label = String((const char*)&data[1], len - 1);
    }
    Serial.printf("[CTRL] START_RECORDING received (label: '%s', seq reset to 0)\n", label.c_str());
    if (sdReady && sdLogFile) {
      sdLogFile.flush();
    }
  } else if (opcode == OP_STOP_RECORDING) {
    is_recording_active = false;
    Serial.println("[CTRL] STOP_RECORDING received (Flushing SD buffer)");
    if (sdReady && sdLogFile) {
      sdLogFile.flush();
    }
  } else if (opcode == OP_START_OFFLINE_SYNC) {
    Serial.println("[CTRL] START_OFFLINE_SYNC received");
    startOfflineSync();
  } else if (opcode == OP_CLEAR_OFFLINE_STORAGE) {
    Serial.println("[CTRL] CLEAR_OFFLINE_STORAGE received");
    clearOfflineStorage();
  } else {
    Serial.printf("[CTRL] Unknown opcode: 0x%02X\n", opcode);
  }
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);

  // USB CDC Serial Enumeration Wait Loop (ESP32-C3 SuperMini)
  uint32_t usb_wait_start = millis();
  while (!Serial && (millis() - usb_wait_start < 3000)) {
    delay(10);
  }
  delay(100);

  session_start_ms = millis();

  Serial.println();
  Serial.println("=================================================");
  Serial.println("   BANDANA PRODUCTION FIRMWARE (ESP32-C3 SuperMini)");
  Serial.println("=================================================");

  // 1. Hardware Role Auto-Detection on GPIO 3
  Serial.println("[BOOT] Step 1: Detecting Hardware Role on GPIO 3...");
  pinMode(PIN_ROLE_SELECT, INPUT_PULLUP);
  delayMicroseconds(200);
  int low_count = 0;
  for (int i = 0; i < 16; i++) {
    if (digitalRead(PIN_ROLE_SELECT) == LOW) low_count++;
    delayMicroseconds(20);
  }
  is_wrist = (low_count < 10);
  device_name = is_wrist ? "BANDANA-WRIST" : "BANDANA-ANKLE";

  Serial.printf("[BOOT] -> Role Detected : %s (GPIO 3 = %s)\n",
                device_name, is_wrist ? "FLOATING [HIGH] -> Wrist Node" : "GND [LOW] -> Ankle Node");
  Serial.printf("[BOOT] -> Target Rate   : %d Hz (%llu us interval)\n",
                (int)(1000000 / SAMPLING_INTERVAL_US), SAMPLING_INTERVAL_US);
  Serial.println("[BOOT] -> Payload Format: 20-Byte Packed Binary (Choice B)");

  // 2. Initialize Sensors & I2C
  Serial.println("[BOOT] Step 2: Initializing Sensors & I2C Bus...");
  bool mpuOk = initMPU();
  Serial.printf("[BOOT] -> MPU6050 Status: %s\n", mpuOk ? "READY" : "FAILED / NOT CONNECTED");

  // 3. Initialize MicroSD (Persistent open, Fast 16 MHz SPI)
  Serial.println("[BOOT] Step 3: Initializing HW-125 MicroSD via SPI (16 MHz)...");
  sdSPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  if (SD.begin(SD_CS, sdSPI, 16000000)) {
    sdLogFile = SD.open("/raw_imu.bin", FILE_APPEND);
    if (sdLogFile) {
      sdReady = true;
      Serial.println("[BOOT] -> MicroSD Card  : READY (/raw_imu.bin opened in binary append mode)");
    } else {
      Serial.println("[BOOT] -> MicroSD Card  : FAILED to open /raw_imu.bin");
    }
  } else {
    Serial.println("[BOOT] -> MicroSD Card  : NOT FOUND / INIT FAILED (Card unseated or 5V missing)");
  }

  // 4. Initialize NimBLE
  Serial.println("[BOOT] Step 4: Initializing NimBLE Peripheral & GATT Server...");
  NimBLEDevice::init(device_name);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  NimBLEDevice::setMTU(256);

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new BleServerCallbacks());

  NimBLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  pCharacteristic->setValue("BANDANA_V2_READY");

  pControlCharacteristic = pService->createCharacteristic(
      CONTROL_CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  pControlCharacteristic->setCallbacks(new ControlCallbacks());

  // Start server & advertising
  pServer->start();

  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData advData;
  advData.setName(device_name);
  advData.addServiceUUID(NimBLEUUID(SERVICE_UUID));
  pAdv->setAdvertisementData(advData);

  NimBLEAdvertisementData scanData;
  scanData.addServiceUUID(NimBLEUUID(SERVICE_UUID));
  pAdv->setScanResponseData(scanData);

  pAdv->start();

  Serial.printf("[BOOT] -> NimBLE Server : ADVERTISING as \"%s\"\n", device_name);
  Serial.println("[BOOT] -> BLE Service   : 0000ffe0-0000-1000-8000-00805f9b34fb");
  Serial.println("[BOOT] -> Char UUID     : 0000ffe1-0000-1000-8000-00805f9b34fb");
  Serial.println("=================================================");
  Serial.printf("[SYSTEM READY] Streaming & Sampling loop starting at %d Hz...\n", (int)(1000000 / SAMPLING_INTERVAL_US));
  Serial.println("=================================================");
}

// ============================================================
// MAIN LOOP: NON-BLOCKING 50 HZ / 40 HZ ENGINE
// ============================================================
void loop() {
  static uint64_t last_sample_us = esp_timer_get_time();
  uint64_t now_us = esp_timer_get_time();

  // 1. Precise Additive Sampling Engine (50 Hz / 20,000 us)
  if (now_us - last_sample_us >= SAMPLING_INTERVAL_US) {
    last_sample_us += SAMPLING_INTERVAL_US;

    ImuBinaryPacket sample;
    if (readMPU(sample)) {
      ring_push(sample);
    }
  }

  // 2. BLE Consumer (Live & Offline Sync Streaming)
  if (deviceConnected && pCharacteristic) {
    if (offline_sync_active) {
      // Offline catch-up streaming: read up to 10 packets (200 bytes) per loop iteration
      static const size_t SYNC_BATCH_PACKETS = 10;
      static const size_t SYNC_BATCH_BYTES = SYNC_BATCH_PACKETS * sizeof(ImuBinaryPacket);
      uint8_t sync_buf[SYNC_BATCH_BYTES];

      size_t available = sdSyncFile.available();
      size_t bytes_to_read = SYNC_BATCH_BYTES;
      if (available < bytes_to_read) {
        bytes_to_read = available;
      }

      if (bytes_to_read > 0) {
        size_t bytes_read = sdSyncFile.read(sync_buf, bytes_to_read);
        if (bytes_read > 0) {
          pCharacteristic->setValue(sync_buf, bytes_read);
          if (!pCharacteristic->notify()) {
            // Stack congested: rewind file pointer to retry on next tick
            sdSyncFile.seek(sdSyncFile.position() - bytes_read);
          }
        }
      } else {
        // EOF reached
        sdSyncFile.close();
        offline_sync_active = false;
        Serial.println("[SYNC] Offline sync complete (EOF reached). Sending EOF marker 0xFFFFFFFF.");

        uint32_t eof_marker = 0xFFFFFFFF;
        pCharacteristic->setValue((uint8_t*)&eof_marker, 4);
        pCharacteristic->notify();

        // Reopen SD log file for continuous live logging
        sdLogFile = SD.open("/raw_imu.bin", FILE_APPEND);
      }
    } else if (ble_tail != ring_head) {
      // Live BLE streaming (Sends up to 2 queued samples per loop)
      for (int i = 0; i < 2 && (ble_tail != ring_head); i++) {
        ImuBinaryPacket pkt = ring_buffer[ble_tail];
        pCharacteristic->setValue((uint8_t*)&pkt, sizeof(ImuBinaryPacket));
        if (pCharacteristic->notify()) {
          ble_tail = (ble_tail + 1) % RING_CAPACITY;
          blePacketsSent++;
        } else {
          break; // Stop draining if BLE stack buffer is full
        }
      }
    }
  }

  // 3. SD Card Consumer (Writes pending samples in binary chunks)
  if (sdReady && (sd_tail != ring_head)) {
    while (sd_tail != ring_head) {
      size_t written = sdLogFile.write((const uint8_t*)&ring_buffer[sd_tail], sizeof(ImuBinaryPacket));
      if (written == sizeof(ImuBinaryPacket)) {
        sdPacketsWritten++;
      }
      sd_tail = (sd_tail + 1) % RING_CAPACITY;
    }
    
    // Periodic Sector Flush (every 2.5 seconds)
    static uint32_t last_flush_ms = 0;
    uint32_t now_ms = millis();
    if (now_ms - last_flush_ms >= 2500) {
      last_flush_ms = now_ms;
      sdLogFile.flush();
    }
  }

  // 4. Periodic Status Telemetry (~5 seconds)
  static uint32_t last_status_ms = 0;
  uint32_t now_ms = millis();
  if (now_ms - last_status_ms >= 5000) {
    last_status_ms = now_ms;
    Serial.printf("[STAT] Role: %s | Cap: %lu | BLE: %lu (tail=%u) | SD: %lu (tail=%u) | I2CErr: %lu\n",
                  device_name, samplesCaptured, blePacketsSent, (unsigned int)ble_tail,
                  sdPacketsWritten, (unsigned int)sd_tail, i2cErrors);
  }
}