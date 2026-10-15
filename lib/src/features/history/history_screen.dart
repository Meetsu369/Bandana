import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/record/session_detail_screen.dart';
import '../../services/database_service.dart';
import '../../services/export_service.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/buttons/secondary_button.dart';
import '../../shared/widgets/feedback/empty_state.dart';

/// Redesigned Neo-Brutalist Bento History Screen.
/// Features grouped date buckets (Today, Yesterday, Date), horizontal modular
/// Bento session cards with 48x48 activity badges, typography hierarchy, metric pills,
/// right action kebab + chevron affordance, swipe-to-reveal quick actions, and filter modal.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.onStartRecording});

  final VoidCallback? onStartRecording;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _db = getIt<DatabaseService>();
  final _exportService = getIt<ExportService>();

  List<Session> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Filter and sort state
  String? _activeFilter; // null = all activities
  String _sortOrder = 'newest'; // 'newest', 'oldest', 'samples', 'duration'

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<int> _selectedSessionIds = {};
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _db.getAllSessions();
      if (mounted) {
        setState(() {
          _sessions = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load history: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedSessionIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedSessionIds.length == _sessions.length) {
        _selectedSessionIds.clear();
      } else {
        _selectedSessionIds.addAll(_sessions.map((s) => s.id));
      }
    });
  }

  void _toggleSessionSelected(int sessionId) {
    setState(() {
      if (_selectedSessionIds.contains(sessionId)) {
        _selectedSessionIds.remove(sessionId);
      } else {
        _selectedSessionIds.add(sessionId);
      }
    });
  }

  Future<void> _shareSingleSession(Session session) async {
    setState(() => _isExporting = true);
    try {
      await _exportService.shareSingleSession(session.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export session: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareSelectedSessionsZip() async {
    if (_selectedSessionIds.isEmpty) return;

    setState(() => _isExporting = true);
    try {
      await _exportService.shareMultipleSessions(
        _selectedSessionIds.toList(),
        asZip: true,
      );
      if (mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedSessionIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to package ZIP export: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _confirmDeleteSingleSession(Session session) async {
    final brightness = Theme.of(context).brightness;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceCard(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: AppColors.borderColor(brightness),
              width: 2,
            ),
          ),
          title: Text(
            'Delete Session?',
            style: AppTypography.h3For(brightness).copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Are you sure you want to delete session #${session.id} (${session.label})? '
            'All associated IMU sample records and feature windows will be permanently removed.',
            style: TextStyle(
              color: AppColors.textSecondary(brightness),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary(brightness),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerText(brightness),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _db.deleteSession(session.id);
      _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted session #${session.id}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteSelectedSessions() async {
    if (_selectedSessionIds.isEmpty) return;

    final brightness = Theme.of(context).brightness;
    final count = _selectedSessionIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceCard(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: AppColors.borderColor(brightness),
              width: 2,
            ),
          ),
          title: Text(
            'Delete $count Sessions?',
            style: AppTypography.h3For(brightness).copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Are you sure you want to delete $count selected session(s)? '
            'This action cannot be undone.',
            style: TextStyle(
              color: AppColors.textSecondary(brightness),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary(brightness),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dangerText(brightness),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Delete All',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      for (final id in _selectedSessionIds) {
        await _db.deleteSession(id);
      }
      setState(() {
        _isSelectionMode = false;
        _selectedSessionIds.clear();
      });
      _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $count sessions'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDuration(DateTime start, DateTime? end) {
    if (end == null) return 'In progress';
    final duration = end.difference(start);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m ${seconds}s';
  }

  String _formatTimeOnly(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final hourStr = hour12.toString().padLeft(2, '0');
    return '$hourStr:$minute $period';
  }

  String _getDateBucket(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDate = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(sessionDate).inDays;

    if (today.year == sessionDate.year &&
        today.month == sessionDate.month &&
        today.day == sessionDate.day) {
      return 'Today';
    } else if (diffDays == 1 ||
        (today.year == sessionDate.year &&
            today.month == sessionDate.month &&
            today.day - sessionDate.day == 1)) {
      return 'Yesterday';
    } else {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      final monthName = months[dt.month - 1];
      if (dt.year == now.year) {
        return '$monthName ${dt.day}';
      }
      return '$monthName ${dt.day}, ${dt.year}';
    }
  }

  Color _getActivityAccent(String label) {
    final l = label.toLowerCase();
    if (l.contains('walk')) {
      return const Color(0xFFD6F865); // Vibrant Lime
    } else if (l.contains('run') || l.contains('sprint') || l.contains('jog')) {
      return const Color(0xFFFF3384); // Neon Pink
    } else if (l.contains('rest') ||
        l.contains('stand') ||
        l.contains('sit') ||
        l.contains('idle') ||
        l.contains('sleep')) {
      return const Color(0xFFBAE6FD); // Sky Blue
    } else {
      return const Color(0xFFE9D5FF); // Soft Lavender
    }
  }

  IconData _getActivityIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('walk')) {
      return Icons.directions_walk;
    } else if (l.contains('run') || l.contains('sprint') || l.contains('jog')) {
      return Icons.directions_run;
    } else if (l.contains('rest') ||
        l.contains('stand') ||
        l.contains('sit') ||
        l.contains('idle')) {
      return Icons.accessibility_new;
    } else {
      return Icons.fitness_center;
    }
  }

  List<String> get _availableActivities {
    final set = <String>{};
    for (final s in _sessions) {
      set.add(s.label);
    }
    return set.toList();
  }

  List<Session> get _filteredSessions {
    var list = List<Session>.from(_sessions);
    if (_activeFilter != null && _activeFilter!.isNotEmpty) {
      list = list
          .where((s) => s.label.toLowerCase() == _activeFilter!.toLowerCase())
          .toList();
    }
    switch (_sortOrder) {
      case 'oldest':
        list.sort((a, b) => a.startTime.compareTo(b.startTime));
        break;
      case 'samples':
        list.sort((a, b) => b.sampleCount.compareTo(a.sampleCount));
        break;
      case 'duration':
        list.sort((a, b) {
          final durA = (a.endTime ?? a.startTime).difference(a.startTime);
          final durB = (b.endTime ?? b.startTime).difference(b.startTime);
          return durB.compareTo(durA);
        });
        break;
      case 'newest':
      default:
        list.sort((a, b) => b.startTime.compareTo(a.startTime));
        break;
    }
    return list;
  }

  Map<String, List<Session>> _groupSessions(List<Session> sessions) {
    final Map<String, List<Session>> grouped = {};
    for (final s in sessions) {
      final bucket = _getDateBucket(s.startTime);
      grouped.putIfAbsent(bucket, () => []).add(s);
    }
    return grouped;
  }

  void _showFilterModal() {
    final brightness = Theme.of(context).brightness;
    final activities = _availableActivities;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.canvasBg(brightness),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: AppColors.borderColor(brightness),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowColor(brightness),
                    offset: const Offset(0, -3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderColor(brightness).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filter & Sort',
                          style: AppTypography.h3For(brightness).copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_activeFilter != null || _sortOrder != 'newest')
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _activeFilter = null;
                                _sortOrder = 'newest';
                              });
                              setModalState(() {});
                            },
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'ACTIVITY TYPE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary(brightness),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip(
                          label: 'All Activities',
                          isSelected: _activeFilter == null,
                          color: AppColors.surfaceCard(brightness),
                          brightness: brightness,
                          onTap: () {
                            setState(() => _activeFilter = null);
                            setModalState(() {});
                          },
                        ),
                        for (final act in activities)
                          _buildFilterChip(
                            label: act,
                            isSelected:
                                _activeFilter?.toLowerCase() == act.toLowerCase(),
                            color: _getActivityAccent(act),
                            brightness: brightness,
                            onTap: () {
                              setState(() => _activeFilter = act);
                              setModalState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'SORT BY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary(brightness),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildSortChip(
                            'Newest first', 'newest', brightness, setModalState),
                        _buildSortChip(
                            'Oldest first', 'oldest', brightness, setModalState),
                        _buildSortChip(
                            'Most samples', 'samples', brightness, setModalState),
                        _buildSortChip('Longest duration', 'duration',
                            brightness, setModalState),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: 'Done',
                      onPressed: () => Navigator.of(ctx).pop(),
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

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required Brightness brightness,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (label == 'All Activities' ? AppColors.brandPink : color)
              : AppColors.surfaceCard(brightness),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.brandPink
                : AppColors.borderColor(brightness),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.shadowColor(brightness),
                    offset: const Offset(2, 2),
                    blurRadius: 0,
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected && label == 'All Activities'
                ? Colors.white
                : (isSelected
                    ? const Color(0xFF18181B)
                    : AppColors.textPrimary(brightness)),
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(
    String label,
    String value,
    Brightness brightness,
    void Function(void Function()) setModalState,
  ) {
    final isSelected = _sortOrder == value;
    return InkWell(
      onTap: () {
        setState(() => _sortOrder = value);
        setModalState(() {});
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandPink
              : AppColors.surfaceCard(brightness),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.brandPink
                : AppColors.borderColor(brightness),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.shadowColor(brightness),
                    offset: const Offset(2, 2),
                    blurRadius: 0,
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textPrimary(brightness),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final filtered = _filteredSessions;
    final grouped = _groupSessions(filtered);
    final groupedKeys = grouped.keys.toList();

    return Scaffold(
      backgroundColor: AppColors.canvasBg(brightness),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.canvasBg(brightness),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          _isSelectionMode
              ? '${_selectedSessionIds.length} Selected'
              : 'History',
          style: AppTypography.h1For(brightness).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          if (_sessions.isNotEmpty && !_isLoading) ...[
            if (_isSelectionMode) ...[
              IconButton(
                icon: Icon(
                  _selectedSessionIds.length == _sessions.length
                      ? Icons.deselect
                      : Icons.select_all,
                  color: AppColors.textPrimary(brightness),
                ),
                tooltip: _selectedSessionIds.length == _sessions.length
                    ? 'Deselect All'
                    : 'Select All',
                onPressed: _toggleSelectAll,
              ),
              TextButton(
                onPressed: _toggleSelectionMode,
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: AppColors.brandPink,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ] else ...[
              // Clean icon button for Filter/Sort (⌥ Filter)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: InkWell(
                  onTap: _showFilterModal,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _activeFilter != null
                          ? AppColors.brandPink
                          : AppColors.surfaceCard(brightness),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.borderColor(brightness),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowColor(brightness),
                          offset: const Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '⌥',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _activeFilter != null
                                ? Colors.white
                                : AppColors.textPrimary(brightness),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _activeFilter != null ? _activeFilter! : 'Filter',
                          style: AppTypography.labelFor(brightness).copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _activeFilter != null
                                ? Colors.white
                                : AppColors.textPrimary(brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.checklist,
                    color: AppColors.textPrimary(brightness)),
                tooltip: 'Multi-select',
                onPressed: _toggleSelectionMode,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.dangerText(brightness)),
                          const SizedBox(height: AppSpacing.md),
                          Text(_errorMessage!,
                              style: AppTypography.bodyFor(brightness)),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton(
                            onPressed: _loadSessions,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _sessions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: EmptyState.noSessions(
                          action: PrimaryButton(
                            label: 'Start Recording',
                            leadingIcon: Icons.fiber_manual_record,
                            onPressed: widget.onStartRecording,
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? _buildEmptyFilterState(brightness)
                        : RefreshIndicator(
                            onRefresh: _loadSessions,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.sm,
                              ),
                              itemCount: groupedKeys.length,
                              itemBuilder: (context, groupIndex) {
                                final bucket = groupedKeys[groupIndex];
                                final bucketSessions = grouped[bucket]!;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDateHeader(bucket,
                                        bucketSessions.length, brightness),
                                    ...bucketSessions.map((session) {
                                      final isSelected = _selectedSessionIds
                                          .contains(session.id);
                                      return _buildSessionCard(
                                        session: session,
                                        isSelected: isSelected,
                                        brightness: brightness,
                                      );
                                    }),
                                  ],
                                );
                              },
                            ),
                          ),
      ),
      bottomNavigationBar: _isSelectionMode && _sessions.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard(brightness),
                border: Border(
                  top: BorderSide(
                    color: AppColors.borderColor(brightness),
                    width: 2,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowColor(brightness),
                    offset: const Offset(0, -3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Delete (${_selectedSessionIds.length})',
                      leadingIcon: Icons.delete_outline,
                      onPressed: _selectedSessionIds.isEmpty
                          ? null
                          : _confirmDeleteSelectedSessions,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryButton(
                      label: _isExporting ? 'Exporting…' : 'Share ZIP',
                      leadingIcon: Icons.archive_outlined,
                      onPressed: (_selectedSessionIds.isEmpty || _isExporting)
                          ? null
                          : _shareSelectedSessionsZip,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildDateHeader(String bucket, int count, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8, left: 2, right: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF272930) : const Color(0xFFE4E4E7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.borderColor(brightness),
                width: 1.5,
              ),
            ),
            child: Text(
              bucket.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.textPrimary(brightness),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count ${count == 1 ? 'session' : 'sessions'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFilterState(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFE9D5FF), // Soft lavender
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.borderColor(brightness),
                  width: 2,
                ),
                boxShadow: AppShadows.bento(isDark),
              ),
              child: const Icon(
                Icons.filter_alt_off_outlined,
                size: 40,
                color: Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No sessions match this filter',
              style: AppTypography.h3For(brightness).copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Try selecting another activity or resetting your filter criteria.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary(brightness),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            InkWell(
              onTap: () {
                setState(() {
                  _activeFilter = null;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard(brightness),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.borderColor(brightness),
                    width: 2,
                  ),
                  boxShadow: AppShadows.bentoSm(isDark),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh,
                        size: 16, color: AppColors.textPrimary(brightness)),
                    const SizedBox(width: 8),
                    Text(
                      'Clear Filters',
                      style: AppTypography.labelFor(brightness).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard({
    required Session session,
    required bool isSelected,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final activityColor = _getActivityAccent(session.label);
    final activityIcon = _getActivityIcon(session.label);

    return Dismissible(
      key: ValueKey('session_${session.id}'),
      direction:
          _isSelectionMode ? DismissDirection.none : DismissDirection.horizontal,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFBAE6FD), // Sky blue
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: AppColors.borderColor(brightness), width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        child: const Row(
          children: [
            Icon(Icons.share_outlined, color: Color(0xFF18181B)),
            SizedBox(width: 8),
            Text(
              'Export CSV',
              style: TextStyle(
                color: Color(0xFF18181B),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C1517) : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
            width: 2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Delete',
              style: TextStyle(
                color:
                    isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.delete_outline,
              color:
                  isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _shareSingleSession(session);
          return false;
        } else {
          await _confirmDeleteSingleSession(session);
          return false;
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandPink.withValues(alpha: 0.15)
              : AppColors.surfaceCard(brightness),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.brandPink
                : AppColors.borderColor(brightness),
            width: 2,
          ),
          boxShadow: AppShadows.bento(isDark),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (_isSelectionMode) {
              _toggleSessionSelected(session.id);
            } else {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SessionDetailScreen(sessionId: session.id),
                    ),
                  )
                  .then((_) => _loadSessions());
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              setState(() {
                _isSelectionMode = true;
                _selectedSessionIds.add(session.id);
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_isSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    activeColor: AppColors.brandPink,
                    checkColor: Colors.white,
                    onChanged: (_) => _toggleSessionSelected(session.id),
                  ),
                  const SizedBox(width: 4),
                ],
                // 1. Left Activity Badge: 48x48px, 14px radius, 2px border, activity color fill
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: activityColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.borderColor(brightness),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      activityIcon,
                      color: const Color(0xFF18181B), // High-contrast black glyph
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 2. Center Details (Typography Hierarchy)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.label,
                        style: AppTypography.h3For(brightness).copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${session.participantId} • ${_formatTimeOnly(session.startTime)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary(brightness),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Metric Pills Row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildMetricPill(
                            prefixSymbol: '⏱',
                            label: _formatDuration(
                                session.startTime, session.endTime),
                            brightness: brightness,
                          ),
                          _buildMetricPill(
                            prefixSymbol: '⚡',
                            label: '${session.sampleCount} samples',
                            brightness: brightness,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 3. Right Action & Affordance
                if (!_isSelectionMode) ...[
                  // Dedicated kebab icon button in 32x32px touch boundary
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: AppColors.textPrimary(brightness),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: AppColors.borderColor(brightness),
                          width: 2,
                        ),
                      ),
                      color: AppColors.surfaceCard(brightness),
                      elevation: 4,
                      onSelected: (action) {
                        if (action == 'export') {
                          _shareSingleSession(session);
                        } else if (action == 'delete') {
                          _confirmDeleteSingleSession(session);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined,
                                  size: 18,
                                  color: AppColors.textPrimary(brightness)),
                              const SizedBox(width: 8),
                              Text(
                                'Share CSV',
                                style: TextStyle(
                                  color: AppColors.textPrimary(brightness),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18,
                                  color: AppColors.dangerText(brightness)),
                              const SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: AppColors.dangerText(brightness),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Clean navigation chevron
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary(brightness)
                        .withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricPill({
    required String prefixSymbol,
    required String label,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF272930) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.borderColor(brightness)
              .withValues(alpha: isDark ? 0.6 : 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            prefixSymbol,
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(brightness),
            ),
          ),
        ],
      ),
    );
  }
}