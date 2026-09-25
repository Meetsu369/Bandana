import 'package:flutter/material.dart';

/// BLE and sensor constants for the Bandana HAR system.
class BleConstants {
  BleConstants._();

  /// The advertised name of the ESP32-C3 peripheral.
  static const String deviceName = 'BANDANA_HAR';

  /// Default GATT Service UUID exposed by the ESP32 firmware.
  /// Update this to match your actual firmware configuration.
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

  /// Default GATT Characteristic UUID (notify) for IMU data.
  static const String characteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// IMU sample rate in Hz.
  static const int sampleRateHz = 40;

  /// Number of samples in one sliding window (2 seconds at 40 Hz).
  static const int windowSize = 80;

  /// Number of axes in the IMU data stream (ax, ay, az, gx, gy, gz).
  static const int axisCount = 6;

  /// Number of statistical features per axis (mean, std, variance, min, max).
  static const int featuresPerAxis = 5;

  /// Total feature vector length: axisCount × featuresPerAxis.
  static const int featureVectorLength = axisCount * featuresPerAxis;

  /// Scan timeout duration.
  static const Duration scanTimeout = Duration(seconds: 15);

  /// Default activity labels available for recording.
  static const List<String> defaultLabels = [
    'Walking',
    'Running',
    'Sitting',
    'Standing',
    'Climbing Stairs',
    'Descending Stairs',
  ];
}

/// Physical placement of a Bandana wearable.
enum BandRole {
  /// Wrist-worn band.
  wrist,

  /// Ankle/leg-worn band.
  ankle;

  /// Display name for UI.
  String get displayName => switch (this) {
    BandRole.wrist => 'Wrist',
    BandRole.ankle => 'Ankle',
  };

  /// Icon for UI.
  IconData get icon => switch (this) {
    BandRole.wrist => Icons.watch,
    BandRole.ankle => Icons.directions_run,
  };

  /// Color for UI.
  Color get color => switch (this) {
    BandRole.wrist => const Color(0xFF2196F3), // Blue
    BandRole.ankle => const Color(0xFF4CAF50), // Green
  };
}

/// Keys for persistent device assignment storage.
class AssignmentKeys {
  AssignmentKeys._();
  static const String wristDeviceId = 'bandana_wrist_device_id';
  static const String wristDeviceName = 'bandana_wrist_device_name';
  static const String ankleDeviceId = 'bandana_ankle_device_id';
  static const String ankleDeviceName = 'bandana_ankle_device_name';
}
