import 'dart:async';
import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart';

/// Snapshot of real-time fitness metrics.
class FitnessMetrics {
  final int totalSteps;
  final double cadenceSpm;
  final double totalCaloriesKcal;
  final Duration activeDuration;

  const FitnessMetrics({
    required this.totalSteps,
    required this.cadenceSpm,
    required this.totalCaloriesKcal,
    required this.activeDuration,
  });

  @override
  String toString() =>
      'Steps: $totalSteps | Cadence: ${cadenceSpm.toStringAsFixed(1)} SPM | Calories: ${totalCaloriesKcal.toStringAsFixed(1)} kcal | Duration: ${activeDuration.inSeconds}s';
}

/// Computes real-time fitness metrics (step count, cadence, MET calories) from 50 Hz IMU streams.
class FitnessMetricsService {
  FitnessMetricsService({
    this.userWeightKg = 70.0,
  });

  final double userWeightKg;

  int _totalSteps = 0;
  double _cadenceSpm = 0.0;
  double _totalCaloriesKcal = 0.0;
  DateTime? _sessionStartTime;

  // Step detection state (peak detector on ankle_az)
  int? _lastStepTimeMs;
  bool _peakArmed = true;
  static const double _stepPeakThreshold = 12.5; // m/s^2 (~1.27g)
  static const double _stepArmThreshold = 9.8;   // m/s^2 (nominal 1g baseline)
  static const int _minStepIntervalMs = 200;    // 300 SPM upper bound
  static const int maxStepIntervalMs = 1200;   // 50 SPM lower bound

  // Rolling step timestamps for instantaneous cadence calculation (past 5 seconds)
  final List<int> _recentStepTimestampsMs = [];

  // Active activity label for MET accumulation
  String _currentActivity = 'Sitting';

  // 1-second MET accumulation timer
  Timer? _calorieTimer;

  final _metricsController = StreamController<FitnessMetrics>.broadcast();
  Stream<FitnessMetrics> get metricsStream => _metricsController.stream;

  FitnessMetrics get currentMetrics => FitnessMetrics(
        totalSteps: _totalSteps,
        cadenceSpm: _cadenceSpm,
        totalCaloriesKcal: _totalCaloriesKcal,
        activeDuration: _sessionStartTime != null
            ? DateTime.now().difference(_sessionStartTime!)
            : Duration.zero,
      );

  /// Start accumulating session metrics.
  void startSession() {
    reset();
    _sessionStartTime = DateTime.now();
    _startCalorieTimer();
    _emit();
  }

  /// Stop accumulating session metrics.
  void stopSession() {
    _calorieTimer?.cancel();
    _calorieTimer = null;
    _emit();
  }

  /// Update the active activity classification label for MET estimation.
  void updateActivity(String label) {
    _currentActivity = label;
  }

  /// Ingests a sensor sample and updates step detection if from the ankle.
  void addSample(ImuSample sample) {
    if (sample.bandRole != BandRole.ankle) return;

    final nowMs = sample.captureTimestampMs >= 0
        ? sample.captureTimestampMs
        : DateTime.now().millisecondsSinceEpoch;

    final az = sample.az.abs();

    // Re-arm peak detector once acceleration drops back near gravity baseline
    if (!_peakArmed && az < _stepArmThreshold) {
      _peakArmed = true;
    }

    // Detect step peak
    if (_peakArmed && az >= _stepPeakThreshold) {
      if (_lastStepTimeMs == null || (nowMs - _lastStepTimeMs! >= _minStepIntervalMs)) {
        _peakArmed = false;
        _lastStepTimeMs = nowMs;
        _totalSteps++;

        // Add to recent timestamps and purge older than 5 seconds (5000 ms)
        _recentStepTimestampsMs.add(nowMs);
        _recentStepTimestampsMs.removeWhere((ts) => nowMs - ts > 5000);

        // Instantaneous cadence (Steps in past 5s * 12 = SPM)
        if (_recentStepTimestampsMs.length >= 2) {
          _cadenceSpm = _recentStepTimestampsMs.length * 12.0;
        } else {
          // Fallback to elapsed session average
          if (_sessionStartTime != null) {
            final elapsedMins = DateTime.now().difference(_sessionStartTime!).inMilliseconds / 60000.0;
            _cadenceSpm = elapsedMins > 0 ? (_totalSteps / elapsedMins) : 0.0;
          }
        }

        _emit();
      }
    }
  }

  void _startCalorieTimer() {
    _calorieTimer?.cancel();
    _calorieTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _accumulateCalories();
      _emit();
    });
  }

  void _accumulateCalories() {
    // MET values:
    // Sitting: 1.3 MET
    // Standing_HandMove: 1.8 MET
    // Walking: 3.5 MET
    // Jumping_Jacks: 8.0 MET
    double met;
    switch (_currentActivity.toLowerCase()) {
      case 'jumping_jacks':
      case 'jumping jacks':
      case 'jumping':
        met = 8.0;
        break;
      case 'walking':
        met = 3.5;
        break;
      case 'standing_handmove':
      case 'standing':
        met = 1.8;
        break;
      case 'sitting':
      default:
        met = 1.3;
        break;
    }

    // Formula: kcal_per_sec = ((MET * 3.5 * weightKg) / 200) / 60
    final kcalPerSec = ((met * 3.5 * userWeightKg) / 200.0) / 60.0;
    _totalCaloriesKcal += kcalPerSec;

    // Fade instantaneous cadence if no steps detected in the last 3 seconds
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _recentStepTimestampsMs.removeWhere((ts) => nowMs - ts > 5000);
    if (_recentStepTimestampsMs.isEmpty) {
      _cadenceSpm = 0.0;
    }
  }

  void _emit() {
    if (!_metricsController.isClosed) {
      _metricsController.add(currentMetrics);
    }
  }

  /// Reset all metrics counters for a fresh session.
  void reset() {
    _totalSteps = 0;
    _cadenceSpm = 0.0;
    _totalCaloriesKcal = 0.0;
    _lastStepTimeMs = null;
    _peakArmed = true;
    _recentStepTimestampsMs.clear();
    _currentActivity = 'Sitting';
    _sessionStartTime = null;
    _calorieTimer?.cancel();
    _calorieTimer = null;
  }

  void dispose() {
    _calorieTimer?.cancel();
    _metricsController.close();
  }
}
