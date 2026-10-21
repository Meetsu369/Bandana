import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart';

/// Supported HAR Model architectures available for live execution.
enum HarModelType {
  cnn1d('1D-CNN (Temporal Conv)'),
  convGru('Conv1D-GRU (Spatial-Temporal)'),
  logisticRegression('Logistic Regression (Linear)'),
  ensembleMajority('Multi-Model Ensemble (Soft-Voting)');

  final String displayName;
  const HarModelType(this.displayName);
}

/// Represents an activity classification result with confidence, model source,
/// and consensus distribution.
class ActivityPrediction {
  final String label;
  final double confidence;
  final DateTime timestamp;
  final HarModelType modelType;
  final Map<String, double>? classProbabilities;
  final bool isHighConfidence;
  final bool hasDisagreement;

  const ActivityPrediction({
    required this.label,
    required this.confidence,
    required this.timestamp,
    this.modelType = HarModelType.ensembleMajority,
    this.classProbabilities,
    this.isHighConfidence = true,
    this.hasDisagreement = false,
  });

  @override
  String toString() => '$label (${(confidence * 100).toStringAsFixed(1)}%) [$modelType]';
}

/// Manages real-time on-device activity inference using 16-channel invariant
/// feature engineering, multi-model loading, model selection, and soft-voting ensembling.
///
/// Window Size: 100 samples (2.0s @ 50 Hz)
/// Stride: 50 samples (1.0s stride / 50% overlap)
/// Channels: 16 total:
///   [0..2]  wrist_ax, ay, az
///   [3..5]  wrist_gx, gy, gz
///   [6..8]  ankle_ax, ay, az
///   [9..11] ankle_gx, gy, gz
///   [12]    wrist_amag (invariant accel magnitude)
///   [13]    wrist_gmag (invariant gyro magnitude)
///   [14]    ankle_amag (invariant accel magnitude)
///   [15]    ankle_gmag (invariant gyro magnitude)
class ClassifierService {
  ClassifierService._internal();
  static final ClassifierService instance = ClassifierService._internal();
  factory ClassifierService() => instance;

  static const int windowSize = 100;
  static const int strideSize = 50;
  static const int channelCount = 16;

  static const List<String> defaultClasses = [
    'Sitting',
    'Standing_HandMove',
    'Walking',
    'Jumping',
  ];

  // 4th-order Butterworth low-pass filter coefficients (fc = 15 Hz, fs = 50 Hz, Wn = 0.6)
  static const List<double> _b = [
    0.16717926860848992,
    0.6687170744339597,
    1.0030756116509396,
    0.6687170744339597,
    0.16717926860848992,
  ];

  static const List<double> _a = [
    1.0,
    0.7820951980233373,
    0.6799785269162992,
    0.18267569775303227,
    0.030118875043169256,
  ];

  // Physical scaling vector: accel (+/- 4g) / 4.0, gyro (+/- 250 dps) / 250.0, mags scaled identically
  static const List<double> _scaleVector16 = [
    4.0, 4.0, 4.0, 250.0, 250.0, 250.0,  // wrist raw
    4.0, 4.0, 4.0, 250.0, 250.0, 250.0,  // ankle raw
    4.0, 250.0, 4.0, 250.0               // w_amag, w_gmag, a_amag, a_gmag
  ];

  static List<String> _targetClasses = List.from(defaultClasses);
  static List<String> get targetClasses => _targetClasses;

  // TFLite Interpreters for the model suite
  Interpreter? _cnnInterpreter;
  Interpreter? _gruInterpreter;
  Interpreter? _logregInterpreter;

  bool _isTfliteLoaded = false;
  bool _isInitializing = false;
  bool get isTfliteLoaded => _isTfliteLoaded;

  // Active Model State
  HarModelType _activeModel = HarModelType.ensembleMajority;
  HarModelType get activeModel => _activeModel;
  final _activeModelController = StreamController<HarModelType>.broadcast();
  Stream<HarModelType> get activeModelStream => _activeModelController.stream;

