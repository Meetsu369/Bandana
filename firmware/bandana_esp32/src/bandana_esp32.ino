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
 * - Packet: capture_ts,ax,ay,az,gx,gy,gz (CSV, timestamp in ms, 4 decimal places)
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

#if ENABLE_WIFI
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>
#endif

// ============================================================
// COMPILE-TIME CONFIGURATION - UNCOMMENT EXACTLY ONE
// ============================================================
#define BAND_ROLE_WRIST
//#define BAND_ROLE_ANKLE

// ============================================================
// TRANSPORT CONFIGURATION
// ============================================================
#define ENABLE_BLE 1
#define ENABLE_SD 1
#define ENABLE_WIFI 0          // DEFAULT 0: Wi-Fi HTTP POST blocks main loop (50-500ms). 
                               // Set to 1 ONLY for testing or when FreeRTOS task is added.

// Transport limits (tunable per transport)
// Moved to transport config structs to avoid macro conflicts

// ============================================================
// CONSTANTS
// ============================================================
#define SAMPLE_INTERVAL_MS 25           // 40 Hz
#define DEBUG 1

// BLE UUIDs (must match Flutter app exactly)
static const char* SERVICE_UUID        = "0000ffe0-0000-1000-8000-00805f9b34fb";
static const char* CHARACTERISTIC_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb";

// Wi-Fi configuration (override via build flags or config.h)
// DO NOT COMMIT CREDENTIALS - use build flags or separate config.h
#ifndef WIFI_SSID
#define WIFI_SSID ""                // Set via -DWIFI_SSID="your_ssid"
#endif
#ifndef WIFI_PASS
#define WIFI_PASS ""                // Set via -DWIFI_PASS="your_password"
#endif
#ifndef WIFI_ENDPOINT
#define WIFI_ENDPOINT ""            // HTTP endpoint, e.g. "http://192.168.1.100:8080/ingest"
#endif

static const unsigned long WIFI_RECONNECT_INTERVAL_MS = 10000;  // 10s between reconnect attempts
static const unsigned long WIFI_CONNECT_TIMEOUT_MS = 15000;     // Max time to wait for connection

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

// Diagnostics for 40 Hz validation
unsigned long sampleIntervalSum = 0;
unsigned long sampleIntervalMin = 0xFFFFFFFF;
unsigned long sampleIntervalMax = 0;
unsigned long sampleIntervalCount = 0;
unsigned long lastSampleTimestamp = 0;

// Diagnostic counters (lightweight, updated in hot path)
volatile uint32_t samplesCaptured = 0;
volatile uint32_t samplesDropped = 0;          // From ring buffer overflow
volatile uint32_t mpuReadErrors = 0;
volatile uint32_t mpuRecoveryCount = 0;

// MPU6050 data
int16_t ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw;
float ax, ay, az, gx, gy, gz;

// Sample structure with capture timestamp
struct Sample {
  uint32_t capture_ts_ms;
  float ax, ay, az;
  float gx, gy, gz;
};

// Ring buffer configuration
static const size_t RING_BUFFER_CAPACITY = 512;  // 512 samples = 12.8s @ 40Hz

// Ring buffer state
Sample ring_buffer[RING_BUFFER_CAPACITY];
volatile size_t ring_head = 0;  // Producer index (written by sensor loop)
volatile size_t ring_tail = 0;  // Consumer index (read by transports)
volatile uint32_t ring_overflow_count = 0;

// Sampling session timing
uint32_t session_start_ms = 0;
Sample current_sample;

// SD card - SPIClass MUST be global
SPIClass sdSPI(FSPI);
File sdFile;
bool sdAvailable = false;
char sdFileName[] = "/activity.csv";

// SD recovery state
unsigned long sdLastRecoveryAttempt = 0;
static const unsigned long SD_RECOVERY_INTERVAL_MS = 5000;  // Try recovery every 5s
volatile uint32_t sd_write_failures = 0;
volatile uint32_t sd_recovery_attempts = 0;

// BLE transport state
volatile uint32_t ble_samples_sent = 0;
volatile uint32_t ble_backlog_drained = 0;
volatile uint32_t ble_send_failures = 0;

// ============================================================
// TRANSPORT MANAGEMENT (moved before BLE CALLBACKS for type visibility)
// ============================================================
// Transport state machine
enum TransportState {
  TRANSPORT_DISABLED = 0,
  TRANSPORT_UNAVAILABLE = 1,
  TRANSPORT_CONNECTING = 2,
  TRANSPORT_READY = 3,
  TRANSPORT_TRANSMITTING = 4,
  TRANSPORT_ERROR = 5
};

