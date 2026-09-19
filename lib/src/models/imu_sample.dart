import 'dart:math';

import '../core/constants/ble_constants.dart';

/// A single IMU sensor reading from a Bandana wearable, tagged with
/// device identity and body placement.
class ImuSample {
  /// Accelerometer X-axis (m/s²).
  final double ax;

  /// Accelerometer Y-axis (m/s²).
  final double ay;

  /// Accelerometer Z-axis (m/s²).
  final double az;

  /// Gyroscope X-axis (°/s).
  final double gx;

  /// Gyroscope Y-axis (°/s).
  final double gy;

  /// Gyroscope Z-axis (°/s).
  final double gz;

  /// Timestamp when this sample was received by the phone.
  final DateTime timestamp;

  /// Physical placement of the device that sent this sample.
  final BandRole bandRole;

  /// Unique identifier of the BLE device (MAC address on Android).
  final String deviceId;

  /// Human-readable name of the device.
  final String deviceName;

  const ImuSample({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.timestamp,
    required this.bandRole,
    required this.deviceId,
    required this.deviceName,
  });

  /// Acceleration magnitude: √(ax² + ay² + az²).
  double get accelMagnitude =>
      sqrt((ax * ax + ay * ay + az * az).clamp(0, double.infinity));

  /// Gyroscope magnitude: √(gx² + gy² + gz²).
  double get gyroMagnitude =>
      sqrt((gx * gx + gy * gy + gz * gz).clamp(0, double.infinity));

  /// Parse a CSV line from the ESP32: "ax,ay,az,gx,gy,gz".
  ///
  /// Returns `null` if the line is malformed (does not throw).
  static ImuSample? tryParseCsv({
    required String csv,
    required BandRole bandRole,
    required String deviceId,
    required String deviceName,
    DateTime? timestamp,
  }) {
    try {
      final parts = csv.split(',');
      if (parts.length < 6) return null;

      return ImuSample(
        ax: double.parse(parts[0].trim()),
        ay: double.parse(parts[1].trim()),
        az: double.parse(parts[2].trim()),
        gx: double.parse(parts[3].trim()),
        gy: double.parse(parts[4].trim()),
        gz: double.parse(parts[5].trim()),
        timestamp: timestamp ?? DateTime.now(),
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
    } catch (_) {
      return null;
    }
  }

  /// Return the 6-axis values as a flat list (for ML feature extraction).
  List<double> toList() => [ax, ay, az, gx, gy, gz];

  /// Return acceleration axes only.
  List<double> accelAxes() => [ax, ay, az];

  /// Return gyroscope axes only.
  List<double> gyroAxes() => [gx, gy, gz];

  @override
  String toString() =>
      'ImuSample(${bandRole.displayName} ax:${ax.toStringAsFixed(2)} '
      'ay:${ay.toStringAsFixed(2)} az:${az.toStringAsFixed(2)} '
      'gx:${gx.toStringAsFixed(2)} gy:${gy.toStringAsFixed(2)} '
      'gz:${gz.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImuSample &&
          runtimeType == other.runtimeType &&
          ax == other.ax &&
          ay == other.ay &&
          az == other.az &&
          gx == other.gx &&
          gy == other.gy &&
          gz == other.gz &&
          timestamp == other.timestamp &&
          bandRole == other.bandRole &&
          deviceId == other.deviceId &&
          deviceName == other.deviceName;

  @override
  int get hashCode => Object.hash(
        ax,
        ay,
        az,
        gx,
        gy,
        gz,
        timestamp,
        bandRole,
        deviceId,
        deviceName,
      );
}