import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';

import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart';
import '../models/prediction_result.dart';
import '../models/sensor_data.dart';

/// On-device machine learning service.
///
/// Handles feature extraction from raw sensor windows,
/// KNN classifier training, and real-time prediction.
/// Supports both single-band (30 features) and dual-band combined (60 features) models.
class MlService {
  // Single-band model (30 features)
  KnnClassifier? _classifier30;
  int _trainedSampleCount30 = 0;
  int _trainedClassCount30 = 0;

  // Combined dual-band model (60 features)
  KnnClassifier? _classifier60;
  int _trainedSampleCount60 = 0;
  int _trainedClassCount60 = 0;

  /// Whether a single-band (30-feature) model has been trained.
  bool get isTrained => _classifier30 != null;

  /// Whether a combined dual-band (60-feature) model has been trained.
  bool get isCombinedTrained => _classifier60 != null;

  /// Number of training samples used in the single-band model.
  int get trainedSampleCount => _trainedSampleCount30;

  /// Number of distinct activity classes in the single-band model.
  int get trainedClassCount => _trainedClassCount30;

  /// Number of training samples used in the combined dual-band model.
  int get trainedSampleCountCombined => _trainedSampleCount60;

  /// Number of distinct activity classes in the combined dual-band model.
  int get trainedClassCountCombined => _trainedClassCount60;

  // Expected feature vector lengths
  static const int singleBandFeatureLength = BleConstants.featureVectorLength; // 30
  static const int combinedFeatureLength = BleConstants.featureVectorLength * 2; // 60

  // ── Feature Extraction ──

  /// Extract a feature vector from a window of [SensorReading]s (legacy).
  ///
  /// For each of the 6 axes, computes: mean, stdDev, variance, min, max.
  /// Returns a flat list of 30 doubles.
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
  ///
  /// For each of the 6 axes, computes: mean, stdDev, variance, min, max.
  /// Returns a flat list of 30 doubles.
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

  /// Extract feature vectors from both wrist and ankle windows, concatenated.
  ///
  /// Returns a 60-feature vector (30 wrist + 30 ankle).
  static List<double> extractCombinedFeatures({
    required List<ImuSample> wristWindow,
    required List<ImuSample> ankleWindow,
  }) {
    final wristFeatures = extractFeaturesFromImuSamples(wristWindow);
    final ankleFeatures = extractFeaturesFromImuSamples(ankleWindow);
    return [...wristFeatures, ...ankleFeatures];
  }

  // ── Feature Vector Validation ──

  /// Validate feature vector length for single-band prediction.
  static void _validateSingleBandFeatures(List<double> features) {
    if (features.length != singleBandFeatureLength) {
      throw ArgumentError(
        'Single-band feature vector must have exactly $singleBandFeatureLength features, got ${features.length}',
      );
    }
  }

  /// Validate feature vector length for combined dual-band prediction.
  static void _validateCombinedFeatures(List<double> features) {
    if (features.length != combinedFeatureLength) {
      throw ArgumentError(
        'Combined dual-band feature vector must have exactly $combinedFeatureLength features, got ${features.length}',
      );
    }
  }

  // ── Training ──

  /// Train a single-band (30-feature) KNN classifier from labeled feature windows.
  ///
  /// [trainingData] is a list of (featureVector, label) pairs loaded
  /// from the database. Each feature vector must be 30 features.
  ///
  /// Returns `true` if training succeeded, `false` if insufficient data.
  bool trainSingleBand(List<({List<double> features, String label})> trainingData) {
    if (!_validateTrainingData(trainingData, singleBandFeatureLength)) {
      return false;
    }

    // Build column headers: f0, f1, ..., f29, label
    final headers = <String>[
      for (int i = 0; i < singleBandFeatureLength; i++) 'f$i',
      'label',
    ];

    // Build data rows.
    final rows = trainingData.map((d) {
      return <dynamic>[...d.features, d.label];
    }).toList();

    // Create DataFrame.
    final dataFrame = DataFrame(
      [headers, ...rows],
      headerExists: true,
    );

    // Determine k: use sqrt(n) clamped to a reasonable range.
    final k = max(3, min(11, sqrt(trainingData.length).floor()));

    // Fit the classifier.
    _classifier30 = KnnClassifier(dataFrame, 'label', k);
    _trainedSampleCount30 = trainingData.length;
    _trainedClassCount30 = trainingData.map((d) => d.label).toSet().length;

    return true;
  }

  /// Train a combined dual-band (60-feature) KNN classifier.
  ///
  /// [trainingData] is a list of (featureVector, label) pairs.
  /// Each feature vector must be exactly 60 features (30 wrist + 30 ankle).
  ///
  /// Returns `true` if training succeeded, `false` if insufficient data.
  bool trainCombined(List<({List<double> features, String label})> trainingData) {
    if (!_validateTrainingData(trainingData, combinedFeatureLength)) {
      return false;
    }

    // Build column headers: f0, f1, ..., f59, label
    final headers = <String>[
      for (int i = 0; i < combinedFeatureLength; i++) 'f$i',
      'label',
    ];

    // Build data rows.
    final rows = trainingData.map((d) {
      return <dynamic>[...d.features, d.label];
    }).toList();

    // Create DataFrame.
    final dataFrame = DataFrame(
      [headers, ...rows],
      headerExists: true,
    );

    // Determine k: use sqrt(n) clamped to a reasonable range.
    final k = max(3, min(11, sqrt(trainingData.length).floor()));

    // Fit the classifier.
    _classifier60 = KnnClassifier(dataFrame, 'label', k);
    _trainedSampleCount60 = trainingData.length;
    _trainedClassCount60 = trainingData.map((d) => d.label).toSet().length;

    return true;
  }

