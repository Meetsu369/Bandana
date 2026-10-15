# 🏃 BANDANA — Edge-AI Wearable Human Activity Recognition (HAR) System

[![Flutter](https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![ESP32-C3](https://img.shields.io/badge/Microcontroller-ESP32--C3-E7352C?logo=espressif&logoColor=white)](https://www.espressif.com/)
[![BLE 5.0](https://img.shields.io/badge/Wireless-BLE%205.0%20(512%20MTU)-0082FC?logo=bluetooth&logoColor=white)](https://www.bluetooth.com/)
[![Architecture](https://img.shields.io/badge/Architecture-Riverpod%20%2B%20Drift%20%2B%20GetIt-8A2BE2)](#architecture--tech-stack)
[![Tests](https://img.shields.io/badge/Tests-172%20Passing-brightgreen?logo=checkmarx&logoColor=white)](#testing--verification)
[![Design](https://img.shields.io/badge/UI%2FUX-Neo--Brutalist%20Bento-FF3384)](#uiux-design-system)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**BANDANA** is a complete, production-grade edge-AI Human Activity Recognition (HAR) system. It captures synchronized 6-axis IMU motion streams (accelerometer + gyroscope) from custom wearable bands (**Wrist** and **Ankle**) over Bluetooth Low Energy (BLE), extracts sliding-window statistical features, and performs real-time machine learning classification directly on mobile devices or via a paired laptop training microservice.

Designed with a high-contrast **Neo-Brutalist Bento Grid** interface in both Light (`#FAF8F5`) and Dark (`#121316`) modes, BANDANA delivers an intuitive and visually engaging experience for researchers, athletes, and bio-mechanical data scientists.

---

## 📑 Table of Contents
1. [System Architecture](#system-architecture)
2. [Core Features](#core-features)
3. [UI/UX Design System](#uiux-design-system)
4. [Hardware Bill of Materials & Circuit Setup](#hardware-bill-of-materials--circuit-setup)
5. [Firmware Setup (ESP32-C3)](#firmware-setup-esp32-c3)
6. [Mobile App Setup from Zero (Flutter)](#mobile-app-setup-from-zero-flutter)
7. [Laptop-Assisted Training Service (Python FastAPI)](#laptop-assisted-training-service-python-fastapi)
8. [End-to-End User Guide](#end-to-end-user-guide)
9. [Project Directory Structure](#project-directory-structure)
10. [Testing & Verification](#testing--verification)
11. [Troubleshooting & FAQ](#troubleshooting--faq)
12. [License & Disclaimers](#license--disclaimers)

---

## 🏛 System Architecture

```
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│     BANDANA Wrist Wearable      │       │     BANDANA Ankle Wearable      │
│  ESP32-C3 + MPU6050 + MicroSD   │       │  ESP32-C3 + MPU6050 + MicroSD   │
│   (Role: BANDANA-WRIST, 10Hz)   │       │   (Role: BANDANA-ANKLE, 10Hz)   │
└────────────────┬────────────────┘       └────────────────┬────────────────┘
                 │ BLE (GATT Notify, MTU 512)              │ BLE (GATT Notify, MTU 512)
                 └────────────────┬────────────────────────┘
                                  ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                        BANDANA Flutter Mobile App                         │
│                                                                           │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────┐  │
│  │     BleService       │  │   DatabaseService    │  │  Theme Manager  │  │
│  │ Dual-Band Manager    │  │ Drift SQLite Storage │  │ Light/Dark Bento│  │
│  └──────────┬───────────┘  └──────────┬───────────┘  └─────────────────┘  │
│             │                         │                                   │
│             ▼                         ▼                                   │
│  ┌────────────────────────────────────────────────┐                       │
│  │      Feature Extractor (2.0s / 80 samples)     │                       │
│  │   Mean, StdDev, Variance, Min, Max (6 Axes)    │                       │
│  │   15 Features (Single) / 30 Features (Dual)    │                       │
│  └──────────────────────┬─────────────────────────┘                       │
│                         ▼                                                 │
│  ┌────────────────────────────────────────────────┐                       │
│  │             On-Device MlService                │                       │
│  │      KNN Classifier / Logistic Regression      │                       │
│  │     Session-Level Train/Validation Split       │                       │
│  └──────────────────────▲─────────────────────────┘                       │
└─────────────────────────┼─────────────────────────────────────────────────┘
                          │ HTTP REST / ADB Reverse Forwarding (Port 8000)
                          ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                  Laptop Training Service (Python FastAPI)                 │
│         Scikit-Learn • Cross-Validation • JSON Model Exporter             │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Core Features

### 1. Dual-Band Synchronous BLE Streaming
- **Simultaneous Dual Tracking**: Connects to both `BANDANA-WRIST` and `BANDANA-ANKLE` at the same time.
- **High-Throughput BLE**: Custom 512-byte MTU negotiation over standard Nordic UART UUIDs (`0000ffe0...`).
- **Resilient Auto-Reconnect**: Automatically reconnects with exponential backoff if a band loses power or goes out of range.
- **Independent Battery & RSSI**: Live connection health indicators with real-time RSSI signal telemetry.

### 2. High-Precision Activity Recording
- **Tagged Motion Capture**: Label sessions with standard categories (*Walking, Running, Sitting, Standing, Climbing Stairs, Descending Stairs*) or user-defined activities.
- **Micro-Cadence Gating & Boundary Detection**: Prevents corrupted sliding windows across pause/resume cycles, `uint32` hardware millisecond rollovers, and sample gaps.
- **Real-Time IMU Charts**: Visualizes 6-axis acceleration and angular velocity streams using dynamic `fl_chart` graphs.
- **Dual Storage**: Logs raw IMU samples into high-speed SQLite (`drift`), with secondary on-hardware MicroSD card backup (`/activity.csv`).

### 3. Edge-AI Machine Learning & Model Training Hub
- **On-Device Training**: Train directly on your phone with zero internet connection required.
- **Algorithms**:
  - **K-Nearest Neighbors (KNN)** with customizable *k* neighbors.
  - **Multi-Class Logistic Regression** with softmax probabilities.
- **Configurable Data Sources**: Train models on Wrist only (15 features), Ankle only (15 features), or Combined Dual-Band (30 features) using Bento segmented button groups.
- **De-duplicated Session Selector**: Clean header with real-time session count badges, `All`, and `Clear` bulk selection actions.
- **Session-Level Validation (Zero Data Leakage)**: Splits whole sessions into training and hold-out sets rather than mixing adjacent time windows.
- **Locked Action Bar**: Dedicated bottom action bar with prerequisite validation tooltips preventing training on 0 selected sessions.
- **Comprehensive Evaluation Metrics**: Evaluates models on-device and computes:
  - Overall Accuracy (%)
  - Macro F1 Score
  - Class-by-Class Precision & Recall
  - Full Confusion Matrix with dynamic heatmap rendering
  - Model Rollback & Versioning

### 4. Laptop-Assisted Training Integration
- **Off-Device ML Engine**: FastAPI Python microservice running on your workstation/laptop for training large datasets.
- **Flexible Connectivity**:
  - **USB ADB Reverse Port Forwarding** (`adb reverse tcp:8000 tcp:8000`) for zero-configuration, lightning-fast offline training.
  - **Local Area Network (Wi-Fi)**: Connect using your computer's local IP (`http://192.168.x.x:8000`).
  - **Android Emulator**: Built-in support via `http://10.0.2.2:8000`.
- **Zero-Overflow Laptop Service Dialog**: Resilient layout with icon tile, status diagnostics, and JSON model artifact paste/import.

### 5. Session History & Data Portability
- **Neo-Brutalist Session Explorer**: Filter recorded sessions by activity label with high-contrast color pills, view sample counts, durations, and sensor timestamps.
- **Batch Management**: Multi-select sessions for batch deletion or bulk export.
- **Comprehensive Data Export**: Export sessions to standardized CSV or JSON formats, zipped and ready to share via Google Drive, WhatsApp, Email, or Slack using Android/iOS native share sheets.

### 6. Consumer Google Drive Cloud Integration
- **One-Tap Consumer Cloud Sign-In**: Simple `[ G Continue with Google Drive ]` button eliminating complex developer setup for end users.
- **Live Backup Status Card**: Bento summary showing destination folder, last backup timestamp, `Disconnect`, and one-click `[ Backup Now ]`.
- **Expandable Developer Accordion**: Advanced technical options (OAuth Client ID, SHA-1 fingerprints, package name verification) tucked neatly into a `Developer & Custom API Settings ▾` accordion.

### 7. My Bands Management & Layout Polish
- **Dynamic Scroll Inset**: Dynamic bottom scroll padding (`96px`) ensuring sticky `[ 📡 Scan for Nearby Bands ]` FAB never obscures Connection Guide steps.
- **High-Contrast Status Badges**: Clear green pills for `● Connected` and red-outlined pills for `○ Disconnected`.
- **Dedicated Kebab Menu**: 44x44pt tap-target `⋮` options menu for `Rename Band`, `Calibrate IMU`, and `Unpair Band`.

### 8. Profile & Fitness Architecture
- **Segmented Sub-Tabs**: Organized into `Fitness & Body` (Demographics, Goals, Calorie/MET calculation) and `App Settings` (Theme toggle, Cloud sync, System Architecture).
- **Metric Summary Bento Strip**: 3-tile strip highlighting `Total Sessions` (`#BAE6FD`), `Recorded Time` (`#E9D5FF`), and `Energy Exp.` (`#D6F865`).
- **Clean Routing**: Removed redundant navigation links duplicating the primary bottom navigation bar.

---

## 🎨 UI/UX Design System

The app adheres strictly to the **Neo-Brutalist Bento Grid** visual language across Light and Dark themes:

| Design Token | Light Mode Value | Dark Mode Value | Usage |
|:---|:---|:---|:---|
| **Canvas Background** | `#FAF8F5` (Light Cream) | `#121316` (Dark Slate) | Root Scaffold background |
| **Surface/Card Fill** | `#FFFFFF` (Pure White) | `#1C1D22` (Elevated Charcoal) | Bento cards, dialogs, sheets |
| **Surface Border** | `2px solid #18181B` | `2px solid #383A42` | Enclosed containers, buttons, inputs |
| **Hard Shadow** | `3px 3px 0px #18181B` | `3px 3px 0px rgba(0,0,0,0.65)` | Interactive cards, CTAs, badges |
| **Brand Pink Accent** | `#FF3384` | `#FF3384` | Primary action buttons, active tab pills |
| **Success/Connected Lime** | `#D6F865` | `#D6F865` | Connected status pill, algorithm active pill |
| **Info/Data Sky Blue** | `#BAE6FD` | `#BAE6FD` | Telemetry cards, step metrics |
| **Warning/Notice Yellow** | `#FEF08A` | `#FEF08A` | Notice banners, calibration alerts |
| **Danger/Error** | `#F87171` | `#F87171` | Disconnected status pill, delete actions |
| **Text Primary** | `#18181B` (95% Black) | `#F4F4F5` (Zinc White) | Headers, metric values, primary titles |
| **Text Secondary** | `#52525B` (Zinc Gray) | `#A1A1AA` (Muted Zinc) | Subtitles, timestamps, captions |
| **Border Radius** | `20px` (Cards), `14px` (Buttons), `999px` (Pills) | Uniform structural geometry |

---

## ⚡ Hardware Bill of Materials & Circuit Setup

To build the dual-band wearable setup, you will need two identical sets of the following hardware:

### Bill of Materials (Per Band)
1. **1x ESP32-C3 SuperMini** (or standard ESP32-C3 Dev Module)
2. **1x MPU6050 6-Axis Accelerometer & Gyroscope** sensor module (I2C address `0x68`)
3. **1x HW-125 MicroSD Card Module** (SPI) + MicroSD Card (formatted FAT32)
4. **1x 3.7V Li-Po Battery (400mAh–800mAh)** or small 5V USB power bank
5. **Wearable elastic strap / arm band enclosure**
6. Connecting jumper wires

### Wiring Diagram

```
       ESP32-C3 SuperMini
     ┌────────────────────┐
     │ 3.3V            5V │─────────────── VCC (HW-125 MicroSD) [5V required]
     │ GND            GND │─────────────── GND (MPU6050 & HW-125)
     │ GPIO 8         VCC │─────────────── VCC (MPU6050) [3.3V]
     │ GPIO 9     GPIO 10 │─────────────── CS   (HW-125 MicroSD)
     │ GPIO 4      GPIO 6 │─────────────── MOSI (HW-125 MicroSD)
     │ GPIO 5             │─────────────── MISO (HW-125 MicroSD)
     └────────────────────┘
        │   │        │
        │   │        └──────────────────── SCK  (HW-125 MicroSD)
        │   └───────────────────────────── SCL  (MPU6050)
        └───────────────────────────────── SDA  (MPU6050)
```

| Component | Pin | ESP32-C3 SuperMini GPIO | Notes |
|:---|:---|:---|:---|
| **MPU6050** | VCC | `3.3V` | Do NOT connect to 5V |
| | GND | `GND` | Ground |
| | SDA | `GPIO 8` | I2C Data line |
| | SCL | `GPIO 9` | I2C Clock line |
| | AD0 | `GND` | Sets I2C address to `0x68` |
| **HW-125 MicroSD** | VCC | `5V` (or `VBUS`) | **Requires 5V** for on-board 3.3V LDO regulator |
| | GND | `GND` | Ground |
| | SCK | `GPIO 4` | SPI Clock |
| | MISO | `GPIO 5` | SPI Master In / Slave Out |
| | MOSI | `GPIO 6` | SPI Master Out / Slave In |
| | CS | `GPIO 10` | SPI Chip Select |

---

## 🛠 Firmware Setup (ESP32-C3)

The firmware source code is located in [`firmware/bandana_esp32/`](firmware/bandana_esp32/).

### Prerequisites
- Install **PlatformIO** (VS Code extension) OR **Arduino IDE** (v2.0+).
- In Arduino IDE, install the ESP32 board support package:
  - Add to Additional Boards URL: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
- Install required library via Arduino Library Manager:
  - **`NimBLE-Arduino`** by *h2zero* (v2.x recommended).

### Flashing Step-by-Step

1. Open [`firmware/bandana_esp32/src/bandana_esp32.ino`](firmware/bandana_esp32/src/bandana_esp32.ino) in your IDE.
2. **Configure Band #1 (Wrist)**:
   ```cpp
   #define BAND_ROLE_WRIST
   // #define BAND_ROLE_ANKLE
   ```
3. Connect your first ESP32-C3 via USB-C.
4. Select board **ESP32C3 Dev Module** (or your specific C3 board).
5. Set Arduino settings:
   - **USB CDC On Boot**: *Enabled*
   - **CPU Frequency**: *160 MHz*
   - **Upload Speed**: *921600*
6. Click **Upload**.
7. Open Serial Monitor (`115200 baud`) to verify:
   ```text
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
   ================================
   ```
8. **Configure Band #2 (Ankle)**:
   - Disconnect Band #1 and connect your second ESP32-C3.
   - Edit the file to uncomment the ankle role:
     ```cpp
     // #define BAND_ROLE_WRIST
     #define BAND_ROLE_ANKLE
     ```
   - Click **Upload**.
   - The device will now advertise as `BANDANA-ANKLE`.

---

## 📱 Mobile App Setup from Zero (Flutter)

Follow these steps to set up the mobile application on your development machine and launch it on your physical device.

### 1. Prerequisites Checklist
- [x] **Flutter SDK**: Version `>=3.24.0` (Dart `>=3.11.1`). Verify with:
  ```bash
  flutter doctor
  ```
- [x] **Android Studio & SDK**: Android SDK Platform-Tools installed (including `adb`).
- [x] **Physical Android Smartphone**:
  - Android 8.0 (API 26) or higher.
  - Bluetooth 4.2+ / BLE support.
  - *Note: Emulators do not support physical BLE hardware scanning. A physical device is required for BLE.*
  - **Enable Developer Options**: Settings → About Phone → Tap *Build Number* 7 times.
  - **Enable USB Debugging**: Settings → Developer Options → *USB Debugging* (ON).

### 2. Clone the Repository
```bash
git clone https://github.com/your-username/bandana.git
cd bandana
```

### 3. Install Dependencies
```bash
flutter pub get
```

### 4. Run Code Generation (Drift SQLite)
The app uses Drift for SQLite database queries. Generate the type-safe database access files:
```bash
dart run build_runner build --delete-conflicting-outputs
```
*This produces `lib/src/services/database_service.g.dart`.*

### 5. Connect Phone & Verify Connection
Connect your smartphone to your laptop via USB cable. Verify ADB and Flutter recognize your device:
```bash
adb devices
flutter devices
```
*Ensure your phone displays `device` (authorize the USB Debugging prompt on the phone screen if prompted).*

### 6. Launch the App
Run the application in debug mode on your connected physical phone:
```bash
flutter run
```
To run on a specific device (if multiple devices are listed):
```bash
flutter run -d <DEVICE_ID>
```

---

## 💻 Laptop-Assisted Training Service (Python FastAPI)

The backend service is located in [`backend/`](backend/). It allows training complex ML models with cross-validation on your computer and importing the resulting weights into your mobile app.

### 1. Requirements
- Python 3.10, 3.11, or 3.12
- `pip` package manager

### 2. Virtual Environment Setup

#### On Windows (PowerShell):
```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

#### On macOS / Linux:
```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Launch the Server
```bash
uvicorn training_service:app --host 0.0.0.0 --port 8000 --reload
```
You should see:
```text
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

### 4. Connecting Your Phone to the Laptop Server

#### Option A: USB ADB Reverse Port Forwarding (Recommended - Zero Config)
Keep your phone connected via USB cable and run:
```bash
adb reverse tcp:8000 tcp:8000
```
In the BANDANA mobile app (Training → Laptop Training Service Settings), enter:
```text
http://127.0.0.1:8000
```
*Your phone will route requests directly to your laptop's localhost over the USB cable!*

#### Option B: Over Local Wi-Fi (LAN)
1. Ensure both your phone and laptop are connected to the same Wi-Fi router.
2. Check your laptop's local IP address:
   - Windows: `ipconfig` (look for IPv4 Address, e.g. `192.168.1.125`).
   - macOS/Linux: `ifconfig` or `ip a`.
3. In the BANDANA mobile app, enter:
   ```text
   http://192.168.1.125:8000
   ```

#### Option C: Android Emulator
If testing UI workflows inside an Android Studio emulator, enter:
```text
http://10.0.2.2:8000
```

---

## 📖 End-to-End User Guide

### Step 1: Pair the Wearable Bands
1. Power on both ESP32-C3 bands.
2. In the BANDANA app, tap the **Settings** tab (or the top-right device badge).
3. Under **Device Pairing**:
   - Tap **Assign Wrist Band** → The app scans for devices starting with `BANDANA-`. Tap `BANDANA-WRIST`.
   - Tap **Assign Ankle Band** → Select `BANDANA-ANKLE`.
4. Tap **Connect** on each band. The top pill badge will change to:
   `[ ⌚ Wrist: 🟢 | 🏃 Ankle: 🟢 ]`.

### Step 2: Record Baseline Activity Data
To train an accurate personal model, record at least 2 to 3 distinct activities (e.g. Walking, Sitting, Standing) for 45–60 seconds each:
1. Tap the **Record** tab (center navigation button).
2. Select your activity label (e.g., **Walking**).
3. Tap **Start Recording** and perform the activity naturally.
4. Watch the live 6-axis IMU waveform and sample counter increment.
5. Tap **Stop & Save Session**.
6. Repeat for **Sitting** and **Running** or any custom labels you have created.

### Step 3: Train Your Movement Model
1. Tap the **Train** button on the Home Screen or open the Training section.
2. Select your **Data Source**:
   - `Wrist Only` (15 features)
   - `Ankle Only` (15 features)
   - `Combined Dual-Band` (30 features — recommended for highest accuracy)
3. Choose your algorithm (**KNN** or **Logistic Regression**).
4. Tap **Train Movement Model**.
5. The app computes sliding-window features, performs session-level cross-validation, and displays your **Accuracy**, **Macro F1**, and **Confusion Matrix**.
6. Tap **Persist & Activate Model**.

### Step 4: Live Real-Time Recognition
1. Navigate to the **Activity** tab (**Live Recognition**).
2. The screen automatically transitions from the preview placeholder into the active telemetry engine.
3. Tap **Start Live Recognition**.
4. Move around! The model evaluates sliding windows in real time and updates:
   - Current Activity Class (e.g., `Walking`, `Climbing Stairs`)
   - Real-Time Confidence Gauge (e.g., `98.4% Confidence`)
   - Activity History Timeline

### Step 5: Exporting Your Dataset
1. Open the **History** tab.
2. Review past sessions. You can swipe to inspect raw sample telemetry.
3. Tap **Export All** to generate a single ZIP archive containing:
   - Individual CSV files with microsecond timestamps and 6-axis values.
   - Master metadata manifest in JSON.
4. Share directly to your PC, Google Drive, or research team.

---

## 📁 Project Directory Structure

```text
c:\Project\Bandana\Bandana\
├── android/                             # Android native configuration & BLE permissions
├── backend/                             # Python FastAPI laptop training microservice
│   ├── requirements.txt                 # FastAPI, Scikit-Learn, Uvicorn, Pydantic
│   ├── training_service.py              # ML training, cross-validation & model JSON export
│   └── README.md                        # Backend setup instructions
├── firmware/
│   └── bandana_esp32/                   # ESP32-C3 Arduino/PlatformIO firmware
│       ├── platformio.ini               # PlatformIO board build config
│       ├── README.md                    # Detailed circuit wiring & hardware test checklist
│       └── src/
│           └── bandana_esp32.ino        # Dual-band firmware (MPU6050 + MicroSD + BLE GATT)
├── lib/                                 # Flutter application source code
│   ├── main.dart                        # App entry point, ServiceLocator, AppShell navigation
│   └── src/
│       ├── core/
│       │   ├── constants/               # BLE UUIDs, sample rates, window sizes
│       │   ├── di/                      # GetIt Service Locator dependency injection
│       │   └── theme/                   # Neo-Brutalist Bento design tokens & ThemeProvider
│       ├── features/
│       │   ├── dashboard/               # Live sensor stream graphs & metrics
│       │   ├── history/                 # Session history list, inspector & multi-delete
│       │   ├── home/                    # Bento home screen, summary cards, quick actions
│       │   ├── live/                    # Live activity recognition & simulated IMU preview
│       │   ├── profile/                 # User demographic metadata & MET calorie engine
│       │   ├── record/                  # Dual-band synchronous recording & labeling
│       │   ├── settings/                # Band pairing, RSSI monitor, theme & label manager
│       │   └── training/                # On-device ML training, confusion matrix & laptop sync
│       ├── models/                      # Evaluation metrics, model artifacts & data classes
│       ├── services/                    # BleService, DatabaseService, MlService, ExportService
│       ├── shared/                      # Reusable Neo-Brutalist buttons, cards, status pills
│       └── utils/                       # Cadence gating, boundary detectors, filename utils
├── test/                                # Automated unit, widget, and integration tests (172 tests)
│   ├── history_screen_test.dart         # History screen filtering, delete & metrics tests
│   ├── live_screen_test.dart            # Live recognition screen state tests
│   ├── profile_screen_test.dart         # Profile & Fitness tabs and Google Drive sync tests
│   ├── record_screen_test.dart          # Recording session flow & pause/resume tests
│   ├── session_detail_screen_test.dart  # Session inspector & telemetry tests
│   ├── theme_test.dart                  # Light/Dark mode switching & token tests
│   ├── training_evaluation_test.dart    # ML algorithms, F1 score & confusion matrix tests
│   └── widget_test.dart                 # App navigation & shell smoke tests
├── pubspec.yaml                         # Flutter dependencies & assets
└── README.md                            # Master project documentation
```

---

## 🧪 Testing & Verification

The BANDANA project maintains a comprehensive automated test suite covering state management, database transactions, BLE reconnection logic, feature extraction, ML training accuracy, and UI widgets:

```bash
# Run all automated tests
flutter test

# Run tests with detailed line output
flutter test --reporter expanded

# Run specific feature tests
flutter test test/live_screen_test.dart
flutter test test/training_evaluation_test.dart
flutter test test/theme_test.dart
```

### Static Analysis
Verify that all Dart code meets strict linting standards:
```bash
flutter analyze
```

---

## ❓ Troubleshooting & FAQ

### 1. App does not discover `BANDANA-WRIST` or `BANDANA-ANKLE` during scan
- **Check Location / Bluetooth Permissions**: On Android 12+, ensure **Nearby Devices** permission is granted. On Android 11 and older, **Location** must be turned ON for BLE scanning to work.
- **Check Device Names**: Ensure the ESP32 firmware was uploaded with either `#define BAND_ROLE_WRIST` or `#define BAND_ROLE_ANKLE` uncommented.
- **ESP32 Serial Output**: Open the Arduino Serial Monitor at 115200 baud. If you see `BLE: OK | Advertising: YES`, the hardware is broadcasting properly.

### 2. Drift Database errors during `flutter run`
- If you modify table definitions in `lib/src/services/database_service.dart`, you must re-generate the Drift code:
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```

### 3. Phone cannot connect to Laptop Training Service
- **If using USB cable**: Make sure you executed:
  ```bash
  adb reverse tcp:8000 tcp:8000
  ```
  And configured the app host to `http://127.0.0.1:8000`.
- **If using Wi-Fi**: Make sure your computer's firewall is not blocking incoming connections on port 8000. Verify connectivity by opening `http://<LAPTOP_IP>:8000/health` inside your phone's mobile browser.

### 4. MicroSD card fails to initialize on ESP32
- The HW-125 MicroSD module requires a **5V** supply to power its on-board 3.3V regulator. Ensure it is connected to the `5V` (or `VBUS`) pin of the ESP32-C3, not `3.3V`.
- Format the MicroSD card as **FAT32** with a standard 32KB allocation unit size.

---

## 📄 License & Disclaimers

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

*Note: This project utilizes `flutter_blue_plus` for Bluetooth Low Energy communication under its open-source terms (`License.nonprofit`).*
