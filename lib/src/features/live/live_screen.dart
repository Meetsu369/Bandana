import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../models/imu_sample.dart';
import '../../models/prediction_result.dart';
import '../../services/activity_label_manager.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../shared/widgets/cards/activity_card.dart';
import '../../utils/dual_band_window_manager.dart';
import '../../utils/session_boundary.dart';
import '../../widgets/confidence_gauge.dart';
import '../record/record_screen.dart';
import '../settings/devices_screen.dart';
import '../training/training_screen.dart';

/// Item in the live prediction timeline holding user feedback state.
class LivePredictionItem {
  final String id;
  final PredictionResult prediction;
  bool? isCorrect;
  String? correctedLabel;

  LivePredictionItem({
    required this.id,
    required this.prediction,
    this.isCorrect,
    this.correctedLabel,
  });
}

/// Live Mode screen – real-time activity classification with honest connection/stale
/// state tracking, non-blocking wrist/ankle streams, neo-brutalist bento preview, and user feedback loop.
class LiveScreen extends StatefulWidget {
  final VoidCallback? onStartRecording;

  const LiveScreen({super.key, this.onStartRecording});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with SingleTickerProviderStateMixin {
  final _ble = getIt<BleService>();
  final _ml = getIt<MlService>();
  final _db = getIt<DatabaseService>();
  final _labelManager = getIt<ActivityLabelManager>();

  // ── State ──
  bool _isRunning = false;
  LivePredictionItem? _currentPredictionItem;
  final List<LivePredictionItem> _timeline = [];
  int _sessionCount = 0;

  late AnimationController _waveformController;

  final _windowManager = DualBandWindowManager(
    sessionDetector: DualBandSessionDetector(),
  );

  StreamSubscription<ImuSample>? _wristSensorSub;
  StreamSubscription<ImuSample>? _ankleSensorSub;
  StreamSubscription<BandConnectionState>? _wristBleSub;
  StreamSubscription<BandConnectionState>? _ankleBleSub;

  BandConnectionState _wristBleState = BandConnectionState.disconnected;
  BandConnectionState _ankleBleState = BandConnectionState.disconnected;

  // Stale data tracking
  DateTime? _lastSampleReceivedAt;
  bool _isDataStale = false;
  Timer? _staleCheckTimer;

  bool get _isTestEnvironment =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');

  @override
  void initState() {
    super.initState();
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (!_isTestEnvironment) {
      _waveformController.repeat();
    } else {
      _waveformController.value = 0.5;
    }

    _loadSessions();

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
    _waveformController.dispose();
    _stopStaleTimer();
    _wristSensorSub?.cancel();
    _ankleSensorSub?.cancel();
    _wristBleSub?.cancel();
    _ankleBleSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _db.getAllSessions();
      if (mounted) {
        setState(() {
          _sessionCount = sessions.length;
        });
      }
    } catch (e) {
      debugPrint('LiveScreen: Failed to load sessions: $e');
    }
  }

