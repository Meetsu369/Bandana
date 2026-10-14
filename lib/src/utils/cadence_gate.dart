import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart';

/// Decision reached by [BandCadenceGate] for an incoming sensor sample.
enum CadenceDecision {
  /// Sample is within the acceptable 40 Hz cadence and is accepted.
  accepted,

  /// Sample arrived in a burst with delta < minimum slot threshold (< 12.5 ms)
  /// relative to the last accepted capture timestamp on this band.
  droppedBurst,

  /// Sample has an identical capture timestamp as the last accepted sample.
  droppedDuplicate,

  /// Sample was out of order (capture timestamp earlier than last accepted without reset).
  droppedOutOfOrder,
}

/// Diagnostics snapshot for a single band's cadence gate.
class CadenceDiagnostics {
  final int receivedCount;
  final int acceptedCount;
  final int burstDroppedCount;
  final int duplicateDroppedCount;
  final int outOfOrderCount;
  final int boundaryResetCount;
  final double? avgAcceptedIntervalMs;

  const CadenceDiagnostics({
    required this.receivedCount,
    required this.acceptedCount,
    required this.burstDroppedCount,
    required this.duplicateDroppedCount,
    required this.outOfOrderCount,
    required this.boundaryResetCount,
    this.avgAcceptedIntervalMs,
  });

  /// Computed actual accepted frequency in Hz.
  double? get acceptedHz =>
      (avgAcceptedIntervalMs != null && avgAcceptedIntervalMs! > 0)
          ? 1000.0 / avgAcceptedIntervalMs!
          : null;

  @override
  String toString() =>
      'received=$receivedCount accepted=$acceptedCount (dropped: bursts=$burstDroppedCount dupes=$duplicateDroppedCount outOfOrder=$outOfOrderCount) boundaries=$boundaryResetCount avgInterval=${avgAcceptedIntervalMs?.toStringAsFixed(1)}ms';
}

/// Enforces a deterministic, consistent 40 Hz accepted cadence per band.
///
/// 40 Hz has a nominal interval of 25 ms per sample.
/// This gate ensures that BLE burst delivery (where multiple buffered packets
/// arrive in milliseconds) does not flood the recording pipeline or skew ML feature windows.
///
/// It uses firmware monotonic [captureTimestampMs] as the primary timing reference.
class BandCadenceGate {
  BandCadenceGate({
    this.nominalIntervalMs = 25,
    this.minIntervalThresholdMs = 12, // ~half nominal slot (Nyquist-safe floor)
    this.sessionBoundaryThresholdMs = 100, // Discontinuity gap > 100ms triggers boundary reset
  });

  final int nominalIntervalMs;
  final int minIntervalThresholdMs;
  final int sessionBoundaryThresholdMs;

  int? _lastAcceptedCaptureTsMs;
  int _receivedCount = 0;
  int _acceptedCount = 0;
  int _burstDroppedCount = 0;
  int _duplicateDroppedCount = 0;
  int _outOfOrderCount = 0;
  int _boundaryResetCount = 0;

  // Running interval calculation for accepted samples
  int _intervalSumMs = 0;
  int _intervalCount = 0;

  /// Process an incoming sample and determine if it should be accepted into the recording dataset.
  CadenceDecision processSample(ImuSample sample) {
    _receivedCount++;
    final captureTs = sample.captureTimestampMs;

    // If capture timestamp is missing/negative, accept by default (fallback)
    if (captureTs < 0) {
      _acceptedCount++;
      return CadenceDecision.accepted;
    }

    // First sample in session
    if (_lastAcceptedCaptureTsMs == null) {
      _lastAcceptedCaptureTsMs = captureTs;
      _acceptedCount++;
      return CadenceDecision.accepted;
    }

    final prevTs = _lastAcceptedCaptureTsMs!;

    // Identical timestamp -> duplicate
    if (captureTs == prevTs) {
      _duplicateDroppedCount++;
      return CadenceDecision.droppedDuplicate;
    }

    // Backward step / counter wrap / firmware reset
    if (captureTs < prevTs) {
      // If large backward jump (e.g. ESP32 rebooted), treat as boundary reset
      _boundaryResetCount++;
      _lastAcceptedCaptureTsMs = captureTs;
      _acceptedCount++;
      return CadenceDecision.accepted;
    }

    final delta = captureTs - prevTs;

    // Large gap -> boundary discontinuity, accept fresh
    if (delta > sessionBoundaryThresholdMs) {
      _boundaryResetCount++;
      _lastAcceptedCaptureTsMs = captureTs;
      _acceptedCount++;
      return CadenceDecision.accepted;
    }

    // Sub-slot burst: arrived too close (<12ms) to previous accepted sample
    if (delta < minIntervalThresholdMs) {
      _burstDroppedCount++;
      return CadenceDecision.droppedBurst;
    }

    // Valid 40 Hz slot accepted
    _intervalSumMs += delta;
    _intervalCount++;
    _lastAcceptedCaptureTsMs = captureTs;
    _acceptedCount++;
    return CadenceDecision.accepted;
  }

  /// Reset the gate (e.g., at the start of a new recording session).
  void reset() {
    _lastAcceptedCaptureTsMs = null;
    _receivedCount = 0;
    _acceptedCount = 0;
    _burstDroppedCount = 0;
    _duplicateDroppedCount = 0;
    _outOfOrderCount = 0;
    _boundaryResetCount = 0;
    _intervalSumMs = 0;
    _intervalCount = 0;
  }

  /// Get current diagnostics snapshot.
  CadenceDiagnostics get diagnostics => CadenceDiagnostics(
        receivedCount: _receivedCount,
        acceptedCount: _acceptedCount,
        burstDroppedCount: _burstDroppedCount,
        duplicateDroppedCount: _duplicateDroppedCount,
        outOfOrderCount: _outOfOrderCount,
        boundaryResetCount: _boundaryResetCount,
        avgAcceptedIntervalMs:
            _intervalCount > 0 ? (_intervalSumMs / _intervalCount) : null,
      );
}

/// Dual-band manager pairing wrist and ankle cadence gates.
class DualBandCadenceGate {
  final BandCadenceGate wristGate = BandCadenceGate();
  final BandCadenceGate ankleGate = BandCadenceGate();

  CadenceDecision processSample(ImuSample sample) {
    return switch (sample.bandRole) {
      BandRole.wrist => wristGate.processSample(sample),
      BandRole.ankle => ankleGate.processSample(sample),
    };
  }

  void reset() {
    wristGate.reset();
    ankleGate.reset();
  }
}
