import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/services/activity_label_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActivityLabelManager', () {
    late ActivityLabelManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      manager = ActivityLabelManager(prefs: prefs);
    });

    test('initializes with default labels', () {
      expect(manager.allLabels, BleConstants.defaultLabels);
      expect(manager.customLabels, isEmpty);
    });

    test('validates and adds custom activity label', () async {
      expect(manager.validateLabel('Cycling'), isNull);
      final added = await manager.addCustomLabel('Cycling');
      expect(added, isTrue);
      expect(manager.allLabels.contains('Cycling'), isTrue);
      expect(manager.customLabels, ['Cycling']);
    });

    test('rejects empty or whitespace-only labels', () async {
      expect(manager.validateLabel(''), isNotNull);
      expect(manager.validateLabel('   '), isNotNull);
      final added = await manager.addCustomLabel('   ');
      expect(added, isFalse);
    });

    test('rejects case-insensitive duplicates of default labels', () async {
      expect(manager.validateLabel('walking'), isNotNull);
      expect(manager.validateLabel('WALKING'), isNotNull);
      final added = await manager.addCustomLabel('walking');
      expect(added, isFalse);
    });

    test('rejects case-insensitive duplicates of custom labels', () async {
      await manager.addCustomLabel('Yoga');
      expect(manager.validateLabel('yoga'), isNotNull);
      expect(manager.validateLabel('YOGA'), isNotNull);
    });

    test('rejects labels with filesystem-unsafe characters', () async {
      expect(manager.validateLabel('Cycling/Rowing'), isNotNull);
      expect(manager.validateLabel('Jump:High'), isNotNull);
      expect(manager.validateLabel('Walk?Run'), isNotNull);
    });

    test('removes custom label', () async {
      await manager.addCustomLabel('Pilates');
      expect(manager.customLabels, ['Pilates']);

      final removed = await manager.removeCustomLabel('pilates');
      expect(removed, isTrue);
      expect(manager.customLabels, isEmpty);
      expect(manager.allLabels.contains('Pilates'), isFalse);
    });
  });
}
