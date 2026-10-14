import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/services/laptop_training_service.dart';
import 'package:bandana/src/services/ml_service.dart';

void main() {
  group('LaptopTrainingService', () {
    late MlService ml;
    late SharedPreferences prefs;
    late LaptopTrainingService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      ml = MlService();
      await ml.initialize(prefs);
      service = LaptopTrainingService(ml: ml, prefs: prefs);
    });

    test('configures and persists custom laptop host', () async {
      expect(service.configuredHost, LaptopTrainingService.defaultHost);

      await service.setConfiguredHost('http://192.168.1.150:8000/');
      expect(service.configuredHost, 'http://192.168.1.150:8000');
    });

    test('checkHealth returns false gracefully when host is unreachable', () async {
      // Connect to non-existent local port with short timeout
      final isHealthy = await service.checkHealth(
        overrideHost: 'http://127.0.0.1:54321',
        timeout: const Duration(milliseconds: 200),
      );

      expect(isHealthy, isFalse);
    });

    test('importModelJson validates and activates valid JSON artifact', () async {
      final artifact = {
        'formatVersion': 2,
        'algorithm': 'knn',
        'classLabels': ['Walking', 'Running'],
        'featureLength': 30,
        'sampleCount': 80,
        'classCount': 2,
        'trainedAt': DateTime.now().toIso8601String(),
      };

      final success = await ml.importModelJson(jsonEncode(artifact), combined: false);
      expect(success, isTrue);
      expect(ml.isTrained, isTrue);
      expect(ml.classLabels30, ['Walking', 'Running']);
    });

    test('importModelJson rejects incompatible feature length artifact', () async {
      final artifact = {
        'formatVersion': 2,
        'algorithm': 'knn',
        'classLabels': ['Walking', 'Running'],
        'featureLength': 15, // Invalid feature length
        'sampleCount': 80,
        'classCount': 2,
      };

      final success = await ml.importModelJson(jsonEncode(artifact), combined: false);
      expect(success, isFalse);
    });
  });
}