// Transport statistics
struct TransportStats {
  volatile uint32_t samples_sent = 0;
  volatile uint32_t send_failures = 0;
  volatile uint32_t reconnect_attempts = 0;
  volatile uint32_t connection_failures = 0;
};

// Transport configuration
struct TransportConfig {
  const char* name;
  bool enabled;
  int max_samples_per_loop;
  int backlog_drain_per_loop;
  size_t backlog_threshold;
  size_t batch_size;
};

// Transport runtime state
struct Transport {
  TransportState state = TRANSPORT_DISABLED;
  TransportConfig config;
  TransportStats stats;
  unsigned long last_reconnect_attempt = 0;
  unsigned long connect_start_time = 0;
  
  // Function pointers (set at init)
  bool (*check_availability)(Transport* t);
  bool (*consume)(Transport* t, Sample* samples, int max_samples);
  void (*try_recovery)(Transport* t);
  void (*reset_stats)(Transport* t);
};

// Forward declarations
bool ble_check_availability(Transport* t);
bool ble_consume(Transport* t, Sample* samples, int max_samples);
void ble_try_recovery(Transport* t);
void ble_reset_stats(Transport* t);

bool sd_check_availability(Transport* t);
bool sd_consume(Transport* t, Sample* samples, int max_samples);
void sd_try_recovery(Transport* t);
void sd_reset_stats(Transport* t);

bool wifi_check_availability(Transport* t);
bool wifi_consume(Transport* t, Sample* samples, int max_samples);
void wifi_try_recovery(Transport* t);
void wifi_reset_stats(Transport* t);

// Transport instances
Transport transports[3];
int transport_count = 0;

// Register a transport
void transport_register(const TransportConfig& config,
                        bool (*check_avail)(Transport*),
                        bool (*consume_fn)(Transport*, Sample*, int),
                        void (*recovery_fn)(Transport*),
                        void (*reset_fn)(Transport*)) {
  if (transport_count >= 3) return;
  Transport* t = &transports[transport_count++];
  t->config = config;
  t->check_availability = check_avail;
  t->consume = consume_fn;
  t->try_recovery = recovery_fn;
  t->reset_stats = reset_fn;
  t->state = config.enabled ? TRANSPORT_UNAVAILABLE : TRANSPORT_DISABLED;
  t->reset_stats(t);
}

// Initialize all registered transports
void transport_init_all() {
  for (int i = 0; i < transport_count; i++) {
    Transport* t = &transports[i];
    if (!t->config.enabled) continue;
    // Initial availability check
    t->check_availability(t);
  }
}

// Transport constants (inline constexpr for compile-time visibility)
static const int BLE_MAX_SAMPLES_PER_LOOP = 4;
static const int BLE_BACKLOG_DRAIN_PER_LOOP = 2;
static const size_t BLE_BACKLOG_THRESHOLD = 100;

static const int SD_MAX_SAMPLES_PER_LOOP = 4;

static const int WIFI_BATCH_SIZE = 16;
static const int WIFI_MAX_SAMPLES_PER_LOOP = 4;

// ============================================================
// WI-FI FREE RTOS TASK & BOUNDED QUEUE (ENABLE_WIFI=1 only)
// ============================================================
#if ENABLE_WIFI
// Wi-Fi queue configuration
static const size_t WIFI_QUEUE_CAPACITY = 32;  // Max batches queued (32 * 16 samples = 512 samples max)

// Wi-Fi queue item: fixed-size batch of samples
struct WiFiQueueItem {
  Sample samples[WIFI_BATCH_SIZE];
  int count;
  uint32_t enqueue_time_ms;
};

// FreeRTOS queue handle
static QueueHandle_t wifiQueue = nullptr;

// Wi-Fi task handle
static TaskHandle_t wifiTaskHandle = nullptr;

// Wi-Fi task configuration
static const uint32_t WIFI_TASK_STACK_SIZE = 4096;  // 4KB stack
static const UBaseType_t WIFI_TASK_PRIORITY = 1;    // Low priority (sensor loop runs at higher effective priority)
static const char* WIFI_TASK_NAME = "WiFiTransport";

// Wi-Fi diagnostics
volatile uint32_t wifiQueueEnqueued = 0;
volatile uint32_t wifiQueueTransmitted = 0;
volatile uint32_t wifiQueueDropped = 0;
volatile uint32_t wifiQueueOverflow = 0;
volatile uint32_t wifiRequestSuccess = 0;
volatile uint32_t wifiRequestFailure = 0;
volatile uint32_t wifiTimeoutCount = 0;
volatile uint32_t wifiReconnectCount = 0;
volatile uint32_t wifiTaskIterations = 0;

