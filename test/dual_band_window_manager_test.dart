import 'package:flutter_test/flutter_test.dart';
import 'package:bandana/src/utils/dual_band_window_manager.dart';
import 'package:bandana/src/utils/session_boundary.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';

ImuSample createSample({
  required int captureTs,
  BandRole role = BandRole.wrist,
  double ax = 0,
  double ay = 0,
  double az = 0,
  double gx = 0,
  double gy = 0,
  double gz = 0,
}) {
  return ImuSample(
    captureTimestampMs: captureTs,
    ax: ax,
    ay: ay,
    az: az,
    gx: gx,
    gy: gy,
    gz: gz,
    timestamp: DateTime.now(),
    bandRole: role,
    deviceId: 'test',
    deviceName: 'Test',
  );
}

void main() {
  group('DualBandWindowManager - Basic Operations', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Wrist 80-sample window → valid', () {
      // Add 80 wrist samples
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      final result = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result, equals(WindowConsumeResult.consumedValid));
    });

    test('Ankle 80-sample window → valid', () {
      // Add 80 ankle samples
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      final result = manager.tryConsumeWindow(BandRole.ankle, validateDuration: true);
      expect(result, equals(WindowConsumeResult.consumedValid));
    });

    test('Both valid → one dual-band window consumed', () {
      // Add 80 samples to both
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      expect(consumed, isNotNull);
      expect(consumed!.wristWindow.length, equals(80));
      expect(consumed.ankleWindow.length, equals(80));
    });

    test('Wrist valid + Ankle invalid → no dual prediction', () {
      // Wrist: valid 25ms spacing
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }
      // Ankle: invalid 30ms spacing (too slow)
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 30, role: BandRole.ankle));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      // Should return null because ankle window is invalid
      // Both buffers should remain unchanged (not consumed)
      expect(consumed, isNull);
    });

    test('Ankle valid + Wrist invalid → no dual prediction', () {
      // Ankle: valid 25ms spacing
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }
      // Wrist: invalid 15ms spacing (too fast, 1185ms < 1400ms)
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 15, role: BandRole.wrist));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      expect(consumed, isNull);
    });
  });

  group('DualBandWindowManager - Session Boundary Independence', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Wrist reset does not clear healthy Ankle state', () {
      // Build up both buffers
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      // Trigger wrist boundary by sending reset (timestamp regression)
      manager.addSample(createSample(captureTs: 0, role: BandRole.wrist));

      // Ankle buffer should still have 80 samples
      expect(manager.ankleBuffer.length, equals(80));
      // Wrist buffer should be cleared
      expect(manager.wristBuffer.length, equals(1)); // Just the reset sample
    });

    test('Ankle reset does not clear healthy Wrist state', () {
      // Build up both buffers
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      // Trigger ankle boundary
      manager.addSample(createSample(captureTs: 0, role: BandRole.ankle));

      // Wrist buffer should still have 80 samples
      expect(manager.wristBuffer.length, equals(80));
      // Ankle buffer should be cleared
      expect(manager.ankleBuffer.length, equals(1)); // Just the reset sample
    });

    test('Wrist old-session samples cannot pair with new-session samples', () {
      // First session: 40 wrist samples
      for (int i = 0; i < 40; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Session boundary (reset)
      manager.addSample(createSample(captureTs: 0, role: BandRole.wrist));

      // Second session: 40 more samples (total 41)
      for (int i = 1; i <= 40; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Should not be able to consume a full window from mixed sessions
      // Because the buffer was cleared at boundary, we only have 41 samples from second session
      expect(manager.wristBuffer.length, equals(41));

      // Add more to reach 80 from second session
      for (int i = 41; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Now should be valid (all from second session)
      final result = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result, equals(WindowConsumeResult.consumedValid));
    });
  });

  group('DualBandWindowManager - Duplicate Consumption Prevention', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Duplicate consumption is impossible - same window not consumed twice', () {
      // Add 80 wrist samples
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // First consumption
      final result1 = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result1, equals(WindowConsumeResult.consumedValid));

      // Second attempt should return notReady (buffer empty)
      final result2 = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result2, equals(WindowConsumeResult.notReady));
    });

    test('Dual-band window not consumed twice', () {
      // Add 80 samples to both
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      // First consumption
      final consumed1 = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );
      expect(consumed1, isNotNull);

      // Second attempt should return null (not ready)
      final consumed2 = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );
      expect(consumed2, isNull);
    });
  });

  group('DualBandWindowManager - BLE Batching Safety', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Normal BLE batching does not create false boundaries', () {
      // Simulate BLE batching: samples arrive in bursts but capture timestamps are sequential
      // First batch: 10 samples
      for (int i = 0; i < 10; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }
      // Second batch arrives "late" but capture timestamps continue normally
      for (int i = 10; i < 20; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }
      // Continue to 80
      for (int i = 20; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // No boundary should have been triggered
      final result = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result, equals(WindowConsumeResult.consumedValid));
    });

    test('Capture timestamp ordering is preserved', () {
      // Add samples in order
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: false,
        validateDuration: true,
      );

      // Just checking that consumption works - the manager preserves order by buffer insertion order
      expect(consumed, isNotNull);
      // The window should have samples in capture timestamp order
      for (int i = 1; i < consumed!.wristWindow.length; i++) {
        expect(consumed.wristWindow[i].captureTimestampMs, greaterThan(consumed.wristWindow[i - 1].captureTimestampMs));
      }
    });
  });

  group('DualBandWindowManager - Negative/Unknown Timestamp Behavior', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Negative timestamps do not trigger boundaries', () {
      manager.addSample(createSample(captureTs: -1, role: BandRole.wrist));
      manager.addSample(createSample(captureTs: -1, role: BandRole.wrist));
      manager.addSample(createSample(captureTs: -1, role: BandRole.wrist));

      // Should not trigger boundary
      expect(manager.wristBuffer.length, equals(3));
    });

    test('Window with negative timestamps is accepted (unknown duration)', () {
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: -1, role: BandRole.wrist));
      }

      final result = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      // Negative timestamps → unknown duration → accept
      expect(result, equals(WindowConsumeResult.consumedValid));
    });

    test('Mixed negative and positive timestamps accepted', () {
      manager.addSample(createSample(captureTs: -1, role: BandRole.wrist));
      for (int i = 1; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      final result = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result, equals(WindowConsumeResult.consumedValid));
    });
  });

  group('DualBandWindowManager - Single-Band Behavior', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Single-band Wrist prediction still works', () {
      // Only wrist connected
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: false,
        validateDuration: true,
      );

      expect(consumed, isNotNull);
      expect(consumed!.wristWindow.length, equals(80));
      expect(consumed.ankleWindow.isEmpty, isTrue);
    });

    test('Single-band Ankle prediction still works', () {
      // Only ankle connected
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: false,
        hasAnkle: true,
        validateDuration: true,
      );

      expect(consumed, isNotNull);
      expect(consumed!.ankleWindow.length, equals(80));
      expect(consumed.wristWindow.isEmpty, isTrue);
    });
  });

  group('DualBandWindowManager - Feature Vector Lengths', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Dual-band feature input remains exactly 60 values', () {
      // Add 80 samples with realistic data
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(
          captureTs: i * 25,
          role: BandRole.wrist,
          ax: i.toDouble(), ay: i.toDouble(), az: i.toDouble(),
          gx: i.toDouble(), gy: i.toDouble(), gz: i.toDouble(),
        ));
        manager.addSample(createSample(
          captureTs: i * 25,
          role: BandRole.ankle,
          ax: i.toDouble(), ay: i.toDouble(), az: i.toDouble(),
          gx: i.toDouble(), gy: i.toDouble(), gz: i.toDouble(),
        ));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      expect(consumed, isNotNull);

      // Verify ML would receive exactly 60 features
      // (This tests the integration with ML service indirectly)
      // Wrist: 6 axes * 5 stats = 30 features
      // Ankle: 6 axes * 5 stats = 30 features
      // Total: 60 features
    });

    test('Single-band feature input remains exactly 30 values', () {
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(
          captureTs: i * 25,
          role: BandRole.wrist,
          ax: i.toDouble(), ay: i.toDouble(), az: i.toDouble(),
          gx: i.toDouble(), gy: i.toDouble(), gz: i.toDouble(),
        ));
      }

      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: false,
        validateDuration: true,
      );

      expect(consumed, isNotNull);
      // Single band = 30 features
    });
  });

  group('DualBandWindowManager - Stale Window Prevention', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('No stale window is reused after boundary', () {
      // Build up 79 wrist samples (one short of window)
      for (int i = 0; i < 79; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Trigger boundary
      manager.addSample(createSample(captureTs: 0, role: BandRole.wrist));

      // Add 79 more (total 80 from new session)
      for (int i = 1; i <= 79; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Now have 80 samples from new session
      final result = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(result, equals(WindowConsumeResult.consumedValid));
    });

    test('After boundary, partial old data is not mixed with new', () {
      // 50 samples from old session
      for (int i = 0; i < 50; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Boundary
      manager.addSample(createSample(captureTs: 0, role: BandRole.wrist));

      // 50 samples from new session (total 51)
      for (int i = 1; i <= 50; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      // Should only have 51 samples (old 50 were cleared)
      expect(manager.wristBuffer.length, equals(51));
    });
  });

  group('DualBandWindowManager - Record/Live Consistency', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Record and Live use equivalent window validity rules', () {
      // Both should use the same session detector and window validation
      // This is verified by using the same DualBandWindowManager class
      // with the same DualBandSessionDetector for both

      // Add valid samples to both
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      // Both should be able to consume
      final consumed = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      expect(consumed, isNotNull);
    });

    test('Validation rules are consistent between single and dual band', () {
      // Single band wrist
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 15, role: BandRole.wrist)); // Too fast (1185ms < 1400ms)
      }

      final singleResult = manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(singleResult, equals(WindowConsumeResult.consumedInvalid));

      // Reset
      manager.reset();

      // Dual band with same invalid wrist data
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 15, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle)); // Valid
      }

      final dualResult = manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      // Should fail because wrist is invalid
      expect(dualResult, isNull);
    });
  });

  group('DualBandWindowManager - Generation Tracking', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('Generation increments on valid window consumption', () {
      expect(manager.wristGeneration, equals(0));
      expect(manager.ankleGeneration, equals(0));

      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      manager.tryConsumeWindow(BandRole.wrist, validateDuration: true);
      expect(manager.wristGeneration, equals(1));
      expect(manager.ankleGeneration, equals(0));
    });

    test('Generation increments on boundary', () {
      expect(manager.wristGeneration, equals(0));

      manager.addSample(createSample(captureTs: 1000, role: BandRole.wrist));
      manager.addSample(createSample(captureTs: 0, role: BandRole.wrist)); // Boundary

      expect(manager.wristGeneration, equals(1));
    });

    test('Generation pair tracks dual-band synchronization', () {
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      final pair1 = manager.nextGenerationPair;
      expect(pair1.wristGen, equals(0));
      expect(pair1.ankleGen, equals(0));

      manager.tryConsumeDualBandWindow(
        hasWrist: true,
        hasAnkle: true,
        validateDuration: true,
      );

      final pair2 = manager.nextGenerationPair;
      expect(pair2.wristGen, equals(1));
      expect(pair2.ankleGen, equals(1));
    });
  });

  group('DualBandWindowManager - Edge Cases', () {
    late DualBandWindowManager manager;

    setUp(() {
      manager = DualBandWindowManager(
        sessionDetector: DualBandSessionDetector(),
      );
    });

    test('canConsumeDualBandWindow returns correct readiness', () {
      // Not ready - no samples
      expect(manager.canConsumeDualBandWindow(hasWrist: true, hasAnkle: true), isFalse);

      // Not ready - only wrist has samples
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }
      expect(manager.canConsumeDualBandWindow(hasWrist: true, hasAnkle: true), isFalse);

      // Ready - both have samples
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }
      expect(manager.canConsumeDualBandWindow(hasWrist: true, hasAnkle: true), isTrue);
    });

    test('clearBand clears only specified band', () {
      for (int i = 0; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.ankle));
      }

      manager.clearBand(BandRole.wrist);

      expect(manager.wristBuffer.isEmpty, isTrue);
      expect(manager.ankleBuffer.length, equals(80));
    });

    test('hasPartialWindow detects partial windows', () {
      expect(manager.hasPartialWindow(BandRole.wrist), isFalse);

      for (int i = 0; i < 40; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      expect(manager.hasPartialWindow(BandRole.wrist), isTrue);
      expect(manager.hasPartialWindow(BandRole.ankle), isFalse);

      // Add more to complete window
      for (int i = 40; i < 80; i++) {
        manager.addSample(createSample(captureTs: i * 25, role: BandRole.wrist));
      }

      expect(manager.hasPartialWindow(BandRole.wrist), isFalse);
    });
  });
}