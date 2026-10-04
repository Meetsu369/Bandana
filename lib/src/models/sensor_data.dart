/// A single IMU sensor reading from the ESP32-C3.
class SensorReading {
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

  /// Timestamp when this reading was received.
  final DateTime timestamp;

  const SensorReading({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.timestamp,
  });

  /// Parse a comma-separated UTF-8 string from the ESP32.
  ///
  /// Supports both legacy 6-value format: "ax,ay,az,gx,gy,gz"
  /// and new 7-value format: "capture_ts,ax,ay,az,gx,gy,gz".
  ///
  /// The firmware capture timestamp is ignored for this legacy model.
  factory SensorReading.fromCsv(String csv) {
    final parts = csv.split(',');
    if (parts.length < 6) {
      throw FormatException('Expected at least 6 comma-separated values, got ${parts.length}: "$csv"');
    }

    // Handle both 6-field (legacy) and 7-field (new) formats
    final hasCaptureTs = parts.length >= 7;
    final axisStart = hasCaptureTs ? 1 : 0;

    if (parts.length < axisStart + 6) {
      throw FormatException('Expected 6 axis values, got ${parts.length - axisStart}: "$csv"');
    }

    return SensorReading(
      ax: double.parse(parts[axisStart].trim()),
      ay: double.parse(parts[axisStart + 1].trim()),
      az: double.parse(parts[axisStart + 2].trim()),
      gx: double.parse(parts[axisStart + 3].trim()),
      gy: double.parse(parts[axisStart + 4].trim()),
      gz: double.parse(parts[axisStart + 5].trim()),
      timestamp: DateTime.now(),
    );
  }

  /// Return the 6-axis values as a flat list.
  List<double> toList() => [ax, ay, az, gx, gy, gz];

  @override
  String toString() =>
      'SensorReading(ax: ${ax.toStringAsFixed(2)}, ay: ${ay.toStringAsFixed(2)}, '
      'az: ${az.toStringAsFixed(2)}, gx: ${gx.toStringAsFixed(2)}, '
      'gy: ${gy.toStringAsFixed(2)}, gz: ${gz.toStringAsFixed(2)})';
}