  void setActiveModel(HarModelType type) {
    _activeModel = type;
    _activeModelController.add(type);
    debugPrint('ClassifierService: Active model switched to -> ${type.displayName}');
  }

  // FIFO Buffer of 16-channel frames
  final List<List<double>> _windowBuffer = [];
  int _samplesSinceLastInference = 0;

  // Latest readings from each band
  List<double> _latestWrist = List.filled(6, 0.0);
  List<double> _latestAnkle = List.filled(6, 0.0);
  bool _hasWristData = false;
  bool _hasAnkleData = false;
  bool get hasWristData => _hasWristData;
  bool get hasAnkleData => _hasAnkleData;

  final _predictionController = StreamController<ActivityPrediction>.broadcast();
  Stream<ActivityPrediction> get predictionStream => _predictionController.stream;

  ActivityPrediction _lastPrediction = ActivityPrediction(
    label: 'Sitting',
    confidence: 0.95,
    timestamp: DateTime.now(),
  );
  ActivityPrediction get currentPrediction => _lastPrediction;

  /// Initialize all available TFLite models and labels.
  Future<void> initialize() async {
    if (_isTfliteLoaded || _isInitializing) return;
    _isInitializing = true;

    try {
      debugPrint('ClassifierService: Loading TFLite model suite...');
      final options = InterpreterOptions()..threads = 2;

      // 1. Try loading 1D-CNN
      try {
        _cnnInterpreter = await Interpreter.fromAsset(
          'assets/models/model_1d_cnn.tflite',
          options: options,
        );
        _cnnInterpreter!.allocateTensors();
        debugPrint('ClassifierService: [LOADED] 1D-CNN -> input ${_cnnInterpreter!.getInputTensor(0).shape}');
      } catch (_) {
        try {
          _cnnInterpreter = await Interpreter.fromAsset(
            'assets/models/dual_band_model.tflite',
            options: options,
          );
          _cnnInterpreter!.allocateTensors();
          debugPrint('ClassifierService: [LOADED] 1D-CNN (from dual_band_model.tflite)');
        } catch (e) {
          debugPrint('ClassifierService: Could not load 1D-CNN: $e');
        }
      }

      // 2. Try loading Conv1D-GRU
      try {
        _gruInterpreter = await Interpreter.fromAsset(
          'assets/models/model_conv_gru.tflite',
          options: options,
        );
        _gruInterpreter!.allocateTensors();
        debugPrint('ClassifierService: [LOADED] Conv1D-GRU -> input ${_gruInterpreter!.getInputTensor(0).shape}');
      } catch (e) {
        debugPrint('ClassifierService: Conv1D-GRU optional asset note: $e');
      }

      // 3. Try loading Logistic Regression
      try {
        _logregInterpreter = await Interpreter.fromAsset(
          'assets/models/model_logistic_regression.tflite',
          options: options,
        );
        _logregInterpreter!.allocateTensors();
        debugPrint('ClassifierService: [LOADED] Logistic Regression -> input ${_logregInterpreter!.getInputTensor(0).shape}');
      } catch (e) {
        debugPrint('ClassifierService: Logistic Regression optional asset note: $e');
      }

      _isTfliteLoaded = _cnnInterpreter != null || _gruInterpreter != null || _logregInterpreter != null;

      // Load labels
      try {
        final labelsStr = await rootBundle.loadString('assets/models/labels.txt');
        final lines = labelsStr
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          _targetClasses = lines;
        }
        debugPrint('ClassifierService: Target activity classes: $_targetClasses');
      } catch (labelErr) {
        debugPrint('ClassifierService: Using default labels: $_targetClasses ($labelErr)');
      }
    } catch (e, stack) {
      _isTfliteLoaded = false;
      debugPrint('ClassifierService: [WARN] Failed to initialize model suite: $e\n$stack');
    } finally {
      _isInitializing = false;
    }
  }

  /// Ingests an IMU sample from either the wrist or ankle band.
  void addSample(ImuSample sample) {
    if (sample.bandRole == BandRole.wrist) {
      _latestWrist = [sample.ax, sample.ay, sample.az, sample.gx, sample.gy, sample.gz];
      _hasWristData = true;
    } else {
      _latestAnkle = [sample.ax, sample.ay, sample.az, sample.gx, sample.gy, sample.gz];
      _hasAnkleData = true;
    }

    // Compute dynamic invariant Euclidean magnitudes
    final wAmag = sqrt(_latestWrist[0] * _latestWrist[0] +
        _latestWrist[1] * _latestWrist[1] +
        _latestWrist[2] * _latestWrist[2]);
    final wGmag = sqrt(_latestWrist[3] * _latestWrist[3] +
        _latestWrist[4] * _latestWrist[4] +
        _latestWrist[5] * _latestWrist[5]);

    final aAmag = sqrt(_latestAnkle[0] * _latestAnkle[0] +
        _latestAnkle[1] * _latestAnkle[1] +
        _latestAnkle[2] * _latestAnkle[2]);
    final aGmag = sqrt(_latestAnkle[3] * _latestAnkle[3] +
        _latestAnkle[4] * _latestAnkle[4] +
        _latestAnkle[5] * _latestAnkle[5]);

    // Construct 16-channel frame
    final frame = <double>[
      ..._latestWrist,
      ..._latestAnkle,
      wAmag,
      wGmag,
      aAmag,
      aGmag,
    ];

    addSynchronizedFrame(frame);
  }

  /// Ingests a synchronized frame (supports both 12-channel legacy and 16-channel invariant).
  void addSynchronizedFrame(List<double> frame) {
    List<double> frame16;
    if (frame.length == 12) {
      // Automatically derive 4 invariant magnitudes from 12 channels
      final wAmag = sqrt(frame[0] * frame[0] + frame[1] * frame[1] + frame[2] * frame[2]);
      final wGmag = sqrt(frame[3] * frame[3] + frame[4] * frame[4] + frame[5] * frame[5]);
      final aAmag = sqrt(frame[6] * frame[6] + frame[7] * frame[7] + frame[8] * frame[8]);
      final aGmag = sqrt(frame[9] * frame[9] + frame[10] * frame[10] + frame[11] * frame[11]);
      frame16 = [...frame, wAmag, wGmag, aAmag, aGmag];
    } else if (frame.length == channelCount) {
      frame16 = List<double>.from(frame);
    } else {
      return;
    }

    _windowBuffer.add(frame16);
    if (_windowBuffer.length > windowSize) {
      _windowBuffer.removeAt(0);
    }

    _samplesSinceLastInference++;

    // Trigger inference every stride (50 samples = 1.0 second stride)
    if (_windowBuffer.length == windowSize && _samplesSinceLastInference >= strideSize) {
      _samplesSinceLastInference = 0;
      _runInference();
    }
  }

  /// 4th-order Butterworth Direct Form I filter implementation matching scipy.signal.lfilter.
  static List<double> _butterworthFilter(List<double> signal) {
    final n = signal.length;
    final y = List<double>.filled(n, 0.0);
    for (var t = 0; t < n; t++) {
      var val = _b[0] * signal[t];
      for (var k = 1; k <= 4; k++) {
        if (t - k >= 0) {
          val += _b[k] * signal[t - k] - _a[k] * y[t - k];
        }
      }
      y[t] = val;
    }
    return y;
  }

  /// Preprocesses 100-sample window: unit check, Butterworth 15 Hz low-pass, and physical scaling.
  List<List<double>> _preprocessWindow(List<List<double>> rawWindow) {
    final nSamples = rawWindow.length;
    final processed = List.generate(
      nSamples,
      (_) => List<double>.filled(channelCount, 0.0),
    );

    // Check if accelerometer data is in m/s^2 (> 5.0) or g (~ 1.0)
    var wristNormSum = 0.0;
    for (var t = 0; t < nSamples; t++) {
      final f = rawWindow[t];
      wristNormSum += sqrt(f[0] * f[0] + f[1] * f[1] + f[2] * f[2]);
    }
    final avgWristNorm = wristNormSum / nSamples;
    final bool accelNeedsMs2Conversion = avgWristNorm > 5.0;

    for (var ch = 0; ch < channelCount; ch++) {
      final rawChannel = List<double>.generate(nSamples, (t) {
        var v = rawWindow[t][ch];
        // Accel channels: 0..2 (wrist), 6..8 (ankle), 12 (wrist_amag), 14 (ankle_amag)
        if (accelNeedsMs2Conversion && (ch < 3 || (ch >= 6 && ch < 9) || ch == 12 || ch == 14)) {
          v /= 9.80665;
        }
        return v;
      });

      final filteredChannel = _butterworthFilter(rawChannel);
      final scale = _scaleVector16[ch];
      for (var t = 0; t < nSamples; t++) {
        processed[t][ch] = filteredChannel[t] / scale;
      }
    }
    return processed;
  }

  /// Extracts 144 statistical and frequency features from a preprocessed [100, 16] window.
  List<double> _extract144Features(List<List<double>> window) {
    final nSamples = window.length;
    final features = <double>[];

    for (var ch = 0; ch < channelCount; ch++) {
      final col = List<double>.generate(nSamples, (t) => window[t][ch]);

      // 1. Mean
      final sum = col.reduce((a, b) => a + b);
      final mean = sum / nSamples;

      // 2. Variance & 3. Std
      var sumSqDiff = 0.0;
      var sumSq = 0.0;
      for (final v in col) {
        final d = v - mean;
        sumSqDiff += d * d;
        sumSq += v * v;
      }
      final variance = sumSqDiff / nSamples;
      final std = sqrt(variance);

      // 4. Peak-to-Peak (max - min)
      var cMin = col[0];
      var cMax = col[0];
      for (final v in col) {
        if (v < cMin) cMin = v;
        if (v > cMax) cMax = v;
      }
      final ptp = cMax - cMin;

      // 5. RMS
      final rms = sqrt(sumSq / nSamples);

      // 6. Median Absolute Deviation (MAD) & 7. IQR
      final sorted = List<double>.from(col)..sort();
      final median = sorted[nSamples ~/ 2];
      final absDevs = sorted.map((v) => (v - median).abs()).toList()..sort();
      final mad = absDevs[nSamples ~/ 2];

      final q25 = sorted[(nSamples * 0.25).floor()];
      final q75 = sorted[(nSamples * 0.75).floor()];
      final iqr = q75 - q25;

      // 8. Zero-Crossing Rate
      var zcrCount = 0;
      for (var i = 0; i < nSamples - 1; i++) {
        if ((col[i] * col[i + 1]) < 0) {
          zcrCount++;
        }
      }
      final zcr = zcrCount / (nSamples - 1.0);

      // 9. Dominant Frequency via DFT magnitude peak (1..49 bins, fs = 50 Hz)
      var maxDftMag = 0.0;
      var domFreq = 0.0;
      for (var k = 1; k < 50; k++) {
        var re = 0.0;
        var im = 0.0;
        final angle = (2.0 * pi * k) / nSamples;
        for (var n = 0; n < nSamples; n++) {
          final x = col[n] - mean;
          re += x * cos(angle * n);
          im -= x * sin(angle * n);
        }
        final mag = re * re + im * im;
        if (mag > maxDftMag) {
          maxDftMag = mag;
          domFreq = (k * 50.0) / nSamples;
        }
      }

      features.addAll([mean, std, variance, ptp, mad, rms, iqr, zcr, domFreq]);
    }

    return features;
  }

  void _runInference() {
    if (_windowBuffer.length < windowSize) return;

    if (_isTfliteLoaded) {
      try {
        final preprocessed = _preprocessWindow(_windowBuffer);

        // Collect outputs from loaded models
        List<double>? cnnProbs;
        List<double>? gruProbs;
        List<double>? lrProbs;

        // Run 1D-CNN
        if (_cnnInterpreter != null) {
          try {
            // Check required input shape
            final shape = _cnnInterpreter!.getInputTensor(0).shape;
            final inChannels = (shape.length == 3) ? shape[2] : 16;
            final tensorIn = [
              inChannels == 12
                  ? preprocessed.map((row) => row.sublist(0, 12)).toList()
                  : preprocessed
            ];
            final tensorOut = [List<double>.filled(_targetClasses.length, 0.0)];
            _cnnInterpreter!.run(tensorIn, tensorOut);
            cnnProbs = tensorOut[0];
          } catch (e) {
            debugPrint('ClassifierService: 1D-CNN error: $e');
          }
        }

        // Run Conv1D-GRU
        if (_gruInterpreter != null) {
          try {
            final tensorIn = [preprocessed];
            final tensorOut = [List<double>.filled(_targetClasses.length, 0.0)];
            _gruInterpreter!.run(tensorIn, tensorOut);
            gruProbs = tensorOut[0];
          } catch (e) {
            debugPrint('ClassifierService: Conv1D-GRU error: $e');
          }
        }

        // Run Logistic Regression (on 144 features)
        if (_logregInterpreter != null) {
          try {
            final feats144 = _extract144Features(preprocessed);
            final tensorIn = [feats144];
            final tensorOut = [List<double>.filled(_targetClasses.length, 0.0)];
            _logregInterpreter!.run(tensorIn, tensorOut);
            lrProbs = tensorOut[0];
          } catch (e) {
            debugPrint('ClassifierService: LogReg error: $e');
          }
        }

        // Determine prediction based on active model
        List<double> finalProbs;
        HarModelType usedModel = _activeModel;

        switch (_activeModel) {
          case HarModelType.cnn1d:
            finalProbs = cnnProbs ?? gruProbs ?? lrProbs ?? [];
            break;
          case HarModelType.convGru:
            finalProbs = gruProbs ?? cnnProbs ?? lrProbs ?? [];
            break;
          case HarModelType.logisticRegression:
            finalProbs = lrProbs ?? cnnProbs ?? gruProbs ?? [];
            break;
          case HarModelType.ensembleMajority:
            final availableOutputs = [cnnProbs, gruProbs, lrProbs]
                .whereType<List<double>>()
                .toList();
            if (availableOutputs.isNotEmpty) {
              final avg = List<double>.filled(_targetClasses.length, 0.0);
              for (final out in availableOutputs) {
                for (var i = 0; i < avg.length; i++) {
                  avg[i] += out[i] / availableOutputs.length;
                }
              }
              finalProbs = avg;
            } else {
              finalProbs = [];
            }
            break;
        }

        if (finalProbs.isNotEmpty) {
          var maxIdx = 0;
          var maxProb = finalProbs[0];
          for (var i = 1; i < finalProbs.length; i++) {
            if (finalProbs[i] > maxProb) {
              maxProb = finalProbs[i];
              maxIdx = i;
            }
          }

          var label = (maxIdx >= 0 && maxIdx < _targetClasses.length)
              ? _targetClasses[maxIdx]
              : 'Unknown';

          // ── Window Kinematics & Sitting vs Standing Energy Gate ──
          final nSamples = _windowBuffer.length;
          var rawWristNormSum = 0.0;
          for (final frame in _windowBuffer) {
            final wAmag = frame.length >= 16
                ? frame[12]
                : sqrt(frame[0] * frame[0] + frame[1] * frame[1] + frame[2] * frame[2]);
            rawWristNormSum += wAmag;
          }
          final isMs2 = (rawWristNormSum / nSamples) > 5.0;
          final gScale = isMs2 ? (1.0 / 9.80665) : 1.0;

          var wristAmagSum = 0.0;
          var ankleAmagSum = 0.0;
          var wristGmagSum = 0.0;
          final wAmags = List<double>.filled(nSamples, 0.0);
          final aAmags = List<double>.filled(nSamples, 0.0);

          for (var i = 0; i < nSamples; i++) {
            final frame = _windowBuffer[i];
            final wAmag = (frame.length >= 16
                ? frame[12]
                : sqrt(frame[0] * frame[0] + frame[1] * frame[1] + frame[2] * frame[2])) * gScale;
            final aAmag = (frame.length >= 16
                ? frame[14]
                : sqrt(frame[6] * frame[6] + frame[7] * frame[7] + frame[8] * frame[8])) * gScale;
            final wGmag = frame.length >= 16
                ? frame[13]
                : sqrt(frame[3] * frame[3] + frame[4] * frame[4] + frame[5] * frame[5]);

            wAmags[i] = wAmag;
            aAmags[i] = aAmag;
            wristAmagSum += wAmag;
            ankleAmagSum += aAmag;
            wristGmagSum += wGmag;
          }

          final wAmagMean = wristAmagSum / nSamples;
          final aAmagMean = ankleAmagSum / nSamples;
          final wristGyroMean = wristGmagSum / nSamples;

          var wAmagVar = 0.0;
          var aAmagVar = 0.0;
          for (var i = 0; i < nSamples; i++) {
            final dw = wAmags[i] - wAmagMean;
            final da = aAmags[i] - aAmagMean;
            wAmagVar += dw * dw;
            aAmagVar += da * da;
          }
          final wristAccStd = sqrt(wAmagVar / nSamples);
          final ankleAccStd = sqrt(aAmagVar / nSamples);

          // Post-processing energy gate to separate Sitting from Standing Hand Movement
          if (ankleAccStd < 0.04 && wristAccStd < 0.12 && wristGyroMean < 45.0) {
            // Ankle is stationary and wrist movement is below dynamic gesturing threshold:
            final sittingIdx = _targetClasses.indexOf('Sitting');
            final standingIdx = _targetClasses.indexOf('Standing_HandMove');
            if (maxIdx == standingIdx || label == 'Standing_HandMove') {
              if (sittingIdx != -1) {
                maxIdx = sittingIdx;
                label = 'Sitting';
                maxProb = 0.98;
                for (var i = 0; i < finalProbs.length; i++) {
                  finalProbs[i] = (i == sittingIdx) ? 0.98 : (0.02 / max(1, finalProbs.length - 1));
                }
              }
            }
          }

          // Check model consensus / disagreement
          var hasDisagreement = false;
          if (cnnProbs != null && gruProbs != null) {
            final cnnTop = _argmax(cnnProbs);
            final gruTop = _argmax(gruProbs);
            if (cnnTop != gruTop) hasDisagreement = true;
          }
          if (cnnProbs != null && lrProbs != null) {
            final cnnTop = _argmax(cnnProbs);
            final lrTop = _argmax(lrProbs);
            if (cnnTop != lrTop) hasDisagreement = true;
          }

          final probMap = <String, double>{};
          for (var i = 0; i < _targetClasses.length; i++) {
            probMap[_targetClasses[i]] = finalProbs[i];
          }

          final prediction = ActivityPrediction(
            label: label,
            confidence: maxProb.clamp(0.0, 1.0),
            timestamp: DateTime.now(),
            modelType: usedModel,
            classProbabilities: probMap,
            isHighConfidence: maxProb >= 0.85,
            hasDisagreement: hasDisagreement,
          );

          debugPrint('ClassifierService [${usedModel.displayName}]: $label (${(maxProb * 100).toStringAsFixed(1)}%) | HighConf: ${prediction.isHighConfidence}');

          _lastPrediction = prediction;
          _predictionController.add(prediction);
          return;
        }
      } catch (e, stack) {
        debugPrint('ClassifierService [RUNTIME ERROR]: $e\n$stack\nFalling back to heuristic engine.');
      }
    }

    // ── Heuristic Fallback Engine ──
    _runHeuristicInference();
  }

  int _argmax(List<double> list) {
    var maxIdx = 0;
    var maxVal = list[0];
    for (var i = 1; i < list.length; i++) {
      if (list[i] > maxVal) {
        maxVal = list[i];
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  void _runHeuristicInference() {
    final wristMagnitudes = <double>[];
    final ankleMagnitudes = <double>[];

    var rawWristNormSum = 0.0;
    for (final frame in _windowBuffer) {
      rawWristNormSum += sqrt(frame[0] * frame[0] + frame[1] * frame[1] + frame[2] * frame[2]);
    }
    final isMs2 = (rawWristNormSum / _windowBuffer.length) > 5.0;

    for (final frame in _windowBuffer) {
      // In 16-channel layout: frame[12] is wAmag, frame[14] is aAmag
      var wMag = (frame.length >= 16)
          ? frame[12]
          : sqrt(frame[0] * frame[0] + frame[1] * frame[1] + frame[2] * frame[2]);
      var aMag = (frame.length >= 16)
          ? frame[14]
          : sqrt(frame[6] * frame[6] + frame[7] * frame[7] + frame[8] * frame[8]);

      if (isMs2) {
        wMag /= 9.80665;
        aMag /= 9.80665;
      }
      wristMagnitudes.add(wMag);
      ankleMagnitudes.add(aMag);
    }

    final wristVar = _variance(wristMagnitudes);
    final ankleVar = _variance(ankleMagnitudes);
    final wristPeak = wristMagnitudes.reduce(max);
    final anklePeak = ankleMagnitudes.reduce(max);
    final wristAccStd = sqrt(wristVar);
    final ankleAccStd = sqrt(ankleVar);

    var wristGmagSum = 0.0;
    for (final frame in _windowBuffer) {
      final wGmag = frame.length >= 16
          ? frame[13]
          : sqrt(frame[3] * frame[3] + frame[4] * frame[4] + frame[5] * frame[5]);
      wristGmagSum += wGmag;
    }
    final wristGyroMean = wristGmagSum / _windowBuffer.length;

    String label;
    double confidence;

    // Disambiguation energy gate:
    if (ankleAccStd < 0.04 && wristAccStd < 0.12 && wristGyroMean < 45.0) {
      label = 'Sitting';
      confidence = 0.98;
    } else if (anklePeak > 1.8 && wristPeak > 1.5) {
      label = _targetClasses.contains('Jumping') ? 'Jumping' : 'Jumping_Jacks';
      confidence = 0.92;
    } else if (ankleVar < 0.02 && wristVar < 0.04) {
      label = 'Sitting';
      confidence = 0.95;
    } else if (ankleVar < 0.04 && (wristVar >= 0.08 || wristGyroMean >= 90.0)) {
      label = 'Standing_HandMove';
      confidence = 0.90;
    } else {
      label = 'Walking';
      confidence = 0.88;
    }

    final probMap = <String, double>{
      for (final c in _targetClasses) c: (c == label ? confidence : (1.0 - confidence) / 3.0)
    };

    final prediction = ActivityPrediction(
      label: label,
      confidence: confidence,
      timestamp: DateTime.now(),
      modelType: HarModelType.ensembleMajority,
      classProbabilities: probMap,
      isHighConfidence: confidence >= 0.85,
      hasDisagreement: false,
    );

    _lastPrediction = prediction;
    _predictionController.add(prediction);
  }

  double _variance(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sumSq = 0.0;
    for (final v in values) {
      final diff = v - mean;
      sumSq += diff * diff;
    }
    return sumSq / values.length;
  }

  /// Resets internal buffers for a new session.
  void reset() {
    _windowBuffer.clear();
    _samplesSinceLastInference = 0;
    _latestWrist = List.filled(6, 0.0);
    _latestAnkle = List.filled(6, 0.0);
    _hasWristData = false;
    _hasAnkleData = false;
    _lastPrediction = ActivityPrediction(
      label: 'Sitting',
      confidence: 0.95,
      timestamp: DateTime.now(),
      modelType: _activeModel,
    );
  }

  void dispose() {
    _cnnInterpreter?.close();
    _gruInterpreter?.close();
    _logregInterpreter?.close();
    _predictionController.close();
    _activeModelController.close();
  }
}
