import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/ble_constants.dart';
import '../../features/record/session_detail_screen.dart';
import '../../services/band_assignment_manager.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../widgets/activity_card.dart';

/// Dashboard screen – high-level summary of recorded activities and model status.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = getIt<DatabaseService>();
  final _ml = getIt<MlService>();
  final _ble = getIt<BleService>();
  final _assignment = getIt<BandAssignmentManager>();

  Map<String, ({int sessionCount, int totalSamples})> _summaries = {};
  List<Session> _sessions = [];
  bool _isLoading = true;
  bool _isTraining = false;
  String? _trainingError;

  StreamSubscription<BandConnectionState>? _wristSub;
  StreamSubscription<BandConnectionState>? _ankleSub;
  BandConnectionState _wristState = BandConnectionState.disconnected;
  BandConnectionState _ankleState = BandConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _loadData();
    _wristState = _ble.wrist.currentState;
    _ankleState = _ble.ankle.currentState;
    _wristSub = _ble.wrist.stateStream.listen((state) {
      if (mounted) setState(() => _wristState = state);
    });
    _ankleSub = _ble.ankle.stateStream.listen((state) {
      if (mounted) setState(() => _ankleState = state);
    });
  }

  @override
  void dispose() {
    _wristSub?.cancel();
    _ankleSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final summaries = await _db.getSessionSummaries();
    final sessions = await _db.getAllSessions();
    if (mounted) {
      setState(() {
        _summaries = summaries;
        _sessions = sessions;
        _isLoading = false;
      });
    }
  }

  Future<void> _trainModel({bool combined = false}) async {
    setState(() {
      _isTraining = true;
      _trainingError = null;
    });

    try {
      final data = await _db.getAllWindowsForTraining();
      if (data.length < 2) {
        setState(() {
          _trainingError = 'Need at least 2 labeled windows to train.';
          _isTraining = false;
        });
        return;
      }

      final labels = data.map((d) => d.label).toSet();
      if (labels.length < 2) {
        setState(() {
          _trainingError = 'Need at least 2 different activity labels.';
          _isTraining = false;
        });
        return;
      }

      // Run training (computationally intensive for large datasets).
      // Convert to format expected by ML service (features, label only)
      final trainingData = data.map((d) => (features: d.features, label: d.label)).toList();
      final success = combined
          ? _ml.trainCombined(trainingData)
          : _ml.trainSingleBand(trainingData);

      if (mounted) {
        setState(() {
          _isTraining = false;
          if (!success) {
            _trainingError = 'Training failed. Check your data.';
          }
        });
        if (success) {
          if (combined) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Combined model trained! ${_ml.trainedClassCountCombined} classes, '
                  '${_ml.trainedSampleCountCombined} samples.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Single-band model trained! ${_ml.trainedClassCount} classes, '
                  '${_ml.trainedSampleCount} samples.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTraining = false;
          _trainingError = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSamples =
        _summaries.values.fold<int>(0, (sum, v) => sum + v.totalSamples);
    final totalSessions =
        _summaries.values.fold<int>(0, (sum, v) => sum + v.sessionCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandana'),
        actions: [
          _buildBandStatusChip(theme, BandRole.wrist, _wristState),
          const SizedBox(width: 4),
          _buildBandStatusChip(theme, BandRole.ankle, _ankleState),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                children: [
                  // ── Model Status Card ──
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _ml.isTrained || _ml.isCombinedTrained
                                    ? Icons.check_circle
                                    : Icons.model_training,
                                color: _ml.isTrained || _ml.isCombinedTrained
                                    ? Colors.green
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ML Models',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildStatRow(
                            'Single-Band (30 feat)',
                            _ml.isTrained ? 'Trained ✓' : 'Not trained',
                            theme,
                          ),
                          if (_ml.isTrained) ...[
                            _buildStatRow(
                              'Classes (30-feat)',
                              '${_ml.trainedClassCount}',
                              theme,
                            ),
                            _buildStatRow(
                              'Samples (30-feat)',
                              '${_ml.trainedSampleCount}',
                              theme,
                            ),
                          ],
                          const SizedBox(height: 8),
                          _buildStatRow(
                            'Combined Dual-Band (60 feat)',
                            _ml.isCombinedTrained ? 'Trained ✓' : 'Not trained',
                            theme,
                          ),
                          if (_ml.isCombinedTrained) ...[
                            _buildStatRow(
                              'Classes (60-feat)',
                              '${_ml.trainedClassCountCombined}',
                              theme,
                            ),
                            _buildStatRow(
                              'Samples (60-feat)',
                              '${_ml.trainedSampleCountCombined}',
                              theme,
                            ),
                          ],
                          _buildStatRow(
                            'Total Recordings',
                            '$totalSessions sessions',
                            theme,
                          ),
                          _buildStatRow(
                            'Total Windows',
                            '$totalSamples',
                            theme,
                          ),
                          if (_trainingError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _trainingError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),

                  // ── Band Status ──
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Band Status',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingSm),
                          Row(
                            children: [
                              Expanded(
                                child: _buildBandDetail(
                                  theme,
                                  BandRole.wrist,
                                  _wristState,
                                  _assignment.wristDeviceName,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildBandDetail(
                                  theme,
                                  BandRole.ankle,
                                  _ankleState,
                                  _assignment.ankleDeviceName,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),

                  // ── Section header ──
                  Text(
                    'Recorded Activities',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),

                  // ── Activity Grid ──
                  if (_summaries.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTheme.spacingLg),
                        child: Column(
                          children: [
                            Icon(
                              Icons.sensors_off,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No recordings yet',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Go to the Record tab to start collecting data.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: _summaries.length,
                      itemBuilder: (context, index) {
                        final entry = _summaries.entries.elementAt(index);
                        return ActivityCard(
                          label: entry.key,
                          sessionCount: entry.value.sessionCount,
                          totalSamples: entry.value.totalSamples,
                        );
                      },
                    ),

                   // ── Session List ──
                   const SizedBox(height: AppTheme.spacingMd),
                   Text(
                     'All Sessions',
                     style: theme.textTheme.titleSmall?.copyWith(
                       fontWeight: FontWeight.w600,
                       color: theme.colorScheme.onSurfaceVariant,
                     ),
                   ),
                   const SizedBox(height: AppTheme.spacingSm),
                   if (_sessions.isEmpty)
                     Card(
                       child: Padding(
                         padding: const EdgeInsets.all(AppTheme.spacingLg),
                         child: Column(
                           children: [
                             Icon(
                               Icons.history,
                               size: 48,
                               color: theme.colorScheme.onSurfaceVariant,
                             ),
                             const SizedBox(height: 12),
                             Text(
                               'No sessions yet',
                               style: theme.textTheme.bodyLarge?.copyWith(
                                 color: theme.colorScheme.onSurfaceVariant,
                               ),
                             ),
                             const SizedBox(height: 4),
                             Text(
                               'Start recording to create sessions.',
                               style: theme.textTheme.bodySmall?.copyWith(
                                 color: theme.colorScheme.onSurfaceVariant,
                               ),
                               textAlign: TextAlign.center,
                             ),
                           ],
                         ),
                       ),
                     )
                   else
                     ListView.separated(
                       shrinkWrap: true,
                       physics: const NeverScrollableScrollPhysics(),
                       itemCount: _sessions.length,
                       separatorBuilder: (_, __) => const Divider(height: 1),
                       itemBuilder: (context, index) {
                         final session = _sessions[index];
                         final duration = session.endTime != null
                             ? session.endTime!.difference(session.startTime)
                             : DateTime.now().difference(session.startTime);
                         final hours = duration.inHours;
                         final minutes = duration.inMinutes % 60;
                         final seconds = duration.inSeconds % 60;
                         String durationStr;
                         if (hours > 0) {
                           durationStr = '${hours}h ${minutes}m ${seconds}s';
                         } else if (minutes > 0) {
                           durationStr = '${minutes}m ${seconds}s';
                         } else {
                           durationStr = '${seconds}s';
                         }
                         final dateStr =
                             '${session.startTime.year}-${session.startTime.month.toString().padLeft(2, '0')}-${session.startTime.day.toString().padLeft(2, '0')} '
                             '${session.startTime.hour.toString().padLeft(2, '0')}:${session.startTime.minute.toString().padLeft(2, '0')}';
                         return ListTile(
                           dense: true,
                           leading: CircleAvatar(
                             backgroundColor: theme.colorScheme.primaryContainer,
                             child: Text(
                               session.id.toString(),
                               style: theme.textTheme.labelMedium?.copyWith(
                                 color: theme.colorScheme.onPrimaryContainer,
                                 fontWeight: FontWeight.w600,
                               ),
                             ),
                           ),
                           title: Text(session.label),
                           subtitle: Text(
                             '$dateStr  •  $durationStr  •  ${session.sampleCount} windows',
                             style: theme.textTheme.bodySmall?.copyWith(
                               color: theme.colorScheme.onSurfaceVariant,
                             ),
                           ),
                           trailing: const Icon(Icons.chevron_right),
                           onTap: () => Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (_) => SessionDetailScreen(sessionId: session.id),
                             ),
                           ),
                         );
                       },
                     ),
                ],
              ),
      ),
      // ── Train FAB ──
      floatingActionButton: _isTraining
          ? FloatingActionButton.extended(
              onPressed: null,
              icon: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: const Text('Training…'),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'train-single',
                  onPressed: () => _trainModel(combined: false),
                  icon: const Icon(Icons.model_training),
                  label: const Text('Train 30-Feat'),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'train-combined',
                  onPressed: () => _trainModel(combined: true),
                  icon: const Icon(Icons.model_training),
                  label: const Text('Train 60-Feat'),
                  backgroundColor: Colors.orange,
                ),
              ],
            ),
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

  Widget _buildBandDetail(
    ThemeData theme,
    BandRole role,
    BandConnectionState state,
    String? deviceName,
  ) {
    final stateColor = switch (state) {
      BandConnectionState.connected => Colors.green,
      BandConnectionState.scanning => Colors.blue,
      BandConnectionState.connecting => Colors.orange,
      BandConnectionState.disconnected => Colors.red,
    };
    final stateLabel = switch (state) {
      BandConnectionState.connected => 'Connected',
      BandConnectionState.scanning => 'Scanning…',
      BandConnectionState.connecting => 'Connecting…',
      BandConnectionState.disconnected => 'Disconnected',
    };

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: role.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: role.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(role.icon, size: 20, color: role.color),
              const SizedBox(width: 8),
              Text(
                '${role.displayName} Band',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: role.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stateLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: stateColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (deviceName != null) ...[
            const SizedBox(height: 4),
            Text(
              deviceName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Not assigned',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}