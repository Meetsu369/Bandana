import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';
import '../../shared/widgets/cards/band_status_card.dart';
import '../../shared/widgets/feedback/loading_state.dart';
import '../../shared/widgets/feedback/error_state.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/status/status_pill.dart';
import '../../features/training/training_screen.dart';
import '../../features/record/record_screen.dart';
import '../../features/record/session_detail_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/settings/devices_screen.dart';
import '../../features/profile/profile_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final hasWrist = _wristState == BandConnectionState.connected;
    final hasAnkle = _ankleState == BandConnectionState.connected;
    final anyConnected = hasWrist || hasAnkle;
    final bothConnected = hasWrist && hasAnkle;
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
              // ── Header / Greeting: Clean single header row ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/banadana_logo.png',
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _getGreeting(),
                                style: AppTypography.displayFor(brightness).copyWith(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.8,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Consolidated Bluetooth Quick-Status Indicator
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const DevicesScreen()),
                              );
                            },
                            child: StatusPill(
                              variant: bothConnected
                                  ? StatusPillVariant.connected
                                  : StatusPillVariant.disconnected,
                              text: bothConnected
                                  ? 'Connected'
                                  : anyConnected
                                      ? '1 Band'
                                      : 'Offline',
                              icon: Icons.bluetooth,
                              showIcon: true,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          // Avatar Icon (Quick Access to Profile)
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ProfileScreen()),
                              );
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryAccent(brightness),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.borderColor(brightness),
                                  width: 2.0,
                                ),
                                boxShadow: AppShadows.hardSm(brightness),
                              ),
                              child: const Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Band Readiness: Side-by-Side Split Row (50% / 50% width) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: BandStatusCard(
                    wristState: _wristState,
                    ankleState: _ankleState,
                    wristDeviceName: _wristDeviceName,
                    ankleDeviceName: _ankleDeviceName,
                    showSignal: false,
                    showDeviceNames: false,
                    onManageTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DevicesScreen()),
                      );
                    },
                  ),
                ),
              ),

              // ── Activity Summary: 4-Cell Bento Modular Grid ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: SectionHeader(
                    title: 'Activity Summary',
                    subtitle: '$_totalSessions ${_totalSessions == 1 ? 'session' : 'sessions'} • ${_formatNumber(_totalWindows)} windows',
                    leadingIcon: Icons.analytics_outlined,
                    leadingIconColor: AppColors.primaryAccent(brightness),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Column(
                    children: [
                      // Cell 1: Today's Focus (Full Width, Sky Blue)
                      _buildBentoCell1(context, brightness, anyConnected),
                      const SizedBox(height: AppSpacing.sm),
                      // Cell 2 & Cell 3 (Side-by-side 50% / 50% split)
                      _buildBentoRow2and3(context, brightness, theme),
                      const SizedBox(height: AppSpacing.sm),
                      // Cell 4: Latest Activity (Full Width, White/Surface)
                      _buildBentoCell4(context, brightness, theme),
                    ],
                  ),
                ),
              ),

              // ── Recent Sessions Section ──
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
                      leadingIconColor: AppColors.primaryAccent(brightness),
                      action: TextButton(
                        onPressed: _navigateToHistory,
                        child: Text(
                          'See all →',
                          style: AppTypography.labelFor(brightness).copyWith(
                            color: AppColors.primaryAccent(brightness),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _buildRecentSessionCard(context, brightness, theme, _recentSessions.first),
                  ),
                ),
              ],

              // ── Bottom Onboarding Card ──
              if (!anyConnected)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    child: _buildOnboardingBanner(context, brightness, theme),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cell 1: Today's Focus (Full Width, 2-Columns) ──
  Widget _buildBentoCell1(BuildContext context, Brightness brightness, bool anyConnected) {
    final isLight = brightness == Brightness.light;
    final strokeColor = AppColors.borderColor(brightness);
    final count = _todaySessionCount;
    // Pluralization rule: ${count} session when count === 1, and ${count} sessions otherwise.
    final sessionText = '$count ${count == 1 ? 'Session' : 'Sessions'}';
    final subtitle = count > 0
        ? 'Keep going — every session counts'
        : 'Ready to record your next session';
    final progress = count > 0 ? (count / 3.0).clamp(0.1, 1.0) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: AppColors.skyBlue(brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : AppColors.darkSurface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isLight ? const Color(0xFF18181B) : Colors.white24,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.directions_run,
                      size: 18,
                      color: isLight ? const Color(0xFF18181B) : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Focus",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isLight ? const Color(0xFF18181B) : Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              if (anyConnected)
                GestureDetector(
                  onTap: _navigateToRecord,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAccent(brightness),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLight ? const Color(0xFF18181B) : Colors.transparent,
                        width: 1.5,
                      ),
                      boxShadow: AppShadows.hardSm(brightness),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, size: 10, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Record',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            sessionText,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: isLight ? const Color(0xFF18181B) : Colors.white,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isLight ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Small progress indicator bar
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.black.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent(brightness),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bento Row 2 & 3: Windows Processed & Model Readiness (50% / 50% split) ──
  Widget _buildBentoRow2and3(BuildContext context, Brightness brightness, ThemeData theme) {
    final isLight = brightness == Brightness.light;
    final strokeColor = AppColors.borderColor(brightness);

    // Cell 2: Windows Processed
    final formattedWindows = _formatNumber(_totalWindows);

    // Cell 3: Model Readiness (Eliminate redundant labels!)
    final modelStatusText = _ml.isCombinedTrained
        ? 'Dual-Band'
        : _ml.isTrained
            ? 'Single-Band'
            : 'Untrained';

    return Row(
      children: [
        // Cell 2: Windows Processed (1-column, 50% Width)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: strokeColor, width: 2.0),
              boxShadow: AppShadows.hard(brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.data_array_rounded,
                      size: 18,
                      color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Data Windows',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  formattedWindows,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isLight ? const Color(0xFF18181B) : Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ready for training',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Cell 3: Model Readiness (1-column, 50% Width)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.softLavender(brightness),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: strokeColor, width: 2.0),
              boxShadow: AppShadows.hard(brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 18,
                      color: isLight ? const Color(0xFF3B0764) : const Color(0xFFE9D5FF),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ML Model',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isLight ? const Color(0xFF3B0764) : const Color(0xFFE9D5FF),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  modelStatusText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isLight ? const Color(0xFF18181B) : Colors.white,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TrainingScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLight ? const Color(0xFF18181B) : const Color(0xFFFAF8F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLight ? const Color(0xFF18181B) : Colors.transparent,
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      _ml.isTrained || _ml.isCombinedTrained ? 'Retrain →' : 'Train Now →',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isLight ? Colors.white : const Color(0xFF18181B),
                      ),
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

  // ── Cell 4: Latest Activity (Full Width, 2-Columns) ──
  Widget _buildBentoCell4(BuildContext context, Brightness brightness, ThemeData theme) {
    final isLight = brightness == Brightness.light;
    final strokeColor = AppColors.borderColor(brightness);

    final latest = _recentSessions.isNotEmpty ? _recentSessions.first : null;
    final duration = latest != null
        ? (latest.endTime != null
            ? latest.endTime!.difference(latest.startTime)
            : DateTime.now().difference(latest.startTime))
        : Duration.zero;

    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    final durStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    final timeStr = latest != null ? _formatTime(latest.startTime) : '--:--';

    return InkWell(
      onTap: latest != null ? () => _navigateToSessionDetail(latest.id) : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: strokeColor, width: 2.0),
          boxShadow: AppShadows.hard(brightness),
        ),
        child: latest != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Activity Tag (Walking with icon) + Duration (1m 58s)
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryAccent(brightness).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_walk_rounded,
                          size: 20,
                          color: AppColors.primaryAccent(brightness),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latest.label,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isLight ? const Color(0xFF18181B) : Colors.white,
                            ),
                          ),
                          Text(
                            durStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Right: Timestamp (01:02 AM) + Chevron
                  Row(
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isLight ? const Color(0xFF18181B) : Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: isLight ? const Color(0xFF18181B) : Colors.white70,
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 20,
                        color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'No recorded activity yet',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Record to begin →',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryAccent(brightness),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Recent Sessions: Single Clean Clickable Card ──
  Widget _buildRecentSessionCard(
    BuildContext context,
    Brightness brightness,
    ThemeData theme,
    Session session,
  ) {
    final isLight = brightness == Brightness.light;
    final strokeColor = AppColors.borderColor(brightness);

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

    return InkWell(
      onTap: () => _navigateToSessionDetail(session.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: strokeColor, width: 2.0),
          boxShadow: AppShadows.hard(brightness),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryAccent(brightness).withValues(alpha: 0.15),
              child: Text(
                session.id.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryAccent(brightness),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isLight ? const Color(0xFF18181B) : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr • $durationStr • ${_formatNumber(session.sampleCount)} windows',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: isLight ? const Color(0xFF18181B) : Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Onboarding Banner ──
  Widget _buildOnboardingBanner(BuildContext context, Brightness brightness, ThemeData theme) {
    final isLight = brightness == Brightness.light;
    final strokeColor = AppColors.borderColor(brightness);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : theme.colorScheme.surface,
        borderRadius: AppRadius.bentoCard,
        border: Border.all(color: strokeColor, width: 2.0),
        boxShadow: AppShadows.hard(brightness),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primaryAccent(brightness).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bluetooth_searching,
              size: 30,
              color: AppColors.primaryAccent(brightness),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Pair Your BANDANA Bands',
            style: AppTypography.h3For(brightness).copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Power on your Wrist or Ankle band to start streaming motion and posture telemetry.',
            style: AppTypography.bodyMediumFor(brightness).copyWith(
              color: isLight ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
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
    );
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${h12.toString().padLeft(2, '0')}:$minute $period';
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
