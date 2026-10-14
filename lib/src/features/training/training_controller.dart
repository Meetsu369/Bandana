import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/ble_constants.dart';
import '../../models/activity_session.dart';
import '../../models/evaluation_metrics.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';

/// Training data source selection.
enum TrainingDataSource {
  wrist,
  ankle,
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

  BandRole get bandRole => switch (this) {
    TrainingDataSource.wrist => BandRole.wrist,
    TrainingDataSource.ankle => BandRole.ankle,
    TrainingDataSource.combined => BandRole.wrist,
  };

  bool get isSingleBand => this != combined;
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
  final int sessionCount;

  const DatasetValidationResult({
    required this.isValid,
    required this.message,
    required this.windowCount,
    required this.labelCount,
    required this.availableLabels,
    required this.labelDistribution,
    this.sessionCount = 0,
  });

  factory DatasetValidationResult.invalid(String message) {
    return DatasetValidationResult(
      isValid: false,
      message: message,
      windowCount: 0,
      labelCount: 0,
      availableLabels: [],
      labelDistribution: {},
      sessionCount: 0,
    );
  }
}

/// Training progress state.
class TrainingProgress {
  final String status;
  final double? progress;
  final int processed;
  final int total;

  const TrainingProgress({
    required this.status,
    this.progress,
    this.processed = 0,
    this.total = 0,
  });

  factory TrainingProgress.preparing() => const TrainingProgress(
        status: 'Preparing training data and validation split…',
        progress: null,
      );

  factory TrainingProgress.training() => const TrainingProgress(
        status: 'Fitting classifier model…',
        progress: null,
      );

  factory TrainingProgress.evaluating() => const TrainingProgress(
        status: 'Evaluating against held-out validation sessions…',
        progress: null,
      );

  factory TrainingProgress.saving() => const TrainingProgress(
        status: 'Persisting versioned model artifact…',
        progress: null,
      );
}

/// Detailed training result.
class TrainingResult {
  final bool success;
  final String message;
  final TrainingDataSource mode;
  final MlAlgorithm algorithm;
  final int windowCount;
  final int labelCount;
  final int sampleCount;
  final int classCount;
  final ModelEvaluationReport? evaluationReport;

  const TrainingResult({
    required this.success,
    required this.message,
    required this.mode,
    required this.algorithm,
    this.windowCount = 0,
    this.labelCount = 0,
    this.sampleCount = 0,
    this.classCount = 0,
    this.evaluationReport,
  });

  factory TrainingResult.success({
    required TrainingDataSource mode,
    required MlAlgorithm algorithm,
    required int windowCount,
    required int labelCount,
    required int sampleCount,
    required int classCount,
    ModelEvaluationReport? evaluationReport,
  }) {
    return TrainingResult(
      success: true,
      message: 'Model trained and evaluated successfully',
      mode: mode,
      algorithm: algorithm,
      windowCount: windowCount,
      labelCount: labelCount,
      sampleCount: sampleCount,
      classCount: classCount,
      evaluationReport: evaluationReport,
    );
  }

  factory TrainingResult.failure(String message, TrainingDataSource mode, MlAlgorithm algorithm) {
    return TrainingResult(
      success: false,
      message: message,
      mode: mode,
      algorithm: algorithm,
    );
  }
}

