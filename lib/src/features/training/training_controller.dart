import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/activity_session.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../core/constants/ble_constants.dart';

/// Training data source selection.
///
/// Distinguishes between single-band (30 features) and dual-band (60 features) training.
/// - Wrist/Ankle: uses the shared single-band 30-feature classifier slot
/// - Combined: uses the separate 60-feature combined classifier
/// Selecting Wrist vs Ankle for 30-feature training is a DATA SOURCE selection only,
/// not a separate model type - both use the same _classifier30 slot in MlService.
enum TrainingDataSource {
  /// Single-band using Wrist band data (30 features)
  wrist,

  /// Single-band using Ankle band data (30 features) - uses same classifier slot as Wrist
  ankle,

  /// Combined dual-band model (60 features) - Wrist + Ankle
  combined;

  String get displayName => switch (this) {
    TrainingDataSource.wrist => 'Wrist (30 features)',
    TrainingDataSource.ankle => 'Ankle (30 features)',
    TrainingDataSource.combined => 'Dual-band (60 features)',
  };

  String get shortName => switch (this) {
    TrainingDataSource.wrist => 'Wrist',
    TrainingDataSource.ankle => 'Ankle',
    TrainingDataSource.combined => 'Dual-band',
  };

  /// The band role to use when querying database windows for single-band training.
  BandRole get bandRole => switch (this) {
    TrainingDataSource.wrist => BandRole.wrist,
    TrainingDataSource.ankle => BandRole.ankle,
    TrainingDataSource.combined => BandRole.wrist, // not used directly for combined
  };

  /// Whether this source uses single-band (30-feature) training.
  bool get isSingleBand => this != combined;

  /// Whether this source uses dual-band (60-feature) combined training.
  bool get isCombined => this == combined;
}

/// Validation result for training dataset.
class DatasetValidationResult {
  final bool isValid;
  final String message;
  final int windowCount;
  final int labelCount;
  final List<String> availableLabels;
  final Map<String, int> labelDistribution;

  const DatasetValidationResult({
    required this.isValid,
    required this.message,
    required this.windowCount,
    required this.labelCount,
    required this.availableLabels,
    required this.labelDistribution,
  });

  factory DatasetValidationResult.invalid(String message) {
    return DatasetValidationResult(
      isValid: false,
      message: message,
      windowCount: 0,
      labelCount: 0,
      availableLabels: [],
      labelDistribution: {},
    );
  }
}

/// Training progress state.
class TrainingProgress {
  final String status;
  final double? progress; // null = indeterminate
  final int processed;
  final int total;

  const TrainingProgress({
    required this.status,
    this.progress,
    this.processed = 0,
    this.total = 0,
  });

  factory TrainingProgress.preparing() => const TrainingProgress(
        status: 'Preparing training data...',
        progress: null,
      );

  factory TrainingProgress.training() => const TrainingProgress(
        status: 'Training model...',
        progress: null,
      );

  factory TrainingProgress.saving() => const TrainingProgress(
        status: 'Saving model...',
        progress: null,
      );
}

/// Training result with details.
class TrainingResult {
  final bool success;
  final String message;
  final TrainingDataSource mode;
  final int windowCount;
  final int labelCount;
  final int sampleCount;
  final int classCount;

  const TrainingResult({
    required this.success,
    required this.message,
    required this.mode,
    this.windowCount = 0,
    this.labelCount = 0,
    this.sampleCount = 0,
    this.classCount = 0,
  });

  factory TrainingResult.success({
    required TrainingDataSource mode,
    required int windowCount,
    required int labelCount,
    required int sampleCount,
    required int classCount,
  }) {
    return TrainingResult(
      success: true,
      message: 'Model trained successfully',
      mode: mode,
      windowCount: windowCount,
      labelCount: labelCount,
      sampleCount: sampleCount,
      classCount: classCount,
    );
  }

  factory TrainingResult.failure(String message, TrainingDataSource mode) {
    return TrainingResult(
      success: false,
      message: message,
      mode: mode,
    );
  }
}

/// Controller for managing training workflow state.
class TrainingController extends ChangeNotifier {
  final DatabaseService _db;
  final MlService _ml;

  TrainingController({
    required DatabaseService db,
    required MlService ml,
  })  : _db = db,
        _ml = ml;

  // Session selection state
  List<ActivitySession> _availableSessions = [];
  final Set<int> _selectedSessionIds = {};
  List<String> _availableLabels = [];

