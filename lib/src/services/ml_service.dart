import 'dart:math';

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
class MlService {
  KnnClassifier? _classifier;
  int _trainedSampleCount = 0;
  int _trainedClassCount = 0;

  /// Whether a model has been trained and is ready for prediction.
  bool get isTrained => _classifier != null;

  /// Number of training samples used in the current model.
  int get trainedSampleCount => _trainedSampleCount;

  /// Number of distinct activity classes in the current model.
  int get trainedClassCount => _trainedClassCount;

  // ── Feature Extraction ──

  /// Extract a feature vector from a window of [SensorReading]s.
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

  // ── Training ──

  /// Train a KNN classifier from labeled feature windows.
  ///
  /// [trainingData] is a list of (featureVector, label) pairs loaded
  /// from the database.
  ///
  /// Returns `true` if training succeeded, `false` if insufficient data.
  bool train(List<({List<double> features, String label})> trainingData) {
    if (trainingData.length < 2) {
      return false;
    }

    // Check that we have at least 2 distinct labels.
    final labels = trainingData.map((d) => d.label).toSet();
    if (labels.length < 2) {
      return false;
    }

    // Build column headers: f0, f1, ..., f29, label
    final headers = <String>[
      for (int i = 0; i < BleConstants.featureVectorLength; i++) 'f$i',
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
    _classifier = KnnClassifier(dataFrame, 'label', k);
    _trainedSampleCount = trainingData.length;
    _trainedClassCount = labels.length;

    return true;
  }

  // ── Prediction ──

  /// Predict the activity label for a raw sensor window (legacy SensorReading).
  ///
  /// Returns `null` if the model has not been trained.
  PredictionResult? predictFromWindow(List<SensorReading> window) {
    if (!isTrained) return null;

    final features = extractFeatures(window);
    return predictFromFeatures(features);
  }

  /// Predict the activity label for a raw IMU sample window.
  ///
  /// Returns `null` if the model has not been trained.
  PredictionResult? predictFromImuWindow(List<ImuSample> window) {
    if (!isTrained) return null;

    final features = extractFeaturesFromImuSamples(window);
    return predictFromFeatures(features);
  }

  /// Predict from an already-extracted feature vector.
  PredictionResult? predictFromFeatures(List<double> features) {
    if (!isTrained || _classifier == null) return null;

    // Build a single-row DataFrame for prediction (without the label column).
    final headers = <String>[
      for (int i = 0; i < BleConstants.featureVectorLength; i++) 'f$i',
    ];

    final dataFrame = DataFrame(
      [headers, features],
      headerExists: true,
    );

    final prediction = _classifier!.predict(dataFrame);

    // Extract the predicted label from the result DataFrame.
    final predictedLabel = prediction.rows.first.last.toString();

    // KNN doesn't natively provide probability, so we estimate confidence
    // as 1.0 for now. A more sophisticated approach would tally neighbor
    /// votes, but ml_algo's KnnClassifier doesn't expose that directly.
    const confidence = 0.85; // Placeholder — could be improved with custom KNN

    return PredictionResult(
      label: predictedLabel,
      confidence: confidence,
    );
  }

  /// Reset the model.
  void reset() {
    _classifier = null;
    _trainedSampleCount = 0;
    _trainedClassCount = 0;
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
