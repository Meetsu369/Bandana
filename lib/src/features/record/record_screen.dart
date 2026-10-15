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
import '../../services/ml_service.dart';
import '../../utils/cadence_gate.dart';
import '../../utils/dual_band_window_manager.dart';
import '../../utils/session_boundary.dart';

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
    _notesController = TextEditingController(text: _sessionNotes);
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
    _notesController.dispose();
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

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
    _sessionNotes = _notesController.text.trim();
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
      _recordingStartTime = DateTime.now();
      _recordingStopped = false; // Reset flag for new recording
    });

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
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
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
        _notesController.clear();
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

        // 2. Split Telemetry Stream Bento (Wrist vs. Ankle)
        _buildSplitTelemetryStream(isDark),
        const SizedBox(height: 14),

        // 3. Live Dual-Band 6-Axis Graph Waveforms (Wrist & Ankle)
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

        // 4. Stop Action Button
        _buildStopButton(isDark),
      ],
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
          // Large activity display text
          Text(
            _selectedLabel,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
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