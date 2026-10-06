import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/services/band_assignment_manager.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BandAssignmentManager', () {
    late SharedPreferences prefs;
    late BandAssignmentManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      manager = await BandAssignmentManager.create(prefs);
    });

    tearDown(() async {
      await prefs.clear();
    });

    test('initially has no assignments', () {
      expect(manager.hasWristAssignment, isFalse);
      expect(manager.hasAnkleAssignment, isFalse);
      expect(manager.wristDeviceId, isNull);
      expect(manager.ankleDeviceId, isNull);
      expect(manager.wristDeviceName, isNull);
      expect(manager.ankleDeviceName, isNull);
    });

    test('assigns wrist successfully', () async {
      final success = await manager.assignWrist('device-1', 'BANDANA-WRIST');
      expect(success, isTrue);
      expect(manager.hasWristAssignment, isTrue);
      expect(manager.wristDeviceId, 'device-1');
      expect(manager.wristDeviceName, 'BANDANA-WRIST');
    });

    test('assigns ankle successfully', () async {
      final success = await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      expect(success, isTrue);
      expect(manager.hasAnkleAssignment, isTrue);
      expect(manager.ankleDeviceId, 'device-2');
      expect(manager.ankleDeviceName, 'BANDANA-ANKLE');
    });

    test('prevents same device assigned to both wrist and ankle', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      final success = await manager.assignAnkle('device-1', 'BANDANA-WRIST');
      expect(success, isFalse);
      expect(manager.hasAnkleAssignment, isFalse);
    });

    test('prevents same device assigned to both ankle and wrist', () async {
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      final success = await manager.assignWrist('device-2', 'BANDANA-ANKLE');
      expect(success, isFalse);
      expect(manager.hasWristAssignment, isFalse);
    });

    test('clears wrist assignment', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      await manager.clearWrist();
      expect(manager.hasWristAssignment, isFalse);
      expect(manager.wristDeviceId, isNull);
      expect(manager.wristDeviceName, isNull);
    });

    test('clears ankle assignment', () async {
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      await manager.clearAnkle();
      expect(manager.hasAnkleAssignment, isFalse);
      expect(manager.ankleDeviceId, isNull);
      expect(manager.ankleDeviceName, isNull);
    });

    test('clears all assignments', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      await manager.clearAll();
      expect(manager.hasWristAssignment, isFalse);
      expect(manager.hasAnkleAssignment, isFalse);
    });

    test('getRoleForDevice returns correct role', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      expect(manager.getRoleForDevice('device-1'), BandRole.wrist);
      expect(manager.getRoleForDevice('device-2'), BandRole.ankle);
      expect(manager.getRoleForDevice('device-3'), isNull);
    });

    test('getAllAssignments returns all assigned devices', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      final assignments = manager.getAllAssignments();
      expect(assignments.length, 2);
      expect(assignments[BandRole.wrist]?.deviceId, 'device-1');
      expect(assignments[BandRole.wrist]?.deviceName, 'BANDANA-WRIST');
      expect(assignments[BandRole.ankle]?.deviceId, 'device-2');
      expect(assignments[BandRole.ankle]?.deviceName, 'BANDANA-ANKLE');
    });

    test('isAssigned returns true for assigned devices', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      expect(manager.isAssigned('device-1'), isTrue);
      expect(manager.isAssigned('device-2'), isTrue);
      expect(manager.isAssigned('device-3'), isFalse);
    });

    test('persists assignments across manager instances', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST');
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE');
      
      // Create new manager instance with same prefs
      final manager2 = await BandAssignmentManager.create(prefs);
      expect(manager2.hasWristAssignment, isTrue);
      expect(manager2.hasAnkleAssignment, isTrue);
      expect(manager2.wristDeviceId, 'device-1');
      expect(manager2.ankleDeviceId, 'device-2');
      expect(manager2.wristDeviceName, 'BANDANA-WRIST');
      expect(manager2.ankleDeviceName, 'BANDANA-ANKLE');
    });

    test('changing wrist assignment replaces previous', () async {
      await manager.assignWrist('device-1', 'BANDANA-WRIST-1');
      await manager.assignWrist('device-2', 'BANDANA-WRIST-2');
      expect(manager.wristDeviceId, 'device-2');
      expect(manager.wristDeviceName, 'BANDANA-WRIST-2');
    });

    test('changing ankle assignment replaces previous', () async {
      await manager.assignAnkle('device-1', 'BANDANA-ANKLE-1');
      await manager.assignAnkle('device-2', 'BANDANA-ANKLE-2');
      expect(manager.ankleDeviceId, 'device-2');
      expect(manager.ankleDeviceName, 'BANDANA-ANKLE-2');
    });
  });
}