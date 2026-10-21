import 'package:flutter_test/flutter_test.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/utils/cadence_gate.dart';

void main() {
  ImuSample createSample({
    required int captureTs,
    BandRole role = BandRole.wrist,
  }) {
    return ImuSample(
      ax: 0,
      ay: 0,
      az: 9.8,
      gx: 0,
      gy: 0,
      gz: 0,
      captureTimestampMs: captureTs,
      timestamp: DateTime.now(),
      bandRole: role,
      deviceId: 'AA:BB:CC:DD',
      deviceName: 'BANDANA_TEST',
    );
  }

  group('BandCadenceGate', () {
    late BandCadenceGate gate;

    setUp(() {
      gate = BandCadenceGate();
    });

    test('accepts nominal 20ms intervals (50 Hz)', () {
      expect(gate.processSample(createSample(captureTs: 1000)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1020)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1040)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1060)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1080)), CadenceDecision.accepted);

      final diag = gate.diagnostics;
      expect(diag.receivedCount, 5);
      expect(diag.acceptedCount, 5);
      expect(diag.burstDroppedCount, 0);
      expect(diag.duplicateDroppedCount, 0);
      expect(diag.avgAcceptedIntervalMs, 20.0);
      expect(diag.acceptedHz, 50.0);
    });

    test('accepts nominal 25ms intervals (40 Hz)', () {
      expect(gate.processSample(createSample(captureTs: 1000)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1025)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1050)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 1075)), CadenceDecision.accepted);

      final diag = gate.diagnostics;
      expect(diag.receivedCount, 4);
      expect(diag.acceptedCount, 4);
      expect(diag.burstDroppedCount, 0);
      expect(diag.duplicateDroppedCount, 0);
      expect(diag.avgAcceptedIntervalMs, 25.0);
      expect(diag.acceptedHz, 40.0);
    });

    test('drops rapid burst packets (< 12 ms delta)', () {
      expect(gate.processSample(createSample(captureTs: 1000)), CadenceDecision.accepted);
      // Arrives 2ms later (burst packet) -> droppedBurst
      expect(gate.processSample(createSample(captureTs: 1002)), CadenceDecision.droppedBurst);
      // Arrives 5ms later -> droppedBurst
      expect(gate.processSample(createSample(captureTs: 1005)), CadenceDecision.droppedBurst);
      // Arrives 25ms after last accepted (1000) -> accepted
      expect(gate.processSample(createSample(captureTs: 1026)), CadenceDecision.accepted);

      final diag = gate.diagnostics;
      expect(diag.receivedCount, 4);
      expect(diag.acceptedCount, 2);
      expect(diag.burstDroppedCount, 2);
    });

    test('drops exact duplicate timestamps', () {
      expect(gate.processSample(createSample(captureTs: 2000)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: 2000)), CadenceDecision.droppedDuplicate);
      expect(gate.processSample(createSample(captureTs: 2025)), CadenceDecision.accepted);

      final diag = gate.diagnostics;
      expect(diag.receivedCount, 3);
      expect(diag.acceptedCount, 2);
      expect(diag.duplicateDroppedCount, 1);
    });

    test('resets on session boundary (> 100ms gap or reboot)', () {
      expect(gate.processSample(createSample(captureTs: 5000)), CadenceDecision.accepted);
      // 500ms gap (session boundary) -> accepted & counted as boundary
      expect(gate.processSample(createSample(captureTs: 5500)), CadenceDecision.accepted);
      // Firmware reboot to 10ms -> accepted & counted as boundary
      expect(gate.processSample(createSample(captureTs: 10)), CadenceDecision.accepted);

      final diag = gate.diagnostics;
      expect(diag.boundaryResetCount, 2);
      expect(diag.acceptedCount, 3);
    });

    test('handles fallback when captureTimestampMs is negative', () {
      expect(gate.processSample(createSample(captureTs: -1)), CadenceDecision.accepted);
      expect(gate.processSample(createSample(captureTs: -1)), CadenceDecision.accepted);
      expect(gate.diagnostics.acceptedCount, 2);
    });
  });
}
