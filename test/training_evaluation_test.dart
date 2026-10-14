import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/features/training/training_controller.dart';
import 'package:bandana/src/models/evaluation_metrics.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/ml_service.dart';

void main() {
  group('Training and Evaluation with Session Split', () {
    late DatabaseService db;
    late MlService ml;
    late TrainingController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = DatabaseService.withExecutor(NativeDatabase.memory());
      ml = MlService();
      await ml.initialize(prefs);
      controller = TrainingController(db: db, ml: ml);
    });

    tearDown(() async {
      await db.close();
    });

    test('ModelEvaluationReport computes accurate multi-class metrics', () {
      final actual = ['Walking', 'Walking', 'Running', 'Running', 'Sitting'];
      final predicted = ['Walking', 'Running', 'Running', 'Running', 'Sitting'];

      final report = ModelEvaluationReport.compute(
        actualLabels: actual,
        predictedLabels: predicted,
        trainSessionCount: 3,
        validationSessionCount: 1,
      );

      expect(report.totalSamples, 5);
      expect(report.correctCount, 4);
      expect(report.accuracy, 4 / 5);
      expect(report.macroPrecision, greaterThan(0.0));
      expect(report.macroRecall, greaterThan(0.0));
      expect(report.macroF1, greaterThan(0.0));
      expect(report.confusionMatrix['Walking']!['Walking'], 1);
      expect(report.confusionMatrix['Walking']!['Running'], 1);
    });

    test('trains Logistic Regression with session split and generates evaluation report', () async {
      // Create 4 sessions across 2 classes (2 walking sessions, 2 running sessions)
      final s1 = await db.createSession('Walking', participantId: 'p1');
      final s2 = await db.createSession('Walking', participantId: 'p1');
      final s3 = await db.createSession('Running', participantId: 'p1');
      final s4 = await db.createSession('Running', participantId: 'p1');

      for (final s in [s1, s2]) {
        for (int i = 0; i < 5; i++) {
          await db.insertWindow(
            sessionId: s,
            bandRole: BandRole.wrist,
            featureVector: List.generate(30, (idx) => 1.0 + idx * 0.05),
            label: 'Walking',
          );
        }
      }

      for (final s in [s3, s4]) {
        for (int i = 0; i < 5; i++) {
          await db.insertWindow(
            sessionId: s,
            bandRole: BandRole.wrist,
            featureVector: List.generate(30, (idx) => 10.0 + idx * 0.05),
            label: 'Running',
          );
        }
      }

      await controller.loadSessions();
      controller.selectAll();
      controller.setSource(TrainingDataSource.wrist);
      controller.setAlgorithm(MlAlgorithm.logisticRegression);

      await controller.validateDataset();
      expect(controller.validationResult!.isValid, isTrue);

      await controller.train();

      expect(controller.lastResult, isNotNull);
      expect(controller.lastResult!.success, isTrue);
      expect(controller.lastResult!.algorithm, MlAlgorithm.logisticRegression);
      expect(ml.isTrained, isTrue);
      expect(ml.algorithm30, MlAlgorithm.logisticRegression);

      // Prediction using trained SoftmaxRegressor outputs true confidence
      final pred = ml.predictFromFeatures30(List.generate(30, (idx) => 1.05 + idx * 0.05));
      expect(pred, isNotNull);
      expect(pred!.label, 'Walking');
      expect(pred.confidence, isNotNull);
      expect(pred.confidence!, greaterThan(0.5));
    });

    test('trains KNN with session split and rollback capability', () async {
      final s1 = await db.createSession('Walking');
      final s2 = await db.createSession('Running');
      final s3 = await db.createSession('Walking');

      for (final s in [s1, s3]) {
        for (int i = 0; i < 4; i++) {
          await db.insertWindow(
            sessionId: s,
            bandRole: BandRole.wrist,
            featureVector: List.filled(30, 1.0),
            label: 'Walking',
          );
        }
      }

      for (int i = 0; i < 4; i++) {
        await db.insertWindow(
          sessionId: s2,
          bandRole: BandRole.wrist,
          featureVector: List.filled(30, 8.0),
          label: 'Running',
        );
      }

      await controller.loadSessions();
      controller.selectAll();
      controller.setSource(TrainingDataSource.wrist);
      controller.setAlgorithm(MlAlgorithm.knn);

      await controller.validateDataset();
      await controller.train();

      expect(controller.lastResult!.success, isTrue);
      expect(ml.isTrained, isTrue);
      expect(ml.algorithm30, MlAlgorithm.knn);

      // Honest KNN confidence is null
      final pred = ml.predictFromFeatures30(List.filled(30, 1.0));
      expect(pred!.label, 'Walking');
      expect(pred.confidence, isNull);
    });
  });
}