  bool _validateTrainingData(
    List<({List<double> features, String label})> trainingData,
    int expectedFeatureLength,
  ) {
    if (trainingData.length < 2) {
      debugPrint('ML: Training rejected - need at least 2 samples, got ${trainingData.length}');
      return false;
    }

    final labels = trainingData.map((d) => d.label).toSet();
    if (labels.length < 2) {
      debugPrint('ML: Training rejected - need at least 2 distinct labels, got ${labels.length}');
      return false;
    }

    for (final d in trainingData) {
      if (d.features.length != expectedFeatureLength) {
        debugPrint('ML: Training rejected - feature vector must have exactly $expectedFeatureLength features, got ${d.features.length}');
        return false;
      }
    }

    return true;
  }

  // ── Prediction ──

  /// Predict the activity label for a raw sensor window (legacy SensorReading).
  ///
  /// Returns `null` if the model has not been trained.
  PredictionResult? predictFromWindow(List<SensorReading> window) {
    if (!isTrained) return null;

    final features = extractFeatures(window);
    _validateSingleBandFeatures(features);
    return predictFromFeatures30(features);
  }

  /// Predict the activity label for a raw IMU sample window (single-band, 30 features).
  ///
  /// Returns `null` if the model has not been trained.
  PredictionResult? predictFromImuWindow(List<ImuSample> window) {
    if (!isTrained) return null;

    final features = extractFeaturesFromImuSamples(window);
    _validateSingleBandFeatures(features);
    return predictFromFeatures30(features);
  }

  /// Predict from a 30-feature vector using the single-band model.
  PredictionResult? predictFromFeatures30(List<double> features) {
    if (!isTrained || _classifier30 == null) return null;

    _validateSingleBandFeatures(features);

    // Build a single-row DataFrame for prediction (without the label column).
    final headers = <String>[
      for (int i = 0; i < singleBandFeatureLength; i++) 'f$i',
    ];

    final dataFrame = DataFrame(
      [headers, features],
      headerExists: true,
    );

    final prediction = _classifier30!.predict(dataFrame);

    // Extract the predicted label from the result DataFrame.
    final predictedLabel = prediction.rows.first.last.toString();

    // Confidence is not available from the current KNN implementation.
    // ml_algo's KnnClassifier does not expose neighbor vote information.
    // This field will be null until a proper confidence estimation is implemented.

    return PredictionResult(
      label: predictedLabel,
      confidence: null,
    );
  }

  /// Predict from a 60-feature vector using the combined dual-band model.
  ///
  /// Returns `null` if the combined model has not been trained.
  PredictionResult? predictFromFeatures60(List<double> features) {
    if (!isCombinedTrained || _classifier60 == null) return null;

    _validateCombinedFeatures(features);

    // Build a single-row DataFrame for prediction (without the label column).
    final headers = <String>[
      for (int i = 0; i < combinedFeatureLength; i++) 'f$i',
    ];

    final dataFrame = DataFrame(
      [headers, features],
      headerExists: true,
    );

    final prediction = _classifier60!.predict(dataFrame);

    // Extract the predicted label from the result DataFrame.
    final predictedLabel = prediction.rows.first.last.toString();

    // Confidence is not available from the current KNN implementation.
    // ml_algo's KnnClassifier does not expose neighbor vote information.
    // This field will be null until a proper confidence estimation is implemented.

    return PredictionResult(
      label: predictedLabel,
      confidence: null,
    );
  }

  /// Predict using the appropriate model based on available bands.
  ///
  /// If both bands are available and combined model exists, uses 60-feature model.
  /// Otherwise uses single-band model if available and only one band is connected.
  /// Returns null if both bands are connected but combined model is not trained
  /// (to avoid presenting single-band predictions as dual-band predictions).
  PredictionResult? predictAdaptive({
    required List<ImuSample> wristWindow,
    required List<ImuSample> ankleWindow,
  }) {
    final hasWrist = wristWindow.isNotEmpty;
    final hasAnkle = ankleWindow.isNotEmpty;

    // Case A: Both bands connected AND combined model trained → 60-feature prediction
    if (hasWrist && hasAnkle && isCombinedTrained) {
      final features = extractCombinedFeatures(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
      );
      return predictFromFeatures60(features);
    }

    // Case B: Both bands connected but NO combined model → NO fallback prediction
    // Returning null prevents presenting single-band predictions as dual-band predictions.
    if (hasWrist && hasAnkle && !isCombinedTrained) {
      return null;
    }

    // Case C: Only one band available → single-band prediction (30 features)
    if (hasWrist && isTrained) {
      final features = extractFeaturesFromImuSamples(wristWindow);
      return predictFromFeatures30(features);
    } else if (hasAnkle && isTrained) {
      final features = extractFeaturesFromImuSamples(ankleWindow);
      return predictFromFeatures30(features);
    }

    return null;
  }

  // Legacy method for backward compatibility.
  PredictionResult? predictFromFeatures(List<double> features) {
    if (!isTrained || _classifier30 == null) return null;

    _validateSingleBandFeatures(features);
    return predictFromFeatures30(features);
  }

  /// Reset both models.
  void reset() {
    _classifier30 = null;
    _trainedSampleCount30 = 0;
    _trainedClassCount30 = 0;
    _classifier60 = null;
    _trainedSampleCount60 = 0;
    _trainedClassCount60 = 0;
  }

  // ── Private Helpers ──

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