// HTTP timeouts (ms)
static const uint32_t WIFI_HTTP_CONNECT_TIMEOUT_MS = 5000;
static const uint32_t WIFI_HTTP_REQUEST_TIMEOUT_MS = 10000;

// Forward declarations
void wifi_task(void* pvParameters);
bool wifi_enqueue_batch(Sample* samples, int count);
#endif

// Get transport by name (for diagnostics)
Transport* transport_get(const char* name) {
  for (int i = 0; i < transport_count; i++) {
    if (strcmp(transports[i].config.name, name) == 0) {
      return &transports[i];
    }
  }
  return nullptr;
}

// Main transport manager - dispatches samples to all available transports
void transport_manager() {
  size_t available = ring_available();
  if (available == 0) return;

  for (int i = 0; i < transport_count; i++) {
    Transport* t = &transports[i];
    
    if (!t->config.enabled) continue;
    
    // Check/try recovery if unavailable
    if (t->state == TRANSPORT_UNAVAILABLE || t->state == TRANSPORT_ERROR) {
      t->try_recovery(t);
      if (t->state != TRANSPORT_READY) continue;
    }
    
    // Check availability for connected transports
    if (t->state == TRANSPORT_READY || t->state == TRANSPORT_CONNECTING) {
      if (!t->check_availability(t)) continue;
    }
    
    if (t->state != TRANSPORT_READY) continue;
    
    // Determine how many samples to process
    bool is_backlog = (available > t->config.backlog_threshold);
    int max_samples = is_backlog ? t->config.backlog_drain_per_loop : t->config.max_samples_per_loop;
    
    // Don't take more than available
    if (max_samples > (int)available) max_samples = available;
    
    // Consume samples
    Sample batch[WIFI_BATCH_SIZE];  // Max batch size
    int consumed = 0;
    for (int j = 0; j < max_samples; j++) {
      Sample s;
      if (!ring_pop(&s)) break;
      batch[consumed++] = s;
    }
    
    if (consumed > 0) {
      t->state = TRANSPORT_TRANSMITTING;
      
      // For Wi-Fi: enqueue to FreeRTOS queue (non-blocking)
      // For BLE/SD: direct consume (non-blocking)
      if (strcmp(t->config.name, "WiFi") == 0) {
#if ENABLE_WIFI
        bool enqueued = wifi_enqueue_batch(batch, consumed);
        if (!enqueued) {
          // Queue full - drop Wi-Fi data, sensor continues
          t->stats.send_failures += consumed;
          wifiQueueOverflow++;
        } else {
          t->stats.samples_sent += consumed;
          wifiQueueEnqueued += consumed;
        }
#else
        // Wi-Fi disabled at compile time
        t->stats.send_failures += consumed;
#endif
      } else {
        // BLE and SD: direct consume (non-blocking)
        if (!t->consume(t, batch, consumed)) {
          // Consume failed - samples lost, mark for recovery
          t->state = TRANSPORT_ERROR;
          t->stats.send_failures += consumed;
        } else {
          t->stats.samples_sent += consumed;
          if (is_backlog) {
            // Track backlog drain per transport
            // Could add backlog_drained to stats if needed
          }
        }
      }
      t->state = TRANSPORT_READY;
    }
  }
}

// ============================================================
// WI-FI TRANSPORT
// ============================================================
// Wi-Fi states
enum WifiState {
  WIFI_DISABLED = 0,
  WIFI_DISCONNECTED = 1,
  WIFI_CONNECTING = 2,
  WIFI_CONNECTED = 3,
  WIFI_TRANSMITTING = 4,
  WIFI_ERROR = 5
};

WifiState wifiState = WIFI_DISABLED;
unsigned long wifiLastReconnectAttempt = 0;
unsigned long wifiConnectStartTime = 0;
volatile uint32_t wifi_samples_sent = 0;
volatile uint32_t wifi_send_failures = 0;
volatile uint32_t wifi_reconnect_attempts = 0;
volatile uint32_t wifi_connection_failures = 0;

#include <WiFi.h>
#include <HTTPClient.h>

// ============================================================
// BLE CALLBACKS
// ============================================================
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    shouldRestartAdvertising = false;
    session_start_ms = 0;  // Reset session timestamp on new BLE connection
    
    // Reset BLE transport stats
    Transport* ble = transport_get("BLE");
    if (ble) ble->reset_stats(ble);
    
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

// Ring buffer push (non-blocking, drop oldest on overflow)
inline bool ring_push(const Sample* sample) {
  size_t next_head = (ring_head + 1) % RING_BUFFER_CAPACITY;
  if (next_head == ring_tail) {
    // Buffer full - drop oldest (advance tail)
    ring_tail = (ring_tail + 1) % RING_BUFFER_CAPACITY;
    ring_overflow_count++;
  }
  ring_buffer[ring_head] = *sample;
  ring_head = next_head;
  return true;
}

