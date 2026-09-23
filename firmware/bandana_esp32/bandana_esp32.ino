/*
 * Bandana ESP32-C3 SuperMini Firmware
 * Dual-band IMU streaming over BLE with local SD logging
 * 
 * Hardware:
 * - ESP32-C3 SuperMini
 * - MPU6050 (SDA=GPIO8, SCL=GPIO9, ADDR=0x68, VCC=3.3V)
 * - HW-125 MicroSD (SCK=GPIO4, MISO=GPIO5, MOSI=GPIO6, CS=GPIO10, VCC=5V)
 * 
 * BLE (must match Flutter app):
 * - Service UUID: 0000ffe0-0000-1000-8000-00805f9b34fb
 * - Char UUID:  0000ffe1-0000-1000-8000-00805f9b34fb
 * - Properties: READ | NOTIFY
 * - MTU: 512
 * - Packet: ax,ay,az,gx,gy,gz (CSV, 4 decimal places, no timestamp)
 * 
 * To configure as WRIST:
 *   #define BAND_ROLE_WRIST
 * To configure as ANKLE:
 *   #define BAND_ROLE_ANKLE
 */

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <NimBLEDevice.h>

// ============================================================
// COMPILE-TIME CONFIGURATION - UNCOMMENT EXACTLY ONE
// ============================================================
#define BAND_ROLE_WRIST
// #define BAND_ROLE_ANKLE

// ============================================================
// CONSTANTS
// ============================================================
#define SAMPLE_INTERVAL_MS 100          // 10 Hz
#define DEBUG 1

// BLE UUIDs (must match Flutter app exactly)
static const char* SERVICE_UUID        = "0000ffe0-0000-1000-8000-00805f9b34fb";
static const char* CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb";

// Device names (role-specific)
#ifdef BAND_ROLE_WRIST
  static const char* DEVICE_NAME = "BANDANA-WRIST";
  static const char* BAND_ROLE_STR = "WRIST";
#else
  static const char* DEVICE_NAME = "BANDANA-ANKLE";
  static const char* BAND_ROLE_STR = "ANKLE";
#endif

// MPU6050 I2C pins
static const uint8_t MPU6050_SDA = 8;
static const uint8_t MPU6050_SCL = 9;
static const uint8_t MPU6050_ADDR = 0x68;

// HW-125 MicroSD SPI pins
static const uint8_t SD_SCK  = 4;
static const uint8_t SD_MISO = 5;
static const uint8_t SD_MOSI = 6;
static const uint8_t SD_CS   = 10;

// MPU6050 scales
static const float ACCEL_SCALE = 16384.0f;  // raw -> g
static const float GYRO_SCALE  = 131.0f;    // raw -> deg/s

// MPU6050 registers
static const uint8_t MPU6050_PWR_MGMT_1 = 0x6B;
static const uint8_t MPU6050_ACCEL_XOUT_H = 0x3B;

// ============================================================
// GLOBAL STATE
// ============================================================
NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;
bool shouldRestartAdvertising = false;
unsigned long advertisingRestartTime = 0;

// Timing
unsigned long lastSampleTime = 0;
unsigned long lastDebugTime = 0;
unsigned long sampleCount = 0;

// MPU6050 data
int16_t ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw;
float ax, ay, az, gx, gy, gz;

// SD card - SPIClass MUST be global
SPIClass sdSPI(FSPI);
File sdFile;
bool sdAvailable = false;
char sdFileName[] = "/activity.csv";

// ============================================================
// BLE CALLBACKS
// ============================================================
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    shouldRestartAdvertising = false;
    #if DEBUG
    Serial.println("BLE: CONNECTED");
    Serial.println("BLE: REQUESTING FAST CONNECTION PARAMETERS");
    #endif

    pServer->updateConnParams(connInfo.getConnHandle(), 16, 24, 0, 400);
  }

  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
    deviceConnected = false;
    shouldRestartAdvertising = true;
    advertisingRestartTime = millis() + 500;  // Stack settling time
    #if DEBUG
    Serial.printf("BLE: DISCONNECTED (reason=%d)\n", reason);
    #endif
  }
};

// ============================================================
// MPU6050 FUNCTIONS
// ============================================================
bool mpu6050_init() {
  Wire.beginTransmission(MPU6050_ADDR);
  uint8_t error = Wire.endTransmission();
  if (error != 0) {
    #if DEBUG
    Serial.println("MPU6050: NOT FOUND at 0x68");
    Serial.println("Check wiring: SDA->GPIO8, SCL->GPIO9, VCC->3.3V, GND->GND");
    #endif
    return false;
  }

  // Wake up MPU6050
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(MPU6050_PWR_MGMT_1);
  Wire.write(0x00);  // Clear sleep mode
  Wire.endTransmission();

  delay(10);

  #if DEBUG
  Serial.println("MPU6050: OK");
  #endif
  return true;
}

bool mpu6050_read() {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(MPU6050_ACCEL_XOUT_H);
  Wire.endTransmission(false);
  
  Wire.requestFrom(MPU6050_ADDR, 14);
  if (Wire.available() < 14) {
    return false;
  }

  // Read 14 bytes: AX, AY, AZ, Temp, GX, GY, GZ
  ax_raw = (Wire.read() << 8) | Wire.read();
  ay_raw = (Wire.read() << 8) | Wire.read();
  az_raw = (Wire.read() << 8) | Wire.read();
  Wire.read(); Wire.read();  // Temperature (discard)
  gx_raw = (Wire.read() << 8) | Wire.read();
  gy_raw = (Wire.read() << 8) | Wire.read();
  gz_raw = (Wire.read() << 8) | Wire.read();

  // Convert to physical units
  ax = ax_raw / ACCEL_SCALE;
  ay = ay_raw / ACCEL_SCALE;
  az = az_raw / ACCEL_SCALE;
  gx = gx_raw / GYRO_SCALE;
  gy = gy_raw / GYRO_SCALE;
  gz = gz_raw / GYRO_SCALE;

  return true;
}