  // Training configuration
  TrainingDataSource _selectedSource = TrainingDataSource.wrist;

  // Validation state
  DatasetValidationResult? _validationResult;

  // Training state
  bool _isTraining = false;
  TrainingProgress? _currentProgress;
  TrainingResult? _lastResult;
  String? _error;

  // Getters
  List<ActivitySession> get availableSessions => _availableSessions;
  Set<int> get selectedSessionIds => _selectedSessionIds;
  List<String> get availableLabels => _availableLabels;
  TrainingDataSource get selectedSource => _selectedSource;
  DatasetValidationResult? get validationResult => _validationResult;
  bool get isTraining => _isTraining;
  TrainingProgress? get currentProgress => _currentProgress;
  TrainingResult? get lastResult => _lastResult;
  String? get error => _error;

  // Derived state
  bool get hasSelection => _selectedSessionIds.isNotEmpty;
  bool get canTrain => _validationResult?.isValid ?? false;
  bool get isWristSource => _selectedSource == TrainingDataSource.wrist;
  bool get isAnkleSource => _selectedSource == TrainingDataSource.ankle;
  bool get isCombinedSource => _selectedSource == TrainingDataSource.combined;

  /// Load available sessions and labels from database.
  Future<void> loadSessions() async {
    _error = null;
    try {
      final sessions = await _db.getAllSessions();
      // Convert drift Session to ActivitySession
      _availableSessions = sessions.map((s) => ActivitySession(
        id: s.id,
        label: s.label,
        startTime: s.startTime,
        endTime: s.endTime,
        sampleCount: s.sampleCount,
      )).toList();

      // Get distinct labels from training windows
      final windows = await _db.getAllWindowsForTraining();
      _availableLabels = windows.map((w) => w.label).toSet().toList()..sort();

      notifyListeners();
    } catch (e) {
      _error = 'Failed to load sessions: $e';
      notifyListeners();
    }
  }

  /// Toggle session selection.
  void toggleSession(int sessionId) {
    if (_selectedSessionIds.contains(sessionId)) {
      _selectedSessionIds.remove(sessionId);
    } else {
      _selectedSessionIds.add(sessionId);
    }
    _validationResult = null; // Invalidate validation
    notifyListeners();
  }

  /// Select all available sessions.
  void selectAll() {
    _selectedSessionIds.addAll(_availableSessions.map((s) => s.id!));
    _validationResult = null;
    notifyListeners();
  }

  /// Clear all selections.
  void clearSelection() {
    _selectedSessionIds.clear();
    _validationResult = null;
    notifyListeners();
  }

  /// Set training data source (Wrist / Ankle / Dual-band).
  void setSource(TrainingDataSource source) {
    _selectedSource = source;
    _validationResult = null; // Source change invalidates validation
    notifyListeners();
  }

