import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../features/record/session_detail_screen.dart';
import '../../models/imu_sample.dart' as model;
import '../../models/sensor_data.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../widgets/sensor_chart.dart';

/// Record Mode screen – tag and record IMU data streams with activity labels.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with SingleTickerProviderStateMixin {
  final _ble = getIt<BleService>();
  final _db = getIt<DatabaseService>();

  // ── Recording state ──
  String _selectedLabel = BleConstants.defaultLabels.first;
  String _sessionNotes = '';
  bool _isRecording = false;
  int? _sessionId;
  int _wristSampleCount = 0;
  int _ankleSampleCount = 0;

  // ── Sensor buffers ──
  final List<model.ImuSample> _wristChartBuffer = [];
  final List<model.ImuSample> _ankleChartBuffer = [];
  final List<model.ImuSample> _wristWindowBuffer = [];
  final List<model.ImuSample> _ankleWindowBuffer = [];
  final List<model.ImuSample> _wristPendingDbWrite = [];
  final List<model.ImuSample> _anklePendingDbWrite = [];

  // Maximum pending writes before we log overflow (prevents unbounded memory growth)
  static const int _maxPendingWrites = 5000;

  StreamSubscription<model.ImuSample>? _wristSensorSub;
  StreamSubscription<model.ImuSample>? _ankleSensorSub;
  StreamSubscription<BandConnectionState>? _wristBleSub;
  StreamSubscription<BandConnectionState>? _ankleBleSub;
  BandConnectionState _wristBleState = BandConnectionState.disconnected;
  BandConnectionState _ankleBleState = BandConnectionState.disconnected;

  // ── Animation ──
  late AnimationController _pulseController;

  // ── Performance tracking ──
  int _wristPacketsReceived = 0;
  int _anklePacketsReceived = 0;
  int _wristMalformedPackets = 0;
  int _ankleMalformedPackets = 0;
  DateTime? _recordingStartTime;

  // Diagnostics for 50 Hz validation
  Timer? _diagnosticsTimer;
  DateTime? _lastWristSampleTime;
  DateTime? _lastAnkleSampleTime;
  final List<int> _wristIntervals = [];
  final List<int> _ankleIntervals = [];
  static const int _maxIntervalSamples = 500; // Keep last 500 intervals (~10 sec at 50 Hz)

  // Flag to prevent DB writes after recording stops
  bool _recordingStopped = false;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Periodic DB flush
    _startDbFlushTimer();

    // Periodic diagnostics (every 5 seconds during recording)
    _startDiagnosticsTimer();
  }

  void _startDiagnosticsTimer() {
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isRecording && !_recordingStopped) {
        _logSamplingDiagnostics();
      }
    });
  }

  void _logSamplingDiagnostics() {
    // Wrist diagnostics
    if (_wristIntervals.isNotEmpty) {
      final avgWristInterval = _wristIntervals.reduce((a, b) => a + b) / _wristIntervals.length;
      final minWristInterval = _wristIntervals.reduce((a, b) => a < b ? a : b);
      final maxWristInterval = _wristIntervals.reduce((a, b) => a > b ? a : b);
      final wristHz = 1000.0 / avgWristInterval;
      debugPrint('DIAG Wrist: avg=${avgWristInterval.toStringAsFixed(1)}ms (${wristHz.toStringAsFixed(1)} Hz) '
                 'min=${minWristInterval}ms max=${maxWristInterval}ms samples=${_wristPacketsReceived}');
    }

    // Ankle diagnostics
    if (_ankleIntervals.isNotEmpty) {
      final avgAnkleInterval = _ankleIntervals.reduce((a, b) => a + b) / _ankleIntervals.length;
      final minAnkleInterval = _ankleIntervals.reduce((a, b) => a < b ? a : b);
      final maxAnkleInterval = _ankleIntervals.reduce((a, b) => a > b ? a : b);
      final ankleHz = 1000.0 / avgAnkleInterval;
      debugPrint('DIAG Ankle: avg=${avgAnkleInterval.toStringAsFixed(1)}ms (${ankleHz.toStringAsFixed(1)} Hz) '
                 'min=${minAnkleInterval}ms max=${maxAnkleInterval}ms samples=${_anklePacketsReceived}');
    }

    // Combined
    final totalSamples = _wristPacketsReceived + _anklePacketsReceived;
    if (_recordingStartTime != null) {
      final elapsedSec = DateTime.now().difference(_recordingStartTime!).inSeconds;
      if (elapsedSec > 0) {
        final combinedHz = totalSamples / elapsedSec;
        debugPrint('DIAG Combined: ${combinedHz.toStringAsFixed(1)} Hz total ($totalSamples samples in ${elapsedSec}s)');
      }
    }
  }

  Timer? _dbFlushTimer;
  void _startDbFlushTimer() {
    _dbFlushTimer?.cancel();
    _dbFlushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_recordingStopped) _flushDbBuffers();
    });
  }

  Future<void> _flushDbBuffers() async {
    if (_sessionId == null) return;
    if (_wristPendingDbWrite.isEmpty && _anklePendingDbWrite.isEmpty) return;
    // Don't flush if recording has been stopped
    if (_recordingStopped) return;

    final wristToWrite = List<model.ImuSample>.from(_wristPendingDbWrite);
    final ankleToWrite = List<model.ImuSample>.from(_anklePendingDbWrite);
    _wristPendingDbWrite.clear();
    _anklePendingDbWrite.clear();

    await Future.wait([
      _db.insertImuSamples(sessionId: _sessionId!, samples: wristToWrite),
      _db.insertImuSamples(sessionId: _sessionId!, samples: ankleToWrite),
    ]);
  }

  @override
  void dispose() {
    // Cancel flush timer first to prevent new flushes
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;

    // Cancel diagnostics timer
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;

    // Prevent any new DB writes
    _recordingStopped = true;

    // Flush any remaining data (fire and forget - dispose can't be async)
    _flushDbBuffers();

    // Cancel sensor subscriptions
    _wristSensorSub?.cancel();
    _ankleSensorSub?.cancel();
    _wristBleSub?.cancel();
    _ankleBleSub?.cancel();

    _pulseController.dispose();
    super.dispose();
  }

  void _startRecording() async {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    if (!hasWrist && !hasAnkle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect at least one band (Wrist or Ankle) first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Create a new session in the DB.
    final sessionId = await _db.createSession(_selectedLabel);

    // Save notes if provided
    if (_sessionNotes.isNotEmpty) {
      await _db.updateSessionNotes(sessionId, _sessionNotes);
    }

    setState(() {
      _isRecording = true;
      _sessionId = sessionId;
      _wristSampleCount = 0;
      _ankleSampleCount = 0;
      _wristWindowBuffer.clear();
      _ankleWindowBuffer.clear();
      _wristChartBuffer.clear();
      _ankleChartBuffer.clear();
      _wristPendingDbWrite.clear();
      _anklePendingDbWrite.clear();
      _wristPacketsReceived = 0;
      _anklePacketsReceived = 0;
      _wristMalformedPackets = 0;
      _ankleMalformedPackets = 0;
      _recordingStartTime = DateTime.now();
      _lastWristSampleTime = null;
      _lastAnkleSampleTime = null;
      _wristIntervals.clear();
      _ankleIntervals.clear();
      _recordingStopped = false; // Reset flag for new recording
    });

    _pulseController.repeat(reverse: true);

    // Start flush timer
    _startDbFlushTimer();

    // Subscribe to wrist sensor stream
    if (hasWrist) {
      _wristSensorSub = _ble.wrist.sensorStream.listen(_onWristSensorData);
    }
    // Subscribe to ankle sensor stream
    if (hasAnkle) {
      _ankleSensorSub = _ble.ankle.sensorStream.listen(_onAnkleSensorData);
    }
  }

  void _onWristSensorData(model.ImuSample sample) {
    if (!_isRecording || _recordingStopped) return;

    // Track sampling interval for diagnostics
    final now = sample.timestamp;
    if (_lastWristSampleTime != null) {
      final interval = now.difference(_lastWristSampleTime!).inMilliseconds;
      _wristIntervals.add(interval);
      if (_wristIntervals.length > _maxIntervalSamples) {
        _wristIntervals.removeAt(0);
      }
    }
    _lastWristSampleTime = now;

    _wristPacketsReceived++;
    setState(() {
      _wristChartBuffer.add(sample);
      if (_wristChartBuffer.length > 100) _wristChartBuffer.removeAt(0);
    });

    // Bounded pending writes with overflow logging
    if (_wristPendingDbWrite.length >= _maxPendingWrites) {
      debugPrint('Record: Wrist pending DB write buffer overflow (${_wristPendingDbWrite.length} samples), dropping oldest');
      _wristPendingDbWrite.removeRange(0, _wristPendingDbWrite.length - _maxPendingWrites + 1);
    }
    _wristPendingDbWrite.add(sample);

    _wristWindowBuffer.add(sample);

    if (_wristWindowBuffer.length >= BleConstants.windowSize) {
      _processWristWindow();
    }
  }

  void _onAnkleSensorData(model.ImuSample sample) {
    if (!_isRecording || _recordingStopped) return;

    // Track sampling interval for diagnostics
    final now = sample.timestamp;
    if (_lastAnkleSampleTime != null) {
      final interval = now.difference(_lastAnkleSampleTime!).inMilliseconds;
      _ankleIntervals.add(interval);
      if (_ankleIntervals.length > _maxIntervalSamples) {
        _ankleIntervals.removeAt(0);
      }
    }
    _lastAnkleSampleTime = now;

    _anklePacketsReceived++;
    setState(() {
      _ankleChartBuffer.add(sample);
      if (_ankleChartBuffer.length > 100) _ankleChartBuffer.removeAt(0);
    });

    // Bounded pending writes with overflow logging
    if (_anklePendingDbWrite.length >= _maxPendingWrites) {
      debugPrint('Record: Ankle pending DB write buffer overflow (${_anklePendingDbWrite.length} samples), dropping oldest');
      _anklePendingDbWrite.removeRange(0, _anklePendingDbWrite.length - _maxPendingWrites + 1);
    }
    _anklePendingDbWrite.add(sample);

    _ankleWindowBuffer.add(sample);

    if (_ankleWindowBuffer.length >= BleConstants.windowSize) {
      _processAnkleWindow();
    }
  }

  Future<void> _processWristWindow() async {
    if (_sessionId == null || _recordingStopped) return;

    final window = List<model.ImuSample>.from(_wristWindowBuffer);
    _wristWindowBuffer.clear();

    final features = MlService.extractFeaturesFromImuSamples(window);

    await _db.insertWindow(
      sessionId: _sessionId!,
      featureVector: features,
      label: _selectedLabel,
      bandRole: BandRole.wrist,
    );

    if (mounted) {
      setState(() => _wristSampleCount++);
    }
  }

  Future<void> _processAnkleWindow() async {
    if (_sessionId == null || _recordingStopped) return;

    final window = List<model.ImuSample>.from(_ankleWindowBuffer);
    _ankleWindowBuffer.clear();

    final features = MlService.extractFeaturesFromImuSamples(window);

    await _db.insertWindow(
      sessionId: _sessionId!,
      featureVector: features,
      label: _selectedLabel,
      bandRole: BandRole.ankle,
    );

    if (mounted) {
      setState(() => _ankleSampleCount++);
    }
  }

  Future<void> _stopRecording({bool showSnackbar = true}) async {
    // Log final diagnostics before stopping
    _logSamplingDiagnostics();

    // Prevent new sensor data from being processed
    _recordingStopped = true;

    // Cancel flush timer to prevent new flushes
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;

    // Cancel diagnostics timer
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;

    _wristSensorSub?.cancel();
    _wristSensorSub = null;
    _ankleSensorSub?.cancel();
    _ankleSensorSub = null;
    _pulseController.stop();
    _pulseController.reset();

    // Flush any remaining data (will respect _recordingStopped flag)
    await _flushDbBuffers();

    // Capture sessionId before clearing state
    final completedSessionId = _sessionId;

    if (completedSessionId != null) {
      final totalSamples = _wristSampleCount + _ankleSampleCount;
      await _db.endSession(completedSessionId, totalSamples);
    }

    if (showSnackbar && mounted && completedSessionId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Session saved: $_selectedLabel – '
            'Wrist: $_wristSampleCount windows, Ankle: $_ankleSampleCount windows.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _sessionId = null;
        _sessionNotes = '';
      });
    }

    // Navigate to session detail screen
    if (mounted && completedSessionId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionDetailScreen(sessionId: completedSessionId),
        ),
      );
    }
  }

  String _formatRate(int count, {bool isWindow = false}) {
    if (_recordingStartTime == null) return '0/s';
    final elapsed = DateTime.now().difference(_recordingStartTime!).inSeconds;
    if (elapsed == 0) return '0/s';
    if (isWindow) {
      return '${(count / elapsed).toStringAsFixed(1)}/s';
    }
    return '${(count / elapsed).toStringAsFixed(1)} Hz';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record'),
        actions: [
          _buildBandStatusChip(theme, BandRole.wrist, _wristBleState),
          const SizedBox(width: 4),
          _buildBandStatusChip(theme, BandRole.ankle, _ankleBleState),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          children: [
            // ── Label Selector ──
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMd,
                  vertical: AppTheme.spacingSm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.label_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLabel,
                          isExpanded: true,
                          onChanged: _isRecording
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _selectedLabel = value);
                                  }
                                },
                          items: BleConstants.defaultLabels.map((label) {
                            return DropdownMenuItem(
                              value: label,
                              child: Text(label),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Session Notes (optional) ──
            if (!_isRecording)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.notes_outlined,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Session Notes (Optional)',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingSm),
                      TextField(
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Add context about this recording session...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          contentPadding: const EdgeInsets.all(AppTheme.spacingMd),
                          isDense: true,
                        ),
                        onChanged: (value) => _sessionNotes = value,
                      ),
                    ],
                  ),
                ),
              ),
            if (!_isRecording) const SizedBox(height: AppTheme.spacingMd),

            // ── Stats Bar ──
            if (_isRecording)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd,
                      vertical: AppTheme.spacingSm,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.3 + _pulseController.value * 0.3,
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.fiber_manual_record,
                              color: theme.colorScheme.error,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Recording: $_selectedLabel',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (_sessionId != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Session ID: $_sessionId',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Wrist: $_wristSampleCount windows, ${_formatRate(_wristPacketsReceived)} samples',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: BandRole.wrist.color,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Ankle: $_ankleSampleCount windows, ${_formatRate(_anklePacketsReceived)} samples',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: BandRole.ankle.color,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: AppTheme.spacingMd),

            // ── Real-time Charts ──
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                  child: Column(
                    children: [
                      // Wrist Chart
                      if (hasWrist) ...[
                        _buildChartSection(
                          theme,
                          'Wrist',
                          BandRole.wrist.color,
                          _wristChartBuffer,
                          _wristBleState,
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Ankle Chart
                      if (hasAnkle) ...[
                        _buildChartSection(
                          theme,
                          'Ankle',
                          BandRole.ankle.color,
                          _ankleChartBuffer,
                          _ankleBleState,
                        ),
                      ],
                      if (!hasWrist && !hasAnkle) ...[
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isRecording
                                    ? 'Waiting for data…'
                                    : 'Connect bands and start recording to see charts',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Performance Stats ──
            if (_isRecording) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Performance',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _buildStatChip(
                            theme,
                            'Wrist RX',
                            '$_wristPacketsReceived (${_formatRate(_wristPacketsReceived)})',
                            BandRole.wrist.color,
                          ),
                          _buildStatChip(
                            theme,
                            'Ankle RX',
                            '$_anklePacketsReceived (${_formatRate(_anklePacketsReceived)})',
                            BandRole.ankle.color,
                          ),
                          if (_wristMalformedPackets > 0)
                            _buildStatChip(
                              theme,
                              'Wrist Bad',
                              '$_wristMalformedPackets',
                              Colors.orange,
                            ),
                          if (_ankleMalformedPackets > 0)
                            _buildStatChip(
                              theme,
                              'Ankle Bad',
                              '$_ankleMalformedPackets',
                              Colors.orange,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

            // ── Start / Stop Button ──
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _isRecording ? _stopRecording : _startRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                label: Text(
                  _isRecording ? 'Stop Recording' : 'Start Recording',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _isRecording
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  foregroundColor: _isRecording
                      ? theme.colorScheme.onError
                      : theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandStatusChip(
    ThemeData theme,
    BandRole role,
    BandConnectionState state,
  ) {
    final (color, label, icon) = switch (state) {
      BandConnectionState.connected => (
          role.color,
          role.displayName,
          role.icon,
        ),
      BandConnectionState.scanning => (
          Colors.blue,
          'Scanning',
          Icons.bluetooth_searching,
        ),
      BandConnectionState.connecting => (
          Colors.orange,
          'Connecting',
          Icons.bluetooth,
        ),
      BandConnectionState.disconnected => (
          theme.colorScheme.outline,
          role.displayName,
          role.icon,
        ),
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

  Widget _buildChartSection(
    ThemeData theme,
    String title,
    Color color,
    List<model.ImuSample> buffer,
    BandConnectionState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '$title (${buffer.length} samples)',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getStateColor(state).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getStateLabel(state),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _getStateColor(state),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: buffer.isEmpty
              ? Center(
                  child: Text(
                    state == BandConnectionState.connected
                        ? 'Waiting for data…'
                        : 'Connect $title band',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : SensorChart(
                  readings: buffer.map((s) => SensorReading(
                        ax: s.ax,
                        ay: s.ay,
                        az: s.az,
                        gx: s.gx,
                        gy: s.gy,
                        gz: s.gz,
                        timestamp: s.timestamp,
                      )).toList(),
                  maxPoints: 100,
                  showGyro: true,
                ),
        ),
      ],
    );
  }

  Color _getStateColor(BandConnectionState state) => switch (state) {
        BandConnectionState.connected => Colors.green,
        BandConnectionState.scanning => Colors.blue,
        BandConnectionState.connecting => Colors.orange,
        BandConnectionState.disconnected => Colors.red,
      };

  String _getStateLabel(BandConnectionState state) => switch (state) {
        BandConnectionState.connected => 'Connected',
        BandConnectionState.scanning => 'Scanning',
        BandConnectionState.connecting => 'Connecting',
        BandConnectionState.disconnected => 'Disconnected',
      };

  Widget _buildStatChip(
    ThemeData theme,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}