// ============================================================
// SD CARD FUNCTIONS
// ============================================================
bool sd_init() {
  sdSPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  
  if (!SD.begin(SD_CS, sdSPI, 4000000)) {
    #if DEBUG
    Serial.println("SD CARD: FAILED");
    #endif
    return false;
  }

  // Check/create CSV file with header
  if (!SD.exists(sdFileName)) {
    sdFile = SD.open(sdFileName, FILE_WRITE);
    if (sdFile) {
      sdFile.println("timestamp_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z");
      sdFile.close();
    }
  }

  #if DEBUG
  Serial.println("SD CARD: OK");
  #endif
  return true;
}

void sd_log_sample() {
  if (!sdAvailable) return;

  sdFile = SD.open(sdFileName, FILE_APPEND);
  if (sdFile) {
    sdFile.printf("%lu,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n",
                  millis(), ax, ay, az, gx, gy, gz);
    sdFile.close();
  }
}

// ============================================================
// BLE FUNCTIONS
// ============================================================
void ble_init() {
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);  // Max TX power
  NimBLEDevice::setMTU(512);                // Match Flutter app request
  
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  NimBLEService* pService = pServer->createService(SERVICE_UUID);
  
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  
  pCharacteristic->setValue("Bandana IMU Ready");
  pService->start();

  // Advertising - with proper device name in advertising packet
  NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
  
  // Create advertising data with device name
  NimBLEAdvertisementData advData;
  advData.setName(DEVICE_NAME);
  advData.addServiceUUID(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setAdvertisementData(advData);
  
  // Also add to scan response for completeness
  NimBLEAdvertisementData scanData;
  scanData.addServiceUUID(NimBLEUUID(SERVICE_UUID));
  pAdvertising->setScanResponseData(scanData);
  
  NimBLEDevice::startAdvertising();

  #if DEBUG
  Serial.println("BLE: OK");
  Serial.println("BLE: ADVERTISING STARTED");
  #endif
}

void ble_notify() {
  if (!deviceConnected || !pCharacteristic) return;

  // Build CSV packet: ax,ay,az,gx,gy,gz (exactly 6 values, 4 decimal places)
  char packet[128];
  int len = snprintf(packet, sizeof(packet), "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
                     ax, ay, az, gx, gy, gz);
  
  if (len > 0 && len < sizeof(packet)) {
    pCharacteristic->setValue((uint8_t*)packet, len);
    pCharacteristic->notify();
  }
}

// ============================================================
// DEBUG OUTPUT
// ============================================================
void print_startup_banner() {
  Serial.println("================================");
  Serial.println("BANDANA ESP32-C3");
  Serial.println("================================");
  Serial.printf("Band Role: %s\n", BAND_ROLE_STR);
  Serial.printf("Device Name: %s\n", DEVICE_NAME);
  Serial.printf("Sample Rate: %d Hz\n", 1000 / SAMPLE_INTERVAL_MS);
  Serial.println();
}

void print_status() {
  #if DEBUG
  Serial.printf("BLE: %s | Samples: %lu | Rate: %d Hz\n",
                deviceConnected ? "CONNECTED" : "DISCONNECTED",
                sampleCount,
                1000 / SAMPLE_INTERVAL_MS);
  Serial.printf("ACC:  %.4f, %.4f, %.4f\n", ax, ay, az);
  Serial.printf("GYRO: %.4f, %.4f, %.4f\n", gx, gy, gz);
  Serial.printf("SD: %s\n", sdAvailable ? "OK" : "FAILED");
  Serial.println("---");
  #endif
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(100);

  print_startup_banner();

  // Initialize I2C for MPU6050
  Wire.begin(MPU6050_SDA, MPU6050_SCL);
  Wire.setClock(400000);

  // Initialize MPU6050
  bool mpuOk = mpu6050_init();

  // Initialize SD Card
  sdAvailable = sd_init();

  // Initialize BLE (even if SD fails)
  ble_init();

  // Final startup status
  #if DEBUG
  Serial.printf("MPU6050: %s\n", mpuOk ? "OK" : "FAILED");
  Serial.printf("SD Card: %s\n", sdAvailable ? "OK" : "FAILED");
  Serial.println("BLE: OK");
  Serial.println("Advertising: YES");
  Serial.println("================================");
  #endif

  // Wait for sensors to stabilize
  delay(500);
  lastSampleTime = millis();
  lastDebugTime = millis();
}

// ============================================================
// MAIN LOOP
// ============================================================
void loop() {
  unsigned long now = millis();

  // 1. Read MPU6050 at fixed interval (10 Hz)
  if (now - lastSampleTime >= SAMPLE_INTERVAL_MS) {
    lastSampleTime = now;

    if (mpu6050_read()) {
      // 2. BLE notify (non-blocking)
      ble_notify();

      // 3. SD log (non-blocking, append mode)
      sd_log_sample();

      sampleCount++;
    }
  }

  // 4. Handle pending BLE advertising restart (non-blocking)
  if (shouldRestartAdvertising && now >= advertisingRestartTime) {
    NimBLEDevice::startAdvertising();
    shouldRestartAdvertising = false;
    #if DEBUG
    Serial.println("BLE: Advertising restarted");
    #endif
  }

  // 5. Periodic debug output (~5 seconds)
  if (now - lastDebugTime >= 5000) {
    lastDebugTime = now;
    print_status();
  }
}