  /// Validate the selected dataset for training.
  Future<void> validateDataset() async {
    if (_selectedSessionIds.isEmpty) {
      _validationResult = DatasetValidationResult.invalid('No sessions selected');
      notifyListeners();
      return;
    }

    try {
      List<({List<double> features, String label})> trainingData;
      int expectedFeatureLength;

      switch (_selectedSource) {
        case TrainingDataSource.wrist:
          trainingData = await _db.getWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
            bandRole: BandRole.wrist,
          );
          expectedFeatureLength = MlService.singleBandFeatureLength;
          break;
        case TrainingDataSource.ankle:
          trainingData = await _db.getWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
            bandRole: BandRole.ankle,
          );
          expectedFeatureLength = MlService.singleBandFeatureLength;
          break;
        case TrainingDataSource.combined:
          final combined = await _db.getCombinedWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
          );
          trainingData = combined.map((d) {
            final combinedFeatures = [...d.wristFeatures, ...d.ankleFeatures];
            return (features: combinedFeatures, label: d.label);
          }).toList();
          expectedFeatureLength = MlService.combinedFeatureLength;
          break;
      }

      // Validate
      if (trainingData.isEmpty) {
        _validationResult = DatasetValidationResult.invalid(
          'No training windows found for selected sessions in ${_selectedSource.shortName} mode. '
          'Ensure sessions have ${_selectedSource == TrainingDataSource.combined ? 'both Wrist and Ankle' : _selectedSource.shortName} data.',
        );
        notifyListeners();
        return;
      }

      // Check feature dimensions
      for (final d in trainingData) {
        if (d.features.length != expectedFeatureLength) {
          _validationResult = DatasetValidationResult.invalid(
            'Feature dimension mismatch: expected $expectedFeatureLength, got ${d.features.length}',
          );
          notifyListeners();
          return;
        }
      }

      // Check labels
      final labels = trainingData.map((d) => d.label).toSet();
      if (labels.length < 2) {
        _validationResult = DatasetValidationResult.invalid(
          'Need at least 2 different activity labels. Found: ${labels.join(", ")}',
        );
        notifyListeners();
        return;
      }

      if (trainingData.length < 2) {
        _validationResult = DatasetValidationResult.invalid(
          'Need at least 2 training windows. Found: ${trainingData.length}',
        );
        notifyListeners();
        return;
      }

      // Check label distribution
      final labelDist = <String, int>{};
      for (final d in trainingData) {
        labelDist[d.label] = (labelDist[d.label] ?? 0) + 1;
      }

      // Check for classes with very few samples
      final minSamplesPerClass = labelDist.values.reduce((a, b) => a < b ? a : b);
      if (minSamplesPerClass < 2) {
        _validationResult = DatasetValidationResult.invalid(
          'Some classes have fewer than 2 samples. Each class needs at least 2 windows.',
        );
        notifyListeners();
        return;
      }

      // All valid
      _validationResult = DatasetValidationResult(
        isValid: true,
        message: 'Ready to train ${_selectedSource.shortName} model',
        windowCount: trainingData.length,
        labelCount: labels.length,
        availableLabels: labels.toList()..sort(),
        labelDistribution: labelDist,
      );
      notifyListeners();
    } catch (e) {
      _validationResult = DatasetValidationResult.invalid('Validation error: $e');
      notifyListeners();
    }
  }

  /// Train the model with current selection.
  Future<void> train() async {
    if (!canTrain) return;

    _isTraining = true;
    _error = null;
    _currentProgress = TrainingProgress.preparing();
    notifyListeners();

    try {
      List<({List<double> features, String label})> trainingData;
      bool success;

      _currentProgress = TrainingProgress.preparing();
      notifyListeners();

      switch (_selectedSource) {
        case TrainingDataSource.wrist:
          trainingData = await _db.getWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
            bandRole: BandRole.wrist,
          );
          _currentProgress = TrainingProgress.training();
          notifyListeners();
          success = await _ml.trainSingleBand(trainingData);
          break;
        case TrainingDataSource.ankle:
          trainingData = await _db.getWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
            bandRole: BandRole.ankle,
          );
          _currentProgress = TrainingProgress.training();
          notifyListeners();
          success = await _ml.trainSingleBand(trainingData);
          break;
        case TrainingDataSource.combined:
          final combined = await _db.getCombinedWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
          );
          trainingData = combined.map((d) {
            final combinedFeatures = [...d.wristFeatures, ...d.ankleFeatures];
            return (features: combinedFeatures, label: d.label);
          }).toList();
          _currentProgress = TrainingProgress.training();
          notifyListeners();
          success = await _ml.trainCombined(trainingData);
          break;
      }

      _currentProgress = TrainingProgress.saving();
      notifyListeners();

      // Model is already persisted by MlService training methods

      if (success) {
        _lastResult = TrainingResult.success(
          mode: _selectedSource,
          windowCount: trainingData.length,
          labelCount: trainingData.map((d) => d.label).toSet().length,
          sampleCount: _selectedSource.isSingleBand
              ? _ml.trainedSampleCount
              : _ml.trainedSampleCountCombined,
          classCount: _selectedSource.isSingleBand
              ? _ml.trainedClassCount
              : _ml.trainedClassCountCombined,
        );
      } else {
        _lastResult = TrainingResult.failure('Training failed - insufficient data', _selectedSource);
      }
    } catch (e) {
      _error = 'Training error: $e';
      _lastResult = TrainingResult.failure('Training error: $e', _selectedSource);
    } finally {
      _isTraining = false;
      _currentProgress = null;
      notifyListeners();
    }
  }

  /// Load model status.
  Future<void> loadModelStatus() async {
    // Models are loaded in MlService.initialize() - just trigger notify
    notifyListeners();
  }

  /// Delete a model.
  Future<void> deleteModel({required bool combined}) async {
    await _ml.deleteModel(combined: combined);
    notifyListeners();
  }

  /// Reset controller state.
  void reset() {
    _selectedSessionIds.clear();
    _selectedSource = TrainingDataSource.wrist;
    _validationResult = null;
    _lastResult = null;
    _error = null;
    notifyListeners();
  }
}

