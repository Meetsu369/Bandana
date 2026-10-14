import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart';
import '../models/prediction_result.dart';
import '../models/sensor_data.dart';

/// Supported machine learning algorithms on device.
enum MlAlgorithm {
  knn,
  logisticRegression;

  String get displayName => switch (this) {
    MlAlgorithm.knn => 'K-Nearest Neighbors (KNN)',
    MlAlgorithm.logisticRegression => 'Logistic Regression (Softmax)',
  };

  String get shortName => switch (this) {
    MlAlgorithm.knn => 'KNN',
    MlAlgorithm.logisticRegression => 'LogReg',
  };
}

/// On-device machine learning service.
///
/// Handles feature extraction from raw sensor windows,
/// classifier training (KNN and Logistic Regression), persistence with rollback,
/// and real-time inference.
/// Supports both single-band (30 features) and dual-band combined (60 features) models.
class MlService {
  // Single-band model (30 features)
  KnnClassifier? _classifier30;
  SoftmaxRegressor? _softmax30;
  MlAlgorithm _algorithm30 = MlAlgorithm.knn;
  List<String> _classLabels30 = [];
  Map<String, int> _labelToIndex30 = {};
  Map<int, String> _indexToLabel30 = {};
  int _trainedSampleCount30 = 0;
  int _trainedClassCount30 = 0;

  // Combined dual-band model (60 features)
  KnnClassifier? _classifier60;
  SoftmaxRegressor? _softmax60;
  MlAlgorithm _algorithm60 = MlAlgorithm.knn;
  List<String> _classLabels60 = [];
  Map<String, int> _labelToIndex60 = {};
  Map<int, String> _indexToLabel60 = {};
  int _trainedSampleCount60 = 0;
  int _trainedClassCount60 = 0;

  /// Label-to-index mapping for 30-feature models.
  Map<String, int> get labelToIndex30 => _labelToIndex30;

  /// Label-to-index mapping for 60-feature models.
  Map<String, int> get labelToIndex60 => _labelToIndex60;

  // Persistence keys
  SharedPreferences? _prefs;
  static const String _prefsKey30 = 'ml_model_30';
  static const String _prefsKey60 = 'ml_model_60';
  static const String _prefsKey30Backup = 'ml_model_30_backup';
  static const String _prefsKey60Backup = 'ml_model_60_backup';

  /// Whether a single-band (30-feature) model has been trained or imported.
  bool get isTrained =>
      _classifier30 != null ||
      _softmax30 != null ||
      (_classLabels30.isNotEmpty && _trainedSampleCount30 > 0);

  /// Whether a combined dual-band (60-feature) model has been trained or imported.
  bool get isCombinedTrained =>
      _classifier60 != null ||
      _softmax60 != null ||
      (_classLabels60.isNotEmpty && _trainedSampleCount60 > 0);

  /// Active algorithm for the single-band model.
  MlAlgorithm get algorithm30 => _algorithm30;

  /// Active algorithm for the combined dual-band model.
  MlAlgorithm get algorithm60 => _algorithm60;

  /// Number of training samples used in the single-band model.
  int get trainedSampleCount => _trainedSampleCount30;

  /// Number of distinct activity classes in the single-band model.
  int get trainedClassCount => _trainedClassCount30;

  /// Number of training samples used in the combined dual-band model.
  int get trainedSampleCountCombined => _trainedSampleCount60;

  /// Number of distinct activity classes in the combined dual-band model.
  int get trainedClassCountCombined => _trainedClassCount60;

  /// Class labels for single-band model.
  List<String> get classLabels30 => List.unmodifiable(_classLabels30);

  /// Class labels for combined dual-band model.
  List<String> get classLabels60 => List.unmodifiable(_classLabels60);

  /// Whether a rollback backup is available for 30-feature model.
  bool get canRollback30 => _prefs?.containsKey(_prefsKey30Backup) ?? false;

  /// Whether a rollback backup is available for 60-feature model.
  bool get canRollback60 => _prefs?.containsKey(_prefsKey60Backup) ?? false;

  /// Active model version string.
  String get activeModelVersion {
    if (isCombinedTrained) {
      return '${_algorithm60.shortName.toLowerCase()}_60_${_trainedSampleCount60}s';
    }
    if (isTrained) {
      return '${_algorithm30.shortName.toLowerCase()}_30_${_trainedSampleCount30}s';
    }
    return 'none';
  }