// Ring buffer pop (returns false if empty)
inline bool ring_pop(Sample* out_sample) {
  if (ring_head == ring_tail) {
    return false;  // Empty
  }
  *out_sample = ring_buffer[ring_tail];
  ring_tail = (ring_tail + 1) % RING_BUFFER_CAPACITY;
  return true;
}

// Ring buffer peek (returns false if empty)
inline bool ring_peek(Sample* out_sample) {
  if (ring_head == ring_tail) {
    return false;
  }
  *out_sample = ring_buffer[ring_tail];
  return true;
}

inline size_t ring_available() {
  return (ring_head >= ring_tail) ? (ring_head - ring_tail) : (RING_BUFFER_CAPACITY - ring_tail + ring_head);
}

bool mpu6050_read() {
  // Capture timestamp at sensor acquisition start (relative to session start)
  uint32_t now = millis();
  if (session_start_ms == 0) {
    session_start_ms = now;
  }
  current_sample.capture_ts_ms = now - session_start_ms;

  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(MPU6050_ACCEL_XOUT_H);
  Wire.endTransmission(false);
  
  Wire.requestFrom(MPU6050_ADDR, 14);
  if (Wire.available() < 14) {
    mpuReadErrors++;
    
    // Attempt controlled recovery: re-init I2C and sensor (non-blocking, rate-limited)
    static unsigned long lastMpuRecovery = 0;
    if (now - lastMpuRecovery > 1000) {  // Max 1 recovery attempt per second
      lastMpuRecovery = now;
      mpuRecoveryCount++;
      #if DEBUG
      Serial.println("MPU6050: Read error, attempting recovery...");
      #endif
      Wire.endTransmission(true);
      Wire.begin(MPU6050_SDA, MPU6050_SCL);
      Wire.setClock(400000);
      Wire.beginTransmission(MPU6050_ADDR);
      Wire.write(MPU6050_PWR_MGMT_1);
      Wire.write(0x00);
      Wire.endTransmission();
    }
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
  current_sample.ax = ax_raw / ACCEL_SCALE;
  current_sample.ay = ay_raw / ACCEL_SCALE;
  current_sample.az = az_raw / ACCEL_SCALE;
  current_sample.gx = gx_raw / GYRO_SCALE;
  current_sample.gy = gy_raw / GYRO_SCALE;
  current_sample.gz = gz_raw / GYRO_SCALE;

  // Also update legacy globals for compatibility
  ax = current_sample.ax;
  ay = current_sample.ay;
  az = current_sample.az;
  gx = current_sample.gx;
  gy = current_sample.gy;
  gz = current_sample.gz;

  // Push to ring buffer (non-blocking, drops oldest if full)
  ring_push(&current_sample);

  samplesCaptured++;
  samplesDropped = ring_overflow_count;  // Keep in sync
  
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

  // Check/create CSV file with header (new format with capture_ts)
  if (!SD.exists(sdFileName)) {
    sdFile = SD.open(sdFileName, FILE_WRITE);
    if (sdFile) {
      sdFile.println("capture_ts_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z");
      sdFile.close();
    }
  }

  #if DEBUG
  Serial.println("SD CARD: OK");
  #endif
  return true;
}

// SD transport implementations for transport manager
bool sd_check_availability(Transport* t) {
  return sdAvailable;
}

// SD write state for batched writes (avoid open/close per sample)
static File sdBatchFile;
static bool sdBatchFileOpen = false;
static uint32_t sdBatchSampleCount = 0;
static const uint32_t SD_BATCH_FLUSH_THRESHOLD = 16;  // Flush every 16 samples

bool sd_consume(Transport* t, Sample* samples, int count) {
  if (!sdAvailable) return false;
  
  // Open file for batch if not already open
  if (!sdBatchFileOpen) {
    sdBatchFile = SD.open(sdFileName, FILE_APPEND);
    if (!sdBatchFile) {
      #if DEBUG
      Serial.println("SD: Batch open failed, marking unavailable");
      #endif
      sd_write_failures++;
      sdAvailable = false;
      return false;
    }
    sdBatchFileOpen = true;
    sdBatchSampleCount = 0;
  }
  
  // Write all samples in this batch
  for (int i = 0; i < count; i++) {
    sdBatchFile.printf("%lu,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n",
                      samples[i].capture_ts_ms,
                      samples[i].ax, samples[i].ay, samples[i].az,
                      samples[i].gx, samples[i].gy, samples[i].gz);
    sdBatchSampleCount++;
  }
  
  // Flush periodically (every 16 samples) or on error
  if (sdBatchSampleCount >= SD_BATCH_FLUSH_THRESHOLD) {
    sdBatchFile.flush();
    // Note: flush() returns void in Arduino SD library, so we can't check return value
    // If flush fails, subsequent writes will fail and be caught on next open
    sdBatchSampleCount = 0;
  }
  
  return true;
}

// Call periodically to ensure data is flushed (e.g., on transport shutdown or recovery)
void sd_flush_batch() {
  if (sdBatchFileOpen && sdBatchSampleCount > 0) {
    sdBatchFile.flush();
    // Note: flush() returns void in Arduino SD library
    sdBatchSampleCount = 0;
  }
  if (sdBatchFileOpen) {
    sdBatchFile.close();
    sdBatchFileOpen = false;
  }
}

void sd_try_recovery(Transport* t) {
  unsigned long now = millis();
  if (now - sdLastRecoveryAttempt < SD_RECOVERY_INTERVAL_MS) {
    return;  // Rate limited
  }
  sdLastRecoveryAttempt = now;
  t->stats.reconnect_attempts++;

  // Flush/close any pending batch file before recovery
  if (sdBatchFileOpen) {
    sdBatchFile.flush();
    sdBatchFile.close();
    sdBatchFileOpen = false;
    sdBatchSampleCount = 0;
  }

  #if DEBUG
  Serial.println("SD: Attempting recovery...");
  #endif

  sdSPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  if (SD.begin(SD_CS, sdSPI, 4000000)) {
    if (!SD.exists(sdFileName)) {
      sdFile = SD.open(sdFileName, FILE_WRITE);
      if (sdFile) {
        sdFile.println("capture_ts_ms,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z");
        sdFile.close();
      }
    }
    sdAvailable = true;
    t->state = TRANSPORT_READY;
    #if DEBUG
    Serial.println("SD CARD: RECOVERED");
    #endif
  } else {
    t->state = TRANSPORT_ERROR;
    #if DEBUG
    Serial.println("SD CARD: Recovery failed");
    #endif
  }
}

void sd_reset_stats(Transport* t) {
  sd_write_failures = 0;
  sd_recovery_attempts = 0;
}

// ============================================================
// WI-FI FUNCTIONS (FreeRTOS Task - Non-blocking)
// ============================================================

// Wi-Fi enqueue function (called from main loop - non-blocking)
#if ENABLE_WIFI
bool wifi_enqueue_batch(Sample* samples, int count) {
  if (!wifiQueue) return false;
  
  WiFiQueueItem item;
  item.count = count;
  item.enqueue_time_ms = millis();
  memcpy(item.samples, samples, count * sizeof(Sample));
  
  // Non-blocking send (0 timeout = don't wait)
  BaseType_t result = xQueueSend(wifiQueue, &item, 0);
  if (result == pdTRUE) {
    return true;
  } else {
    wifiQueueDropped += count;
    return false;
  }
}

// Wi-Fi FreeRTOS task - handles all blocking network operations
void wifi_task(void* pvParameters) {
  WiFiQueueItem item;
  Transport* wifiTransport = transport_get("WiFi");
  
  // Initialize Wi-Fi connection
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(false);
  
  unsigned long lastReconnectAttempt = 0;
  bool wifiConnected = false;
  
  #if DEBUG
  Serial.println("WIFI TASK: Started");
  #endif
  
  while (true) {
    wifiTaskIterations++;
    
    // Handle Wi-Fi connection state machine
    if (!wifiConnected) {
      if (millis() - lastReconnectAttempt >= WIFI_RECONNECT_INTERVAL_MS) {
        lastReconnectAttempt = millis();
        wifiReconnectCount++;
        
        #if DEBUG
        Serial.printf("WIFI TASK: Connecting to %s (attempt %lu)...\n", WIFI_SSID, wifiReconnectCount);
        #endif
        
        WiFi.begin(WIFI_SSID, WIFI_PASS);
        
        // Wait for connection with timeout
        unsigned long connectStart = millis();
        while (WiFi.status() != WL_CONNECTED) {
          if (millis() - connectStart > WIFI_CONNECT_TIMEOUT_MS) {
            #if DEBUG
            Serial.println("WIFI TASK: Connection timeout");
            #endif
            wifi_connection_failures++;
            WiFi.disconnect(true);
            break;
          }
          vTaskDelay(pdMS_TO_TICKS(100));
        }
        
        if (WiFi.status() == WL_CONNECTED) {
          wifiConnected = true;
          if (wifiTransport) {
            wifiTransport->state = TRANSPORT_READY;
          }
          #if DEBUG
          Serial.printf("WIFI TASK: Connected! IP: %s\n", WiFi.localIP().toString().c_str());
          #endif
        }
      }
      
      // No connection yet, wait before retry
      vTaskDelay(pdMS_TO_TICKS(1000));
      continue;
    }
    
    // Check if still connected
    if (WiFi.status() != WL_CONNECTED) {
      wifiConnected = false;
      if (wifiTransport) {
        wifiTransport->state = TRANSPORT_UNAVAILABLE;
      }
      #if DEBUG
      Serial.println("WIFI TASK: Disconnected");
      #endif
      continue;
    }
    
    // Connected - try to receive batch from queue
    if (xQueueReceive(wifiQueue, &item, pdMS_TO_TICKS(100)) == pdTRUE) {
      // Process the batch - this is where blocking HTTP happens
      if (strlen(WIFI_ENDPOINT) > 0) {
        // Build JSON payload
        String json = "[";
        for (int i = 0; i < item.count; i++) {
          if (i > 0) json += ",";
          json += "{\"ts\":";
          json += String(item.samples[i].capture_ts_ms);
          json += ",\"ax\":";
          json += String(item.samples[i].ax, 4);
          json += ",\"ay\":";
          json += String(item.samples[i].ay, 4);
          json += ",\"az\":";
          json += String(item.samples[i].az, 4);
          json += ",\"gx\":";
          json += String(item.samples[i].gx, 4);
          json += ",\"gy\":";
          json += String(item.samples[i].gy, 4);
          json += ",\"gz\":";
          json += String(item.samples[i].gz, 4);
          json += "}";
        }
        json += "]";
        
        HTTPClient http;
        http.begin(WIFI_ENDPOINT);
        http.addHeader("Content-Type", "application/json");
        http.setTimeout(WIFI_HTTP_REQUEST_TIMEOUT_MS);
        http.setConnectTimeout(WIFI_HTTP_CONNECT_TIMEOUT_MS);
        
        int httpCode = http.POST(json);
        
        bool success = false;
        if (httpCode > 0) {
          if (httpCode == 200 || httpCode == 201 || httpCode == 202) {
            success = true;
            wifiRequestSuccess++;
            wifiQueueTransmitted += item.count;
            if (wifiTransport) {
              wifiTransport->stats.samples_sent += item.count;
            }
            #if DEBUG
            Serial.printf("WIFI TASK: Sent %d samples (HTTP %d)\n", item.count, httpCode);
            #endif
          } else {
            #if DEBUG
            Serial.printf("WIFI TASK: HTTP error %d\n", httpCode);
            #endif
            wifiRequestFailure++;
            if (wifiTransport) {
              wifiTransport->stats.send_failures += item.count;
            }
          }
        } else {
          #if DEBUG
          Serial.printf("WIFI TASK: POST failed: %s\n", http.errorToString(httpCode).c_str());
          #endif
          wifiRequestFailure++;
          wifiTimeoutCount++;
          if (wifiTransport) {
            wifiTransport->stats.send_failures += item.count;
          }
        }
        
        http.end();
      } else {
        // No endpoint configured
        wifiRequestFailure++;
        if (wifiTransport) {
          wifiTransport->stats.send_failures += item.count;
        }
      }
    }
    
    // Small delay to prevent tight loop
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

bool wifi_check_availability(Transport* t) {
  // Check if Wi-Fi is connected and queue is available
  return (WiFi.status() == WL_CONNECTED && strlen(WIFI_ENDPOINT) > 0 && wifiQueue != nullptr);
}

void wifi_try_recovery(Transport* t) {
  if (strlen(WIFI_SSID) == 0 || strlen(WIFI_PASS) == 0) {
    t->state = TRANSPORT_DISABLED;
    return;
  }
  // Recovery is handled by the Wi-Fi task
  // Just ensure task is running
  if (wifiTaskHandle == nullptr) {
    t->state = TRANSPORT_ERROR;
  }
}

void wifi_reset_stats(Transport* t) {
  // Stats are in transport struct
}

// Wi-Fi initialization - creates queue and starts task
void wifi_init() {
#if ENABLE_WIFI
  if (strlen(WIFI_SSID) == 0 || strlen(WIFI_PASS) == 0) {
    #if DEBUG
    Serial.println("WIFI: Disabled (no credentials)");
    #endif
    return;
  }
  
  // Create bounded Wi-Fi queue
  wifiQueue = xQueueCreate(WIFI_QUEUE_CAPACITY, sizeof(WiFiQueueItem));
  if (wifiQueue == nullptr) {
    #if DEBUG
    Serial.println("WIFI: Failed to create queue");
    #endif
    return;
  }
  
  // Reset diagnostics
  wifiQueueEnqueued = 0;
  wifiQueueTransmitted = 0;
  wifiQueueDropped = 0;
  wifiQueueOverflow = 0;
  wifiRequestSuccess = 0;
  wifiRequestFailure = 0;
  wifiTimeoutCount = 0;
  wifiReconnectCount = 0;
  wifiTaskIterations = 0;
  
  // Create Wi-Fi task
  BaseType_t result = xTaskCreate(
    wifi_task,
    WIFI_TASK_NAME,
    WIFI_TASK_STACK_SIZE,
    nullptr,
    WIFI_TASK_PRIORITY,
    &wifiTaskHandle
  );
  
  if (result != pdPASS) {
    #if DEBUG
    Serial.println("WIFI: Failed to create task");
    #endif
    vQueueDelete(wifiQueue);
    wifiQueue = nullptr;
    return;
  }
  
  #if DEBUG
  Serial.printf("WIFI: Task created (stack=%d, priority=%d, queue_capacity=%d)\n", 
                WIFI_TASK_STACK_SIZE, WIFI_TASK_PRIORITY, WIFI_QUEUE_CAPACITY);
  #endif
#else
  #if DEBUG
  Serial.println("WIFI: Disabled at compile time");
  #endif
#endif
}
#endif  // ENABLE_WIFI

#if !ENABLE_WIFI
// Dummy Wi-Fi functions when disabled (to satisfy forward declarations)
bool wifi_check_availability(Transport* t) { return false; }
bool wifi_consume(Transport* t, Sample* samples, int count) { return false; }
void wifi_try_recovery(Transport* t) { t->state = TRANSPORT_DISABLED; }
void wifi_reset_stats(Transport* t) { }
void wifi_init() { 
  #if DEBUG
  Serial.println("WIFI: Disabled at compile time");
  #endif
}
#endif

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

// BLE transport implementations for transport manager
bool ble_check_availability(Transport* t) {
  return (deviceConnected && pCharacteristic != nullptr);
}

bool ble_consume(Transport* t, Sample* samples, int count) {
  if (!deviceConnected || !pCharacteristic) return false;
  
  for (int i = 0; i < count; i++) {
    char packet[128];
    int len = snprintf(packet, sizeof(packet), "%lu,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
                       samples[i].capture_ts_ms, samples[i].ax, samples[i].ay, samples[i].az,
                       samples[i].gx, samples[i].gy, samples[i].gz);
    if (len > 0 && len < sizeof(packet)) {
      pCharacteristic->setValue((uint8_t*)packet, len);
      bool notify_ok = pCharacteristic->notify();
      if (!notify_ok) {
        return false;
      }
    }
  }
  return true;
}

void ble_try_recovery(Transport* t) {
  // BLE recovery is handled by advertising restart in main loop
  // Just check availability
  if (deviceConnected && pCharacteristic) {
    t->state = TRANSPORT_READY;
  }
}

void ble_reset_stats(Transport* t) {
  // Stats are in transport struct
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
  Serial.printf("BLE: %s | Samples: %lu | Target Rate: %d Hz\n",
                deviceConnected ? "CONNECTED" : "DISCONNECTED",
                sampleCount,
                1000 / SAMPLE_INTERVAL_MS);
  Serial.printf("ACC:  %.4f, %.4f, %.4f\n", ax, ay, az);
  Serial.printf("GYRO: %.4f, %.4f, %.4f\n", gx, gy, gz);
  
  // Sampling diagnostics
  if (sampleIntervalCount > 0) {
    float avgInterval = (float)sampleIntervalSum / sampleIntervalCount;
    float actualRate = 1000.0f / avgInterval;
    Serial.printf("SAMPLING: avg=%.2f ms (%.2f Hz) min=%lu ms max=%lu ms count=%lu\n",
                  avgInterval, actualRate, sampleIntervalMin, sampleIntervalMax, sampleIntervalCount);
  }
  
  // Core diagnostics
  Serial.printf("CORE: captured=%lu dropped=%lu overflow=%lu\n",
                samplesCaptured, samplesDropped, ring_overflow_count);
  
  // MPU6050 diagnostics
  Serial.printf("MPU: read_err=%lu recovery=%lu\n",
                mpuReadErrors, mpuRecoveryCount);
  
  // Ring buffer diagnostics
  Serial.printf("RING: used=%u/%u\n",
                ring_available(), RING_BUFFER_CAPACITY);
  
  // Transport diagnostics
  static const char* transportStateNames[] = {"DISABLED", "UNAVAILABLE", "CONNECTING", "READY", "TX", "ERROR"};
  for (int i = 0; i < transport_count; i++) {
    Transport* t = &transports[i];
    Serial.printf("%s: %s sent=%lu fail=%lu reconnect=%lu conn_fail=%lu\n",
                  t->config.name,
                  transportStateNames[t->state],
                  t->stats.samples_sent,
                  t->stats.send_failures,
                  t->stats.reconnect_attempts,
                  t->stats.connection_failures);
  }
  
#if ENABLE_WIFI
  // Wi-Fi queue diagnostics
  if (wifiQueue) {
    UBaseType_t queueWaiting = uxQueueMessagesWaiting(wifiQueue);
    Serial.printf("WIFI QUEUE: waiting=%u/%u enqueued=%lu transmitted=%lu dropped=%lu overflow=%lu\n",
                  queueWaiting, WIFI_QUEUE_CAPACITY,
                  wifiQueueEnqueued, wifiQueueTransmitted, wifiQueueDropped, wifiQueueOverflow);
    Serial.printf("WIFI HTTP: success=%lu failure=%lu timeout=%lu reconnect=%lu task_iter=%lu\n",
                  wifiRequestSuccess, wifiRequestFailure, wifiTimeoutCount, wifiReconnectCount, wifiTaskIterations);
  }
#endif
  
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

  // Initialize Wi-Fi
  wifi_init();

  // Register transports with transport manager
  TransportConfig bleConfig = {"BLE", ENABLE_BLE, BLE_MAX_SAMPLES_PER_LOOP, BLE_BACKLOG_DRAIN_PER_LOOP, BLE_BACKLOG_THRESHOLD, 1};
  transport_register(bleConfig, ble_check_availability, ble_consume, ble_try_recovery, ble_reset_stats);

  TransportConfig sdConfig = {"SD", ENABLE_SD, SD_MAX_SAMPLES_PER_LOOP, SD_MAX_SAMPLES_PER_LOOP, 0, 1};
  transport_register(sdConfig, sd_check_availability, sd_consume, sd_try_recovery, sd_reset_stats);

#if ENABLE_WIFI
  TransportConfig wifiConfig = {"WiFi", ENABLE_WIFI, WIFI_MAX_SAMPLES_PER_LOOP, WIFI_MAX_SAMPLES_PER_LOOP, 0, WIFI_BATCH_SIZE};
  transport_register(wifiConfig, wifi_check_availability, wifi_consume, wifi_try_recovery, wifi_reset_stats);
#endif

  // Initialize all transports
  transport_init_all();

  // Final startup status
  #if DEBUG
  Serial.printf("MPU6050: %s\n", mpuOk ? "OK" : "FAILED");
  Serial.printf("SD Card: %s\n", sdAvailable ? "OK" : "FAILED");
  Serial.println("BLE: OK");
  Serial.println("Advertising: YES");
  #if ENABLE_WIFI
  if (strlen(WIFI_SSID) > 0) {
    Serial.printf("WIFI: SSID=%s, Endpoint=%s\n", WIFI_SSID, strlen(WIFI_ENDPOINT) > 0 ? WIFI_ENDPOINT : "NOT SET");
  } else {
    Serial.println("WIFI: DISABLED");
  }
  #endif
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

  // 1. Read MPU6050 at fixed interval (40 Hz) - PRODUCER (absolute priority)
  if (now - lastSampleTime >= SAMPLE_INTERVAL_MS) {
    // Track sample interval for diagnostics
    if (lastSampleTimestamp > 0) {
      unsigned long interval = now - lastSampleTimestamp;
      sampleIntervalSum += interval;
      if (interval < sampleIntervalMin) sampleIntervalMin = interval;
      if (interval > sampleIntervalMax) sampleIntervalMax = interval;
      sampleIntervalCount++;
    }
    lastSampleTimestamp = now;
    lastSampleTime = now;

    if (mpu6050_read()) {
      sampleCount++;
    }
  }

  // 2. Transport manager - dispatches to all available transports
  //    Each transport fails independently, no transport blocks another
  transport_manager();

  // 3. Handle pending BLE advertising restart (non-blocking)
  if (shouldRestartAdvertising && now >= advertisingRestartTime) {
    NimBLEDevice::startAdvertising();
    shouldRestartAdvertising = false;
    #if DEBUG
    Serial.println("BLE: Advertising restarted");
    #endif
  }

  // 4. Periodic SD flush (every 5 seconds) to ensure data durability
  static unsigned long lastSdFlush = 0;
  if (now - lastSdFlush >= 5000) {
    lastSdFlush = now;
    sd_flush_batch();
  }

  // 5. Periodic debug output (~5 seconds)
  if (now - lastDebugTime >= 5000) {
    lastDebugTime = now;
    print_status();
  }
}