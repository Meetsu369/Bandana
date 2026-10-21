import 'package:flutter_test/flutter_test.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/services/classifier_service.dart';
import 'package:bandana/src/services/fitness_metrics_service.dart';
import 'package:bandana/src/features/record/record_screen.dart';

void main() {
  group('ClassifierService Real-Time Sliding Window & Heuristic Tests', () {
    late ClassifierService classifier;

    setUp(() {
      classifier = ClassifierService.instance;
      classifier.reset();
    });

    tearDown(() {
      classifier.reset();
    });

    test('Classifies Sitting when wrist and ankle are static (low variance)', () async {
      ActivityPrediction? lastPrediction;
      final sub = classifier.predictionStream.listen((p) {
        lastPrediction = p;
      });

      // Feed 100 samples of resting data (gravity 9.8 on az, minor noise)
      for (int i = 0; i < 100; i++) {
        classifier.addSynchronizedFrame([
          0.01, 0.01, 9.80, 0.0, 0.0, 0.0, // wrist
          0.01, 0.01, 9.80, 0.0, 0.0, 0.0, // ankle
        ]);
      }

      await Future.delayed(const Duration(milliseconds: 20));
      expect(lastPrediction, isNotNull);
      expect(lastPrediction!.label, equals('Sitting'));
      expect(lastPrediction!.confidence, closeTo(0.95, 0.01));

      await sub.cancel();
    });

    test('Classifies Standing_HandMove when ankle is static but wrist is dynamic', () async {
      ActivityPrediction? lastPrediction;
      final sub = classifier.predictionStream.listen((p) {
        lastPrediction = p;
      });

      // Ankle static (<0.02 variance), wrist oscillating (>0.08 variance)
      for (int i = 0; i < 100; i++) {
        final wristAx = (i % 2 == 0) ? 14.0 : 0.0;
        classifier.addSynchronizedFrame([
          wristAx, 0.0, 9.80, 50.0, 20.0, 0.0, // wrist dynamic magnitude
          0.01, 0.01, 9.80, 0.0, 0.0, 0.0,     // ankle static
        ]);
      }

      await Future.delayed(const Duration(milliseconds: 20));
      expect(lastPrediction, isNotNull);
      expect(lastPrediction!.label, equals('Standing_HandMove'));
      expect(lastPrediction!.confidence, closeTo(0.90, 0.01));

      await sub.cancel();
    });

    test('Classifies Jumping_Jacks on bilateral synchronous high impact peaks', () async {
      ActivityPrediction? lastPrediction;
      final sub = classifier.predictionStream.listen((p) {
        lastPrediction = p;
      });

      for (int i = 0; i < 100; i++) {
        // High bilateral impact peak > 1.8g (~18 m/s^2) on ankle, > 1.5g on wrist
        final wristAz = (i == 50) ? 16.0 : 9.8;
        final ankleAz = (i == 50) ? 20.0 : 9.8;
        classifier.addSynchronizedFrame([
          0.0, 0.0, wristAz, 0.0, 0.0, 0.0,
          0.0, 0.0, ankleAz, 0.0, 0.0, 0.0,
        ]);
      }

      await Future.delayed(const Duration(milliseconds: 20));
      expect(lastPrediction, isNotNull);
      expect(lastPrediction!.label, anyOf(equals('Jumping'), equals('Jumping_Jacks')));
      expect(lastPrediction!.confidence, closeTo(0.92, 0.01));

      await sub.cancel();
    });

    test('Triggers inference every stride (50 samples)', () async {
      int predictionCount = 0;
      final sub = classifier.predictionStream.listen((_) => predictionCount++);

      // 100 samples -> 1st inference
      for (int i = 0; i < 100; i++) {
        classifier.addSynchronizedFrame(List.filled(12, 1.0));
      }
      await Future.delayed(const Duration(milliseconds: 10));
      expect(predictionCount, equals(1));

      // Another 50 samples -> 2nd inference (stride)
      for (int i = 0; i < 50; i++) {
        classifier.addSynchronizedFrame(List.filled(12, 1.0));
      }
      await Future.delayed(const Duration(milliseconds: 10));
      expect(predictionCount, equals(2));

      await sub.cancel();
    });
  });

  group('FitnessMetricsService Real-Time Signal Processing Tests', () {
    late FitnessMetricsService fitness;

    setUp(() {
      fitness = FitnessMetricsService(userWeightKg: 70.0);
      fitness.startSession();
    });

    tearDown(() {
      fitness.stopSession();
      fitness.dispose();
    });

    test('Detects steps on ankle_az impact peaks with re-arming hysteresis', () {
      expect(fitness.currentMetrics.totalSteps, equals(0));

      final baseTime = DateTime.now().millisecondsSinceEpoch;

      // 1. Peak above threshold 12.5 m/s^2
      final stepSample1 = ImuSample(
        ax: 0.1,
        ay: 0.2,
        az: 14.0, // > 12.5
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        captureTimestampMs: baseTime + 300,
        seq: 1,
        timestamp: DateTime.now(),
        bandRole: BandRole.ankle,
        deviceId: 'TEST_ANKLE',
        deviceName: 'BANDANA-ANKLE',
      );
      fitness.addSample(stepSample1);
      expect(fitness.currentMetrics.totalSteps, equals(1));

      // 2. Duplicate high peak before re-arming should be rejected
      final duplicateSample = ImuSample(
        ax: 0.1,
        ay: 0.2,
        az: 13.8,
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        captureTimestampMs: baseTime + 350,
        seq: 2,
        timestamp: DateTime.now(),
        bandRole: BandRole.ankle,
        deviceId: 'TEST_ANKLE',
        deviceName: 'BANDANA-ANKLE',
      );
      fitness.addSample(duplicateSample);
      expect(fitness.currentMetrics.totalSteps, equals(1));

      // 3. Drop back below arming threshold (9.8 m/s^2)
      final armSample = ImuSample(
        ax: 0.1,
        ay: 0.2,
        az: 8.5, // < 9.8
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        captureTimestampMs: baseTime + 500,
        seq: 3,
        timestamp: DateTime.now(),
        bandRole: BandRole.ankle,
        deviceId: 'TEST_ANKLE',
        deviceName: 'BANDANA-ANKLE',
      );
      fitness.addSample(armSample);
      expect(fitness.currentMetrics.totalSteps, equals(1));

      // 4. Second valid step
      final stepSample2 = ImuSample(
        ax: 0.1,
        ay: 0.2,
        az: 13.5,
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        captureTimestampMs: baseTime + 700, // > 200ms from last step
        seq: 4,
        timestamp: DateTime.now(),
        bandRole: BandRole.ankle,
        deviceId: 'TEST_ANKLE',
        deviceName: 'BANDANA-ANKLE',
      );
      fitness.addSample(stepSample2);
      expect(fitness.currentMetrics.totalSteps, equals(2));
    });

    test('Ignores wrist samples for step detection', () {
      final wristSample = ImuSample(
        ax: 0.0,
        ay: 0.0,
        az: 15.0, // High acceleration on wrist
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
        captureTimestampMs: 1000,
        seq: 1,
        timestamp: DateTime.now(),
        bandRole: BandRole.wrist,
        deviceId: 'TEST_WRIST',
        deviceName: 'BANDANA-WRIST',
      );

      fitness.addSample(wristSample);
      expect(fitness.currentMetrics.totalSteps, equals(0));
    });
  });

  group('BandLiveDiagnostics Diagnostic Tracker Tests', () {
    test('Calculates live Hz, sequence drops, and MicroSD status', () {
      final diag = BandLiveDiagnostics();

      final now = DateTime.now();

      // Sample 1: Seq 100, SD OK (bit 1=1 -> 0x02)
      diag.onSample(ImuSample(
        ax: 0.5,
        ay: -0.2,
        az: 0.98,
        gx: 1.0,
        gy: -2.0,
        gz: 0.0,
        captureTimestampMs: 1000,
        seq: 100,
        statusFlags: 0x02,
        timestamp: now,
        bandRole: BandRole.wrist,
        deviceId: 'WRIST',
        deviceName: 'BANDANA-WRIST',
      ));

      expect(diag.packetsReceived, equals(1));
      expect(diag.droppedPackets, equals(0));
      expect(diag.isSdOk, isTrue);
      expect(diag.latestSample, isNotNull);
      expect(diag.latestSample!.ax, equals(0.5));

      // Sample 2 with a drop (Seq 103 -> dropped 2 packets: 101, 102)
      diag.onSample(ImuSample(
        ax: 0.6,
        ay: -0.1,
        az: 0.99,
        gx: 1.1,
        gy: -1.9,
        gz: 0.1,
        captureTimestampMs: 1040,
        seq: 103,
        statusFlags: 0x02,
        timestamp: now.add(const Duration(milliseconds: 20)),
        bandRole: BandRole.wrist,
        deviceId: 'WRIST',
        deviceName: 'BANDANA-WRIST',
      ));

      expect(diag.packetsReceived, equals(2));
      expect(diag.droppedPackets, equals(2));
    });
  });
}
