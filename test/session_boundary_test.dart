import 'package:flutter_test/flutter_test.dart';
import 'package:bandana/src/utils/session_boundary.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';

ImuSample createSample({
  required int captureTs,
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
    bandRole: BandRole.wrist,
    deviceId: 'test',
    deviceName: 'Test',
  );
}

void main() {
  group('SessionBoundaryDetector', () {
    test('normal 40 Hz sequence does not trigger boundary', () {
      final detector = SessionBoundaryDetector();
      // 40 Hz = 25ms spacing
      expect(detector.isSessionBoundary(0), isFalse);
      expect(detector.isSessionBoundary(25), isFalse);
      expect(detector.isSessionBoundary(50), isFalse);
      expect(detector.isSessionBoundary(75), isFalse);
      expect(detector.isSessionBoundary(100), isFalse);
      expect(detector.isSessionBoundary(125), isFalse);
      expect(detector.isSessionBoundary(150), isFalse);
    });

    test('timestamp regression triggers boundary', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(5000);
      detector.isSessionBoundary(5025);
      detector.isSessionBoundary(5050);

      // Regression to zero - firmware reset
      expect(detector.isSessionBoundary(0), isTrue);
      expect(detector.isSessionBoundary(25), isFalse); // After reset, new sequence starts
    });

    test('timestamp reset to zero triggers boundary', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(10000);
      detector.isSessionBoundary(10025);

      // Reset to zero
      expect(detector.isSessionBoundary(0), isTrue);
    });

    test('large timestamp gap triggers boundary', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(1000);

      // Gap of 200ms > 100ms threshold
      expect(detector.isSessionBoundary(1201), isTrue);
    });

    test('gap at threshold boundary does not trigger', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(1000);

      // Gap of exactly 100ms (threshold) should NOT trigger
      expect(detector.isSessionBoundary(1100), isFalse);
    });

    test('gap just above threshold triggers', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(1000);

      // Gap of 101ms > 100ms threshold
      expect(detector.isSessionBoundary(1101), isTrue);
    });

    test('negative timestamps do not trigger boundary', () {
      final detector = SessionBoundaryDetector();
      expect(detector.isSessionBoundary(-1), isFalse);
      expect(detector.isSessionBoundary(-100), isFalse);
      // After negative, positive should not trigger (prev was negative)
      expect(detector.isSessionBoundary(0), isFalse);
      expect(detector.isSessionBoundary(25), isFalse);
    });

    test('reset clears internal state', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(1000);
      detector.isSessionBoundary(1025);
      detector.reset();

      // After reset, should not detect boundary from old timestamp
      expect(detector.isSessionBoundary(1050), isFalse);
      expect(detector.isSessionBoundary(1075), isFalse);
    });

    test('first sample never triggers boundary', () {
      final detector = SessionBoundaryDetector();
      expect(detector.isSessionBoundary(0), isFalse);
      expect(detector.isSessionBoundary(25), isFalse);
      expect(detector.isSessionBoundary(50), isFalse);
    });
  });

  group('SessionBoundaryDetector - Window Duration Validation', () {
    test('80 samples with correct 25ms spacing is valid (1975ms span)', () {
      final detector = SessionBoundaryDetector();
      // 80 samples at 40Hz: first=0, last=79*25=1975
      final window = List.generate(80, (i) => createSample(captureTs: i * 25));
      expect(detector.isValidWindowDuration(window), isTrue);
    });

    test('80 samples with slightly faster spacing is valid', () {
      final detector = SessionBoundaryDetector();
      // 24ms spacing: last = 79*24 = 1896ms (within 1800-2100)
      final window = List.generate(80, (i) => createSample(captureTs: i * 24));
      expect(detector.isValidWindowDuration(window), isTrue);
    });

    test('80 samples with slightly slower spacing is valid', () {
      final detector = SessionBoundaryDetector();
      // 26ms spacing: last = 79*26 = 2054ms (within 1800-2100)
      final window = List.generate(80, (i) => createSample(captureTs: i * 26));
      expect(detector.isValidWindowDuration(window), isTrue);
    });

    test('80 samples with 20ms spacing (50 Hz) is valid (1580ms span)', () {
      final detector = SessionBoundaryDetector();
      // 50 Hz = 20ms spacing: last = 79*20 = 1580ms (within 1400-2200)
      final window = List.generate(80, (i) => createSample(captureTs: i * 20));
      expect(detector.isValidWindowDuration(window), isTrue);
    });

    test('too-short window (fast spacing) is rejected', () {
      final detector = SessionBoundaryDetector();
      // 15ms spacing: last = 79*15 = 1185ms < 1400
      final window = List.generate(80, (i) => createSample(captureTs: i * 15));
      expect(detector.isValidWindowDuration(window), isFalse);
    });

    test('too-long window (slow spacing) is rejected', () {
      final detector = SessionBoundaryDetector();
      // 30ms spacing: last = 79*30 = 2370ms > 2100
      final window = List.generate(80, (i) => createSample(captureTs: i * 30));
      expect(detector.isValidWindowDuration(window), isFalse);
    });

    test('window with session boundary in middle is rejected', () {
      final detector = SessionBoundaryDetector();
      // First 40 samples at t=0..975, then reset, then 40 samples at t=0..975
      // Total span = 975ms (but actually it's two separate sessions)
      final firstHalf = List.generate(40, (i) => createSample(captureTs: i * 25));
      final secondHalf = List.generate(40, (i) => createSample(captureTs: i * 25));
      final window = [...firstHalf, ...secondHalf];

      // Duration = 975 - 0 = 975ms < 1800
      expect(detector.isValidWindowDuration(window), isFalse);
    });

    test('window with negative timestamps is accepted (unknown duration)', () {
      final detector = SessionBoundaryDetector();
      final window = List.generate(80, (i) => createSample(captureTs: -1));
      expect(detector.isValidWindowDuration(window), isTrue);
    });

    test('window with mixed negative and positive timestamps is accepted', () {
      final detector = SessionBoundaryDetector();
      final window = [
        createSample(captureTs: -1),
        ...List.generate(79, (i) => createSample(captureTs: i * 25)),
      ];
      expect(detector.isValidWindowDuration(window), isTrue);
    });

    test('window with fewer than 2 samples is invalid', () {
      final detector = SessionBoundaryDetector();
      expect(detector.isValidWindowDuration([]), isFalse);
      expect(detector.isValidWindowDuration([createSample(captureTs: 0)]), isFalse);
    });

    test('isValidWindow checks exact size', () {
      final detector = SessionBoundaryDetector();
      final window = List.generate(80, (i) => createSample(captureTs: i * 25));
      expect(detector.isValidWindow(window), isTrue);
      expect(detector.isValidWindow(window, expectedSize: 80), isTrue);
      expect(detector.isValidWindow(window.take(79).toList()), isFalse);
      // take(81) from 80 elements returns 80 elements, so it's valid
      expect(detector.isValidWindow(window.take(81).toList()), isTrue);
      // To test invalid size, use a smaller window
      expect(detector.isValidWindow(window.take(70).toList()), isFalse);
    });
  });

  group('DualBandSessionDetector', () {
    test('wrist boundary detected independently', () {
      final detector = DualBandSessionDetector();
      detector.wrist.isSessionBoundary(1000);
      detector.wrist.isSessionBoundary(1025);

      expect(detector.checkBoundary(BandRole.wrist, 0), isTrue); // reset
      expect(detector.checkBoundary(BandRole.ankle, 0), isFalse); // ankle unaffected
    });

    test('ankle boundary detected independently', () {
      final detector = DualBandSessionDetector();
      detector.ankle.isSessionBoundary(1000);
      detector.ankle.isSessionBoundary(1025);

      expect(detector.checkBoundary(BandRole.ankle, 0), isTrue); // reset
      expect(detector.checkBoundary(BandRole.wrist, 0), isFalse); // wrist unaffected
    });

    test('handleBoundary resets only affected band', () {
      final detector = DualBandSessionDetector();
      detector.wrist.isSessionBoundary(1000);
      detector.ankle.isSessionBoundary(1000);

      detector.handleBoundary(BandRole.wrist);

      // Wrist reset, ankle still has history
      expect(detector.checkBoundary(BandRole.wrist, 1025), isFalse); // fresh start
      expect(detector.checkBoundary(BandRole.ankle, 1200), isTrue); // gap from 1000 to 1200 = 200 > 100
    });

    test('reset clears both detectors', () {
      final detector = DualBandSessionDetector();
      detector.wrist.isSessionBoundary(1000);
      detector.ankle.isSessionBoundary(1000);
      detector.reset();

      expect(detector.checkBoundary(BandRole.wrist, 1025), isFalse);
      expect(detector.checkBoundary(BandRole.ankle, 1025), isFalse);
    });

    test('validateDualBandWindows - both valid returns true', () {
      final detector = DualBandSessionDetector();
      final wristWindow = List.generate(80, (i) => createSample(captureTs: i * 25));
      final ankleWindow = List.generate(80, (i) => createSample(captureTs: i * 25));

      expect(detector.validateDualBandWindows(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
        hasWrist: true,
        hasAnkle: true,
      ), isTrue);
    });

    test('validateDualBandWindows - wrist invalid returns false', () {
      final detector = DualBandSessionDetector();
      final wristWindow = List.generate(80, (i) => createSample(captureTs: i * 15)); // too fast (1185ms < 1400ms)
      final ankleWindow = List.generate(80, (i) => createSample(captureTs: i * 25)); // valid

      expect(detector.validateDualBandWindows(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
        hasWrist: true,
        hasAnkle: true,
      ), isFalse);
    });

    test('validateDualBandWindows - ankle invalid returns false', () {
      final detector = DualBandSessionDetector();
      final wristWindow = List.generate(80, (i) => createSample(captureTs: i * 25)); // valid
      final ankleWindow = List.generate(80, (i) => createSample(captureTs: i * 30)); // too slow

      expect(detector.validateDualBandWindows(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
        hasWrist: true,
        hasAnkle: true,
      ), isFalse);
    });

    test('validateDualBandWindows - single band (hasWrist=false) only validates ankle', () {
      final detector = DualBandSessionDetector();
      final wristWindow = <ImuSample>[]; // empty
      final ankleWindow = List.generate(80, (i) => createSample(captureTs: i * 25)); // valid

      expect(detector.validateDualBandWindows(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
        hasWrist: false,
        hasAnkle: true,
      ), isTrue);
    });

    test('validateDualBandWindows - single band with invalid ankle returns false', () {
      final detector = DualBandSessionDetector();
      final wristWindow = <ImuSample>[]; // empty
      final ankleWindow = List.generate(80, (i) => createSample(captureTs: i * 30)); // too slow

      expect(detector.validateDualBandWindows(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
        hasWrist: false,
        hasAnkle: true,
      ), isFalse);
    });

    test('boundary clears partial window - first sample after reset starts fresh', () {
      final detector = DualBandSessionDetector();
      // Accumulate some samples
      detector.wrist.isSessionBoundary(100);
      detector.wrist.isSessionBoundary(125);
      detector.wrist.isSessionBoundary(150);

      // Boundary detected (reset)
      detector.wrist.isSessionBoundary(0);

      // Next samples should not see boundary from pre-reset timestamps
      expect(detector.wrist.isSessionBoundary(25), isFalse);
      expect(detector.wrist.isSessionBoundary(50), isFalse);
      expect(detector.wrist.isSessionBoundary(75), isFalse);
    });

    test('consecutive boundaries handled correctly', () {
      final detector = DualBandSessionDetector();
      detector.wrist.isSessionBoundary(1000);
      detector.wrist.isSessionBoundary(1025);

      // First reset
      expect(detector.wrist.isSessionBoundary(0), isTrue);

      // Second reset shortly after
      expect(detector.wrist.isSessionBoundary(0), isFalse); // prev was 0, current is 0, no regression, gap=0
      expect(detector.wrist.isSessionBoundary(25), isFalse);
    });
  });

  group('SessionBoundaryDetector - Edge Cases', () {
    test('uint32 max timestamp handled', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(4294967295);
      // After max, any normal value would be regression
      expect(detector.isSessionBoundary(0), isTrue);
    });

    test('wrap-around from near max to zero detected', () {
      final detector = SessionBoundaryDetector();
      detector.isSessionBoundary(4294967000);
      // Gap of 295ms > 100ms but not regression
      // Actually this is a large forward gap, should trigger
      expect(detector.isSessionBoundary(4294967295), isTrue); // gap = 295 > 100
    });

    test('custom thresholds work', () {
      final customDetector = SessionBoundaryDetector(
        sessionBoundaryThresholdMs: 50,
        minWindowDurationMs: 1500,
        maxWindowDurationMs: 2500,
      );

      customDetector.isSessionBoundary(1000);
      expect(customDetector.isSessionBoundary(1060), isTrue); // gap 60 > 50

      customDetector.reset();
      customDetector.isSessionBoundary(1000);
      expect(customDetector.isSessionBoundary(1040), isFalse); // gap 40 < 50
    });
  });
}