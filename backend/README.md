# BANDANA — Laptop-Assisted Training Service

This Python microservice provides local off-device model training and evaluation for the BANDANA wearable activity recognition project.

## Requirements
- Python 3.10, 3.11, or 3.12
- `pip` package manager

## Quickstart

### 1. Setup Virtual Environment
```bash
cd backend
python -m venv venv

# Windows PowerShell:
.\venv\Scripts\Activate.ps1

# Linux / macOS:
source venv/bin/activate

pip install -r requirements.txt
```

### 2. Start the Service
```bash
uvicorn training_service:app --host 0.0.0.0 --port 8000 --reload
```
You should see:
```text
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

## Phone Connectivity Workflows

### Option A: USB ADB Reverse Port Forwarding (Recommended for physical devices)
When connecting an Android phone via USB cable with USB Debugging enabled:
```bash
adb reverse tcp:8000 tcp:8000
```
Then in the BANDANA app settings / laptop service configuration, use:
`http://127.0.0.1:8000`

### Option B: Local Wi-Fi (LAN)
1. Ensure both laptop and phone are connected to the same Wi-Fi network.
2. Find your laptop's local IP address (`ipconfig` on Windows or `ifconfig` on macOS/Linux, e.g. `192.168.1.125`).
3. In the BANDANA app, enter: `http://192.168.1.125:8000`.

### Option C: Android Emulator
If running on the Android emulator:
Use: `http://10.0.2.2:8000` (the Android emulator's alias for the host machine).

## API Endpoints

- `GET /health`: Connectivity check returning service version and supported feature dimensions.
- `POST /upload-dataset`: Accepts multipart CSV file upload with participant and sensor timing metadata.
- `POST /train`: Trains model with session-level cross-validation and returns validation accuracy, macro F1, and confusion matrix.
- `GET /model-artifact/{model_id}`: Downloads safe, versioned JSON model representation for direct Flutter runtime import.