  void _navigateToRecord() {
    if (widget.onStartRecording != null) {
      widget.onStartRecording!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RecordScreen()),
      ).then((_) {
        _loadSessions();
        if (mounted) setState(() {});
      });
    }
  }

  void _navigateToTraining() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrainingScreen()),
    ).then((_) {
      _loadSessions();
      if (mounted) setState(() {});
    });
  }

  void _startStaleTimer() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!_isRunning) return;
      if (_lastSampleReceivedAt != null) {
        final elapsed = DateTime.now().difference(_lastSampleReceivedAt!);
        final nowStale = elapsed > const Duration(milliseconds: 2500);
        if (nowStale != _isDataStale && mounted) {
          setState(() => _isDataStale = nowStale);
        }
      }
    });
  }

  void _stopStaleTimer() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = null;
    _isDataStale = false;
  }

  void _start() {
    if (!_ml.isTrained && !_ml.isCombinedTrained) return;

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

    _windowManager.reset();
    _lastSampleReceivedAt = null;
    _isDataStale = false;
    _startStaleTimer();

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
    _stopStaleTimer();
    _windowManager.reset();
    if (mounted) setState(() => _isRunning = false);
  }

  void _onWristSensorData(ImuSample sample) {
    _lastSampleReceivedAt = DateTime.now();
    if (_isDataStale && mounted) {
      setState(() => _isDataStale = false);
    }
    _windowManager.addSample(sample);
    _tryPredict();
  }

  void _onAnkleSensorData(ImuSample sample) {
    _lastSampleReceivedAt = DateTime.now();
    if (_isDataStale && mounted) {
      setState(() => _isDataStale = false);
    }
    _windowManager.addSample(sample);
    _tryPredict();
  }

  void _tryPredict() {
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;

    if (!_windowManager.canConsumeDualBandWindow(hasWrist: hasWrist, hasAnkle: hasAnkle)) {
      return;
    }

    final consumed = _windowManager.tryConsumeDualBandWindow(
      hasWrist: hasWrist,
      hasAnkle: hasAnkle,
      validateDuration: true,
    );

    if (consumed == null) {
      debugPrint('Live: Invalid window duration or incomplete pair, waiting');
      return;
    }

    // Adaptive prediction selects appropriate model based on bands and models
    final result = _ml.predictAdaptive(
      wristWindow: consumed.wristWindow,
      ankleWindow: consumed.ankleWindow,
    );

    if (result != null && mounted) {
      setState(() {
        final item = LivePredictionItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          prediction: result,
        );
        _currentPredictionItem = item;
        _timeline.insert(0, item);
        if (_timeline.length > 30) {
          _timeline.removeLast();
        }
      });
    }
  }

  String _getModelVersionString() {
    if (_ml.isCombinedTrained) return 'dual_60';
    if (_ml.isTrained) return 'single_30';
    return 'active_model';
  }

  Future<void> _recordFeedback({
    required LivePredictionItem item,
    required bool isCorrect,
    String? correctedLabel,
  }) async {
    setState(() {
      item.isCorrect = isCorrect;
      item.correctedLabel = correctedLabel;
    });

    try {
      await _db.insertPredictionFeedback(
        predictedLabel: item.prediction.label,
        confidence: item.prediction.confidence,
        userFeedback: isCorrect ? 'correct' : 'incorrect',
        correctedLabel: correctedLabel,
        modelVersion: _getModelVersionString(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCorrect
                  ? 'Marked as correct ✓'
                  : 'Correction recorded: $correctedLabel',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to save feedback: $e');
    }
  }

  Future<void> _promptCorrectionDialog(LivePredictionItem item) async {
    final currentLabel = item.prediction.label;
    final activities = _labelManager.allLabels
        .where((l) => l.toLowerCase() != currentLabel.toLowerCase())
        .toList();

    String? selected = activities.isNotEmpty ? activities.first : null;
    final customController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Correct Activity'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Predicted: "$currentLabel". What were you actually doing?',
                      style: AppTypography.captionFor(Theme.of(context).brightness),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (activities.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selected,
                        decoration: InputDecoration(
                          labelText: 'Select actual activity',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        items: activities.map((label) {
                          return DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selected = val;
                            customController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Center(child: Text('— OR —')),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    TextField(
                      controller: customController,
                      decoration: InputDecoration(
                        labelText: 'Enter custom label',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      onChanged: (val) {
                        if (val.trim().isNotEmpty) {
                          setDialogState(() => selected = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final customText = customController.text.trim();
                    final finalLabel = customText.isNotEmpty ? customText : selected;
                    if (finalLabel != null && finalLabel.isNotEmpty) {
                      Navigator.of(context).pop(finalLabel);
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      await _recordFeedback(
        item: item,
        isCorrect: false,
        correctedLabel: result,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final hasWrist = _wristBleState == BandConnectionState.connected;
    final hasAnkle = _ankleBleState == BandConnectionState.connected;
    final bothConnected = hasWrist && hasAnkle;
    final hasModel = _ml.isTrained || _ml.isCombinedTrained;

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        backgroundColor: AppColors.background(brightness),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Live Recognition',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.ink(brightness),
            ),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DevicesScreen()),
              );
            },
            child: _buildSplitDevicePill(brightness, hasWrist, hasAnkle),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: !hasModel
          ? _buildUntrainedBentoView(
              brightness: brightness,
              hasWrist: hasWrist,
              hasAnkle: hasAnkle,
              bothConnected: bothConnected,
            )
          : _buildTrainedLiveView(
              brightness: brightness,
              hasWrist: hasWrist,
              hasAnkle: hasAnkle,
              bothConnected: bothConnected,
            ),
    );
  }

  /// Right Accessory: Split device connectivity badge enclosed in a neo-brutalist pill
  Widget _buildSplitDevicePill(Brightness brightness, bool hasWrist, bool hasAnkle) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: isLight ? AppShadows.hardSm(brightness) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDeviceMicroChip(
            label: 'Wrist',
            icon: Icons.watch_outlined,
            isConnected: hasWrist,
            brightness: brightness,
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 1.5,
            height: 14,
            color: strokeColor.withValues(alpha: 0.25),
          ),
          _buildDeviceMicroChip(
            label: 'Ankle',
            icon: Icons.directions_run,
            isConnected: hasAnkle,
            brightness: brightness,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceMicroChip({
    required String label,
    required IconData icon,
    required bool isConnected,
    required Brightness brightness,
  }) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);
    final dotColor = isConnected
        ? const Color(0xFF10B981) // Crisp vibrant emerald green
        : const Color(0xFFEF4444); // Crisp vibrant red
    final textColor = isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: textColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: strokeColor,
              width: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  /// Untrained State: Educational Simulation Card + Onboarding Guide + Dual Action CTAs
  Widget _buildUntrainedBentoView({
    required Brightness brightness,
    required bool hasWrist,
    required bool hasAnkle,
    required bool bothConnected,
  }) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroPreviewCard(brightness),
            const SizedBox(height: 12),
            _buildGuideBlock(
              brightness: brightness,
              hasWrist: hasWrist,
              hasAnkle: hasAnkle,
              bothConnected: bothConnected,
            ),
            const SizedBox(height: 14),
            _buildActionCtas(
              brightness: brightness,
              sessionCount: _sessionCount,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Hero Bento Preview Card (Replacing Dead Void)
  Widget _buildHeroPreviewCard(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFE9D5FF) : const Color(0xFF2E1B4E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: isLight ? AppShadows.hard(brightness) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Status badge PREVIEW MODE + Animated pulse icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: strokeColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLight ? const Color(0xFFD6F865) : const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'PREVIEW MODE',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: isLight ? Colors.white : const Color(0xFF18181B),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _waveformController,
                builder: (context, _) {
                  final pulseScale = 0.85 + 0.25 * math.sin(_waveformController.value * 2 * math.pi).abs();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : const Color(0xFF1E1E22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: strokeColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6 * pulseScale,
                          height: 6 * pulseScale,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFF3384),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.graphic_eq,
                          size: 13,
                          color: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Mock Telemetry UI
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Walking • 1.2 m/s',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF18181B),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.verified, size: 12, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      '98.4% Confidence',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF18181B),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Ghost skeleton waveform simulating live streams
          Container(
            height: 62,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.white.withValues(alpha: 0.65)
                  : Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (isLight ? const Color(0xFF18181B) : Colors.white).withValues(alpha: 0.18),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    top: 4,
                    child: Text(
                      'SIMULATED 6-AXIS IMU STREAM (40Hz)',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: (isLight ? const Color(0xFF18181B) : Colors.white).withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _waveformController,
                    builder: (context, _) {
                      return CustomPaint(
                        size: const Size(double.infinity, 62),
                        painter: GhostWaveformPainter(
                          animationProgress: _waveformController.value,
                          isLight: isLight,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Actionable Onboarding & Guide Block
  Widget _buildGuideBlock({
    required Brightness brightness,
    required bool hasWrist,
    required bool hasAnkle,
    required bool bothConnected,
  }) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: isLight ? AppShadows.hard(brightness) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.limeYellow(brightness),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: Color(0xFF18181B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ready to analyze your movement?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Collect motion data from your bands to train your personal AI recognition model.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFFAF8F5) : const Color(0xFF121316),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isLight ? const Color(0xFFE4E4E7) : const Color(0xFF27272A),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                _buildChecklistItem(
                  title: 'Bands Connected',
                  subtitle: bothConnected
                      ? 'Wrist & Ankle paired'
                      : (hasWrist ? 'Wrist paired (pair Ankle)' : (hasAnkle ? 'Ankle paired (pair Wrist)' : 'Wrist & Ankle disconnected')),
                  isComplete: hasWrist && hasAnkle,
                  brightness: brightness,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, thickness: 1),
                ),
                _buildChecklistItem(
                  title: 'Baseline Data',
                  subtitle: _sessionCount > 0
                      ? '$_sessionCount recorded ${_sessionCount == 1 ? 'session' : 'sessions'} ready'
                      : 'At least 1 recorded session needed',
                  isComplete: _sessionCount > 0,
                  brightness: brightness,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required String title,
    required String subtitle,
    required bool isComplete,
    required Brightness brightness,
  }) {
    final isLight = brightness == Brightness.light;
    final badgeColor = isComplete
        ? const Color(0xFFD1FAE5) // Connected / complete fill
        : const Color(0xFFFEE2E2); // Disconnected / incomplete fill
    final iconColor = isComplete
        ? const Color(0xFF065F46) // Connected text/border
        : const Color(0xFF991B1B); // Disconnected text/border
    final iconData = isComplete ? Icons.check : Icons.close;

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: badgeColor,
            shape: BoxShape.circle,
            border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Center(
            child: Icon(iconData, size: 15, color: iconColor),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: isLight ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Dynamic Action CTAs based on session count and training state
  Widget _buildActionCtas({
    required Brightness brightness,
    required int sessionCount,
  }) {
    final isLight = brightness == Brightness.light;
    final isModelReadyForTraining = sessionCount > 0;

    return Column(
      children: [
        // Primary CTA (Full width)
        _buildNeoButton(
          label: isModelReadyForTraining ? 'Train Movement Model' : 'Record First Session',
          leadingIcon: isModelReadyForTraining ? Icons.bolt : Icons.fiber_manual_record,
          backgroundColor: const Color(0xFFFF3384),
          textColor: Colors.white,
          brightness: brightness,
          height: 48,
          onTap: () {
            if (isModelReadyForTraining) {
              _navigateToTraining();
            } else {
              _navigateToRecord();
            }
          },
        ),
        const SizedBox(height: 8),
        // Secondary Ghost Action
        _buildNeoButton(
          label: isModelReadyForTraining ? 'Record Another Session' : 'Manage & Train Models',
          leadingIcon: isModelReadyForTraining ? Icons.fiber_manual_record : Icons.settings,
          backgroundColor: isLight ? Colors.white : const Color(0xFF1E2024),
          textColor: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
          brightness: brightness,
          height: 48,
          onTap: () {
            if (isModelReadyForTraining) {
              _navigateToRecord();
            } else {
              _navigateToTraining();
            }
          },
        ),
      ],
    );
  }

  Widget _buildNeoButton({
    required String label,
    required IconData leadingIcon,
    required Color backgroundColor,
    required Color textColor,
    required Brightness brightness,
    required VoidCallback onTap,
    double height = 50,
  }) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: isLight ? AppShadows.hard(brightness) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(leadingIcon, size: 18, color: textColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Trained State: Live Telemetry Feed, Real-time Activity Class & Streams
  Widget _buildTrainedLiveView({
    required Brightness brightness,
    required bool hasWrist,
    required bool hasAnkle,
    required bool bothConnected,
  }) {
    final isLight = brightness == Brightness.light;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Single clean Status Row
            _buildStatusBar(
              hasWrist: hasWrist,
              hasAnkle: hasAnkle,
              bothConnected: bothConnected,
              brightness: brightness,
            ),
            const SizedBox(height: AppSpacing.md),

            // Stale Data Warning
            if (_isRunning && _isDataStale) ...[
              _buildStaleWarningBanner(brightness),
              const SizedBox(height: AppSpacing.md),
            ],

            // Model Capability Notice (if both connected but only 30-feature trained)
            if (bothConnected && !_ml.isCombinedTrained && _ml.isTrained) ...[
              _buildDualBandNotice(brightness),
              const SizedBox(height: AppSpacing.md),
            ],

            // Main Prediction Hero Card
            _buildHeroPredictionCard(brightness),
            const SizedBox(height: AppSpacing.lg),

            // Start / Stop CTA
            _buildNeoButton(
              label: _isRunning ? 'Stop Recognition' : 'Start Recognition',
              leadingIcon: _isRunning ? Icons.stop : Icons.play_arrow,
              backgroundColor: _isRunning
                  ? (isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038))
                  : const Color(0xFFFF3384),
              textColor: Colors.white,
              brightness: brightness,
              onTap: _isRunning ? _stop : _start,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Prediction Timeline
            _buildTimelineSection(brightness),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar({
    required bool hasWrist,
    required bool hasAnkle,
    required bool bothConnected,
    required Brightness brightness,
  }) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: isLight ? AppShadows.hardSm(brightness) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Connection summary
          Row(
            children: [
              Icon(
                bothConnected
                    ? Icons.sensors
                    : (hasWrist || hasAnkle ? Icons.sensors : Icons.sensors_off),
                size: 18,
                color: (hasWrist || hasAnkle) ? AppColors.success(brightness) : AppColors.danger(brightness),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                bothConnected
                    ? 'Dual Bands'
                    : hasWrist
                        ? 'Wrist Only'
                        : hasAnkle
                            ? 'Ankle Only'
                            : 'No Bands',
                style: AppTypography.captionFor(brightness).copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink(brightness),
                ),
              ),
            ],
          ),
          // Active Model summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFFAF8F5) : const Color(0xFF121316),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: strokeColor.withValues(alpha: 0.3), width: 1.0),
            ),
            child: Text(
              _ml.isCombinedTrained
                  ? '60-feat Dual Model'
                  : _ml.isTrained
                      ? '30-feat Single Model'
                      : 'No Model',
              style: AppTypography.captionFor(brightness).copyWith(
                fontWeight: FontWeight.w700,
                color: _ml.isCombinedTrained ? AppColors.secondaryStrong(brightness) : AppColors.secondaryInfo(brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaleWarningBanner(Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.warning, width: 2.0),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: context.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Sensor data is stale (no samples for > 2.5s). Waiting for firmware packets…',
              style: AppTypography.captionFor(brightness).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDualBandNotice(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.disabledSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: strokeColor,
          width: 2.0,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: context.secondaryInfo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Dual bands connected, but dual-band (60-feat) model is not trained. Single-band model will not be substituted.',
              style: AppTypography.captionFor(brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPredictionCard(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);
    final item = _currentPredictionItem;
    final pred = item?.prediction;
    final colors = pred != null
        ? ActivityCard.colorsForLabel(pred.label)
        : [AppColors.ink(brightness), AppColors.ink(brightness)];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: isLight ? AppShadows.hard(brightness) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isRunning) ...[
            ConfidenceGauge(
              confidence: null,
              size: 150,
              child: Icon(
                Icons.play_circle_outline,
                size: 44,
                color: AppColors.secondaryInfo(brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Ready for Live Recognition',
              style: AppTypography.h3For(brightness).copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink(brightness),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Press Start to begin real-time activity classification.',
              style: AppTypography.captionFor(brightness).copyWith(
                color: AppColors.secondaryInfo(brightness),
              ),
              textAlign: TextAlign.center,
            ),
          ] else if (pred == null) ...[
            ConfidenceGauge(
              confidence: null,
              size: 150,
              child: Icon(
                Icons.sensors,
                size: 44,
                color: AppColors.primaryAccent(brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Buffering sensor window…',
              style: AppTypography.h3For(brightness).copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink(brightness),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Collecting 80 samples at 40 Hz (2.0 seconds).',
              style: AppTypography.captionFor(brightness).copyWith(
                color: AppColors.secondaryInfo(brightness),
              ),
            ),
          ] else ...[
            ConfidenceGauge(
              confidence: pred.confidence,
              size: 160,
              child: Icon(
                ActivityCard.iconForLabel(pred.label),
                size: 40,
                color: colors[0],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              pred.label,
              style: AppTypography.h1For(brightness).copyWith(
                color: colors[0],
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Confidence: ${pred.confidencePercent != null ? '${pred.confidencePercent}%' : 'N/A (KNN)'}',
              style: AppTypography.captionFor(brightness).copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryInfo(brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Quick Feedback Buttons for latest prediction
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item!.isCorrect == null) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success(brightness),
                      side: BorderSide(color: AppColors.success(brightness), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                    label: const Text('Correct', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () => _recordFeedback(item: item, isCorrect: true),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger(brightness),
                      side: BorderSide(color: AppColors.danger(brightness), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    icon: const Icon(Icons.thumb_down_alt_outlined, size: 16),
                    label: const Text('Incorrect', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () => _promptCorrectionDialog(item),
                  ),
                ] else if (item.isCorrect == true) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success(brightness).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.success(brightness), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: AppColors.success(brightness)),
                        const SizedBox(width: 6),
                        Text(
                          'Marked Correct ✓',
                          style: AppTypography.captionFor(brightness).copyWith(
                            color: AppColors.success(brightness),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warning(brightness).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.warning(brightness), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 16, color: AppColors.warning(brightness)),
                        const SizedBox(width: 6),
                        Text(
                          'Corrected to "${item.correctedLabel}"',
                          style: AppTypography.captionFor(brightness).copyWith(
                            color: AppColors.warning(brightness),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineSection(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final strokeColor = isLight ? const Color(0xFF18181B) : const Color(0xFF2E3038);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Prediction Timeline',
              style: AppTypography.h3For(brightness).copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink(brightness),
              ),
            ),
            if (_timeline.isNotEmpty)
              Text(
                '${_timeline.length} events',
                style: AppTypography.captionFor(brightness).copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryInfo(brightness),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_timeline.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface(brightness),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: strokeColor, width: 2.0),
              boxShadow: isLight ? AppShadows.hardSm(brightness) : null,
            ),
            child: Center(
              child: Text(
                'No predictions yet. Predictions will stream here in real time.',
                style: AppTypography.captionFor(brightness).copyWith(
                  color: AppColors.secondaryInfo(brightness),
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _timeline.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final item = _timeline[index];
              final pred = item.prediction;
              final colors = ActivityCard.colorsForLabel(pred.label);
              final timeStr =
                  '${pred.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${pred.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${pred.timestamp.second.toString().padLeft(2, '0')}';

              return Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface(brightness),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: strokeColor, width: 2.0),
                  boxShadow: isLight ? AppShadows.hardSm(brightness) : null,
                ),
                child: Row(
                  children: [
                    // Activity Icon
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: colors[0].withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        ActivityCard.iconForLabel(pred.label),
                        color: colors[0],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pred.label,
                            style: AppTypography.bodyFor(brightness).copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink(brightness),
                            ),
                          ),
                          Text(
                            '$timeStr • ${pred.confidencePercent != null ? '${pred.confidencePercent}%' : 'N/A'}',
                            style: AppTypography.captionFor(brightness).copyWith(
                              color: AppColors.secondaryInfo(brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Feedback status / buttons
                    if (item.isCorrect == null) ...[
                      IconButton(
                        icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                        color: AppColors.success(brightness),
                        tooltip: 'Correct',
                        onPressed: () => _recordFeedback(item: item, isCorrect: true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                        color: AppColors.danger(brightness),
                        tooltip: 'Incorrect',
                        onPressed: () => _promptCorrectionDialog(item),
                      ),
                    ] else if (item.isCorrect == true) ...[
                      Icon(Icons.check_circle, size: 20, color: AppColors.success(brightness)),
                    ] else ...[
                      Tooltip(
                        message: 'Corrected to ${item.correctedLabel}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning(brightness).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            item.correctedLabel ?? 'Edited',
                            style: AppTypography.captionFor(brightness).copyWith(
                              color: AppColors.warning(brightness),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Custom painter for the ghost skeleton waveform simulating 6-DOF IMU streams
class GhostWaveformPainter extends CustomPainter {
  final double animationProgress;
  final bool isLight;

  GhostWaveformPainter({
    required this.animationProgress,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final centerY = size.height * 0.55;
    final width = size.width;

    // Draw subtle grid lines
    final gridPaint = Paint()
      ..color = (isLight ? const Color(0xFF18181B) : Colors.white).withValues(alpha: 0.06)
      ..strokeWidth = 1.0;
    for (double x = 0; x < width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    canvas.drawLine(Offset(0, centerY), Offset(width, centerY), gridPaint);

    // Channel 1: Accel X - Vibrant Pink (#FF3384)
    _drawSineWave(
      canvas: canvas,
      size: size,
      centerY: centerY,
      amplitude: 14.0,
      frequency: 2.2,
      phase: animationProgress * 2 * math.pi,
      color: const Color(0xFFFF3384),
      strokeWidth: 2.2,
    );

    // Channel 2: Accel Y - Deep Violet (#8B5CF6)
    _drawSineWave(
      canvas: canvas,
      size: size,
      centerY: centerY + 2,
      amplitude: 10.0,
      frequency: 3.4,
      phase: (animationProgress * 2 * math.pi) + 1.2,
      color: isLight ? const Color(0xFF7C3AED) : const Color(0xFFA78BFA),
      strokeWidth: 1.8,
    );

    // Channel 3: Accel Z - Cobalt Blue (#3B82F6)
    _drawSineWave(
      canvas: canvas,
      size: size,
      centerY: centerY - 2,
      amplitude: 12.0,
      frequency: 1.6,
      phase: (animationProgress * 2 * math.pi) + 2.5,
      color: isLight ? const Color(0xFF2563EB) : const Color(0xFF60A5FA),
      strokeWidth: 1.8,
    );
  }

  void _drawSineWave({
    required Canvas canvas,
    required Size size,
    required double centerY,
    required double amplitude,
    required double frequency,
    required double phase,
    required Color color,
    required double strokeWidth,
  }) {
    final path = Path();
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const points = 70;
    for (int i = 0; i <= points; i++) {
      final x = (size.width / points) * i;
      final normalizedX = x / size.width;
      // Damped window edges so wave smoothly enters and exits the viewport
      final envelope = math.sin(normalizedX * math.pi);
      final y = centerY + math.sin(normalizedX * frequency * 2 * math.pi + phase) * amplitude * envelope;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GhostWaveformPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.isLight != isLight;
  }
}