import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/services/database_service.dart';

void main() {
  group('DatabaseService Schema v5 & Persistence', () {
    late DatabaseService db;

    setUp(() {
      db = DatabaseService.withExecutor(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('creates session with participantId', () async {
      final sessionId = await db.createSession('Walking', participantId: 'sumeet_1');
      expect(sessionId, greaterThan(0));

      final sessions = await db.getAllSessions();
      expect(sessions.length, 1);
      expect(sessions.first.id, sessionId);
      expect(sessions.first.label, 'Walking');
      expect(sessions.first.participantId, 'sumeet_1');
    });

    test('persists captureTimestampMs and retrieves it', () async {
      final sessionId = await db.createSession('Running', participantId: 'participant_test');

      final sample = ImuSample(
        ax: 0.1,
        ay: 0.2,
        az: 9.8,
        gx: 1.0,
        gy: 2.0,
        gz: 3.0,
        captureTimestampMs: 123456,
        timestamp: DateTime(2026, 10, 14, 12, 0, 0),
        bandRole: BandRole.wrist,
        deviceId: 'AA:BB:CC',
        deviceName: 'BANDANA_WRIST',
      );

      await db.insertImuSamples(sessionId: sessionId, samples: [sample]);

      final retrieved = await db.getImuSamples(sessionId: sessionId);
      expect(retrieved.length, 1);
      expect(retrieved.first.captureTimestampMs, 123456);
      expect(retrieved.first.ax, 0.1);
      expect(retrieved.first.bandRole, BandRole.wrist);

      final modelSample = retrieved.first.toModelImuSample();
      expect(modelSample.captureTimestampMs, 123456);
    });

    test('records and retrieves prediction feedback', () async {
      final id = await db.insertPredictionFeedback(
        predictedLabel: 'Walking',
        userFeedback: 'incorrect',
        correctedLabel: 'Running',
        modelVersion: 'knn_30_v1',
        confidence: 0.85,
      );

      expect(id, greaterThan(0));

      final unreviewed = await db.getUnreviewedFeedbacks();
      expect(unreviewed.length, 1);
      expect(unreviewed.first.predictedLabel, 'Walking');
      expect(unreviewed.first.correctedLabel, 'Running');
      expect(unreviewed.first.isReviewed, isFalse);

      await db.markFeedbackReviewed(id);

      final unreviewedAfter = await db.getUnreviewedFeedbacks();
      expect(unreviewedAfter, isEmpty);
    });
  });
}
