import 'dart:math';
import 'dart:typed_data';

import '../core/constants/ble_constants.dart';

/// A single IMU sensor reading from a Bandana wearable, tagged with
/// device identity and body placement.
class ImuSample {
  /// Accelerometer X-axis (m/s² or g depending on source).
  final double ax;

  /// Accelerometer Y-axis (m/s² or g depending on source).
  final double ay;

  /// Accelerometer Z-axis (m/s² or g depending on source).
  final double az;

  /// Gyroscope X-axis (°/s).
  final double gx;

  /// Gyroscope Y-axis (°/s).
  final double gy;

  /// Gyroscope Z-axis (°/s).
  final double gz;

  /// Firmware capture timestamp in milliseconds, relative to the ESP32
  /// firmware boot. Monotonic, NOT Unix epoch.
  /// Defaults to -1 if not available (e.g., from database records before migration).
  final int captureTimestampMs;

  /// Hardware sequence number (0..65535) for packet drop and loss tracking.
  final int seq;

  /// Hardware status flags (bit 0: 0=wrist, 1=ankle; bit 1: SD OK).
  final int statusFlags;

  /// Timestamp when this sample was received by the phone (wall-clock time).
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
    this.captureTimestampMs = -1,
    this.seq = 0,
    this.statusFlags = 0,
    required this.timestamp,
    required this.bandRole,
    required this.deviceId,
    required this.deviceName,
  });

  /// True if MicroSD card is initialized and operational (bit 1 of status_flags).
  bool get isSdOk => (statusFlags & 0x02) != 0;

  /// Monotonic hardware timer alias for [captureTimestampMs].
  int get sensorTickMs => captureTimestampMs;

  /// Convenience getter for checking if the placement is on the ankle.
  bool get isAnkle => bandRole == BandRole.ankle;

  /// Acceleration magnitude: √(ax² + ay² + az²).
  double get accelMagnitude =>
      sqrt((ax * ax + ay * ay + az * az).clamp(0, double.infinity));

  /// Gyroscope magnitude: √(gx² + gy² + gz²).
  double get gyroMagnitude =>
      sqrt((gx * gx + gy * gy + gz * gz).clamp(0, double.infinity));

  /// Parse a 20-byte packed binary payload from the ESP32 (Choice B).
  ///
  /// Binary Packet Layout (20 bytes, little-endian):
  /// - [0..3]: uint32 sensor_tick_ms
  /// - [4..5]: uint16 seq
  /// - [6..7]: int16 ax (±8g, 4096.0 LSB/g)
  /// - [8..9]: int16 ay
  /// - [10..11]: int16 az
  /// - [12..13]: int16 gx (±1000 dps, 32.8 LSB/dps)
  /// - [14..15]: int16 gy
  /// - [16..17]: int16 gz
  /// - [18..19]: uint16 status_flags (bit 0: 0=wrist, 1=ankle; bit 1: SD OK)
  factory ImuSample.fromBinary(
    List<int> rawBytes, {
    BandRole? bandRole,
    String deviceId = '',
    String deviceName = '',
    DateTime? timestamp,
  }) {
    if (rawBytes.length < 20) {
      throw ArgumentError(
        'Expected at least 20 bytes for ImuBinaryPacket, got ${rawBytes.length}',
      );
    }

    final byteData = ByteData.sublistView(
      rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes),
    );

    final sensorTickMs = byteData.getUint32(0, Endian.little);
    final seq = byteData.getUint16(4, Endian.little);

    // Accelerometer: +/- 8g -> 4096.0 LSB/g
    final ax = byteData.getInt16(6, Endian.little) / 4096.0;
    final ay = byteData.getInt16(8, Endian.little) / 4096.0;
    final az = byteData.getInt16(10, Endian.little) / 4096.0;

    // Gyroscope: +/- 1000 dps -> 32.8 LSB/dps
    final gx = byteData.getInt16(12, Endian.little) / 32.8;
    final gy = byteData.getInt16(14, Endian.little) / 32.8;
    final gz = byteData.getInt16(16, Endian.little) / 32.8;

    final flags = byteData.getUint16(18, Endian.little);
    final isAnkleFlag = (flags & 0x01) == 1;
    final resolvedRole = bandRole ?? (isAnkleFlag ? BandRole.ankle : BandRole.wrist);

    return ImuSample(
      ax: ax,
      ay: ay,
      az: az,
      gx: gx,
      gy: gy,
      gz: gz,
      captureTimestampMs: sensorTickMs,
      seq: seq,
      statusFlags: flags,
      timestamp: timestamp ?? DateTime.now(),
      bandRole: resolvedRole,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  /// Parse a legacy CSV line from the ESP32: "capture_ts,ax,ay,az,gx,gy,gz".
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
      if (parts.length < 7) return null;

      final captureTs = int.tryParse(parts[0].trim());
      if (captureTs == null) return null;

      return ImuSample(
        captureTimestampMs: captureTs,
        seq: 0,
        statusFlags: 0,
        ax: double.parse(parts[1].trim()),
        ay: double.parse(parts[2].trim()),
        az: double.parse(parts[3].trim()),
        gx: double.parse(parts[4].trim()),
        gy: double.parse(parts[5].trim()),
        gz: double.parse(parts[6].trim()),
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
      'ImuSample(${bandRole.displayName} ts:$captureTimestampMs seq:$seq '
      'ax:${ax.toStringAsFixed(2)} ay:${ay.toStringAsFixed(2)} '
      'az:${az.toStringAsFixed(2)} gx:${gx.toStringAsFixed(2)} '
      'gy:${gy.toStringAsFixed(2)} gz:${gz.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImuSample &&
          runtimeType == other.runtimeType &&
          captureTimestampMs == other.captureTimestampMs &&
          seq == other.seq &&
          statusFlags == other.statusFlags &&
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
        captureTimestampMs,
        seq,
        statusFlags,
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