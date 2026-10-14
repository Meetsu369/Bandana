import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:archive/archive.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bandana_export_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return tempDir.path;
    });
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  });

  group('ExportService', () {
    late DatabaseService db;
    late ExportService exportService;

    setUp(() {
      db = DatabaseService.withExecutor(NativeDatabase.memory());
      exportService = ExportService(db: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('exports single session CSV with standard filename and metadata header', () async {
      final sessionId = await db.createSession('Walking', participantId: 'sumeet');
      final sample = ImuSample(
        ax: 0.1,
        ay: 0.2,
        az: 9.8,
        gx: 1.0,
        gy: 2.0,
        gz: 3.0,
        captureTimestampMs: 1000,
        timestamp: DateTime(2026, 10, 14, 15, 30, 0),
        bandRole: BandRole.wrist,
        deviceId: 'AA:BB',
        deviceName: 'WRIST',
      );
      await db.insertImuSamples(sessionId: sessionId, samples: [sample]);

      final csvFile = await exportService.exportSessionCsv(sessionId);
      expect(await csvFile.exists(), isTrue);

      final content = await csvFile.readAsString();
      expect(content.contains('# BANDANA IMU Session Export'), isTrue);
      expect(content.contains('# Participant ID: sumeet'), isTrue);
      expect(content.contains('# Activity: Walking'), isTrue);
      expect(content.contains('captureTimestampMs'), isTrue);
      expect(content.contains('1000'), isTrue);
    });

    test('exports multiple sessions into ZIP archive containing manifest.json', () async {
      final s1 = await db.createSession('Walking', participantId: 'sumeet');
      final s2 = await db.createSession('Running', participantId: 'sumeet');

      final sample = ImuSample(
        ax: 0.5,
        ay: 0.5,
        az: 9.8,
        gx: 0,
        gy: 0,
        gz: 0,
        captureTimestampMs: 2000,
        timestamp: DateTime.now(),
        bandRole: BandRole.wrist,
        deviceId: 'AA:BB',
        deviceName: 'WRIST',
      );
      await db.insertImuSamples(sessionId: s1, samples: [sample]);
      await db.insertImuSamples(sessionId: s2, samples: [sample]);

      final zipFile = await exportService.exportSessionsAsZip([s1, s2]);
      expect(await zipFile.exists(), isTrue);

      final zipBytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      // Verify archive contains manifest.json and 2 CSV files
      expect(archive.findFile('manifest.json'), isNotNull);
      final manifestFile = archive.findFile('manifest.json')!;
      final manifestStr = utf8.decode(manifestFile.content as List<int>);
      final manifestJson = jsonDecode(manifestStr) as Map<String, dynamic>;

      expect(manifestJson['sessionCount'], 2);
      expect(manifestJson['schemaVersion'], 2);
      expect((manifestJson['sessions'] as List).length, 2);
    });
  });
}
