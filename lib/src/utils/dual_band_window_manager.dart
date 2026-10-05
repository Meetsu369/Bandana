import 'package:bandana/src/models/imu_sample.dart';
import 'package:bandana/src/utils/session_boundary.dart';
import 'package:bandana/src/core/constants/ble_constants.dart';

/// Result of attempting to consume a window from the buffer.
enum WindowConsumeResult {
  /// Window was successfully consumed and is valid.
  consumedValid,
  /// Window was consumed but failed validation (discarded).
  consumedInvalid,
  /// Not enough samples yet.
  notReady,
}

/// Manages dual-band window buffering, session-boundary handling,
/// and atomic window consumption for both Live and Record pipelines.
class DualBandWindowManager {
  DualBandWindowManager({
    required this.sessionDetector,
    int windowSize = BleConstants.windowSize,
  }) : _windowSize = windowSize;

  final DualBandSessionDetector sessionDetector;
  final int _windowSize;

  // Per-band state
  final List<ImuSample> _wristBuffer = [];
  final List<ImuSample> _ankleBuffer = [];

  // Window generation counters - incremented each time a valid window is consumed.
  // Used to detect stale cross-session pairing.
  int _wristGeneration = 0;
  int _ankleGeneration = 0;

  // Accessors
  List<ImuSample> get wristBuffer => List.unmodifiable(_wristBuffer);
  List<ImuSample> get ankleBuffer => List.unmodifiable(_ankleBuffer);
  int get wristGeneration => _wristGeneration;
  int get ankleGeneration => _ankleGeneration;
  int get windowSize => _windowSize;

  /// Adds a sample to the appropriate band's buffer.
  /// Handles session boundary detection and buffer clearing.
  ///
  /// Returns true if a boundary was detected (and buffer was cleared).
  bool addSample(ImuSample sample) {
    final role = sample.bandRole;
    final isBoundary = sessionDetector.checkBoundary(role, sample.captureTimestampMs);

    if (isBoundary) {
      sessionDetector.handleBoundary(role);
      _clearBuffer(role);
      // Invalidate the generation for this band - any pending window is now stale
      _invalidateGeneration(role);
    }

    _addToBuffer(role, sample);
    return isBoundary;
  }

  void _addToBuffer(BandRole role, ImuSample sample) {
    switch (role) {
      case BandRole.wrist:
        _wristBuffer.add(sample);
      case BandRole.ankle:
        _ankleBuffer.add(sample);
    }
  }

  void _clearBuffer(BandRole role) {
    switch (role) {
      case BandRole.wrist:
        _wristBuffer.clear();
      case BandRole.ankle:
        _ankleBuffer.clear();
    }
  }

  void _invalidateGeneration(BandRole role) {
    switch (role) {
      case BandRole.wrist:
        _wristGeneration++;
      case BandRole.ankle:
        _ankleGeneration++;
    }
  }

  /// Attempts to consume an 80-sample window from the specified band.
  ///
  /// Returns the consumed window if ready and valid, null if not ready,
  /// or throws if consumed but invalid (caller should handle via result enum).
  WindowConsumeResult tryConsumeWindow(BandRole role, {required bool validateDuration, List<ImuSample>? outWindow}) {
    final buffer = role == BandRole.wrist ? _wristBuffer : _ankleBuffer;

    if (buffer.length < _windowSize) {
      return WindowConsumeResult.notReady;
    }

    // Snapshot and consume atomically
    final window = buffer.take(_windowSize).toList();
    buffer.removeRange(0, _windowSize);

    // Validate duration if requested
    if (validateDuration) {
      final detector = role == BandRole.wrist ? sessionDetector.wrist : sessionDetector.ankle;
      if (!detector.isValidWindowDuration(window)) {
        _invalidateGeneration(role); // Mark this generation as invalid
        return WindowConsumeResult.consumedInvalid;
      }
    }

    // Mark generation as valid and increment
    switch (role) {
      case BandRole.wrist:
        _wristGeneration++;
      case BandRole.ankle:
        _ankleGeneration++;
    }

    // Return window via out parameter if provided
    if (outWindow != null) {
      outWindow.clear();
      outWindow.addAll(window);
    }

    return WindowConsumeResult.consumedValid;
  }

  /// Attempts to atomically consume a dual-band window pair.
  ///
  /// Both bands must have >= windowSize samples.
  /// Both windows are validated before either is consumed.
  ///
  /// Returns:
  /// - (wristWindow, ankleWindow) if both valid and consumed
  /// - null if either band not ready
  /// - throws/returns invalid if validation fails (both buffers already consumed)
  ({List<ImuSample> wristWindow, List<ImuSample> ankleWindow})? tryConsumeDualBandWindow({
    required bool hasWrist,
    required bool hasAnkle,
    required bool validateDuration,
  }) {
    // Check readiness
    if (hasWrist && _wristBuffer.length < _windowSize) return null;
    if (hasAnkle && _ankleBuffer.length < _windowSize) return null;

    // Snapshot both windows
    final wristSnapshot = hasWrist ? _wristBuffer.take(_windowSize).toList() : <ImuSample>[];
    final ankleSnapshot = hasAnkle ? _ankleBuffer.take(_windowSize).toList() : <ImuSample>[];

    // Validate both before consuming either
    if (validateDuration) {
      if (hasWrist && !sessionDetector.wrist.isValidWindowDuration(wristSnapshot)) {
        return null; // Don't consume - let caller handle
      }
      if (hasAnkle && !sessionDetector.ankle.isValidWindowDuration(ankleSnapshot)) {
        return null;
      }
    }

    // Both valid - consume atomically
    if (hasWrist) _wristBuffer.removeRange(0, _windowSize);
    if (hasAnkle) _ankleBuffer.removeRange(0, _windowSize);

    if (hasWrist) {
      _wristGeneration++;
    }
    if (hasAnkle) {
      _ankleGeneration++;
    }

    return (wristWindow: wristSnapshot, ankleWindow: ankleSnapshot);
  }

  /// Checks if a dual-band window can be consumed without consuming.
  bool canConsumeDualBandWindow({required bool hasWrist, required bool hasAnkle}) {
    if (hasWrist && _wristBuffer.length < _windowSize) return false;
    if (hasAnkle && _ankleBuffer.length < _windowSize) return false;
    return true;
  }

  /// Gets the current "generation pair" for dual-band synchronization.
  /// Returns (wristGen, ankleGen) representing the next window generation for each band.
  ({int wristGen, int ankleGen}) get nextGenerationPair => (
    wristGen: _wristGeneration,
    ankleGen: _ankleGeneration,
  );

  /// Checks if the current dual-band generation pair matches a previously recorded pair.
  /// Used to detect stale cross-session pairing after reconnect.
  bool isGenerationPairFresh({required int expectedWristGen, required int expectedAnkleGen}) {
    return _wristGeneration == expectedWristGen && _ankleGeneration == expectedAnkleGen;
  }

  /// Resets all state (new session start).
  void reset() {
    _wristBuffer.clear();
    _ankleBuffer.clear();
    _wristGeneration = 0;
    _ankleGeneration = 0;
    sessionDetector.reset();
  }

  /// Clears only the specified band's buffer and increments its generation.
  void clearBand(BandRole role) {
    _clearBuffer(role);
    _invalidateGeneration(role);
  }

  /// Returns true if the specified band has a partial window that spans a session boundary.
  /// This can be used for diagnostics.
  bool hasPartialWindow(BandRole role) {
    final buffer = role == BandRole.wrist ? _wristBuffer : _ankleBuffer;
    return buffer.isNotEmpty && buffer.length < _windowSize;
  }
}