  // Expected feature vector lengths
  static const int singleBandFeatureLength = BleConstants.featureVectorLength; // 30
  static const int combinedFeatureLength = BleConstants.featureVectorLength * 2; // 60

  /// Initialize the ML service and load persisted models.
  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    await _loadModels();
  }

  // ── Feature Extraction ──

  /// Extract a feature vector from a window of [SensorReading]s (legacy).
  static List<double> extractFeatures(List<SensorReading> window) {
    if (window.isEmpty) {
      return List.filled(BleConstants.featureVectorLength, 0.0);
    }

    final features = <double>[];
    for (int axis = 0; axis < BleConstants.axisCount; axis++) {
      final values = window.map((r) => r.toList()[axis]).toList();
      final mean = _mean(values);
      final std = _stdDev(values, mean);
      final variance = std * std;
      final minVal = values.reduce(min);
      final maxVal = values.reduce(max);
      features.addAll([mean, std, variance, minVal, maxVal]);
    }
    return features;
  }

  /// Extract a feature vector from a window of [ImuSample]s.
  static List<double> extractFeaturesFromImuSamples(List<ImuSample> window) {
    if (window.isEmpty) {
      return List.filled(BleConstants.featureVectorLength, 0.0);
    }

    final features = <double>[];
    for (int axis = 0; axis < BleConstants.axisCount; axis++) {
      final values = window.map((r) => r.toList()[axis]).toList();
      final mean = _mean(values);
      final std = _stdDev(values, mean);
      final variance = std * std;
      final minVal = values.reduce(min);
      final maxVal = values.reduce(max);
      features.addAll([mean, std, variance, minVal, maxVal]);
    }
    return features;
  }

  /// Extract combined feature vector (30 wrist + 30 ankle = 60).
  static List<double> extractCombinedFeatures({
    required List<ImuSample> wristWindow,
    required List<ImuSample> ankleWindow,
  }) {
    final wristFeatures = extractFeaturesFromImuSamples(wristWindow);
    final ankleFeatures = extractFeaturesFromImuSamples(ankleWindow);
    return [...wristFeatures, ...ankleFeatures];
  }

  // ── Training ──

  /// Train a single-band (30-feature) classifier from labeled feature windows.
  Future<bool> trainSingleBand(
    List<({List<double> features, String label})> trainingData, {
    MlAlgorithm algorithm = MlAlgorithm.knn,
  }) async {
    if (!_validateTrainingData(trainingData, singleBandFeatureLength)) {
      return false;
    }

    final labelList = trainingData.map((d) => d.label).toSet().toList()..sort();
    final labelToIndex = {for (int i = 0; i < labelList.length; i++) labelList[i]: i};
    final indexToLabel = {for (int i = 0; i < labelList.length; i++) i: labelList[i]};

    if (algorithm == MlAlgorithm.knn) {
      final headers = [
        for (int i = 0; i < singleBandFeatureLength; i++) 'f$i',
        'label',
      ];
      final rows = trainingData.map((d) {
        return <dynamic>[...d.features, labelToIndex[d.label]!];
      }).toList();

      final dataFrame = DataFrame([headers, ...rows], headerExists: true);
      final k = max(3, min(11, sqrt(trainingData.length).floor()));

      _classifier30 = KnnClassifier(dataFrame, 'label', k);
      _softmax30 = null;
      _algorithm30 = MlAlgorithm.knn;
      _classLabels30 = labelList;
      _labelToIndex30 = labelToIndex;
      _indexToLabel30 = indexToLabel;
      _trainedSampleCount30 = trainingData.length;
      _trainedClassCount30 = labelList.length;

      await _persistModel(combined: false);
      return true;
    } else {
      // Logistic Regression (Softmax)
      final headers = [
        for (int i = 0; i < singleBandFeatureLength; i++) 'f$i',
        ...labelList,
      ];
      final rows = trainingData.map((d) {
        final oneHot = labelList.map((l) => l == d.label ? 1 : 0).toList();
        return <dynamic>[...d.features, ...oneHot];
      }).toList();

      final dataFrame = DataFrame([headers, ...rows], headerExists: true);
      _softmax30 = SoftmaxRegressor(
        dataFrame,
        labelList,
        iterationsLimit: 300,
        learningRateType: LearningRateType.constant,
        initialLearningRate: 0.001,
      );
      _classifier30 = null;
      _algorithm30 = MlAlgorithm.logisticRegression;
      _classLabels30 = labelList;
      _labelToIndex30 = labelToIndex;
      _indexToLabel30 = indexToLabel;
      _trainedSampleCount30 = trainingData.length;
      _trainedClassCount30 = labelList.length;

      await _persistModel(combined: false);
      return true;
    }
  }

  /// Train a single-band (30-feature) classifier for a specific band role.
  Future<bool> trainSingleBandForRole(
    BandRole role,
    List<({List<double> features, String label})> trainingData, {
    MlAlgorithm algorithm = MlAlgorithm.knn,
  }) async {
    return await trainSingleBand(trainingData, algorithm: algorithm);
  }

  /// Train a combined dual-band (60-feature) classifier.
  Future<bool> trainCombined(
    List<({List<double> features, String label})> trainingData, {
    MlAlgorithm algorithm = MlAlgorithm.knn,
  }) async {
    if (!_validateTrainingData(trainingData, combinedFeatureLength)) {
      return false;
    }

    final labelList = trainingData.map((d) => d.label).toSet().toList()..sort();
    final labelToIndex = {for (int i = 0; i < labelList.length; i++) labelList[i]: i};
    final indexToLabel = {for (int i = 0; i < labelList.length; i++) i: labelList[i]};

    if (algorithm == MlAlgorithm.knn) {
      final headers = [
        for (int i = 0; i < combinedFeatureLength; i++) 'f$i',
        'label',
      ];
      final rows = trainingData.map((d) {
        return <dynamic>[...d.features, labelToIndex[d.label]!];
      }).toList();

      final dataFrame = DataFrame([headers, ...rows], headerExists: true);
      final k = max(3, min(11, sqrt(trainingData.length).floor()));

      _classifier60 = KnnClassifier(dataFrame, 'label', k);
      _softmax60 = null;
      _algorithm60 = MlAlgorithm.knn;
      _classLabels60 = labelList;
      _labelToIndex60 = labelToIndex;
      _indexToLabel60 = indexToLabel;
      _trainedSampleCount60 = trainingData.length;
      _trainedClassCount60 = labelList.length;

      await _persistModel(combined: true);
      return true;
    } else {
      // Logistic Regression (Softmax)
      final headers = [
        for (int i = 0; i < combinedFeatureLength; i++) 'f$i',
        ...labelList,
      ];
      final rows = trainingData.map((d) {
        final oneHot = labelList.map((l) => l == d.label ? 1 : 0).toList();
        return <dynamic>[...d.features, ...oneHot];
      }).toList();

      final dataFrame = DataFrame([headers, ...rows], headerExists: true);
      _softmax60 = SoftmaxRegressor(
        dataFrame,
        labelList,
        iterationsLimit: 300,
        learningRateType: LearningRateType.constant,
        initialLearningRate: 0.001,
      );
      _classifier60 = null;
      _algorithm60 = MlAlgorithm.logisticRegression;
      _classLabels60 = labelList;
      _labelToIndex60 = labelToIndex;
      _indexToLabel60 = indexToLabel;
      _trainedSampleCount60 = trainingData.length;
      _trainedClassCount60 = labelList.length;

      await _persistModel(combined: true);
      return true;
    }
  }

  /// Train a combined dual-band classifier from separate wrist/ankle windows.
  Future<bool> trainCombinedFromSeparate(
    List<({List<double> wristFeatures, List<double> ankleFeatures, String label})> trainingData, {
    MlAlgorithm algorithm = MlAlgorithm.knn,
  }) async {
    final combinedData = trainingData.map((d) {
      final combinedFeatures = [...d.wristFeatures, ...d.ankleFeatures];
      return (features: combinedFeatures, label: d.label);
    }).toList();

    return await trainCombined(combinedData, algorithm: algorithm);
  }

  bool _validateTrainingData(
    List<({List<double> features, String label})> trainingData,
    int expectedFeatureLength,
  ) {
    if (trainingData.length < 2) {
      debugPrint('ML: Need at least 2 samples, got ${trainingData.length}');
      return false;
    }

    final labels = trainingData.map((d) => d.label).toSet();
    if (labels.length < 2) {
      debugPrint('ML: Need at least 2 distinct labels, got ${labels.length}');
      return false;
    }

    for (final d in trainingData) {
      if (d.features.length != expectedFeatureLength) {
        debugPrint('ML: Expected $expectedFeatureLength features, got ${d.features.length}');
        return false;
      }
    }

    return true;
  }

  // ── Prediction ──

  /// Predict the activity label for a raw sensor window (legacy SensorReading).
  PredictionResult? predictFromWindow(List<SensorReading> window) {
    if (!isTrained) return null;
    final features = extractFeatures(window);
    return predictFromFeatures30(features);
  }

  /// Predict the activity label for an IMU sample window (single-band, 30 features).
  PredictionResult? predictFromImuWindow(List<ImuSample> window) {
    if (!isTrained) return null;
    final features = extractFeaturesFromImuSamples(window);
    return predictFromFeatures30(features);
  }

  /// Predict from a 30-feature vector using the single-band model.
  PredictionResult? predictFromFeatures30(List<double> features) {
    if (!isTrained || features.length != singleBandFeatureLength) return null;

    if (_algorithm30 == MlAlgorithm.logisticRegression && _softmax30 != null) {
      final headers = [for (int i = 0; i < singleBandFeatureLength; i++) 'f$i'];
      final dataFrame = DataFrame([headers, features], headerExists: true);
      final probs = _softmax30!.predictProbabilities(dataFrame);
      final row = probs.rows.first.map((v) => (v as num).toDouble()).toList();

      var maxIndex = 0;
      var maxProb = row[0];
      for (int i = 1; i < row.length; i++) {
        if (row[i] > maxProb) {
          maxProb = row[i];
          maxIndex = i;
        }
      }

      final targetNames = probs.header.toList();
      final label = maxIndex < targetNames.length ? targetNames[maxIndex] : 'Unknown';
      return PredictionResult(
        label: label,
        confidence: maxProb.clamp(0.0, 1.0),
      );
    } else if (_classifier30 != null) {
      final headers = [for (int i = 0; i < singleBandFeatureLength; i++) 'f$i'];
      final dataFrame = DataFrame([headers, features], headerExists: true);
      final prediction = _classifier30!.predict(dataFrame);
      final predictedId = (prediction.rows.first.last as num).toInt();
      final label = _indexToLabel30[predictedId] ?? 'Unknown';

      return PredictionResult(
        label: label,
        confidence: null, // KNN does not expose probabilities
      );
    }

    return null;
  }

  /// Predict from a 60-feature vector using the combined dual-band model.
  PredictionResult? predictFromFeatures60(List<double> features) {
    if (!isCombinedTrained || features.length != combinedFeatureLength) return null;

    if (_algorithm60 == MlAlgorithm.logisticRegression && _softmax60 != null) {
      final headers = [for (int i = 0; i < combinedFeatureLength; i++) 'f$i'];
      final dataFrame = DataFrame([headers, features], headerExists: true);
      final probs = _softmax60!.predictProbabilities(dataFrame);
      final row = probs.rows.first.map((v) => (v as num).toDouble()).toList();

      var maxIndex = 0;
      var maxProb = row[0];
      for (int i = 1; i < row.length; i++) {
        if (row[i] > maxProb) {
          maxProb = row[i];
          maxIndex = i;
        }
      }

      final targetNames = probs.header.toList();
      final label = maxIndex < targetNames.length ? targetNames[maxIndex] : 'Unknown';
      return PredictionResult(
        label: label,
        confidence: maxProb.clamp(0.0, 1.0),
      );
    } else if (_classifier60 != null) {
      final headers = [for (int i = 0; i < combinedFeatureLength; i++) 'f$i'];
      final dataFrame = DataFrame([headers, features], headerExists: true);
      final prediction = _classifier60!.predict(dataFrame);
      final predictedId = (prediction.rows.first.last as num).toInt();
      final label = _indexToLabel60[predictedId] ?? 'Unknown';

      return PredictionResult(
        label: label,
        confidence: null, // KNN does not expose probabilities
      );
    }

    return null;
  }

  /// Predict using the appropriate model based on available bands.
  ///
  /// - If both bands are available and combined model exists: uses 60-feature model.
  /// - If only wrist available and single-band model exists: uses 30-feature model.
  /// - If only ankle available and single-band model exists: uses 30-feature model.
  /// - If both bands connected but no combined model exists: returns null
  ///   (never falsely claim dual-band inference with single-band model).
  PredictionResult? predictAdaptive({
    required List<ImuSample> wristWindow,
    required List<ImuSample> ankleWindow,
  }) {
    final hasWrist = wristWindow.isNotEmpty;
    final hasAnkle = ankleWindow.isNotEmpty;

    if (hasWrist && hasAnkle) {
      if (isCombinedTrained) {
        final features = extractCombinedFeatures(
          wristWindow: wristWindow,
          ankleWindow: ankleWindow,
        );
        return predictFromFeatures60(features);
      }
      return null;
    }

    if (hasWrist && isTrained) {
      final features = extractFeaturesFromImuSamples(wristWindow);
      return predictFromFeatures30(features);
    }

    if (hasAnkle && isTrained) {
      final features = extractFeaturesFromImuSamples(ankleWindow);
      return predictFromFeatures30(features);
    }

    return null;
  }

  // Legacy method
  PredictionResult? predictFromFeatures(List<double> features) => predictFromFeatures30(features);

  /// Reset all loaded models and remove saved models from disk.
  void reset() {
    _classifier30 = null;
    _softmax30 = null;
    _trainedSampleCount30 = 0;
    _trainedClassCount30 = 0;
    _classLabels30 = [];
    _labelToIndex30 = {};
    _indexToLabel30 = {};

    _classifier60 = null;
    _softmax60 = null;
    _trainedSampleCount60 = 0;
    _trainedClassCount60 = 0;
    _classLabels60 = [];
    _labelToIndex60 = {};
    _indexToLabel60 = {};

    _clearPersistedModels();
  }

  /// Delete a specific model by type.
  Future<void> deleteModel({required bool combined}) async {
    if (combined) {
      _classifier60 = null;
      _softmax60 = null;
      _trainedSampleCount60 = 0;
      _trainedClassCount60 = 0;
      _classLabels60 = [];
      _labelToIndex60 = {};
      _indexToLabel60 = {};
      await _prefs?.remove(_prefsKey60);
    } else {
      _classifier30 = null;
      _softmax30 = null;
      _trainedSampleCount30 = 0;
      _trainedClassCount30 = 0;
      _classLabels30 = [];
      _labelToIndex30 = {};
      _indexToLabel30 = {};
      await _prefs?.remove(_prefsKey30);
    }
  }

  /// Roll back the active model to the previously backed-up model.
  Future<bool> rollbackModel({required bool combined}) async {
    if (_prefs == null) return false;
    final backupKey = combined ? _prefsKey60Backup : _prefsKey30Backup;
    final activeKey = combined ? _prefsKey60 : _prefsKey30;

    final backupJson = _prefs!.getString(backupKey);
    if (backupJson == null) return false;

    // Restore backup to active
    await _prefs!.setString(activeKey, backupJson);
    await _loadModels();
    debugPrint('ML: Successfully rolled back ${combined ? "60" : "30"}-feature model');
    return true;
  }

  // ── Model Persistence & Versioning ──

  Future<void> _persistModel({required bool combined}) async {
    if (_prefs == null) return;
    final key = combined ? _prefsKey60 : _prefsKey30;
    final backupKey = combined ? _prefsKey60Backup : _prefsKey30Backup;

    // Save previous active model as backup before overwriting
    final previousActive = _prefs!.getString(key);
    if (previousActive != null) {
      await _prefs!.setString(backupKey, previousActive);
    }

    final algorithm = combined ? _algorithm60 : _algorithm30;
    final classLabels = combined ? _classLabels60 : _classLabels30;
    final featureLength = combined ? combinedFeatureLength : singleBandFeatureLength;
    final sampleCount = combined ? _trainedSampleCount60 : _trainedSampleCount30;

    final map = <String, dynamic>{
      'formatVersion': 2,
      'algorithm': algorithm.name,
      'classLabels': classLabels,
      'featureLength': featureLength,
      'sampleCount': sampleCount,
      'classCount': classLabels.length,
      'trainedAt': DateTime.now().toIso8601String(),
    };

    if (algorithm == MlAlgorithm.logisticRegression) {
      final regressor = combined ? _softmax60 : _softmax30;
      if (regressor != null) {
        map['softmaxJson'] = jsonEncode(regressor.toJson());
      }
    }

    await _prefs!.setString(key, jsonEncode(map));
    debugPrint('ML: Persisted ${combined ? "60" : "30"}-feature model ($algorithm)');
  }

  Future<void> _loadModels() async {
    if (_prefs == null) return;

    // Load 30-feature model
    final model30Json = _prefs!.getString(_prefsKey30);
    if (model30Json != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(model30Json);
        final formatVersion = data['formatVersion'] as int? ?? 1;

        if (formatVersion >= 2) {
          final algName = data['algorithm'] as String? ?? 'knn';
          final alg = MlAlgorithm.values.byName(algName);
          final labels = (data['classLabels'] as List).cast<String>();

          _classLabels30 = labels;
          _labelToIndex30 = {for (int i = 0; i < labels.length; i++) labels[i]: i};
          _indexToLabel30 = {for (int i = 0; i < labels.length; i++) i: labels[i]};
          _trainedSampleCount30 = data['sampleCount'] as int? ?? 0;
          _trainedClassCount30 = labels.length;
          _algorithm30 = alg;

          if (alg == MlAlgorithm.logisticRegression && data['softmaxJson'] != null) {
            _softmax30 = SoftmaxRegressor.fromJson(data['softmaxJson'] as String);
            _classifier30 = null;
          }
        }
      } catch (e) {
        debugPrint('ML: Failed to restore 30-feature model: $e');
      }
    }

    // Load 60-feature model
    final model60Json = _prefs!.getString(_prefsKey60);
    if (model60Json != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(model60Json);
        final formatVersion = data['formatVersion'] as int? ?? 1;

        if (formatVersion >= 2) {
          final algName = data['algorithm'] as String? ?? 'knn';
          final alg = MlAlgorithm.values.byName(algName);
          final labels = (data['classLabels'] as List).cast<String>();

          _classLabels60 = labels;
          _labelToIndex60 = {for (int i = 0; i < labels.length; i++) labels[i]: i};
          _indexToLabel60 = {for (int i = 0; i < labels.length; i++) i: labels[i]};
          _trainedSampleCount60 = data['sampleCount'] as int? ?? 0;
          _trainedClassCount60 = labels.length;
          _algorithm60 = alg;

          if (alg == MlAlgorithm.logisticRegression && data['softmaxJson'] != null) {
            _softmax60 = SoftmaxRegressor.fromJson(data['softmaxJson'] as String);
            _classifier60 = null;
          }
        }
      } catch (e) {
        debugPrint('ML: Failed to restore 60-feature model: $e');
      }
    }
  }

  Future<void> _clearPersistedModels() async {
    if (_prefs == null) return;
    await _prefs!.remove(_prefsKey30);
    await _prefs!.remove(_prefsKey60);
    await _prefs!.remove(_prefsKey30Backup);
    await _prefs!.remove(_prefsKey60Backup);
  }

  // ── Laptop Service Interop (JSON Model Artifacts) ──

  /// Export model configuration and weights as JSON artifact string.
  String? exportModelJson({required bool combined}) {
    if (_prefs == null) return null;
    final key = combined ? _prefsKey60 : _prefsKey30;
    return _prefs!.getString(key);
  }

  /// Import and activate a model artifact JSON string.
  Future<bool> importModelJson(String jsonStr, {required bool combined}) async {
    if (_prefs == null) return false;
    try {
      final Map<String, dynamic> map = jsonDecode(jsonStr);
      final expectedLength = combined ? combinedFeatureLength : singleBandFeatureLength;
      final featureLength = map['featureLength'] as int?;

      if (featureLength != expectedLength) {
        throw ArgumentError('Feature length mismatch: expected $expectedLength, got $featureLength');
      }

      final key = combined ? _prefsKey60 : _prefsKey30;
      final backupKey = combined ? _prefsKey60Backup : _prefsKey30Backup;

      final current = _prefs!.getString(key);
      if (current != null) {
        await _prefs!.setString(backupKey, current);
      }

      await _prefs!.setString(key, jsonStr);
      await _loadModels();
      return true;
    } catch (e) {
      debugPrint('ML: Failed to import model artifact: $e');
      return false;
    }
  }

  // ── Math Helpers ──

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double _stdDev(List<double> values, double mean) {
    if (values.length < 2) return 0.0;
    final sumSqDiff = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
    return sqrt(sumSqDiff / values.length);
  }
}