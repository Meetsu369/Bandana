import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../shared/widgets/cards/band_status_card.dart';
import '../../shared/widgets/cards/hero_metric_card.dart';
import '../../shared/widgets/cards/metric_card.dart';
import '../../shared/widgets/feedback/empty_state.dart';
import '../../shared/widgets/feedback/loading_state.dart';
import '../../shared/widgets/feedback/error_state.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/section_header.dart';
import '../../features/record/record_screen.dart';
import '../../features/record/session_detail_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/settings/devices_screen.dart';

/// Home screen – polished professional BANDANA experience.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ble = getIt<BleService>();
  final _db = getIt<DatabaseService>();
  final _ml = getIt<MlService>();

  // Data state
  List<Session> _recentSessions = [];
  int _todaySessionCount = 0;
  int _totalSessions = 0;
  int _totalWindows = 0;

  // Connection state
  BandConnectionState _wristState = BandConnectionState.disconnected;
  BandConnectionState _ankleState = BandConnectionState.disconnected;
  String? _wristDeviceName;
  String? _ankleDeviceName;

  // Loading/error states
  bool _isLoading = true;
  String? _error;

  // Subscriptions
  StreamSubscription<BandConnectionState>? _wristSub;
  StreamSubscription<BandConnectionState>? _ankleSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToConnections();
  }

  @override
  void dispose() {
    _wristSub?.cancel();
    _ankleSub?.cancel();
    super.dispose();
  }

  void _listenToConnections() {
    _wristState = _ble.wrist.currentState;
    _ankleState = _ble.ankle.currentState;
    _wristDeviceName = _ble.wrist.deviceName;
    _ankleDeviceName = _ble.ankle.deviceName;

    _wristSub = _ble.wrist.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _wristState = state;
        });
      }
    });

    _ankleSub = _ble.ankle.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _ankleState = state;
        });
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summaries = await _db.getSessionSummaries();
      final sessions = await _db.getAllSessions();

      // Calculate today's sessions
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todaySessions = sessions.where((s) => s.startTime.isAfter(todayStart)).toList();

      final totalSessions = sessions.length;
      final totalWindows = summaries.values.fold<int>(0, (sum, v) => sum + v.totalSamples);

      if (mounted) {
        setState(() {
          _recentSessions = sessions.take(5).toList(); // Show 5 most recent
          _todaySessionCount = todaySessions.length;
          _totalSessions = totalSessions;
          _totalWindows = totalWindows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load activity data';
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToRecord() {
    // Navigate to Collect tab (index 2)
    // We need to find the AppShell and change its index
    // Since we can't easily access AppShell from here, we'll push the RecordScreen
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecordScreen()),
    ).then((_) => _loadData()); // Refresh on return
  }

  void _navigateToHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoryScreen(onStartRecording: _navigateToRecord),
      ),
    ).then((_) => _loadData());
  }

  void _navigateToSessionDetail(int sessionId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionDetailScreen(sessionId: sessionId)),
    ).then((_) => _loadData());
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _getReadinessText() {
    final hasWrist = _wristState == BandConnectionState.connected;
    final hasAnkle = _ankleState == BandConnectionState.connected;

    if (hasWrist && hasAnkle) {
      return 'Dual-band ready';
    } else if (hasWrist) {
      return 'Wrist ready — connect Ankle for dual-band';
    } else if (hasAnkle) {
      return 'Ankle ready — connect Wrist for dual-band';
    } else {
      return 'Connect a band to start';
    }
  }

  String _getReadinessSubtext() {
    final hasWrist = _wristState == BandConnectionState.connected;
    final hasAnkle = _ankleState == BandConnectionState.connected;

    if (hasWrist && hasAnkle) {
      return 'Both bands connected and streaming';
    } else if (hasWrist || hasAnkle) {
      return 'Single-band recording available';
    } else {
      return 'No bands connected';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final hasWrist = _wristState == BandConnectionState.connected;
    final hasAnkle = _ankleState == BandConnectionState.connected;
    final anyConnected = hasWrist || hasAnkle;
    final bothConnected = hasWrist && hasAnkle;
    final modelReady = _ml.isTrained || _ml.isCombinedTrained;
    final hasData = _recentSessions.isNotEmpty;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const LoadingState.generic(
          message: 'Loading your activity…',
          fullScreen: true,
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ErrorState.generic(
              message: _error!,
              primaryAction: PrimaryButton(
                label: 'Retry',
                leadingIcon: Icons.refresh,
                onPressed: _loadData,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              // ── Header / Greeting ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: AppTypography.h1For(brightness).copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _getReadinessSubtext(),
                              style: AppTypography.bodyMediumFor(brightness).copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Hero Card: Today's Activity / Recording Readiness ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: HeroMetricCard(
                    label: _todaySessionCount > 0 ? "Today's activity" : 'Ready to record',
                    value: _todaySessionCount > 0 ? '$_todaySessionCount' : '—',
                    unit: _todaySessionCount == 1 ? 'session' : 'sessions',
                    description: _todaySessionCount > 0
                        ? 'Keep going — every session counts'
                        : _getReadinessText(),
                    leading: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: anyConnected
                            ? (bothConnected ? theme.colorScheme.secondaryContainer : theme.colorScheme.primaryContainer)
                            : theme.colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        anyConnected
                            ? (bothConnected ? Icons.directions_walk : Icons.watch)
                            : Icons.sensors_off,
                        size: 28,
                        color: anyConnected
                            ? (bothConnected ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onPrimaryContainer)
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    trailingAction: anyConnected
                        ? PrimaryButton(
                            label: 'Start Recording',
                            leadingIcon: Icons.fiber_manual_record,
                            showArrow: true,
                            onPressed: _navigateToRecord,
                            height: 44,
                          )
                        : null,
                    valueColor: anyConnected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    gradient: anyConnected && bothConnected
                        ? LinearGradient(
                            colors: [
                              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                              theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    isTappable: anyConnected,
                    onTap: _navigateToRecord,
                    semanticsLabel: _todaySessionCount > 0
                        ? "Today's activity: $_todaySessionCount sessions recorded"
                        : 'Ready to record: ${_getReadinessText()}',
                  ),
                ),
              ),

              // ── Band Readiness ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: SectionHeader(
                    title: 'Band Readiness',
                    subtitle: _getReadinessText(),
                    leadingIcon: Icons.bluetooth_connected,
                    leadingIconColor: theme.colorScheme.primary,
                    action: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DevicesScreen()),
                        );
                      },
                      child: Text(
                        'Manage',
                        style: AppTypography.labelFor(brightness).copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: BandStatusCard(
                    wristState: _wristState,
                    ankleState: _ankleState,
                    wristDeviceName: _wristDeviceName,
                    ankleDeviceName: _ankleDeviceName,
                    showSignal: false,
                    showDeviceNames: true,
                    onManageTap: null,
                  ),
                ),
              ),

              // ── Activity Summary ──
              if (hasData) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: SectionHeader(
                      title: 'Activity Summary',
                      subtitle: '$_totalSessions sessions • $_totalWindows windows',
                      leadingIcon: Icons.analytics_outlined,
                      leadingIconColor: theme.colorScheme.primary,
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Use 2 columns on wider screens, 1 on narrow
                        final crossAxisCount = constraints.maxWidth > 400 ? 2 : 1;
                        final cards = <Widget>[];

                        // Today's sessions
                        cards.add(MetricCard(
                          label: "Today's Sessions",
                          value: _todaySessionCount.toString(),
                          unit: 'sessions',
                          supportingText: _todaySessionCount > 0 ? 'Well done!' : 'Start your first session',
                          leadingIcon: Icons.today_outlined,
                          valueColor: _todaySessionCount > 0 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          onTap: _navigateToRecord,
                          semanticsLabel: "Today's sessions: $_todaySessionCount",
                        ));

                        // Total sessions
                        cards.add(MetricCard(
                          label: 'Total Sessions',
                          value: _totalSessions.toString(),
                          unit: 'sessions',
                          supportingText: 'All time',
                          leadingIcon: Icons.history_outlined,
                          valueColor: theme.colorScheme.onSurface,
                          semanticsLabel: 'Total sessions: $_totalSessions',
                        ));

                        // Total windows
                        cards.add(MetricCard(
                          label: 'Feature Windows',
                          value: _totalWindows.toString(),
                          unit: 'windows',
                          supportingText: 'For training',
                          leadingIcon: Icons.data_array_outlined,
                          valueColor: theme.colorScheme.onSurface,
                          semanticsLabel: 'Total feature windows: $_totalWindows',
                        ));

                        // Model status
                        final modelText = _ml.isCombinedTrained
                            ? 'Dual-band ready (60 feat)'
                            : _ml.isTrained
                                ? 'Single-band ready (30 feat)'
                                : 'Not trained';
                        final modelColor = _ml.isCombinedTrained
                            ? theme.colorScheme.secondary
                            : _ml.isTrained
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant;

                        cards.add(MetricCard(
                          label: 'Model Status',
                          value: _ml.isTrained || _ml.isCombinedTrained ? 'Ready' : 'Not trained',
                          supportingText: modelText,
                          leadingIcon: Icons.psychology_outlined,
                          valueColor: modelColor,
                          semanticsLabel: 'Model: $modelText',
                        ));

                        // Latest activity (if any)
                        if (_recentSessions.isNotEmpty) {
                          final latest = _recentSessions.first;
                          final duration = latest.endTime != null
                              ? latest.endTime!.difference(latest.startTime)
                              : DateTime.now().difference(latest.startTime);
                          final mins = duration.inMinutes;
                          final secs = duration.inSeconds % 60;
                          final durStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';

                          cards.add(MetricCard(
                            label: 'Latest Activity',
                            value: latest.label,
                            supportingText: '$durStr • ${_formatDate(latest.startTime)}',
                            leadingIcon: Icons.directions_run_outlined,
                            valueColor: theme.colorScheme.primary,
                            onTap: () => _navigateToSessionDetail(latest.id),
                            semanticsLabel: 'Latest activity: ${latest.label}, $durStr',
                          ));
                        }

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: AppSpacing.sm,
                            crossAxisSpacing: AppSpacing.sm,
                            childAspectRatio: crossAxisCount == 2 ? 1.3 : 2.2,
                          ),
                          itemCount: cards.length,
                          itemBuilder: (context, index) => cards[index],
                        );
                      },
                    ),
                  ),
                ),
              ],

              // ── Recent Sessions ──
              if (hasData) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: SectionHeader(
                      title: 'Recent Sessions',
                      subtitle: 'Tap to view details',
                      leadingIcon: Icons.history_outlined,
                      leadingIconColor: theme.colorScheme.primary,
                      action: TextButton(
                        onPressed: _navigateToHistory,
                        child: Text(
                          'See all →',
                          style: AppTypography.labelFor(brightness).copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Column(
                      children: _recentSessions.map((session) {
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

                        final dateStr = _formatDate(session.startTime);

                        return Card(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                session.id.toString(),
                                style: AppTypography.labelSmallFor(brightness).copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(
                              session.label,
                              style: AppTypography.bodyMediumFor(brightness).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '$dateStr  •  $durationStr  •  ${session.sampleCount} windows',
                              style: AppTypography.bodySmallFor(brightness).copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _navigateToSessionDetail(session.id),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ] else ...[
                // Empty state when no sessions
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: EmptyState.noData(
                      action: anyConnected
                          ? PrimaryButton(
                              label: 'Start Recording',
                              leadingIcon: Icons.fiber_manual_record,
                              showArrow: true,
                              onPressed: _navigateToRecord,
                            )
                          : null,
                    ),
                  ),
                ),
              ],

// ── Primary Recording CTA (always accessible) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  child: _buildPrimaryCta(
                    theme,
                    brightness,
                    anyConnected,
                    bothConnected,
                    modelReady,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryCta(
    ThemeData theme,
    Brightness brightness,
    bool anyConnected,
    bool bothConnected,
    bool modelReady,
  ) {
    final List<Widget> children = [];

    if (!anyConnected) {
      // No bands connected - clear guidance
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.heroCard,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: AppShadows.surface,
          ),
          child: Column(
            children: [
              Icon(
                Icons.sensors_off,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Connect a band to begin',
                style: AppTypography.h3For(brightness).copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Power on your Wrist or Ankle band and it will appear here automatically.',
                style: AppTypography.bodyMediumFor(brightness).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Open Band Settings',
                leadingIcon: Icons.settings_outlined,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevicesScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      );
    } else if (!modelReady && bothConnected) {
      // Bands connected but no model
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: AppRadius.heroCard,
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Model not trained yet',
                style: AppTypography.h3For(brightness).copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Record some sessions in the Collect tab, then train a model from the Dashboard to enable activity recognition.',
                style: AppTypography.bodyMediumFor(brightness).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Record Training Data',
                leadingIcon: Icons.fiber_manual_record,
                showArrow: true,
                onPressed: _navigateToRecord,
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: children);
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sessionDate = DateTime(dt.year, dt.month, dt.day);

    if (sessionDate == today) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (sessionDate == yesterday) {
      return 'Yesterday ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
  }
}
