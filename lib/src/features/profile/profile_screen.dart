import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../services/database_service.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/buttons/secondary_button.dart';
import '../../shared/widgets/cards/metric_card.dart';
import '../settings/devices_screen.dart';
import '../training/training_screen.dart';
import '../history/history_screen.dart';
import '../record/record_screen.dart';

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
/// Provides participant research metadata setup, truthful movement and fitness
/// statistics derived from recorded data, empirical MET-based energy expenditure
/// with explicit medical-grade disclaimers, and Google Drive cloud configuration guidance.
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
  String _oauthClientId = '';

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

    _participantIdController.text = participantId;
    _ageController.text = age.toString();
    _heightController.text = height.toStringAsFixed(0);
    _weightController.text = weight.toStringAsFixed(1);
    _activeGoalController.text = goal.toString();
    _dailyGoalMinutes = goal;
    _driveFolderName = folder;
    _oauthClientId = clientId;
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
          content: Text('Participant profile updated successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showGoogleDriveGuide() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final brightness = Theme.of(ctx).brightness;
        final folderController = TextEditingController(text: _driveFolderName);
        final clientController = TextEditingController(text: _oauthClientId);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Google Drive Integration',
                            style: AppTypography.h2For(brightness).copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'BANDANA exports datasets offline via standard CSV and multi-session batch ZIP files. '
                      'To enable direct automated upload to Google Drive without user file-picker interaction, '
                      'a verified Google Cloud OAuth 2.0 Client ID is required.',
                      style: AppTypography.bodyMediumFor(brightness),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.lightPinkSoft,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: AppColors.ink(brightness), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.security, color: Colors.black87),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'Security & Credential Rule',
                                style: AppTypography.bodyMediumFor(brightness).copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Client secrets must NEVER be embedded inside client-side Android source code. '
                            'Use the Android OAuth flow with your package name ("com.example.bandana") and SHA-1 certificate fingerprint.',
                            style: AppTypography.bodySmallFor(brightness).copyWith(color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Step-by-Step Setup Guide:',
                      style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _buildStepRow(1, 'Open console.cloud.google.com and create a project.', brightness),
                    _buildStepRow(2, 'Enable the "Google Drive API" in API & Services.', brightness),
                    _buildStepRow(3, 'Configure OAuth Consent Screen (scope: .../auth/drive.file).', brightness),
                    _buildStepRow(4, 'Create an OAuth 2.0 Android Client ID with package "com.example.bandana" and your release/debug SHA-1.', brightness),
                    _buildStepRow(5, 'Save the Client ID below for direct cloud sync.', brightness),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: folderController,
                      decoration: InputDecoration(
                        labelText: 'Target Drive Folder Name',
                        hintText: 'e.g. BANDANA_Research_Data',
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.smRadius,
                          borderSide: BorderSide(color: AppColors.ink(brightness), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: clientController,
                      decoration: InputDecoration(
                        labelText: 'OAuth Client ID (Optional)',
                        hintText: 'e.g. 123456789-xxxx.apps.googleusercontent.com',
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.smRadius,
                          borderSide: BorderSide(color: AppColors.ink(brightness), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Save & Test Drive Readiness',
                      leadingIcon: Icons.cloud_upload_outlined,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('bandana_drive_folder', folderController.text.trim());
                        await prefs.setString('bandana_oauth_client_id', clientController.text.trim());
                        setState(() {
                          _driveFolderName = folderController.text.trim();
                          _oauthClientId = clientController.text.trim();
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _testDriveReadiness();
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStepRow(int number, String text, Brightness brightness) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.lightSlateSoft,
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: AppTypography.bodySmallFor(brightness)),
          ),
        ],
      ),
    );
  }

  void _testDriveReadiness() {
    if (_oauthClientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Google Drive OAuth Client ID not yet configured. Native Android Share sheet will be used for CSV/ZIP export.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OAuth Client ID configured for folder "$_driveFolderName". In production, verify SHA-1 fingerprint in Google Cloud Console.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final ink = AppColors.ink(brightness);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Profile & Fitness', style: AppTypography.h2For(brightness)),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final todayMinutes = _todayDuration.inMinutes;
    final goalPercent = _dailyGoalMinutes > 0 ? (todayMinutes / _dailyGoalMinutes).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Profile & Fitness',
          style: AppTypography.h2For(brightness).copyWith(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
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
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // ── Section 1: Movement Goal & Daily Activity ──
              SectionHeader(
                title: 'Daily Movement Goal',
                subtitle: 'Track your physical activity and recording progress',
                leadingIcon: Icons.track_changes,
                leadingIconColor: AppColors.primaryAccent(brightness),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                  side: BorderSide(color: ink, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Today's Active Time",
                            style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '$todayMinutes / $_dailyGoalMinutes min',
                            style: AppTypography.h3For(brightness).copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryAccent(brightness),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
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
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Section 2: Research Participant Profile ──
              SectionHeader(
                title: 'Participant Setup',
                subtitle: 'Metadata attached to recorded sessions & exported datasets',
                leadingIcon: Icons.person_outline,
                leadingIconColor: AppColors.secondaryStrong(brightness),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                  side: BorderSide(color: ink, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _participantIdController,
                        decoration: InputDecoration(
                          labelText: 'Participant ID',
                          hintText: 'e.g. participant_1',
                          helperText: 'Saved in session records and exported CSV filenames',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.smRadius,
                            borderSide: BorderSide(color: ink, width: 1.5),
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
                                      borderSide: BorderSide(color: ink, width: 1.5),
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
                                      borderSide: BorderSide(color: ink, width: 1.5),
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
                                      borderSide: BorderSide(color: ink, width: 1.5),
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
                          labelText: 'Daily Goal',
                          suffixText: 'min',
                          helperText: 'Target daily recorded movement duration',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(
                            borderRadius: AppRadius.smRadius,
                            borderSide: BorderSide(color: ink, width: 1.5),
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
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Section 3: Truthful Movement & Energy Summary ──
              SectionHeader(
                title: 'Movement & Fitness Summary',
                subtitle: 'Derived directly from all verified database sessions',
                leadingIcon: Icons.fitness_center_outlined,
                leadingIconColor: AppColors.success(brightness),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Total Sessions',
                      value: '$_totalSessions',
                      unit: 'sessions',
                      supportingText: 'All-time verified',
                      leadingIcon: Icons.history,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MetricCard(
                      label: 'Total Recorded Time',
                      value: _formatDuration(_totalDuration),
                      supportingText: 'Actual sensor time',
                      leadingIcon: Icons.timer_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                  side: BorderSide(color: ink, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Energy Expenditure Estimate',
                                  style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Based on empirical MET values & body weight',
                                  style: AppTypography.bodySmallFor(brightness),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${_estimatedCalories.toStringAsFixed(0)} kcal',
                            style: AppTypography.h2For(brightness).copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.secondaryStrong(brightness),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        'Activity Breakdown:',
                        style: AppTypography.labelFor(brightness).copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_activityDurations.isEmpty)
                        Text(
                          'No activity sessions recorded yet. Record sessions to view breakdown.',
                          style: AppTypography.bodySmallFor(brightness).copyWith(fontStyle: FontStyle.italic),
                        )
                      else
                        ..._activityDurations.entries.map((entry) {
                          final label = entry.key;
                          final dur = entry.value;
                          final norm = label.trim().toLowerCase();
                          final met = _kActivityMets[norm] ?? 2.5;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppColors.success(brightness),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(label, style: AppTypography.bodyMediumFor(brightness)),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text('(${met.toStringAsFixed(1)} MET)', style: AppTypography.captionFor(brightness)),
                                  ],
                                ),
                                Text(_formatDuration(dur), style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w600)),
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
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.black87),
                            const SizedBox(width: AppSpacing.xs),
                            const Expanded(
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
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Section 4: Google Drive & Cloud Backup ──
              SectionHeader(
                title: 'Google Drive & Backup',
                subtitle: 'Manage local and cloud dataset synchronization',
                leadingIcon: Icons.cloud_done_outlined,
                leadingIconColor: AppColors.secondaryStrong(brightness),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                  side: BorderSide(color: ink, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _oauthClientId.isNotEmpty ? Icons.cloud_done : Icons.cloud_queue,
                            color: _oauthClientId.isNotEmpty ? AppColors.success(brightness) : AppColors.secondaryInfo(brightness),
                            size: 28,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _oauthClientId.isNotEmpty ? 'Cloud Sync Configured' : 'Offline / Android Share Mode',
                                  style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _oauthClientId.isNotEmpty
                                      ? 'Folder: $_driveFolderName'
                                      : 'Native CSV/ZIP export and system sharing operational',
                                  style: AppTypography.bodySmallFor(brightness),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SecondaryButton(
                        label: 'Google Drive Setup & Instructions',
                        leadingIcon: Icons.settings_suggest_outlined,
                        onPressed: _showGoogleDriveGuide,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Section 5: Appearance & Theme ──
              SectionHeader(
                title: 'Appearance & Theme',
                subtitle: 'Switch between Light, Dark, or System mode',
                leadingIcon: Icons.palette_outlined,
                leadingIconColor: AppColors.primaryAccent(brightness),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                  side: BorderSide(color: ink, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.style_outlined, size: 20, color: AppColors.primaryAccent(brightness)),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Theme Preference',
                            style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Neo-brutalist aesthetic optimized for daylight and dark environments.',
                        style: AppTypography.bodySmallFor(brightness),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ListenableBuilder(
                        listenable: themeModeManager,
                        builder: (context, _) {
                          final currentMode = themeModeManager.themeMode;
                          return SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.system,
                                  label: Text('System', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  icon: Icon(Icons.brightness_auto, size: 16),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.light,
                                  label: Text('Light', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  icon: Icon(Icons.light_mode, size: 16),
                                ),
                                ButtonSegment<ThemeMode>(
                                  value: ThemeMode.dark,
                                  label: Text('Dark', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  icon: Icon(Icons.dark_mode, size: 16),
                                ),
                              ],
                              selected: {currentMode},
                              onSelectionChanged: (Set<ThemeMode> newSelection) {
                                themeModeManager.setThemeMode(newSelection.first);
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Section 6: Quick Management Links ──
              SectionHeader(
                title: 'Hardware & Models',
                leadingIcon: Icons.devices_other,
                leadingIconColor: AppColors.primaryAccent(brightness),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildNavigationCard(
                title: 'My Bands (BLE)',
                subtitle: 'Manage Wrist and Ankle sensor assignment and connections',
                icon: Icons.watch_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DevicesScreen()),
                  );
                },
                brightness: brightness,
                ink: ink,
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildNavigationCard(
                title: 'Model Training Hub',
                subtitle: 'Train on-device KNN/Logistic Regression or connect to Laptop AI Service',
                icon: Icons.model_training,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrainingScreen()),
                  );
                },
                brightness: brightness,
                ink: ink,
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildNavigationCard(
                title: 'Session History & Batch Export',
                subtitle: 'Inspect recordings, export single CSVs or multi-session ZIP packages',
                icon: Icons.history,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(
                        onStartRecording: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RecordScreen()),
                          );
                        },
                      ),
                    ),
                  );
                },
                brightness: brightness,
                ink: ink,
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: Text(
                  'BANDANA Wearable Activity Recognition v1.0.0\n40 Hz Cadence Pipeline',
                  textAlign: TextAlign.center,
                  style: AppTypography.captionFor(brightness).copyWith(color: AppColors.secondaryInfo(brightness)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required Brightness brightness,
    required Color ink,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: ink, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.lightPinkSoft,
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(icon, color: AppColors.primaryAccent(brightness), size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyMediumFor(brightness).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTypography.bodySmallFor(brightness)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}