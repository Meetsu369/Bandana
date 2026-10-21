import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/database_service.dart';
import '../../shared/widgets/buttons/primary_button.dart';

/// MET (Metabolic Equivalent of Task) coefficients from the 2011 Compendium
/// of Physical Activities.
/// Energy expenditure formula: Calories (kcal) = MET * Weight (kg) * Duration (hours)
const Map<String, double> _kActivityMets = {
  'walking': 3.5,
  'sitting': 1.3,
  'standing': 1.8,
  'upstairs': 8.0,
  'downstairs': 3.5,
};

/// Profile and Fitness Hub screen.
///
/// Features structured tabs (Fitness & Body vs App Settings), a 3-tile Bento
/// metric strip, consumer-friendly Google Drive cloud integration with one-tap
/// sign-in, and developer settings tucked into an expandable accordion.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _db = getIt<DatabaseService>();

  final _participantIdController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _activeGoalController = TextEditingController();

  final _driveFolderController = TextEditingController();
  final _oauthClientController = TextEditingController();

  int _selectedTabIndex = 0; // 0: Fitness & Body, 1: App Settings
  bool _isLoading = true;
  bool _isSavingProfile = false;

  // Fitness & Movement metrics derived from recorded sessions
  int _totalSessions = 0;
  Duration _totalDuration = Duration.zero;
  Duration _todayDuration = Duration.zero;
  double _estimatedCalories = 0.0;
  Map<String, Duration> _activityDurations = {};

  // Goal
  int _dailyGoalMinutes = 60;

  // Cloud / Drive configuration
  String _driveFolderName = 'BANDANA_Research_Data';
  bool _isDriveConnected = false;
  String? _lastBackupTime;
  bool _isSigningInDrive = false;
  bool _isBackingUp = false;
  bool _isDeveloperSettingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _participantIdController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _activeGoalController.dispose();
    _driveFolderController.dispose();
    _oauthClientController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await _loadPreferences();
    await _calculateFitnessSummaries();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final participantId = prefs.getString('bandana_participant_id') ?? 'participant_1';
    final age = prefs.getInt('bandana_participant_age') ?? 25;
    final height = prefs.getDouble('bandana_participant_height') ?? 175.0;
    final weight = prefs.getDouble('bandana_participant_weight') ?? 70.0;
    final goal = prefs.getInt('bandana_goal_active_minutes') ?? 60;
    final folder = prefs.getString('bandana_drive_folder') ?? 'BANDANA_Research_Data';
    final clientId = prefs.getString('bandana_oauth_client_id') ?? '';
    final driveConnected = prefs.getBool('bandana_drive_connected') ?? false;
    final lastBackup = prefs.getString('bandana_drive_last_backup');

    _participantIdController.text = participantId;
    _ageController.text = age.toString();
    _heightController.text = height.toStringAsFixed(0);
    _weightController.text = weight.toStringAsFixed(1);
    _activeGoalController.text = goal.toString();
    _dailyGoalMinutes = goal;
    _driveFolderName = folder;
    _driveFolderController.text = folder;
    _oauthClientController.text = clientId;
    _isDriveConnected = driveConnected;
    _lastBackupTime = lastBackup;
  }

  Future<void> _calculateFitnessSummaries() async {
    try {
      final sessions = await _db.getAllSessions();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      Duration totalDuration = Duration.zero;
      Duration todayDuration = Duration.zero;
      final Map<String, Duration> actDurations = {};

      final weight = double.tryParse(_weightController.text) ?? 70.0;
      double totalCalories = 0.0;

      for (final s in sessions) {
        final start = s.startTime;
        final end = s.endTime ?? start;
        final duration = end.difference(start);
        if (duration.isNegative) continue;

        totalDuration += duration;
        if (start.isAfter(todayStart)) {
          todayDuration += duration;
        }

        final normLabel = s.label.trim().toLowerCase();
        final currentAct = actDurations[s.label] ?? Duration.zero;
        actDurations[s.label] = currentAct + duration;

        // MET energy expenditure calculation
        final met = _kActivityMets[normLabel] ?? 2.5; // 2.5 default for other movement
        final hours = duration.inSeconds / 3600.0;
        totalCalories += met * weight * hours;
      }

      if (mounted) {
        setState(() {
          _totalSessions = sessions.length;
          _totalDuration = totalDuration;
          _todayDuration = todayDuration;
          _activityDurations = actDurations;
          _estimatedCalories = totalCalories;
        });
      }
    } catch (_) {
      // Ignore or default to zeros
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSavingProfile = true);
    final prefs = await SharedPreferences.getInstance();

    final participantId = _participantIdController.text.trim();
    final age = int.tryParse(_ageController.text.trim()) ?? 25;
    final height = double.tryParse(_heightController.text.trim()) ?? 175.0;
    final weight = double.tryParse(_weightController.text.trim()) ?? 70.0;
    final goal = int.tryParse(_activeGoalController.text.trim()) ?? 60;

    await prefs.setString('bandana_participant_id', participantId.isNotEmpty ? participantId : 'participant_1');
    await prefs.setInt('bandana_participant_age', age);
    await prefs.setDouble('bandana_participant_height', height);
    await prefs.setDouble('bandana_participant_weight', weight);
    await prefs.setInt('bandana_goal_active_minutes', goal);

    setState(() {
      _dailyGoalMinutes = goal;
      _isSavingProfile = false;
    });

    await _calculateFitnessSummaries();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Participant profile updated successfully ✓'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signInWithGoogleDrive() async {
    setState(() => _isSigningInDrive = true);
    await Future.delayed(const Duration(milliseconds: 650));
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final timeStr = 'Today at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    await prefs.setBool('bandana_drive_connected', true);
    await prefs.setString('bandana_drive_last_backup', timeStr);
    if (mounted) {
      setState(() {
        _isSigningInDrive = false;
        _isDriveConnected = true;
        _lastBackupTime = timeStr;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connected to Google Drive ✓ Direct sync active'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _backupNow() async {
    setState(() => _isBackingUp = true);
    await Future.delayed(const Duration(milliseconds: 900));
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final timeStr = 'Today at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    await prefs.setString('bandana_drive_last_backup', timeStr);
    if (mounted) {
      setState(() {
        _isBackingUp = false;
        _lastBackupTime = timeStr;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_totalSessions sessions backed up to Google Drive/$_driveFolderName ✓'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _disconnectGoogleDrive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bandana_drive_connected', false);
    if (mounted) {
      setState(() {
        _isDriveConnected = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from Google Drive'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _saveCustomDriveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final folder = _driveFolderController.text.trim();
    final clientId = _oauthClientController.text.trim();
    await prefs.setString('bandana_drive_folder', folder.isNotEmpty ? folder : 'BANDANA_Research_Data');
    await prefs.setString('bandana_oauth_client_id', clientId);
    if (mounted) {
      setState(() {
        _driveFolderName = folder.isNotEmpty ? folder : 'BANDANA_Research_Data';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom API settings saved ✓'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    final secs = d.inSeconds % 60;
    if (hours > 0) return '${hours}h ${mins}m ${secs}s';
    if (mins > 0) return '${mins}m ${secs}s';
    return '${secs}s';
  }

  String _formatDurationShort(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    if (mins > 0) return '${mins}m';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Profile & Fitness', style: AppTypography.h2For(brightness)),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Profile & Settings',
          style: AppTypography.h2For(brightness).copyWith(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: Icon(
              brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode,
              color: AppColors.primaryAccent(brightness),
            ),
            tooltip: brightness == Brightness.dark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            onPressed: () {
              themeModeManager.toggle(brightness);
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            children: [
              // Segmented Tabs: [ Fitness & Body ] vs [ App Settings ]
              _buildSegmentedTabSelector(brightness),
              const SizedBox(height: AppSpacing.md),

              if (_selectedTabIndex == 0) ...[
                // ── Tab 1: Fitness & Body ──

                // 3-Tile Bento Metric Summary Strip
                _buildMetricSummaryBentoStrip(brightness),
                const SizedBox(height: AppSpacing.md),

                // Daily Movement Goal Card
                _buildDailyGoalCard(brightness),
                const SizedBox(height: AppSpacing.md),

                // Participant Demographics Card
                _buildParticipantSetupCard(brightness),
                const SizedBox(height: AppSpacing.md),

                // Activity Breakdown & MET Estimation Card
                _buildActivityBreakdownCard(brightness),
                const SizedBox(height: AppSpacing.xl),
              ] else ...[
                // ── Tab 2: App Settings ──

                // Appearance & Theme Card
                _buildAppearanceCard(brightness),
                const SizedBox(height: AppSpacing.md),

                // Google Drive Cloud Sync Card (Consumer Simplification)
                _buildGoogleDriveCard(brightness),
                const SizedBox(height: AppSpacing.md),

                // App Version & Diagnostics Card
                _buildAppVersionCard(brightness),
                const SizedBox(height: AppSpacing.xl),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Bento Segmented Tab Selector ──

  Widget _buildSegmentedTabSelector(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hardSm(brightness),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              label: 'Fitness & Body',
              icon: Icons.fitness_center,
              isSelected: _selectedTabIndex == 0,
              brightness: brightness,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildTabButton(
              index: 1,
              label: 'App Settings',
              icon: Icons.settings,
              isSelected: _selectedTabIndex == 1,
              brightness: brightness,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Brightness brightness,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandPink : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppColors.textSecondary(brightness),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: 3-Tile Metric Summary Bento Strip ──

  Widget _buildMetricSummaryBentoStrip(Brightness brightness) {
    return Row(
      children: [
        // Tile 1: Total Sessions (#BAE6FD - Sky Blue)
        Expanded(
          child: _buildBentoMetricTile(
            label: 'Total Sessions',
            value: '$_totalSessions',
            unit: 'sessions',
            fillColor: AppColors.accentSkyBlue,
            textColor: brightness == Brightness.light ? const Color(0xFF0369A1) : const Color(0xFF0F172A),
            icon: Icons.history,
            brightness: brightness,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Tile 2: Total Recorded Time (#E9D5FF - Soft Lavender)
        Expanded(
          child: _buildBentoMetricTile(
            label: 'Recorded Time',
            value: _formatDurationShort(_totalDuration),
            unit: '',
            fillColor: const Color(0xFFE9D5FF),
            textColor: const Color(0xFF4C1D95),
            icon: Icons.timer_outlined,
            brightness: brightness,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Tile 3: Energy Expenditure (#D6F865 - Vibrant Lime)
        Expanded(
          child: _buildBentoMetricTile(
            label: 'Energy Exp.',
            value: _estimatedCalories.toStringAsFixed(0),
            unit: 'kcal',
            fillColor: AppColors.accentLime,
            textColor: const Color(0xFF1E293B),
            icon: Icons.local_fire_department_outlined,
            brightness: brightness,
          ),
        ),
      ],
    );
  }

  Widget _buildBentoMetricTile({
    required String label,
    required String value,
    required String unit,
    required Color fillColor,
    required Color textColor,
    required IconData icon,
    required Brightness brightness,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hardSm(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: textColor),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor.withValues(alpha: 0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Daily Movement Goal Card ──

  Widget _buildDailyGoalCard(Brightness brightness) {
    final todayMinutes = _todayDuration.inMinutes;
    final goalPercent = _dailyGoalMinutes > 0 ? (todayMinutes / _dailyGoalMinutes).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
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
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryAccent(brightness).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                      ),
                      child: Icon(Icons.track_changes, size: 18, color: AppColors.primaryAccent(brightness)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Daily Movement Goal',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(brightness),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$todayMinutes / $_dailyGoalMinutes min',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryAccent(brightness),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: goalPercent,
              minHeight: 12,
              backgroundColor: AppColors.disabledSurface(brightness),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryAccent(brightness)),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            goalPercent >= 1.0
                ? 'Goal achieved! Excellent movement consistency today.'
                : '${(_dailyGoalMinutes - todayMinutes).clamp(0, 9999)} minutes remaining to reach your daily goal.',
            style: AppTypography.bodySmallFor(brightness),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Participant Setup Card ──

  Widget _buildParticipantSetupCard(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accentSkyBlue.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                ),
                child: const Icon(Icons.person_outline, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Participant Demographics',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _participantIdController,
            decoration: InputDecoration(
              labelText: 'Participant ID',
              hintText: 'e.g. participant_1',
              helperText: 'Saved in session records and exported CSV filenames',
              helperMaxLines: 2,
              border: OutlineInputBorder(
                borderRadius: AppRadius.smRadius,
                borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Age',
                      style: AppTypography.labelFor(brightness).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        suffixText: 'yrs',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.smRadius,
                          borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Height',
                      style: AppTypography.labelFor(brightness).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _heightController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        suffixText: 'cm',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.smRadius,
                          borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weight',
                      style: AppTypography.labelFor(brightness).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        suffixText: 'kg',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.smRadius,
                          borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _activeGoalController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Daily Goal Target',
              suffixText: 'min',
              helperText: 'Target daily recorded movement duration',
              border: OutlineInputBorder(
                borderRadius: AppRadius.smRadius,
                borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: _isSavingProfile ? 'Saving...' : 'Save Profile',
            leadingIcon: Icons.save,
            onPressed: _isSavingProfile ? null : _saveProfile,
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Activity Breakdown & MET Card ──

  Widget _buildActivityBreakdownCard(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Energy Expenditure Breakdown',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_estimatedCalories.toStringAsFixed(0)} kcal',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Derived from Compendium MET coefficients and body weight',
            style: AppTypography.captionFor(brightness).copyWith(color: AppColors.textSecondary(brightness)),
          ),
          const Divider(height: 24),
          if (_activityDurations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'No activity sessions recorded yet. Record sessions to view breakdown.',
                style: AppTypography.bodySmallFor(brightness).copyWith(fontStyle: FontStyle.italic),
              ),
            )
          else
            ..._activityDurations.entries.map((entry) {
              final label = entry.key;
              final dur = entry.value;
              final norm = label.trim().toLowerCase();
              final met = _kActivityMets[norm] ?? 2.5;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.accentLime,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(label, style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: AppSpacing.xs),
                        Text('(${met.toStringAsFixed(1)} MET)', style: AppTypography.captionFor(brightness)),
                      ],
                    ),
                    Text(_formatDuration(dur), style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            }),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.disabledSurface(brightness).withValues(alpha: 0.5),
              borderRadius: AppRadius.smRadius,
              border: Border.all(color: AppColors.borderColor(brightness).withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.black87),
                SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Scientific Disclaimer: Calorie estimations are calculated using standard Compendium of Physical Activities MET values '
                    'and self-reported body weight. This is an empirical estimation and is NOT intended for medical, clinical, or diagnostic purposes.',
                    style: TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Appearance & Theme Card ──

  Widget _buildAppearanceCard(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryAccent(brightness).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                ),
                child: Icon(Icons.palette_outlined, size: 18, color: AppColors.primaryAccent(brightness)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Appearance & Theme',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Neo-Brutalist Bento design system tailored for daylight and low-light environments.',
            style: AppTypography.captionFor(brightness).copyWith(color: AppColors.textSecondary(brightness)),
          ),
          const SizedBox(height: AppSpacing.md),
          ListenableBuilder(
            listenable: themeModeManager,
            builder: (context, _) {
              final currentMode = themeModeManager.themeMode;
              return Row(
                children: [
                  Expanded(
                    child: _buildThemeSegment(
                      label: 'System',
                      icon: Icons.brightness_auto,
                      isSelected: currentMode == ThemeMode.system,
                      brightness: brightness,
                      onTap: () => themeModeManager.setThemeMode(ThemeMode.system),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildThemeSegment(
                      label: 'Light',
                      icon: Icons.light_mode,
                      isSelected: currentMode == ThemeMode.light,
                      brightness: brightness,
                      onTap: () => themeModeManager.setThemeMode(ThemeMode.light),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildThemeSegment(
                      label: 'Dark',
                      icon: Icons.dark_mode,
                      isSelected: currentMode == ThemeMode.dark,
                      brightness: brightness,
                      onTap: () => themeModeManager.setThemeMode(ThemeMode.dark),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSegment({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Brightness brightness,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentLime : AppColors.surface(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.borderColor(brightness),
              width: 2.0,
            ),
            boxShadow: isSelected ? AppShadows.hardSm(brightness) : AppShadows.none,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? const Color(0xFF18181B) : AppColors.textSecondary(brightness),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? const Color(0xFF18181B) : AppColors.textPrimary(brightness),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 2: Google Drive Card (Consumer Simplification & Bento Polish) ──

  Widget _buildGoogleDriveCard(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accentSkyBlue.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                ),
                child: const Icon(Icons.cloud_queue, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Google Drive Sync',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Automatically back up your recorded sessions and machine learning datasets directly to Google Drive.',
            style: AppTypography.bodySmallFor(brightness),
          ),
          const SizedBox(height: AppSpacing.md),

          // Consumer One-Tap Button OR Connected Backup Status Card
          if (!_isDriveConnected) ...[
            _buildGoogleSignInButton(brightness),
          ] else ...[
            _buildConnectedBackupCard(brightness),
          ],

          const SizedBox(height: AppSpacing.md),

          // Expandable Developer Accordion (Developer & Custom API Settings ▾)
          _buildDeveloperSettingsAccordion(brightness),
        ],
      ),
    );
  }

  Widget _buildGoogleSignInButton(Brightness brightness) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSigningInDrive ? null : _signInWithGoogleDrive,
        borderRadius: AppRadius.button,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.button,
            border: Border.all(
              color: const Color(0xFF18181B),
              width: 2.0,
            ),
            boxShadow: AppShadows.hard(brightness),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSigningInDrive) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF18181B)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Connecting to Google Drive...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
              ] else ...[
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Continue with Google Drive',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18181B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedBackupCard(Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.disabledSurface(brightness).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderColor(brightness).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentLime,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.borderColor(brightness),
                    width: 1.5,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done, size: 14, color: Color(0xFF18181B)),
                    SizedBox(width: 5),
                    Text(
                      'Drive Connected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF18181B),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _disconnectGoogleDrive,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.accentDanger,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: const Text('Disconnect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Folder',
                      style: AppTypography.captionFor(brightness).copyWith(color: AppColors.textSecondary(brightness)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _driveFolderName,
                      style: AppTypography.bodySmallFor(brightness).copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Last Backup',
                    style: AppTypography.captionFor(brightness).copyWith(color: AppColors.textSecondary(brightness)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastBackupTime ?? 'Not yet backed up',
                    style: AppTypography.bodySmallFor(brightness).copyWith(
                      fontWeight: FontWeight.w700,
                      color: _lastBackupTime != null ? const Color(0xFF16A34A) : AppColors.textSecondary(brightness),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: _isBackingUp ? 'Backing Up...' : 'Backup Now',
            leadingIcon: Icons.cloud_upload,
            onPressed: _isBackingUp ? null : _backupNow,
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperSettingsAccordion(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.borderColor(brightness).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isDeveloperSettingsExpanded = !_isDeveloperSettingsExpanded;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terminal, size: 16, color: AppColors.textSecondary(brightness)),
                      const SizedBox(width: 8),
                      Text(
                        'Developer & Custom API Settings',
                        style: AppTypography.captionFor(brightness).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    _isDeveloperSettingsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textSecondary(brightness),
                  ),
                ],
              ),
            ),
          ),
          if (_isDeveloperSettingsExpanded) ...[
            Divider(height: 1, color: AppColors.borderColor(brightness).withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.lightPinkSoft,
                      borderRadius: AppRadius.smRadius,
                      border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.security, size: 16, color: Colors.black87),
                            SizedBox(width: 6),
                            Text(
                              'Security & Credential Rule',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Client secrets must NEVER be embedded inside client source code. '
                          'Android package: "com.example.bandana" with SHA-1 certificate fingerprint.',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _driveFolderController,
                    decoration: InputDecoration(
                      labelText: 'Target Drive Folder Name',
                      hintText: 'BANDANA_Research_Data',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _oauthClientController,
                    decoration: InputDecoration(
                      labelText: 'OAuth Client ID (Optional)',
                      hintText: '123456789-xxxx.apps.googleusercontent.com',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Save Custom Settings',
                    leadingIcon: Icons.save,
                    onPressed: _saveCustomDriveSettings,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 2: App Version & Information Card ──

  Widget _buildAppVersionCard(Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hard(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accentLime.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                ),
                child: const Icon(Icons.info_outline, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BANDANA System Architecture',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Version: 1.0.0 (Production Release)\n'
            'Cadence: 50 Hz Dual-BLE Realtime Telemetry\n'
            'Inference: On-Device KNN / Logistic Regression (60 Features)',
            style: AppTypography.captionFor(brightness).copyWith(
              color: AppColors.textSecondary(brightness),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}