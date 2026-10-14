import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandana/src/utils/filename_utils.dart';

void main() {
  group('FilenameUtils.sanitizeToken', () {
    test('normalizes standard strings', () {
      expect(FilenameUtils.sanitizeToken('Sumeet'), 'sumeet');
      expect(FilenameUtils.sanitizeToken('Walking'), 'walking');
      expect(FilenameUtils.sanitizeToken('Climbing Stairs'), 'climbing_stairs');
      expect(FilenameUtils.sanitizeToken('Running-Fast'), 'running_fast');
    });

    test('handles special characters and whitespace safely', () {
      expect(FilenameUtils.sanitizeToken('  user@123!!  '), 'user123');
      expect(FilenameUtils.sanitizeToken('path/../traversal'), 'pathtraversal');
      expect(FilenameUtils.sanitizeToken('___mixed___'), 'mixed');
    });

    test('falls back when sanitized result is empty', () {
      expect(FilenameUtils.sanitizeToken('', fallback: 'anon'), 'anon');
      expect(FilenameUtils.sanitizeToken('   ', fallback: 'anon'), 'anon');
      expect(FilenameUtils.sanitizeToken('!@#\$%', fallback: 'anon'), 'anon');
    });
  });

  group('FilenameUtils.generateSessionCsvFilename', () {
    test('generates expected format sumeet_walking_20261014_153000.csv', () {
      final dt = DateTime(2026, 10, 14, 15, 30, 0);
      final filename = FilenameUtils.generateSessionCsvFilename(
        participantId: 'Sumeet',
        activityLabel: 'Walking',
        timestamp: dt,
      );
      expect(filename, 'sumeet_walking_20261014_153000.csv');
    });

    test('handles empty inputs with fallbacks', () {
      final dt = DateTime(2026, 1, 5, 9, 5, 2);
      final filename = FilenameUtils.generateSessionCsvFilename(
        participantId: '',
        activityLabel: '',
        timestamp: dt,
      );
      expect(filename, 'participant_activity_20260105_090502.csv');
    });
  });

  group('FilenameUtils.resolveUniqueFile', () {
    test('resolves file with counter when collision occurs', () async {
      final tempDir = await Directory.systemTemp.createTemp('bandana_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // Create base file
      final file1 = await FilenameUtils.resolveUniqueFile(tempDir, 'test.csv');
      await file1.writeAsString('file1');

      // Second file should get _1
      final file2 = await FilenameUtils.resolveUniqueFile(tempDir, 'test.csv');
      expect(file2.path.endsWith('test_1.csv'), isTrue);
      await file2.writeAsString('file2');

      // Third file should get _2
      final file3 = await FilenameUtils.resolveUniqueFile(tempDir, 'test.csv');
      expect(file3.path.endsWith('test_2.csv'), isTrue);
    });
  });
}