/// Controller managing training workflow, session-level validation splits,
/// algorithm selection, and model comparison.
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

  // Configuration
  TrainingDataSource _selectedSource = TrainingDataSource.wrist;
  MlAlgorithm _selectedAlgorithm = MlAlgorithm.knn;

  // Feedback integration
  bool _includeReviewedFeedback = false;
  int _pendingFeedbackCount = 0;

  // State
  DatasetValidationResult? _validationResult;
  bool _isTraining = false;
  TrainingProgress? _currentProgress;
  TrainingResult? _lastResult;
  String? _error;

  // Getters
  List<ActivitySession> get availableSessions => _availableSessions;
  Set<int> get selectedSessionIds => _selectedSessionIds;
  List<String> get availableLabels => _availableLabels;
  TrainingDataSource get selectedSource => _selectedSource;
  MlAlgorithm get selectedAlgorithm => _selectedAlgorithm;
  bool get includeReviewedFeedback => _includeReviewedFeedback;
  int get pendingFeedbackCount => _pendingFeedbackCount;
  DatasetValidationResult? get validationResult => _validationResult;
  bool get isTraining => _isTraining;
  TrainingProgress? get currentProgress => _currentProgress;
  TrainingResult? get lastResult => _lastResult;
  String? get error => _error;

  bool get hasSelection => _selectedSessionIds.isNotEmpty;
  bool get canTrain => _validationResult?.isValid ?? false;
  bool get isWristSource => _selectedSource == TrainingDataSource.wrist;
  bool get isAnkleSource => _selectedSource == TrainingDataSource.ankle;
  bool get isCombinedSource => _selectedSource == TrainingDataSource.combined;

  /// Load available sessions, labels, and feedback count from DB.
  Future<void> loadSessions() async {
    _error = null;
    try {
      final sessions = await _db.getAllSessions();
      _availableSessions = sessions
          .map((s) => ActivitySession(
                id: s.id,
                label: s.label,
                startTime: s.startTime,
                endTime: s.endTime,
                sampleCount: s.sampleCount,
              ))
          .toList();

      final windows = await _db.getAllWindowsForTraining();
      _availableLabels = windows.map((w) => w.label).toSet().toList()..sort();

      final feedbacks = await _db.getUnreviewedFeedbacks();
      _pendingFeedbackCount = feedbacks.length;

      notifyListeners();
    } catch (e) {
      _error = 'Failed to load sessions: $e';
      notifyListeners();
    }
  }

  void toggleSession(int sessionId) {
    if (_selectedSessionIds.contains(sessionId)) {
      _selectedSessionIds.remove(sessionId);
    } else {
      _selectedSessionIds.add(sessionId);
    }
    _validationResult = null;
    notifyListeners();
  }

  void selectAll() {
    _selectedSessionIds.addAll(_availableSessions.map((s) => s.id!));
    _validationResult = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedSessionIds.clear();
    _validationResult = null;
    notifyListeners();
  }

  void setSource(TrainingDataSource source) {
    _selectedSource = source;
    _validationResult = null;
    notifyListeners();
  }

  void setAlgorithm(MlAlgorithm algorithm) {
    _selectedAlgorithm = algorithm;
    notifyListeners();
  }

  void toggleIncludeReviewedFeedback(bool value) {
    _includeReviewedFeedback = value;
    notifyListeners();
  }

  /// Validate selected dataset before training.
  Future<void> validateDataset() async {
    if (_selectedSessionIds.isEmpty) {
      _validationResult = DatasetValidationResult.invalid('No sessions selected');
      notifyListeners();
      return;
    }

    try {
      List<({List<double> features, String label})> data;
      int expectedLength;

      switch (_selectedSource) {
        case TrainingDataSource.wrist:
          data = await _db.getWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
            bandRole: BandRole.wrist,
          );
          expectedLength = MlService.singleBandFeatureLength;
          break;
        case TrainingDataSource.ankle:
          data = await _db.getWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
            bandRole: BandRole.ankle,
          );
          expectedLength = MlService.singleBandFeatureLength;
          break;
        case TrainingDataSource.combined:
          final combined = await _db.getCombinedWindowsForTrainingBySessions(
            sessionIds: _selectedSessionIds.toList(),
          );
          data = combined.map((d) {
            return (features: [...d.wristFeatures, ...d.ankleFeatures], label: d.label);
          }).toList();
          expectedLength = MlService.combinedFeatureLength;
          break;
      }

      if (data.isEmpty) {
        _validationResult = DatasetValidationResult.invalid(
          'No training windows found for selected sessions in ${_selectedSource.shortName} mode.',
        );
        notifyListeners();
        return;
      }

      for (final d in data) {
        if (d.features.length != expectedLength) {
          _validationResult = DatasetValidationResult.invalid(
            'Feature dimension mismatch: expected $expectedLength, got ${d.features.length}',
          );
          notifyListeners();
          return;
        }
      }

      final labels = data.map((d) => d.label).toSet();
      if (labels.length < 2) {
        _validationResult = DatasetValidationResult.invalid(
          'Need at least 2 different activity labels. Found: ${labels.join(", ")}',
        );
        notifyListeners();
        return;
      }

      if (data.length < 2) {
        _validationResult = DatasetValidationResult.invalid(
          'Need at least 2 training windows. Found: ${data.length}',
        );
        notifyListeners();
        return;
      }

      final labelDist = <String, int>{};
      for (final d in data) {
        labelDist[d.label] = (labelDist[d.label] ?? 0) + 1;
      }

      final minSamples = labelDist.values.reduce((a, b) => a < b ? a : b);
      if (minSamples < 2) {
        _validationResult = DatasetValidationResult.invalid(
          'Some classes have fewer than 2 samples. Each class needs at least 2 windows.',
        );
        notifyListeners();
        return;
      }

      _validationResult = DatasetValidationResult(
        isValid: true,
        message: 'Ready to train ${_selectedAlgorithm.shortName} (${_selectedSource.shortName})',
        windowCount: data.length,
        labelCount: labels.length,
        availableLabels: labels.toList()..sort(),
        labelDistribution: labelDist,
        sessionCount: _selectedSessionIds.length,
      );
      notifyListeners();
    } catch (e) {
      _validationResult = DatasetValidationResult.invalid('Validation error: $e');
      notifyListeners();
    }
  }

  /// Train model with session-level validation split to prevent leakage.
  Future<void> train() async {
    if (!canTrain) return;

    _isTraining = true;
    _error = null;
    _currentProgress = TrainingProgress.preparing();
    notifyListeners();

    try {
      final selectedList = _selectedSessionIds.toList()..sort();

      // Session-level split:
      // If we have >= 3 sessions, hold out sessions for validation without window leakage.
      List<int> trainSessionIds;
      List<int> valSessionIds;

      if (selectedList.length >= 3) {
        // Reserve 1 session for validation
        final valCount = (selectedList.length * 0.25).ceil().clamp(1, selectedList.length - 1);
        valSessionIds = selectedList.sublist(selectedList.length - valCount);
        trainSessionIds = selectedList.sublist(0, selectedList.length - valCount);
      } else {
        // If 1 or 2 sessions, train on all selected sessions
        trainSessionIds = selectedList;
        valSessionIds = [];
      }

      _currentProgress = TrainingProgress.training();
      notifyListeners();

      List<({List<double> features, String label})> trainData;
      List<({List<double> features, String label})> valData = [];

      switch (_selectedSource) {
        case TrainingDataSource.wrist:
          trainData = await _db.getWindowsForTrainingBySessions(
            sessionIds: trainSessionIds,
            bandRole: BandRole.wrist,
          );
          if (valSessionIds.isNotEmpty) {
            valData = await _db.getWindowsForTrainingBySessions(
              sessionIds: valSessionIds,
              bandRole: BandRole.wrist,
            );
          }
          break;
        case TrainingDataSource.ankle:
          trainData = await _db.getWindowsForTrainingBySessions(
            sessionIds: trainSessionIds,
            bandRole: BandRole.ankle,
          );
          if (valSessionIds.isNotEmpty) {
            valData = await _db.getWindowsForTrainingBySessions(
              sessionIds: valSessionIds,
              bandRole: BandRole.ankle,
            );
          }
          break;
        case TrainingDataSource.combined:
          final combinedTrain = await _db.getCombinedWindowsForTrainingBySessions(
            sessionIds: trainSessionIds,
          );
          trainData = combinedTrain.map((d) {
            return (features: [...d.wristFeatures, ...d.ankleFeatures], label: d.label);
          }).toList();

          if (valSessionIds.isNotEmpty) {
            final combinedVal = await _db.getCombinedWindowsForTrainingBySessions(
              sessionIds: valSessionIds,
            );
            valData = combinedVal.map((d) {
              return (features: [...d.wristFeatures, ...d.ankleFeatures], label: d.label);
            }).toList();
          }
          break;
      }

      // Check if trainData has at least 2 distinct classes
      final trainClasses = trainData.map((d) => d.label).toSet();
      if (trainClasses.length < 2 && valData.isNotEmpty) {
        // Fall back to using all sessions for training if split isolated all instances of a class
        trainData = [...trainData, ...valData];
        valData = [];
        trainSessionIds = selectedList;
        valSessionIds = [];
      }

      bool success;
      if (_selectedSource.isCombined) {
        success = await _ml.trainCombined(trainData, algorithm: _selectedAlgorithm);
      } else {
        success = await _ml.trainSingleBand(trainData, algorithm: _selectedAlgorithm);
      }

      ModelEvaluationReport? evalReport;

      if (success && valData.isNotEmpty) {
        _currentProgress = TrainingProgress.evaluating();
        notifyListeners();

        final actualLabels = <String>[];
        final predictedLabels = <String>[];

        for (final item in valData) {
          actualLabels.add(item.label);
          final pred = _selectedSource.isCombined
              ? _ml.predictFromFeatures60(item.features)
              : _ml.predictFromFeatures30(item.features);
          predictedLabels.add(pred?.label ?? 'Unknown');
        }

        evalReport = ModelEvaluationReport.compute(
          actualLabels: actualLabels,
          predictedLabels: predictedLabels,
          trainSessionCount: trainSessionIds.length,
          validationSessionCount: valSessionIds.length,
        );
      }

      _currentProgress = TrainingProgress.saving();
      notifyListeners();

      if (success) {
        _lastResult = TrainingResult.success(
          mode: _selectedSource,
          algorithm: _selectedAlgorithm,
          windowCount: trainData.length,
          labelCount: trainData.map((d) => d.label).toSet().length,
          sampleCount: _selectedSource.isSingleBand
              ? _ml.trainedSampleCount
              : _ml.trainedSampleCountCombined,
          classCount: _selectedSource.isSingleBand
              ? _ml.trainedClassCount
              : _ml.trainedClassCountCombined,
          evaluationReport: evalReport,
        );
      } else {
        _lastResult = TrainingResult.failure(
          'Training failed — insufficient data',
          _selectedSource,
          _selectedAlgorithm,
        );
      }
    } catch (e) {
      _error = 'Training error: $e';
      _lastResult = TrainingResult.failure('Training error: $e', _selectedSource, _selectedAlgorithm);
    } finally {
      _isTraining = false;
      _currentProgress = null;
      notifyListeners();
    }
  }

  Future<void> deleteModel({required bool combined}) async {
    await _ml.deleteModel(combined: combined);
    notifyListeners();
  }

  Future<bool> rollbackModel({required bool combined}) async {
    final success = await _ml.rollbackModel(combined: combined);
    notifyListeners();
    return success;
  }

  void reset() {
    _selectedSessionIds.clear();
    _selectedSource = TrainingDataSource.wrist;
    _selectedAlgorithm = MlAlgorithm.knn;
    _validationResult = null;
    _lastResult = null;
    _error = null;
    notifyListeners();
  }
}
