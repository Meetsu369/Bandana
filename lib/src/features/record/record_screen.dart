import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_theme.dart';
import '../../features/record/session_detail_screen.dart';
import '../../models/imu_sample.dart' as model;
import '../../services/activity_label_manager.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/fitness_metrics_service.dart';
import '../../services/ml_service.dart';
import '../../utils/cadence_gate.dart';
import '../../utils/dual_band_window_manager.dart';
import '../../utils/session_boundary.dart';

/// Flow states for Record Mode:
/// - [idle]: No bands connected, pre-recording setup.
/// - [testingConnection]: At least one band connected; streaming live 50 Hz packets to UI only (ZERO DB writes).
/// - [recordingSession]: Active session recording, persistent DB writes, real-time ML inference & fitness metrics.
/// - [paused]: Recording temporarily paused.
enum RecordFlowState {
  idle,
  testingConnection,
  recordingSession,
  paused,
}

/// Tracks real-time connection diagnostics (Hz rate, sequence drops, SD status, latest IMU values).
class BandLiveDiagnostics {
  int packetsReceived = 0;
  int lastSeq = -1;
  int droppedPackets = 0;
  bool isSdOk = false;
  double liveHz = 0.0;
  model.ImuSample? latestSample;

  final List<DateTime> _arrivalTimes = [];

