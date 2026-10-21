import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';

void main() {
  group('ImuSample.tryParseCsv', () {
    const deviceId = 'test_device_id';
    const deviceName = 'Test Device';
    const bandRole = BandRole.wrist;

    test('parses valid 7-field packet with capture_ts', () {
      const csv = '1000,1.0,2.0,3.0,4.0,5.0,6.0';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );

      expect(sample, isNotNull);
      expect(sample!.captureTimestampMs, equals(1000));
      expect(sample.ax, equals(1.0));
      expect(sample.ay, equals(2.0));
      expect(sample.az, equals(3.0));
      expect(sample.gx, equals(4.0));
      expect(sample.gy, equals(5.0));
      expect(sample.gz, equals(6.0));
      expect(sample.bandRole, equals(bandRole));
      expect(sample.deviceId, equals(deviceId));
      expect(sample.deviceName, equals(deviceName));
      expect(sample.timestamp, isA<DateTime>());
    });

    test('parses another valid packet with different capture_ts', () {
      const csv = '1025,0.1,0.2,0.3,0.4,0.5,0.6';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: BandRole.ankle,
        deviceId: deviceId,
        deviceName: deviceName,
      );

      expect(sample, isNotNull);
      expect(sample!.captureTimestampMs, equals(1025));
      expect(sample.ax, equals(0.1));
      expect(sample.ay, equals(0.2));
      expect(sample.az, equals(0.3));
      expect(sample.gx, equals(0.4));
      expect(sample.gy, equals(0.5));
      expect(sample.gz, equals(0.6));
      expect(sample.bandRole, equals(BandRole.ankle));
    });

    test('rejects packet with fewer than 7 fields (6 fields)', () {
      const csv = '1.0,2.0,3.0,4.0,5.0,6.0'; // Missing capture_ts
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNull);
    });

    test('rejects packet with fewer than 7 fields (5 fields)', () {
      const csv = '1000,1.0,2.0,3.0,4.0,5.0'; // Missing gz
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNull);
    });

    test('rejects packet with invalid capture timestamp (non-integer)', () {
      const csv = 'abc,1.0,2.0,3.0,4.0,5.0,6.0';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNull);
    });

    test('rejects packet with empty capture timestamp', () {
      const csv = ',1.0,2.0,3.0,4.0,5.0,6.0';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNull);
    });

    test('rejects packet with invalid sensor values', () {
      const csv = '1000,abc,2.0,3.0,4.0,5.0,6.0';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNull);
    });

    test('handles negative capture timestamp gracefully', () {
      const csv = '-100,1.0,2.0,3.0,4.0,5.0,6.0';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNotNull);
      expect(sample!.captureTimestampMs, equals(-100));
    });

    test('handles large capture timestamp', () {
      const csv = '4294967295,1.0,2.0,3.0,4.0,5.0,6.0'; // Max uint32
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNotNull);
      expect(sample!.captureTimestampMs, equals(4294967295));
    });

    test('handles whitespace around values', () {
      const csv = ' 1000 , 1.0 , 2.0 , 3.0 , 4.0 , 5.0 , 6.0 ';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      expect(sample, isNotNull);
      expect(sample!.captureTimestampMs, equals(1000));
      expect(sample.ax, equals(1.0));
    });

    test('preserves captureTimestampMs in toList for ML features', () {
      const csv = '1000,1.0,2.0,3.0,4.0,5.0,6.0';
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );

      final list = sample!.toList();
      expect(list.length, equals(6));
      expect(list, equals([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]));
      // captureTimestampMs should NOT be in toList (ML features only use 6 axes)
    });

    test('does not convert captureTimestampMs to Unix epoch DateTime', () {
      const csv = '1000,1.0,2.0,3.0,4.0,5.0,6.0';
      final beforeParse = DateTime.now();
      final sample = ImuSample.tryParseCsv(
        csv: csv,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      final afterParse = DateTime.now();

      expect(sample, isNotNull);
      // timestamp should be phone receive time (wall-clock), NOT firmware capture_ts
      expect(sample!.timestamp.isAfter(beforeParse.subtract(const Duration(seconds: 1))), isTrue);
      expect(sample.timestamp.isBefore(afterParse.add(const Duration(seconds: 1))), isTrue);
      // captureTimestampMs should be the raw firmware value
      expect(sample.captureTimestampMs, equals(1000));
      // timestamp should NOT be DateTime.fromMillisecondsSinceEpoch(1000)
      expect(sample.timestamp.millisecondsSinceEpoch, isNot(equals(1000)));
    });
  });

  group('ImuSample.fromBinary (20-byte packed struct)', () {
    test('parses valid 20-byte binary packet for Wrist', () {
      final bytes = ByteData(20);
      bytes.setUint32(0, 104325, Endian.little); // sensor_tick_ms
      bytes.setUint16(4, 1024, Endian.little);   // seq
      bytes.setInt16(6, 4096, Endian.little);    // ax = 1.0g
      bytes.setInt16(8, -2048, Endian.little);   // ay = -0.5g
      bytes.setInt16(10, 0, Endian.little);      // az = 0.0g
      bytes.setInt16(12, 328, Endian.little);    // gx = 10.0 dps
      bytes.setInt16(14, -656, Endian.little);   // gy = -20.0 dps
      bytes.setInt16(16, 0, Endian.little);      // gz = 0.0 dps
      bytes.setUint16(18, 0x0002, Endian.little); // Wrist (bit 0=0), SD OK (bit 1=1)

      final sample = ImuSample.fromBinary(
        bytes.buffer.asUint8List(),
        deviceId: 'TEST_WRIST_MAC',
        deviceName: 'BANDANA-WRIST',
      );

      expect(sample.sensorTickMs, equals(104325));
      expect(sample.captureTimestampMs, equals(104325));
      expect(sample.seq, equals(1024));
      expect(sample.ax, closeTo(1.0, 0.001));
      expect(sample.ay, closeTo(-0.5, 0.001));
      expect(sample.az, closeTo(0.0, 0.001));
      expect(sample.gx, closeTo(10.0, 0.001));
      expect(sample.gy, closeTo(-20.0, 0.001));
      expect(sample.gz, closeTo(0.0, 0.001));
      expect(sample.isAnkle, isFalse);
      expect(sample.bandRole, equals(BandRole.wrist));
      expect(sample.deviceId, equals('TEST_WRIST_MAC'));
      expect(sample.deviceName, equals('BANDANA-WRIST'));
    });

    test('parses valid 20-byte binary packet for Ankle', () {
      final bytes = ByteData(20);
      bytes.setUint32(0, 50000, Endian.little);  // sensor_tick_ms
      bytes.setUint16(4, 42, Endian.little);      // seq
      bytes.setInt16(6, -4096, Endian.little);   // ax = -1.0g
      bytes.setInt16(8, 8192, Endian.little);    // ay = 2.0g
      bytes.setInt16(10, -8192, Endian.little);  // az = -2.0g
      bytes.setInt16(12, 1640, Endian.little);   // gx = 50.0 dps
      bytes.setInt16(14, -1640, Endian.little);  // gy = -50.0 dps
      bytes.setInt16(16, 328, Endian.little);    // gz = 10.0 dps
      bytes.setUint16(18, 0x0001, Endian.little); // Ankle (bit 0=1)

      final sample = ImuSample.fromBinary(
        bytes.buffer.asUint8List(),
        deviceId: 'TEST_ANKLE_MAC',
        deviceName: 'BANDANA-ANKLE',
      );

      expect(sample.sensorTickMs, equals(50000));
      expect(sample.seq, equals(42));
      expect(sample.ax, closeTo(-1.0, 0.001));
      expect(sample.ay, closeTo(2.0, 0.001));
      expect(sample.az, closeTo(-2.0, 0.001));
      expect(sample.gx, closeTo(50.0, 0.001));
      expect(sample.gy, closeTo(-50.0, 0.001));
      expect(sample.gz, closeTo(10.0, 0.001));
      expect(sample.isAnkle, isTrue);
      expect(sample.bandRole, equals(BandRole.ankle));
    });

    test('explicit bandRole overrides status flag role', () {
      final bytes = ByteData(20);
      bytes.setUint16(18, 0x0001, Endian.little); // Ankle flag

      final sample = ImuSample.fromBinary(
        bytes.buffer.asUint8List(),
        bandRole: BandRole.wrist, // Explicitly assigned
      );

      expect(sample.bandRole, equals(BandRole.wrist));
      expect(sample.isAnkle, isFalse);
    });

    test('rejects payload under 20 bytes', () {
      final shortBytes = [1, 2, 3, 4, 5];
      expect(
        () => ImuSample.fromBinary(shortBytes),
        throwsArgumentError,
      );
    });
  });
}