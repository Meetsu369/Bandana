import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';

import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/ml_service.dart';
import 'package:bandana/src/features/training/training_controller.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';

void main() {
  group('TrainingDataSource enum', () {
    test('wrist source has correct properties', () {
      expect(TrainingDataSource.wrist.displayName, equals('Wrist (30 features)'));
      expect(TrainingDataSource.wrist.shortName, equals('Wrist'));
      expect(TrainingDataSource.wrist.isSingleBand, isTrue);
      expect(TrainingDataSource.wrist.isCombined, isFalse);
      expect(TrainingDataSource.wrist.bandRole, equals(BandRole.wrist));
    });

    test('ankle source has correct properties', () {
      expect(TrainingDataSource.ankle.displayName, equals('Ankle (30 features)'));
      expect(TrainingDataSource.ankle.shortName, equals('Ankle'));
      expect(TrainingDataSource.ankle.isSingleBand, isTrue);
      expect(TrainingDataSource.ankle.isCombined, isFalse);
      expect(TrainingDataSource.ankle.bandRole, equals(BandRole.ankle));
    });

    test('combined source has correct properties', () {
      expect(TrainingDataSource.combined.displayName, equals('Dual-band (60 features)'));
      expect(TrainingDataSource.combined.shortName, equals('Dual-band'));
      expect(TrainingDataSource.combined.isSingleBand, isFalse);
      expect(TrainingDataSource.combined.isCombined, isTrue);
    });
  });

  group('TrainingController', () {
    late DatabaseService db;
    late MlService ml;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Use in-memory database for test isolation
      db = DatabaseService.withExecutor(NativeDatabase.memory());
      ml = MlService();
      await ml.initialize(await SharedPreferences.getInstance());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedTestData(DatabaseService database) async {
      // Create 3 sessions with different labels
      final session1 = await database.createSession('walking');
      final session2 = await database.createSession('running');
      final session3 = await database.createSession('cycling');

      // Add windows for each session and band role
      for (final sessionId in [session1, session2, session3]) {
        final sessions = await database.getAllSessions();
        final session = sessions.firstWhere((s) => s.id == sessionId);
        final label = session.label;
        for (final role in [BandRole.wrist, BandRole.ankle]) {
          for (var i = 0; i < 2; i++) {
            await database.insertWindow(
              sessionId: sessionId,
              bandRole: role,
              featureVector: List.filled(30, 1.0),
              label: label,
            );
          }
        }
      }
    }

    test('controller initial state', () {
      final controller = TrainingController(db: db, ml: ml);

      expect(controller.availableSessions, isEmpty);
      expect(controller.selectedSessionIds, isEmpty);
      expect(controller.availableLabels, isEmpty);
      expect(controller.selectedSource, equals(TrainingDataSource.wrist));
      expect(controller.hasSelection, isFalse);
      expect(controller.canTrain, isFalse);
      expect(controller.validationResult, equals(null));
      expect(controller.isTraining, isFalse);
      expect(controller.error, equals(null));
      expect(controller.lastResult, equals(null));
    });

    test('toggle session adds then removes session id', () async {
      final controller = TrainingController(db: db, ml: ml);
      await controller.loadSessions();

      controller.toggleSession(1);
      expect(controller.selectedSessionIds, contains(1));

      controller.toggleSession(1);
      expect(controller.selectedSessionIds, isEmpty);
    });

    test('select all adds all session ids', () async {
      final controller = TrainingController(db: db, ml: ml);
      await seedTestData(db);
      await controller.loadSessions();
      controller.selectAll();
      expect(controller.selectedSessionIds.length, equals(3));
    });

    test('clear selection removes all session ids', () async {
      final controller = TrainingController(db: db, ml: ml);
      await seedTestData(db);
      await controller.loadSessions();
      controller.selectAll();
      controller.clearSelection();
      expect(controller.selectedSessionIds, isEmpty);
      expect(controller.hasSelection, isFalse);
    });

    test('changing data source', () async {
      final controller = TrainingController(db: db, ml: ml);
      await controller.loadSessions();

      expect(controller.selectedSource, equals(TrainingDataSource.wrist));
      expect(controller.isWristSource, isTrue);

      controller.setSource(TrainingDataSource.ankle);
      expect(controller.selectedSource, equals(TrainingDataSource.ankle));
      expect(controller.isAnkleSource, isTrue);
      expect(controller.isWristSource, isFalse);

      controller.setSource(TrainingDataSource.combined);
      expect(controller.selectedSource, equals(TrainingDataSource.combined));
      expect(controller.isCombinedSource, isTrue);
      expect(controller.isAnkleSource, isFalse);
      expect(controller.isWristSource, isFalse);

      controller.setSource(TrainingDataSource.wrist);
      expect(controller.selectedSource, equals(TrainingDataSource.wrist));
    });

    test('reset returns to initial state', () async {
      final controller = TrainingController(db: db, ml: ml);
      await seedTestData(db);
      await controller.loadSessions();

      controller.toggleSession(1);
      controller.setSource(TrainingDataSource.combined);
      controller.selectAll();

      controller.reset();

      expect(controller.selectedSessionIds, isEmpty);
      expect(controller.selectedSource, equals(TrainingDataSource.wrist));
      expect(controller.validationResult, equals(null));
      expect(controller.lastResult, equals(null));
      expect(controller.error, equals(null));
      expect(controller.hasSelection, isFalse);
    });

    test('no-selection validation', () async {
      final controller = TrainingController(db: db, ml: ml);
      await controller.loadSessions();

      controller.validateDataset();
      expect(controller.validationResult!.isValid, isFalse);
      expect(controller.validationResult!.message, contains('No sessions selected'));
    });

    test('invalid dataset - empty state', () async {
      final controller = TrainingController(db: db, ml: ml);
      await controller.loadSessions();

      controller.toggleSession(1);
      await controller.validateDataset();
      expect(controller.validationResult, isNot(equals(null)));
      expect(controller.validationResult!.isValid, isFalse);
      expect(controller.validationResult!.message, contains('No training windows found'));
    });

    test('valid dataset - single band wrist', () async {
      final controller = TrainingController(db: db, ml: ml);
      await seedTestData(db);
      await controller.loadSessions();

      controller.selectAll();
      controller.setSource(TrainingDataSource.wrist);
      await controller.validateDataset();

      expect(controller.validationResult!.isValid, isTrue);
      expect(controller.validationResult!.windowCount, greaterThan(0));
      expect(controller.validationResult!.labelCount, equals(3));
      expect(controller.canTrain, isTrue);
    });

    test('valid dataset - single band ankle', () async {
      final controller = TrainingController(db: db, ml: ml);
      await seedTestData(db);
      await controller.loadSessions();

      controller.selectAll();
      controller.setSource(TrainingDataSource.ankle);
      await controller.validateDataset();

      expect(controller.validationResult!.isValid, isTrue);
      expect(controller.validationResult!.windowCount, greaterThan(0));
      expect(controller.validationResult!.labelCount, equals(3));
      expect(controller.canTrain, isTrue);
    });

    test('valid dataset - combined', () async {
      final controller = TrainingController(db: db, ml: ml);
      await seedTestData(db);
      await controller.loadSessions();

      controller.selectAll();
      controller.setSource(TrainingDataSource.combined);
      await controller.validateDataset();

      expect(controller.validationResult!.isValid, isTrue);
      expect(controller.validationResult!.windowCount, greaterThan(0));
      expect(controller.validationResult!.labelCount, equals(3));
      expect(controller.canTrain, isTrue);
    });

    test('insufficient labels fails validation', () async {
      // Create data with only one label
      final singleLabelDb = DatabaseService.withExecutor(NativeDatabase.memory());
      final singleLabelMl = MlService();
      await singleLabelMl.initialize(await SharedPreferences.getInstance());

      final sessionId = await singleLabelDb.createSession('walking');
      for (final role in [BandRole.wrist, BandRole.ankle]) {
        for (var i = 0; i < 5; i++) {
          await singleLabelDb.insertWindow(
            sessionId: sessionId,
            bandRole: role,
            featureVector: List.filled(30, 1.0),
            label: 'walking',
          );
        }
      }

      final controller = TrainingController(db: singleLabelDb, ml: singleLabelMl);
      await controller.loadSessions();
      controller.selectAll();
      controller.setSource(TrainingDataSource.wrist);
      await controller.validateDataset();

      expect(controller.validationResult!.isValid, isFalse);
      expect(controller.validationResult!.message, contains('at least 2 different activity labels'));

      await singleLabelDb.close();
    });

    test('insufficient windows per class fails validation', () async {
      // Create data with one class having only 1 window
      final fewWindowsDb = DatabaseService.withExecutor(NativeDatabase.memory());
      final fewWindowsMl = MlService();
      await fewWindowsMl.initialize(await SharedPreferences.getInstance());

      final session1 = await fewWindowsDb.createSession('walking');
      final session2 = await fewWindowsDb.createSession('running');
      
      // walking: 5 windows
      for (final role in [BandRole.wrist, BandRole.ankle]) {
        for (var i = 0; i < 5; i++) {
          await fewWindowsDb.insertWindow(
            sessionId: session1,
            bandRole: role,
            featureVector: List.filled(30, 1.0),
            label: 'walking',
          );
        }
      }
      // running: only 1 window per band
      for (final role in [BandRole.wrist, BandRole.ankle]) {
        await fewWindowsDb.insertWindow(
          sessionId: session2,
          bandRole: role,
          featureVector: List.filled(30, 1.0),
          label: 'running',
        );
      }

      final controller = TrainingController(db: fewWindowsDb, ml: fewWindowsMl);
      await controller.loadSessions();
      controller.selectAll();
      controller.setSource(TrainingDataSource.wrist);
      await controller.validateDataset();

      expect(controller.validationResult!.isValid, isFalse);
      expect(controller.validationResult!.message, contains('fewer than 2 samples'));

      await fewWindowsDb.close();
    });
  });
}