  void onSample(model.ImuSample sample) {
    packetsReceived++;
    latestSample = sample;
    isSdOk = sample.isSdOk;

    if (lastSeq != -1) {
      final diff = (sample.seq - lastSeq) & 0xFFFF;
      if (diff > 1 && diff < 1000) {
        droppedPackets += (diff - 1);
      }
    }
    lastSeq = sample.seq;

    final now = DateTime.now();
    _arrivalTimes.add(now);
    _arrivalTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);
    if (_arrivalTimes.length >= 2) {
      final spanMs = _arrivalTimes.last.difference(_arrivalTimes.first).inMilliseconds;
      if (spanMs > 0) {
        liveHz = (_arrivalTimes.length - 1) * 1000.0 / spanMs;
      }
    }
  }

  void reset() {
    packetsReceived = 0;
    lastSeq = -1;
    droppedPackets = 0;
    liveHz = 0.0;
    latestSample = null;
    _arrivalTimes.clear();
  }
}

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
  RecordFlowState _flowState = RecordFlowState.idle;
  RecordFlowState get flowState => _flowState;

  final _fitnessMetrics = FitnessMetricsService();

  FitnessMetrics? _currentMetrics;
  StreamSubscription<FitnessMetrics>? _metricsSub;

  final _wristDiag = BandLiveDiagnostics();
  final _ankleDiag = BandLiveDiagnostics();

  String _selectedLabel = BleConstants.defaultLabels.first;
  String _participantId = 'participant_1';
  final _participantController = TextEditingController(text: 'participant_1');
  late TextEditingController _notesController;
  String _sessionNotes = '';
  bool _isRecording = false;
  int? _sessionId;
  int _wristSampleCount = 0;
  int _ankleSampleCount = 0;
  Timer? _elapsedTimer;

  bool get _isTestEnvironment =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

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

  // 50 Hz Cadence Gates
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
  DateTime? _recordingStartTime;

  // Diagnostics for 40 Hz validation
  Timer? _diagnosticsTimer;

  // Flag to prevent DB writes after recording stops
  bool _recordingStopped = false;

  // Offline Sync State
  bool _isWristSyncing = false;
  bool _isAnkleSyncing = false;

  @override
  void initState() {
    super.initState();
    _wristBleState = _ble.wrist.currentState;
    _ankleBleState = _ble.ankle.currentState;

    if (_wristBleState == BandConnectionState.connected ||
        _ankleBleState == BandConnectionState.connected) {
      _flowState = RecordFlowState.testingConnection;
    }

    _wristBleSub = _ble.wrist.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _wristBleState = state;
          _updateFlowStateOnConnectionChange();
        });
      }
    });
    _ankleBleSub = _ble.ankle.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _ankleBleState = state;
          _updateFlowStateOnConnectionChange();
        });
      }
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
    _notesController = TextEditingController(text: _sessionNotes);
    _selectedLabel = _labelManager.allLabels.first;
    _labelManager.addListener(_onLabelsChanged);


    // Listen to real-time fitness metrics
    _metricsSub = _fitnessMetrics.metricsStream.listen((metrics) {
      if (mounted && _flowState == RecordFlowState.recordingSession) {
        setState(() {
          _currentMetrics = metrics;
        });
      }
    });

    // Setup preview sensor stream listeners
    _ensureSensorSubscriptions();

    // Periodic DB flush
    _startDbFlushTimer();

    // Periodic diagnostics (every 5 seconds during recording)
    _startDiagnosticsTimer();
  }

  void _updateFlowStateOnConnectionChange() {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    if (_flowState == RecordFlowState.recordingSession) {
      return;
    }

    if (hasWrist || hasAnkle) {
      _flowState = RecordFlowState.testingConnection;
    } else {
      _flowState = RecordFlowState.idle;
    }
    _ensureSensorSubscriptions();
  }

  void _ensureSensorSubscriptions() {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    if (hasWrist && _wristSensorSub == null) {
      _wristSensorSub = _ble.wrist.sensorStream.listen(_onWristSensorData);
    } else if (!hasWrist && _wristSensorSub != null) {
      _wristSensorSub?.cancel();
      _wristSensorSub = null;
    }

    if (hasAnkle && _ankleSensorSub == null) {
      _ankleSensorSub = _ble.ankle.sensorStream.listen(_onAnkleSensorData);
    } else if (!hasAnkle && _ankleSensorSub != null) {
      _ankleSensorSub?.cancel();
      _ankleSensorSub = null;
    }
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
    _notesController.dispose();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    // Cancel flush timer first to prevent new flushes
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;

    // Cancel diagnostics timer
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;

    // Cancel sensor & ble subscriptions
    _wristSensorSub?.cancel();
    _ankleSensorSub?.cancel();
    _wristBleSub?.cancel();
    _ankleBleSub?.cancel();
    _metricsSub?.cancel();

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
    _sessionNotes = _notesController.text.trim();
    if (_sessionNotes.isNotEmpty) {
      await _db.updateSessionNotes(sessionId, _sessionNotes);
    }

    setState(() {
      _flowState = RecordFlowState.recordingSession;
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
      _recordingStartTime = DateTime.now();
      _recordingStopped = false; // Reset flag for new recording
      _currentMetrics = null;
    });

    _fitnessMetrics.startSession();
    _fitnessMetrics.updateActivity(_selectedLabel);

    _wristDiag.reset();
    _ankleDiag.reset();

    _windowManager.reset();
    _cadenceGate.reset();

    _elapsedTimer?.cancel();
    if (!_isTestEnvironment) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _isRecording) setState(() {});
      });
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.value = 1.0;
    }

    // Start flush timer
    _startDbFlushTimer();

    // Ensure sensor subscriptions are listening
    _ensureSensorSubscriptions();

    // Broadcast START_RECORDING (0x01) with ground-truth activity label
    unawaited(_ble.startRecording(label: _selectedLabel));
  }

  void _onWristSensorData(model.ImuSample sample) {
    _wristDiag.onSample(sample);

    if (mounted) {
      setState(() {
        _wristChartBuffer.add(sample);
        if (_wristChartBuffer.length > 100) _wristChartBuffer.removeAt(0);
      });
    }

    // In Preview (testingConnection), DO NOT perform any database writes or window management
    if (_flowState != RecordFlowState.recordingSession || !_isRecording || _recordingStopped) {
      return;
    }

    // Enforce 50 Hz accepted cadence gate
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
    _ankleDiag.onSample(sample);

    if (mounted) {
      setState(() {
        _ankleChartBuffer.add(sample);
        if (_ankleChartBuffer.length > 100) _ankleChartBuffer.removeAt(0);
      });
    }

    // In Preview (testingConnection), DO NOT perform any database writes or window management
    if (_flowState != RecordFlowState.recordingSession || !_isRecording || _recordingStopped) {
      return;
    }

    // Enforce 50 Hz accepted cadence gate
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

    // Feed real-time fitness metrics engine
    _fitnessMetrics.addSample(sample);

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

    _fitnessMetrics.stopSession();

    // 1. Cancel timers and animation
    _dbFlushTimer?.cancel();
    _dbFlushTimer = null;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _pulseController.stop();
    _pulseController.reset();

    // 2. Guaranteed final buffer flush BEFORE marking recording stopped
    await _flushDbBuffers(force: true);

    // 3. Mark recording stopped and broadcast STOP_RECORDING (0x02) to seal SD buffers
    _recordingStopped = true;
    unawaited(_ble.stopRecording());

    // 4. Finalize session in DB with exact persisted sample count
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
        _notesController.clear();
        final hasAny = _wristBleState == BandConnectionState.connected ||
            _ankleBleState == BandConnectionState.connected;
        _flowState = hasAny ? RecordFlowState.testingConnection : RecordFlowState.idle;
      });
    }

    // Keep sensor subscriptions alive in preview mode if bands remain connected
    _ensureSensorSubscriptions();

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
    if (_recordingStartTime == null) return isWindow ? '0.0/s' : '0.0 Hz';
    final elapsed = DateTime.now().difference(_recordingStartTime!).inSeconds;
    if (elapsed == 0) return isWindow ? '0.0/s' : '0.0 Hz';
    if (isWindow) {
      return '${(count / elapsed).toStringAsFixed(1)}/s';
    }
    return '${(count / elapsed).toStringAsFixed(1)} Hz';
  }

  String _formatElapsed() {
    if (_recordingStartTime == null) return '00:00:00';
    final elapsed = DateTime.now().difference(_recordingStartTime!);
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _startOfflineSync(BandRole role) async {
    final connection = _ble.getConnection(role);
    if (connection.currentState != BandConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${role.displayName} band is not connected.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      if (role == BandRole.wrist) {
        _isWristSyncing = true;
      } else {
        _isAnkleSyncing = true;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting offline catch-up sync from ${role.displayName} band MicroSD...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Create a new session in DB for offline data
    final sessionId = await _db.createSession(
      'Offline Sync - ${role.displayName}',
      participantId: _participantId,
    );
    await _db.updateSessionNotes(
      sessionId,
      'Batch synced from ${role.displayName} band (/raw_imu.bin) at 50 Hz.',
    );

    final syncBuffer = <model.ImuSample>[];
    StreamSubscription<model.ImuSample>? sampleSub;
    StreamSubscription<int>? completeSub;

    sampleSub = connection.offlineSyncSampleStream.listen((sample) async {
      syncBuffer.add(sample);
      if (syncBuffer.length >= 50) {
        final toWrite = List<model.ImuSample>.from(syncBuffer);
        syncBuffer.clear();
        await _db.insertImuSamples(sessionId: sessionId, samples: toWrite);
      }
    });

    completeSub = connection.offlineSyncCompleteStream.listen((totalCount) async {
      if (syncBuffer.isNotEmpty) {
        final toWrite = List<model.ImuSample>.from(syncBuffer);
        syncBuffer.clear();
        await _db.insertImuSamples(sessionId: sessionId, samples: toWrite);
      }

      await sampleSub?.cancel();
      await completeSub?.cancel();

      final actualTotal = await _db.getSampleCount(sessionId);
      await _db.endSession(sessionId, actualTotal);

      if (mounted) {
        setState(() {
          if (role == BandRole.wrist) {
            _isWristSyncing = false;
          } else {
            _isAnkleSyncing = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              actualTotal > 0
                  ? 'Offline sync complete: $actualTotal samples synced from ${role.displayName} band!'
                  : 'Offline sync complete: No stored data found on ${role.displayName} band SD card.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    });

    final sent = await connection.startOfflineSync();
    if (!sent) {
      await sampleSub.cancel();
      await completeSub.cancel();
      if (mounted) {
        setState(() {
          if (role == BandRole.wrist) {
            _isWristSyncing = false;
          } else {
            _isAnkleSyncing = false;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send offline sync command to ${role.displayName} band.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkCanvas : AppColors.lightCanvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Record',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        actions: [
          _buildSplitDevicePill(isDark),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _isRecording
              ? _buildLiveRecordingView(isDark, hasWrist, hasAnkle)
              : _buildPreRecordingSetup(isDark, hasWrist, hasAnkle),
        ),
      ),
    );
  }

  // ── Split Device Connectivity Badge (Top Right) ──
  Widget _buildSplitDevicePill(bool isDark) {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 2,
        ),
        boxShadow: isDark ? null : [AppShadows.hardShadowSm],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDeviceStatusItem(
            icon: Icons.watch,
            name: 'Wrist',
            isConnected: hasWrist,
            isDark: isDark,
          ),
          Container(
            height: 12,
            width: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          _buildDeviceStatusItem(
            icon: Icons.directions_run,
            name: 'Ankle',
            isConnected: hasAnkle,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusItem({
    required IconData icon,
    required String name,
    required bool isConnected,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
        const SizedBox(width: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
        ),
      ],
    );
  }

  Color _getColorForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'walking':
        return const Color(0xFF10B981);
      case 'running':
        return const Color(0xFFFF3384);
      case 'sitting':
        return const Color(0xFF6366F1);
      case 'standing':
        return const Color(0xFFF59E0B);
      case 'jumping':
        return const Color(0xFFEC4899);
      case 'stairs':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF06B6D4);
    }
  }

  IconData _getIconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'sitting':
        return Icons.airline_seat_recline_normal;
      case 'standing_handmove':
      case 'standing':
        return Icons.pan_tool;
      case 'walking':
        return Icons.directions_walk;
      case 'jumping_jacks':
      case 'jumping':
        return Icons.sports_kabaddi;
      case 'running':
        return Icons.directions_run;
      default:
        return Icons.fitness_center;
    }
  }

  Widget _buildPreFlightHealthCard(bool isDark) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: AppShadows.bentoSm(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                      ),
                      child: const Icon(Icons.sensors, size: 14, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Pre-Flight Diagnostics',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF132E2B) : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981), width: 1),
                ),
                child: const Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildBandDiagnosticColumn(
                  roleName: 'BANDANA-WRIST',
                  icon: Icons.watch,
                  accentColor: isDark ? AppColors.darkBadgeWristBg : AppColors.lightBadgeWristBg,
                  isConnected: hasWrist,
                  diag: _wristDiag,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBandDiagnosticColumn(
                  roleName: 'BANDANA-ANKLE',
                  icon: Icons.directions_run,
                  accentColor: isDark ? AppColors.darkBadgeAnkleBg : AppColors.lightBadgeAnkleBg,
                  isConnected: hasAnkle,
                  diag: _ankleDiag,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBandDiagnosticColumn({
    required String roleName,
    required IconData icon,
    required Color accentColor,
    required bool isConnected,
    required BandLiveDiagnostics diag,
    required bool isDark,
  }) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? const Color(0xFF1E2025) : const Color(0xFFF1F5F9);
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final isNominalHz = diag.liveHz >= 48.0 && diag.liveHz <= 52.0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: textColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        roleName.replaceFirst('BANDANA-', ''),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Live Transmission Rate (Hz)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rate: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                Text(
                  isConnected ? '${diag.liveHz.toStringAsFixed(1)} Hz' : '0.0 Hz',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: isConnected && isNominalHz ? const Color(0xFF10B981) : textColor,
                  ),
                ),
                if (isConnected && isNominalHz) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle, size: 13, color: Color(0xFF10B981)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Drop Rate / Seq Validator & MicroSD Status
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Text(
                '${diag.droppedPackets} Drops',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: diag.droppedPackets == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: diag.isSdOk
                      ? (isDark ? const Color(0xFF132E2B) : const Color(0xFFD1FAE5))
                      : (isDark ? const Color(0xFF2E2218) : const Color(0xFFFEF3C7)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      diag.isSdOk ? Icons.sd_card : Icons.sd_card_alert,
                      size: 10,
                      color: diag.isSdOk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      diag.isSdOk ? 'SD OK' : 'SD Missing',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: diag.isSdOk ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Mini Sparkline / Value Ticker (aX, aY, aZ)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111215) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: diag.latestSample != null
                  ? Text(
                      'aX:${diag.latestSample!.ax.toStringAsFixed(2)}  aY:${diag.latestSample!.ay.toStringAsFixed(2)}  aZ:${diag.latestSample!.az.toStringAsFixed(2)}g',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    )
                  : Text(
                      'Waiting for stream...',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'monospace',
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── A. Record Setup Screen (Pre-Recording) ──
  Widget _buildPreRecordingSetup(bool isDark, bool hasWrist, bool hasAnkle) {
    final canRecord = hasWrist || hasAnkle;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canRecord) ...[
          _buildPreFlightHealthCard(isDark),
          const SizedBox(height: 16),
        ],

        // 1. Participant ID (Placed directly on canvas with clean label)
        Row(
          children: [
            Icon(Icons.person_outline, size: 18, color: textColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Participant ID',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: AppShadows.bentoSm(isDark),
          ),
          child: TextField(
            controller: _participantController,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
            decoration: InputDecoration(
              hintText: 'e.g. participant_1, runner_02',
              hintStyle: TextStyle(color: mutedColor, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Participant label is used in exported CSV filenames',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
        ),
        const SizedBox(height: 18),

        // 2. Activity Selector Label Row + Dropdown Trigger Pill
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.directions_run_outlined, size: 18, color: textColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Activity',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showAddCustomActivityDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E1B4E) : const Color(0xFFFCE7F3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accentPink, width: 1.5),
                ),
                child: const Text(
                  '+ Custom Activity',
                  style: TextStyle(
                    color: AppColors.accentPink,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: AppShadows.bentoSm(isDark),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _labelManager.allLabels.contains(_selectedLabel)
                  ? _selectedLabel
                  : _labelManager.allLabels.first,
              icon: Icon(Icons.arrow_drop_down, color: textColor),
              dropdownColor: surfaceColor,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedLabel = value);
                }
              },
              items: _labelManager.allLabels.map((label) {
                return DropdownMenuItem<String>(
                  value: label,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: _getColorForLabel(label),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(label),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // 3. Session Notes (Optional)
        Row(
          children: [
            Icon(Icons.notes_outlined, size: 18, color: textColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Session Notes (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: AppShadows.bentoSm(isDark),
          ),
          child: TextField(
            controller: _notesController,
            maxLines: 3,
            style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: 'Add context about this recording session...',
              hintStyle: TextStyle(color: mutedColor, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (val) => _sessionNotes = val,
          ),
        ),
        const SizedBox(height: 18),

        // 4. Device Connection Summary Strip (2-Column Split Bento Card)
        Row(
          children: [
            Expanded(
              child: _buildDeviceStripCard(
                title: 'Wrist Band',
                icon: Icons.watch,
                accentColor: isDark ? AppColors.darkBadgeWristBg : AppColors.lightBadgeWristBg,
                isConnected: hasWrist,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDeviceStripCard(
                title: 'Ankle Band',
                icon: Icons.directions_run,
                accentColor: isDark ? AppColors.darkBadgeAnkleBg : AppColors.lightBadgeAnkleBg,
                isConnected: hasAnkle,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 5. Validation Micro-caption & Primary Start CTA
        if (!canRecord) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: isDark ? AppColors.darkDangerText : AppColors.lightDangerText),
                const SizedBox(width: 6),
                Text(
                  'Connect at least one band to start recording.',
                  style: TextStyle(
                    color: isDark ? AppColors.darkDangerText : AppColors.lightDangerText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: !canRecord ? null : AppShadows.bento(isDark),
          ),
          child: ElevatedButton(
            onPressed: canRecord
                ? _startRecording
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please connect at least one band in Devices settings to record.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: canRecord ? AppColors.accentPink : AppColors.accentPink.withValues(alpha: 0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: borderColor, width: 2),
              ),
              shadowColor: Colors.transparent,
            ),
            child: Container(
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fiber_manual_record, size: 14, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Start Recording',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceStripCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required bool isConnected,
    required bool isDark,
  }) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    final isWrist = title.contains('Wrist');
    final glyphColor = isDark
        ? (isWrist ? AppColors.darkBadgeWristText : AppColors.darkBadgeAnkleText)
        : (isWrist ? AppColors.lightBadgeWristText : AppColors.lightBadgeAnkleText);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: AppShadows.bentoSm(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Icon(
                  icon,
                  size: 15,
                  color: glyphColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: isConnected
                  ? (isDark ? const Color(0xFF132E2B) : const Color(0xFFD1FAE5))
                  : (isDark ? AppColors.darkDangerBg : AppColors.lightDangerBg),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected
                    ? (isDark ? const Color(0xFF065F46) : const Color(0xFF34D399))
                    : (isDark ? AppColors.darkDangerText.withValues(alpha: 0.5) : const Color(0xFFF87171)),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF10B981)
                        : (isDark ? AppColors.darkDangerText : const Color(0xFFEF4444)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isConnected ? 'Connected (Ready)' : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isConnected
                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                            : (isDark ? AppColors.darkDangerText : AppColors.lightDangerText),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isConnected) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: OutlinedButton.icon(
                onPressed: (isWrist ? _isWristSyncing : _isAnkleSyncing)
                    ? null
                    : () => _startOfflineSync(isWrist ? BandRole.wrist : BandRole.ankle),
                icon: (isWrist ? _isWristSyncing : _isAnkleSyncing)
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 13),
                label: Text(
                  (isWrist ? _isWristSyncing : _isAnkleSyncing) ? 'Syncing...' : 'Sync Offline',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── B. Live Recording Screen ──
  Widget _buildLiveRecordingView(bool isDark, bool hasWrist, bool hasAnkle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Hero Live Telemetry Card (Dark Bento Card)
        _buildHeroTelemetryCard(),
        const SizedBox(height: 14),

        // 2. 4-Metric Grid Dashboard (Steps, Cadence, Calories, Duration)
        _build4MetricGrid(isDark),
        const SizedBox(height: 14),

        // 4. Split Telemetry Stream Bento (Wrist vs. Ankle)
        _buildSplitTelemetryStream(isDark),
        const SizedBox(height: 14),

        // 5. Live Dual-Band 6-Axis Graph Waveforms (Wrist & Ankle)
        _buildBandGraphCard(
          title: 'Wrist Band',
          icon: Icons.watch,
          accentColor: isDark ? AppColors.darkBadgeWristBg : AppColors.lightBadgeWristBg,
          samples: _wristChartBuffer,
          isConnected: hasWrist,
          isDark: isDark,
        ),
        const SizedBox(height: 14),
        _buildBandGraphCard(
          title: 'Ankle Band',
          icon: Icons.directions_run,
          accentColor: isDark ? AppColors.darkBadgeAnkleBg : AppColors.lightBadgeAnkleBg,
          samples: _ankleChartBuffer,
          isConnected: hasAnkle,
          isDark: isDark,
        ),
        const SizedBox(height: 20),

        // 6. Stop Action Button
        _buildStopButton(isDark),
      ],
    );
  }



  Widget _build4MetricGrid(bool isDark) {
    final metrics = _currentMetrics ?? _fitnessMetrics.currentMetrics;

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _buildMetricTile(
                label: 'Steps',
                value: '${metrics.totalSteps}',
                unit: 'steps',
                icon: Icons.directions_walk,
                accentColor: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMetricTile(
                label: 'Cadence',
                value: metrics.cadenceSpm.toStringAsFixed(1),
                unit: 'SPM',
                icon: Icons.speed,
                accentColor: const Color(0xFF06B6D4),
                isDark: isDark,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              _buildMetricTile(
                label: 'Calories',
                value: metrics.totalCaloriesKcal.toStringAsFixed(1),
                unit: 'kcal',
                icon: Icons.local_fire_department,
                accentColor: const Color(0xFFF59E0B),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildMetricTile(
                label: 'Duration',
                value: _formatElapsed(),
                unit: 'active',
                icon: Icons.timer_outlined,
                accentColor: const Color(0xFF8B5CF6),
                isDark: isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
  }) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: AppShadows.bentoSm(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
              Icon(icon, size: 14, color: accentColor),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTelemetryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.liveTelemetry,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF383A42), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xFF18181B), offset: Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Flashing REC pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _pulseController,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Right: Monospace elapsed timer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF27272A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3F3F46), width: 1.2),
                ),
                child: Text(
                  _formatElapsed(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Large activity display text with icon
          Row(
            children: [
              Icon(_getIconForLabel(_selectedLabel), size: 26, color: _getColorForLabel(_selectedLabel)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedLabel,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Subtitle
          Text(
            'Session #${_sessionId ?? 1}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitTelemetryStream(bool isDark) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Row(
      children: [
        // Left Box (Wrist - Sky Blue / Deep Midnight Blue)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBadgeWristBg : AppColors.lightBadgeWristBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: AppShadows.bentoSm(isDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.watch,
                      size: 15,
                      color: isDark ? AppColors.darkBadgeWristText : AppColors.lightBadgeWristText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '⌚ Wrist Band',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkBadgeWristText : AppColors.lightBadgeWristText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatRate(_wristPacketsReceived),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$_wristPacketsReceived Samples • $_wristSampleCount Windows',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkBadgeWristText : AppColors.lightBadgeWristText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right Box (Ankle - Volt Lime / Deep Forest Olive)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBadgeAnkleBg : AppColors.lightBadgeAnkleBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 2),
              boxShadow: AppShadows.bentoSm(isDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.directions_run,
                      size: 15,
                      color: isDark ? AppColors.darkBadgeAnkleText : AppColors.lightBadgeAnkleText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '🏃 Ankle Band',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkBadgeAnkleText : AppColors.lightBadgeAnkleText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatRate(_anklePacketsReceived),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$_anklePacketsReceived Samples • $_ankleSampleCount Windows',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkBadgeAnkleText : AppColors.lightBadgeAnkleText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBandGraphCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<model.ImuSample> samples,
    required bool isConnected,
    required bool isDark,
  }) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    final isWrist = title.contains('Wrist');
    final glyphColor = isDark
        ? (isWrist ? AppColors.darkBadgeWristText : AppColors.darkBadgeAnkleText)
        : (isWrist ? AppColors.lightBadgeWristText : AppColors.lightBadgeAnkleText);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: AppShadows.bentoSm(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderColor, width: 1.2),
                          ),
                          child: Icon(
                            icon,
                            size: 13,
                            color: glyphColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? (isDark ? const Color(0xFF132E2B) : const Color(0xFFD1FAE5))
                                : (isDark ? AppColors.darkDangerBg : AppColors.lightDangerBg),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isConnected ? 'LIVE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isConnected
                                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                                  : (isDark ? AppColors.darkDangerText : AppColors.lightDangerText),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '6-AXIS REAL-TIME IMU STREAM',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildLegendItem('aX', AppTheme.axisColors[0], isDark),
                    _buildLegendItem('aY', AppTheme.axisColors[1], isDark),
                    _buildLegendItem('aZ', AppTheme.axisColors[2], isDark),
                    _buildLegendItem('gX', AppTheme.axisColors[3], isDark),
                    _buildLegendItem('gY', AppTheme.axisColors[4], isDark),
                    _buildLegendItem('gZ', AppTheme.axisColors[5], isDark),
                  ],
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: Container(
              height: 160,
              width: double.infinity,
              color: isDark ? const Color(0xFF0F1013) : const Color(0xFFF8FAFC),
              child: CustomPaint(
                painter: _LiveImuWaveformPainter(
                  samples: samples,
                  isDark: isDark,
                  pulseValue: _pulseController.value,
                  bandName: title,
                  isConnected: isConnected,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStopButton(bool isDark) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.bento(isDark),
      ),
      child: ElevatedButton(
        onPressed: _stopRecording,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626), // Crimson
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              width: 2,
            ),
          ),
          shadowColor: Colors.transparent,
        ),
        child: Container(
          alignment: Alignment.center,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stop_rounded, size: 20, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Stop Recording',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the dedicated 6-axis real-time IMU waveform canvas with zero-baseline.
class _LiveImuWaveformPainter extends CustomPainter {
  final List<model.ImuSample> samples;
  final bool isDark;
  final double pulseValue;
  final String bandName;
  final bool isConnected;

  _LiveImuWaveformPainter({
    required this.samples,
    required this.isDark,
    required this.pulseValue,
    required this.bandName,
    required this.isConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // 1. Draw subtle horizontal grid lines
    final gridPaint = Paint()
      ..color = isDark ? const Color(0x18FFFFFF) : const Color(0x14000000)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, size.height * 0.25), Offset(size.width, size.height * 0.25), gridPaint);
    canvas.drawLine(Offset(0, size.height * 0.75), Offset(size.width, size.height * 0.75), gridPaint);

    // 2. Draw prominent zero-baseline
    final baselinePaint = Paint()
      ..color = isDark ? const Color(0x38FFFFFF) : const Color(0x30000000)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double startX = 0.0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, midY), Offset(startX + dashWidth, midY), baselinePaint);
      startX += dashWidth + dashSpace;
    }

    // Zero-baseline text indicator
    final textPainter = TextPainter(
      text: TextSpan(
        text: '0.0',
        style: TextStyle(
          fontSize: 8.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0x60FFFFFF) : const Color(0x60000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(6, midY - 11));

    // 3. If samples are empty, render a smooth faint rolling preview wave
    if (samples.isEmpty) {
      final previewPaint = Paint()
        ..color = isDark ? const Color(0x2538BDF8) : const Color(0x250284C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final path = Path();
      for (double x = 0; x <= size.width; x += 4) {
        final normX = x / size.width;
        final y = midY + 14 * math.sin(normX * 4 * math.pi + pulseValue * 2 * math.pi);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, previewPaint);

      final statusMsg = isConnected
          ? 'Waiting for $bandName live stream...'
          : '$bandName offline (not connected)';
      final statusPainter = TextPainter(
        text: TextSpan(
          text: statusMsg,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0x80FFFFFF) : const Color(0x80000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      statusPainter.paint(
        canvas,
        Offset((size.width - statusPainter.width) / 2, midY + 12),
      );
      return;
    }

    // 4. Plot real-time 6-axis IMU values (aX, aY, aZ, gX, gY, gZ)
    final pointsToPlot = samples.length > 60 ? samples.sublist(samples.length - 60) : samples;
    final stepX = size.width / (pointsToPlot.length > 1 ? (pointsToPlot.length - 1) : 1);

    // Compute independent dynamic ranges for Accel and Gyro to prevent mutual clipping/squashing
    double maxAccel = 12.0; // Baseline 12 m/s² (~1.2g)
    double maxGyro = 60.0;  // Baseline 60 deg/s
    for (final s in pointsToPlot) {
      if (s.ax.abs() > maxAccel) maxAccel = s.ax.abs();
      if (s.ay.abs() > maxAccel) maxAccel = s.ay.abs();
      if (s.az.abs() > maxAccel) maxAccel = s.az.abs();
      if (s.gx.abs() > maxGyro) maxGyro = s.gx.abs();
      if (s.gy.abs() > maxGyro) maxGyro = s.gy.abs();
      if (s.gz.abs() > maxGyro) maxGyro = s.gz.abs();
    }
    maxAccel *= 1.15;
    maxGyro *= 1.15;

    final usableHalfHeight = midY - 8.0;
    final scaleAccel = usableHalfHeight / maxAccel;
    final scaleGyro = usableHalfHeight / maxGyro;

    // Corner indicator for Accel scale (left)
    final accelUnitPainter = TextPainter(
      text: TextSpan(
        text: '±${(maxAccel / 9.80665).toStringAsFixed(1)}g',
        style: TextStyle(
          fontSize: 8.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0x70FFFFFF) : const Color(0x70000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    accelUnitPainter.paint(canvas, const Offset(6, 6));

    // Corner indicator for Gyro scale (right)
    final gyroUnitPainter = TextPainter(
      text: TextSpan(
        text: '±${maxGyro.toInt()}°/s',
        style: TextStyle(
          fontSize: 8.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0x70FFFFFF) : const Color(0x70000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    gyroUnitPainter.paint(canvas, Offset(size.width - gyroUnitPainter.width - 6, 6));

    void plotAxis(double Function(model.ImuSample) getVal, double scale, Color color, {double width = 1.8}) {
      final path = Path();
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (int i = 0; i < pointsToPlot.length; i++) {
        final x = i * stepX;
        final val = getVal(pointsToPlot[i]);
        final y = (midY - (val * scale)).clamp(4.0, size.height - 4.0);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Plot Accelerometer axes (aX, aY, aZ)
    plotAxis((s) => s.ax, scaleAccel, AppTheme.axisColors[0]);
    plotAxis((s) => s.ay, scaleAccel, AppTheme.axisColors[1]);
    plotAxis((s) => s.az, scaleAccel, AppTheme.axisColors[2]);

    // Plot Gyroscope axes (gX, gY, gZ)
    plotAxis((s) => s.gx, scaleGyro, AppTheme.axisColors[3]);
    plotAxis((s) => s.gy, scaleGyro, AppTheme.axisColors[4]);
    plotAxis((s) => s.gz, scaleGyro, AppTheme.axisColors[5]);
  }

  @override
  bool shouldRepaint(covariant _LiveImuWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.bandName != bandName;
  }
}