import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/imu_sample.dart';
import '../../models/prediction_result.dart';
import '../../services/ble_service.dart';
import '../../services/ml_service.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/confidence_gauge.dart';

/// Live Mode screen – real-time activity classification.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final _ble = getIt<BleService>();
  final _ml = getIt<MlService>();

  // ── State ──
  bool _isRunning = false;
  PredictionResult? _currentPrediction;
  final List<PredictionResult> _history = [];
  final List<ImuSample> _wristWindowBuffer = [];
  final List<ImuSample> _ankleWindowBuffer = [];

  StreamSubscription<ImuSample>? _wristSensorSub;
  StreamSubscription<ImuSample>? _ankleSensorSub;
  StreamSubscription<BandConnectionState>? _wristBleSub;
  StreamSubscription<BandConnectionState>? _ankleBleSub;
  BandConnectionState _wristBleState = BandConnectionState.disconnected;
  BandConnectionState _ankleBleState = BandConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _wristBleState = _ble.wrist.currentState;
    _ankleBleState = _ble.ankle.currentState;
    _wristBleSub = _ble.wrist.stateStream.listen((state) {
      if (mounted) setState(() => _wristBleState = state);
    });
    _ankleBleSub = _ble.ankle.stateStream.listen((state) {
      if (mounted) setState(() => _ankleBleState = state);
    });
  }

  @override
  void dispose() {
    _wristSensorSub?.cancel();
    _ankleSensorSub?.cancel();
    _wristBleSub?.cancel();
    _ankleBleSub?.cancel();
    super.dispose();
  }

  void _start() {
    if (!_ml.isTrained) return;
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;
    if (!hasWrist && !hasAnkle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect at least one band first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isRunning = true);

    if (hasWrist) {
      _wristSensorSub = _ble.wrist.sensorStream.listen(_onWristSensorData);
    }
    if (hasAnkle) {
      _ankleSensorSub = _ble.ankle.sensorStream.listen(_onAnkleSensorData);
    }
  }

  void _stop() {
    _wristSensorSub?.cancel();
    _wristSensorSub = null;
    _ankleSensorSub?.cancel();
    _ankleSensorSub = null;
    _wristWindowBuffer.clear();
    _ankleWindowBuffer.clear();
    if (mounted) setState(() => _isRunning = false);
  }

  void _onWristSensorData(ImuSample sample) {
    _wristWindowBuffer.add(sample);
    _tryPredict();
  }

  void _onAnkleSensorData(ImuSample sample) {
    _ankleWindowBuffer.add(sample);
    _tryPredict();
  }

  void _tryPredict() {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    // Wait for both bands if both connected, otherwise use available one
    final wristReady = !hasWrist || _wristWindowBuffer.length >= BleConstants.windowSize;
    final ankleReady = !hasAnkle || _ankleWindowBuffer.length >= BleConstants.windowSize;

    if (!wristReady || !ankleReady) return;

    List<double> features;
    if (hasWrist && hasAnkle) {
      // Use combined features (60-dim)
      final wristWindow = List<ImuSample>.from(_wristWindowBuffer);
      final ankleWindow = List<ImuSample>.from(_ankleWindowBuffer);
      _wristWindowBuffer.clear();
      _ankleWindowBuffer.clear();
      features = MlService.extractCombinedFeatures(
        wristWindow: wristWindow,
        ankleWindow: ankleWindow,
      );
    } else if (hasWrist) {
      final window = List<ImuSample>.from(_wristWindowBuffer);
      _wristWindowBuffer.clear();
      features = MlService.extractFeaturesFromImuSamples(window);
    } else {
      final window = List<ImuSample>.from(_ankleWindowBuffer);
      _ankleWindowBuffer.clear();
      features = MlService.extractFeaturesFromImuSamples(window);
    }

    final result = _ml.predictFromFeatures(features);
    if (result != null && mounted) {
      setState(() {
        _currentPrediction = result;
        _history.insert(0, result);
        if (_history.length > 20) _history.removeLast();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          _buildBandStatusChip(theme, BandRole.wrist, _wristBleState),
          const SizedBox(width: 4),
          _buildBandStatusChip(theme, BandRole.ankle, _ankleBleState),
          const SizedBox(width: 8),
        ],
      ),
      body: !_ml.isTrained
          ? _buildNotTrainedView(theme)
          : Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                children: [
                  // ── Band Status Row ──
                  if (hasWrist || hasAnkle) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        child: Row(
                          children: [
                            if (hasWrist) ...[
                              _buildBandInfoChip(theme, BandRole.wrist, _wristBleState),
                              const SizedBox(width: 8),
                            ],
                            if (hasAnkle) ...[
                              _buildBandInfoChip(theme, BandRole.ankle, _ankleBleState),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                  ],

                  // ── Main prediction display ──
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: Center(
                        child: _currentPrediction == null
                            ? _buildWaitingView(theme)
                            : _buildPredictionView(theme),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),

                  // ── Start / Stop ──
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _isRunning ? _stop : _start,
                      icon: Icon(
                        _isRunning ? Icons.stop : Icons.play_arrow,
                      ),
                      label: Text(
                        _isRunning ? 'Stop Inference' : 'Start Inference',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _isRunning
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                        foregroundColor: _isRunning
                            ? theme.colorScheme.onError
                            : theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),

                  // ── Prediction History ──
                  if (_history.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent Predictions',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Expanded(
                      flex: 2,
                      child: ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          final pred = _history[index];
                          final timeStr =
                              '${pred.timestamp.hour.toString().padLeft(2, '0')}:'
                              '${pred.timestamp.minute.toString().padLeft(2, '0')}:'
                              '${pred.timestamp.second.toString().padLeft(2, '0')}';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              ActivityCard.iconForLabel(pred.label),
                              color: ActivityCard.colorsForLabel(pred.label)[0],
                            ),
                            title: Text(pred.label),
                            trailing: Text(
                              timeStr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildNotTrainedView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.model_training,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Model Not Trained',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Record some activities in the Record tab, then train '
              'the model from the Dashboard before using Live mode.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingView(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConfidenceGauge(
          confidence: 0,
          child: Icon(
            Icons.sensors,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isRunning ? 'Waiting for data…' : 'Press Start to begin',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionView(ThemeData theme) {
    final pred = _currentPrediction!;
    final colors = ActivityCard.colorsForLabel(pred.label);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConfidenceGauge(
          confidence: pred.confidence,
          size: 180,
          child: Icon(
            ActivityCard.iconForLabel(pred.label),
            size: 36,
            color: colors[0],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          pred.label,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors[0],
          ),
        ),
      ],
    );
  }

  Widget _buildBandStatusChip(
    ThemeData theme,
    BandRole role,
    BandConnectionState state,
  ) {
    final (color, label, icon) = switch (state) {
      BandConnectionState.connected => (role.color, role.displayName, role.icon),
      BandConnectionState.scanning => (Colors.blue, 'Scanning', Icons.bluetooth_searching),
      BandConnectionState.connecting => (Colors.orange, 'Connecting', Icons.bluetooth),
      BandConnectionState.disconnected => (theme.colorScheme.outline, role.displayName, role.icon),
    };

    return Tooltip(
      message: '$label: ${state.name}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandInfoChip(ThemeData theme, BandRole role, BandConnectionState state) {
    final isConnected = state == BandConnectionState.connected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: isConnected ? 0.2 : 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: role.color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, size: 16, color: role.color),
          const SizedBox(width: 6),
          Text(
            '${role.displayName}: ${isConnected ? 'Connected' : 'Disconnected'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: role.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}