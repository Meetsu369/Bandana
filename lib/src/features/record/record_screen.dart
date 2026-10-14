import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../features/record/session_detail_screen.dart';
import '../../models/imu_sample.dart' as model;
import '../../models/sensor_data.dart';
import '../../services/activity_label_manager.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../utils/cadence_gate.dart';
import '../../utils/dual_band_window_manager.dart';
import '../../utils/session_boundary.dart';
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
  final _labelManager = getIt<ActivityLabelManager>();

  // ── Session Setup & Recording state ──
  String _selectedLabel = BleConstants.defaultLabels.first;
  String _participantId = 'participant_1';
  final _participantController = TextEditingController(text: 'participant_1');
  String _sessionNotes = '';
  bool _isRecording = false;
  int? _sessionId;
  int _wristSampleCount = 0;
  int _ankleSampleCount = 0;

  // ── Sensor buffers ──
  final List<model.ImuSample> _wristChartBuffer = [];
  final List<model.ImuSample> _ankleChartBuffer = [];
  final List<model.ImuSample> _wristPendingDbWrite = [];
  final List<model.ImuSample> _anklePendingDbWrite = [];

  // Maximum pending writes before we log overflow (prevents unbounded memory growth)
  static const int _maxPendingWrites = 5000;

  // Window manager for dual-band synchronization
  final _windowManager = DualBandWindowManager(
    sessionDetector: DualBandSessionDetector(),
  );

  // 40 Hz Cadence Gates
  final _cadenceGate = DualBandCadenceGate();

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

  // Diagnostics for 40 Hz validation
  Timer? _diagnosticsTimer;

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

    // Initialize participant and activity labels
    final prefs = getIt<SharedPreferences>();
    final savedParticipant = prefs.getString('bandana_participant_id');
    if (savedParticipant != null && savedParticipant.trim().isNotEmpty) {
      _participantId = savedParticipant.trim();
      _participantController.text = _participantId;
    }
    _selectedLabel = _labelManager.allLabels.first;
    _labelManager.addListener(_onLabelsChanged);

    // Periodic DB flush
    _startDbFlushTimer();

    // Periodic diagnostics (every 5 seconds during recording)
    _startDiagnosticsTimer();
  }

  void _onLabelsChanged() {
    if (mounted) {
      setState(() {
        if (!_labelManager.allLabels.contains(_selectedLabel)) {
          _selectedLabel = _labelManager.allLabels.first;
        }
      });
    }
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
    final wristDiag = _cadenceGate.wristGate.diagnostics;
    final ankleDiag = _cadenceGate.ankleGate.diagnostics;
    debugPrint('DIAG Wrist: ${wristDiag.toString()}');
    debugPrint('DIAG Ankle: ${ankleDiag.toString()}');

    // Combined diagnostic log
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

  Future<void> _flushDbBuffers({bool force = false}) async {
    if (_sessionId == null) return;
    if (_wristPendingDbWrite.isEmpty && _anklePendingDbWrite.isEmpty) return;
    // Don't flush if recording has been stopped, unless explicitly forced for final persistence
    if (_recordingStopped && !force) return;

    final wristToWrite = List<model.ImuSample>.from(_wristPendingDbWrite);
    final ankleToWrite = List<model.ImuSample>.from(_anklePendingDbWrite);
    _wristPendingDbWrite.clear();
    _anklePendingDbWrite.clear();

    await Future.wait([
      if (wristToWrite.isNotEmpty)
        _db.insertImuSamples(sessionId: _sessionId!, samples: wristToWrite),
      if (ankleToWrite.isNotEmpty)
        _db.insertImuSamples(sessionId: _sessionId!, samples: ankleToWrite),
    ]);
  }

  @override
  void dispose() {
    _labelManager.removeListener(_onLabelsChanged);
    _participantController.dispose();

    // Cancel flush timer first to prevent new flushes
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;

    // Cancel diagnostics timer
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;

    // Cancel sensor subscriptions
    _wristSensorSub?.cancel();
    _ankleSensorSub?.cancel();
    _wristBleSub?.cancel();
    _ankleBleSub?.cancel();

    // Final flush if recording
    if (_isRecording) {
      _flushDbBuffers(force: true);
    }

    _recordingStopped = true;
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

    // Persist participant ID
    final prefs = getIt<SharedPreferences>();
    _participantId = _participantController.text.trim();
    if (_participantId.isEmpty) _participantId = 'participant_1';
    await prefs.setString('bandana_participant_id', _participantId);

    // Create a new session in the DB with participant ID
    final sessionId = await _db.createSession(
      _selectedLabel,
      participantId: _participantId,
    );

    // Save notes if provided
    if (_sessionNotes.isNotEmpty) {
      await _db.updateSessionNotes(sessionId, _sessionNotes);
    }

    setState(() {
      _isRecording = true;
      _sessionId = sessionId;
      _wristSampleCount = 0;
      _ankleSampleCount = 0;
      _wristChartBuffer.clear();
      _ankleChartBuffer.clear();
      _wristPendingDbWrite.clear();
      _anklePendingDbWrite.clear();
      _wristPacketsReceived = 0;
      _anklePacketsReceived = 0;
      _wristMalformedPackets = 0;
      _ankleMalformedPackets = 0;
      _recordingStartTime = DateTime.now();
      _recordingStopped = false; // Reset flag for new recording
    });

    _windowManager.reset();
    _cadenceGate.reset();

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

    // Enforce 40 Hz accepted cadence gate
    final decision = _cadenceGate.wristGate.processSample(sample);
    if (decision == CadenceDecision.droppedBurst ||
        decision == CadenceDecision.droppedDuplicate ||
        decision == CadenceDecision.droppedOutOfOrder) {
      // Discard sub-interval burst or duplicate sample
      return;
    }

    // Add accepted sample to window manager
    _windowManager.addSample(sample);

    _wristPacketsReceived++;
    if (mounted) {
      setState(() {
        _wristChartBuffer.add(sample);
        if (_wristChartBuffer.length > 100) _wristChartBuffer.removeAt(0);
      });
    }

    // Bounded pending writes with overflow logging
    if (_wristPendingDbWrite.length >= _maxPendingWrites) {
      debugPrint('Record: Wrist pending DB write buffer overflow (${_wristPendingDbWrite.length} samples), dropping oldest');
      _wristPendingDbWrite.removeRange(0, _wristPendingDbWrite.length - _maxPendingWrites + 1);
    }
    _wristPendingDbWrite.add(sample);

    // Try to consume window(s) - atomic dual-band if both connected
    _tryProcessWindows();
  }

  void _onAnkleSensorData(model.ImuSample sample) {
    if (!_isRecording || _recordingStopped) return;

    // Enforce 40 Hz accepted cadence gate
    final decision = _cadenceGate.ankleGate.processSample(sample);
    if (decision == CadenceDecision.droppedBurst ||
        decision == CadenceDecision.droppedDuplicate ||
        decision == CadenceDecision.droppedOutOfOrder) {
      // Discard sub-interval burst or duplicate sample
      return;
    }

    // Add accepted sample to window manager
    _windowManager.addSample(sample);

    _anklePacketsReceived++;
    if (mounted) {
      setState(() {
        _ankleChartBuffer.add(sample);
        if (_ankleChartBuffer.length > 100) _ankleChartBuffer.removeAt(0);
      });
    }

    // Bounded pending writes with overflow logging
    if (_anklePendingDbWrite.length >= _maxPendingWrites) {
      debugPrint('Record: Ankle pending DB write buffer overflow (${_anklePendingDbWrite.length} samples), dropping oldest');
      _anklePendingDbWrite.removeRange(0, _anklePendingDbWrite.length - _maxPendingWrites + 1);
    }
    _anklePendingDbWrite.add(sample);

    // Try to consume window(s) - atomic dual-band if both connected
    _tryProcessWindows();
  }

  /// Attempts to process completed windows atomically.
  /// For dual-band: both windows must be ready and valid.
  /// For single-band: the available band's window is processed when ready.
  void _tryProcessWindows() {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    // Check if we can consume a dual-band window
    if (!_windowManager.canConsumeDualBandWindow(hasWrist: hasWrist, hasAnkle: hasAnkle)) {
      return;
    }

    // Try to atomically consume
    final consumed = _windowManager.tryConsumeDualBandWindow(
      hasWrist: hasWrist,
      hasAnkle: hasAnkle,
      validateDuration: true,
    );

    if (consumed == null) {
      // One or both windows failed validation - they were already consumed
      debugPrint('Record: Invalid window duration, discarding');
      return;
    }

    // Process wrist window if available
    if (hasWrist && consumed.wristWindow.isNotEmpty) {
      _processWindow(consumed.wristWindow, BandRole.wrist);
    }

    // Process ankle window if available
    if (hasAnkle && consumed.ankleWindow.isNotEmpty) {
      _processWindow(consumed.ankleWindow, BandRole.ankle);
    }
  }

  Future<void> _processWindow(List<model.ImuSample> window, BandRole role) async {
    if (_sessionId == null || _recordingStopped) return;

    final features = MlService.extractFeaturesFromImuSamples(window);

    await _db.insertWindow(
      sessionId: _sessionId!,
      featureVector: features,
      label: _selectedLabel,
      bandRole: role,
    );

    if (mounted) {
      setState(() {
        if (role == BandRole.wrist) {
          _wristSampleCount++;
        } else {
          _ankleSampleCount++;
        }
      });
    }
  }

  Future<void> _stopRecording({bool showSnackbar = true}) async {
    // Log final cadence diagnostics before stopping
    _logSamplingDiagnostics();

    // 1. Immediately cancel sensor stream subscriptions so no new incoming packets are accepted
    await _wristSensorSub?.cancel();
    _wristSensorSub = null;
    await _ankleSensorSub?.cancel();
    _ankleSensorSub = null;

    // 2. Cancel timers and animation
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
    _pulseController.stop();
    _pulseController.reset();

    // 3. Guaranteed final buffer flush BEFORE marking recording stopped
    await _flushDbBuffers(force: true);

    // 4. Mark recording stopped
    _recordingStopped = true;

    // 5. Finalize session in DB with exact persisted sample count
    final completedSessionId = _sessionId;

    if (completedSessionId != null) {
      final totalSamples = await _db.getSampleCount(completedSessionId);
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

  void _showAddCustomActivityDialog() {
    final textController = TextEditingController();
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Custom Activity'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter a new activity label:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Activity Name',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        errorText = _labelManager.validateLabel(val);
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final validation = _labelManager.validateLabel(textController.text);
                    if (validation != null) {
                      setDialogState(() => errorText = validation);
                      return;
                    }
                    final added = await _labelManager.addCustomLabel(textController.text);
                    if (added && mounted && context.mounted) {
                      setState(() {
                        _selectedLabel = textController.text.trim();
                      });
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
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
            // ── Session Setup (Participant, Activity, Notes) ──
            if (!_isRecording) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person_outline, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text('Participant ID', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingXs),
                      TextField(
                        controller: _participantController,
                        decoration: InputDecoration(
                          hintText: 'e.g. sumeet_1, participant_1',
                          helperText: 'Participant label is used in exported CSV filenames',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.label_outline, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text('Activity', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _showAddCustomActivityDialog,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Custom Activity'),
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingXs),
                      DropdownButtonFormField<String>(
                        initialValue: _labelManager.allLabels.contains(_selectedLabel)
                            ? _selectedLabel
                            : _labelManager.allLabels.first,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedLabel = value);
                          }
                        },
                        items: _labelManager.allLabels.map((label) {
                          return DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      Row(
                        children: [
                          Icon(Icons.notes_outlined, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text('Session Notes (Optional)', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingXs),
                      TextField(
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Add context about this recording session...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                          contentPadding: const EdgeInsets.all(AppTheme.spacingMd),
                          isDense: true,
                        ),
                        onChanged: (value) => _sessionNotes = value,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
            ],

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
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                  child: !hasWrist && !hasAnkle
                      ? Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CustomPaint(
                                    painter: _BlueprintChartPainter(theme.brightness),
                                  ),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: (theme.brightness == Brightness.light ? Colors.white : const Color(0xFF1E2129))
                                        .withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.brightness == Brightness.light
                                          ? const Color(0xFF1A1A1A)
                                          : const Color(0xFF383B46),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        offset: const Offset(0, 4),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.sensors_outlined,
                                        size: 26,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Live Telemetry Blueprint',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Connect bands to stream real-time 6-DOF IMU data',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          children: [
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
                            if (hasAnkle) ...[
                              _buildChartSection(
                                theme,
                                'Ankle',
                                BandRole.ankle.color,
                                _ankleChartBuffer,
                                _ankleBleState,
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

/// Custom painter for the blueprint telemetry illustration when no bands are streaming.
class _BlueprintChartPainter extends CustomPainter {
  final Brightness brightness;
  _BlueprintChartPainter(this.brightness);

  @override
  void paint(Canvas canvas, Size size) {
    final isLight = brightness == Brightness.light;
    final gridPaint = Paint()
      ..color = isLight ? const Color(0x18000000) : const Color(0x1FFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw horizontal grid lines
    const hDivisions = 4;
    for (int i = 0; i <= hDivisions; i++) {
      final y = size.height * (i / hDivisions);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw vertical grid lines
    const vDivisions = 8;
    for (int i = 0; i <= vDivisions; i++) {
      final x = size.width * (i / vDivisions);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Waveform paths (faint preview waveforms)
    void drawWave(Color color, double freq, double amp, double phase) {
      final wavePaint = Paint()
        ..color = color.withValues(alpha: isLight ? 0.22 : 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      final path = Path();
      final midY = size.height / 2;
      for (double x = 0; x <= size.width; x += 4) {
        final normX = x / size.width;
        final y = midY + amp * math.sin(normX * freq * 2 * math.pi + phase);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wavePaint);
    }

    drawWave(const Color(0xFFFF3388), 3.0, size.height * 0.25, 0.0);
    drawWave(const Color(0xFF4CAF50), 4.5, size.height * 0.20, 1.2);
    drawWave(const Color(0xFF2196F3), 2.0, size.height * 0.30, 2.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}