import 'package:bandana/src/core/constants/ble_constants.dart';
import 'package:bandana/src/models/imu_sample.dart';

/// Detects firmware session boundaries and validates window durations
/// using the firmware-provided captureTimestampMs.
class SessionBoundaryDetector {
  SessionBoundaryDetector({
    this.sessionBoundaryThresholdMs = _defaultSessionBoundaryThresholdMs,
    this.minWindowDurationMs = _defaultMinWindowDurationMs,
    this.maxWindowDurationMs = _defaultMaxWindowDurationMs,
  });

  // 50 Hz = 20 ms per sample (79 * 20 = 1580 ms for 80 samples).
  // 40 Hz = 25 ms per sample (79 * 25 = 1975 ms for 80 samples).
  // Min 1400ms / Max 2200ms accommodates both rates with jitter tolerance.
  static const int _defaultSessionBoundaryThresholdMs = 100;
  static const int _defaultMinWindowDurationMs = 1400;
  static const int _defaultMaxWindowDurationMs = 2200;

  final int sessionBoundaryThresholdMs;
  final int minWindowDurationMs;
  final int maxWindowDurationMs;

  int? _lastCaptureTimestampMs;

  /// Returns true if the current sample indicates a firmware session boundary
  /// (reset/regression) relative to the previous sample.
  ///
  /// A boundary is detected when:
  /// - Current timestamp is less than previous (regression/reset to zero)
  /// - Gap between timestamps exceeds [sessionBoundaryThresholdMs] (discontinuity)
  ///
  /// Negative timestamps are treated as invalid and do not trigger boundaries.
  bool isSessionBoundary(int currentCaptureTimestampMs) {
    final prev = _lastCaptureTimestampMs;
    _lastCaptureTimestampMs = currentCaptureTimestampMs;

    if (prev == null) return false;
    if (currentCaptureTimestampMs < 0 || prev < 0) return false;
    if (currentCaptureTimestampMs < prev) return true;

    final gap = currentCaptureTimestampMs - prev;
    return gap > sessionBoundaryThresholdMs;
  }

  /// Resets the internal timestamp tracker.
  /// Call when starting a new recording or live session, or after a detected boundary.
  void reset() {
    _lastCaptureTimestampMs = null;
  }

  /// Gets the last seen capture timestamp (for debugging/inspection).
  int? get lastCaptureTimestampMs => _lastCaptureTimestampMs;

  /// Validates that a window of samples has an acceptable duration.
  ///
  /// For 80 samples at 40 Hz (25 ms spacing), the expected first-to-last
  /// timestamp span is 79 * 25 = 1975 ms. We accept a tolerance around this.
  ///
  /// Returns false if:
  /// - Window has fewer than 2 samples
  /// - Duration is outside [minWindowDurationMs, maxWindowDurationMs]
  /// - Either first or last timestamp is negative (unknown duration → accept)
  bool isValidWindowDuration(List<ImuSample> window) {
    if (window.length < 2) return false;

    final firstTs = window.first.captureTimestampMs;
    final lastTs = window.last.captureTimestampMs;

    // Unknown timestamps (negative) → cannot validate duration → accept
    if (firstTs < 0 || lastTs < 0) return true;

    final duration = lastTs - firstTs;
    return duration >= minWindowDurationMs && duration <= maxWindowDurationMs;
  }

  /// Validates that a window has exactly [expectedSize] samples AND valid duration.
  bool isValidWindow(List<ImuSample> window, {int expectedSize = 80}) {
    if (window.length != expectedSize) return false;
    return isValidWindowDuration(window);
  }
}

/// Pair of detectors for dual-band (wrist + ankle) session management.
class DualBandSessionDetector {
  DualBandSessionDetector({
    int sessionBoundaryThresholdMs = SessionBoundaryDetector._defaultSessionBoundaryThresholdMs,
    int minWindowDurationMs = SessionBoundaryDetector._defaultMinWindowDurationMs,
    int maxWindowDurationMs = SessionBoundaryDetector._defaultMaxWindowDurationMs,
  }) : _wrist = SessionBoundaryDetector(
           sessionBoundaryThresholdMs: sessionBoundaryThresholdMs,
           minWindowDurationMs: minWindowDurationMs,
           maxWindowDurationMs: maxWindowDurationMs,
         ),
         _ankle = SessionBoundaryDetector(
           sessionBoundaryThresholdMs: sessionBoundaryThresholdMs,
           minWindowDurationMs: minWindowDurationMs,
           maxWindowDurationMs: maxWindowDurationMs,
         );

  final SessionBoundaryDetector _wrist;
  final SessionBoundaryDetector _ankle;

  SessionBoundaryDetector get wrist => _wrist;
  SessionBoundaryDetector get ankle => _ankle;

  /// Checks for session boundary on the given band.
  /// Returns true if a boundary was detected (and buffer should be cleared).
  bool checkBoundary(BandRole role, int captureTimestampMs) {
    return switch (role) {
      BandRole.wrist => _wrist.isSessionBoundary(captureTimestampMs),
      BandRole.ankle => _ankle.isSessionBoundary(captureTimestampMs),
    };
  }

  /// Handles a detected session boundary by clearing the band's timestamp tracker.
  void handleBoundary(BandRole role) {
    switch (role) {
      case BandRole.wrist:
        _wrist.reset();
      case BandRole.ankle:
        _ankle.reset();
    }
  }

  /// Resets both detectors (e.g., when starting a new session).
  void reset() {
    _wrist.reset();
    _ankle.reset();
  }

  /// Validates a dual-band window pair.
  /// Returns true only if BOTH wrist and ankle windows are valid (or absent).
  bool validateDualBandWindows({
    required List<ImuSample> wristWindow,
    required List<ImuSample> ankleWindow,
    bool hasWrist = true,
    bool hasAnkle = true,
  }) {
    if (hasWrist && !_wrist.isValidWindowDuration(wristWindow)) return false;
    if (hasAnkle && !_ankle.isValidWindowDuration(ankleWindow)) return false;
    return true;
  }
}