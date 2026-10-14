import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../features/record/session_detail_screen.dart';
import '../../services/database_service.dart';
import '../../services/export_service.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/buttons/secondary_button.dart';
import '../../shared/widgets/feedback/empty_state.dart';

/// History Screen showing recorded activity sessions from SQLite.
/// Supports multi-session selection, single and batch CSV/ZIP export,
/// Android share sheet integration, and confirmed session deletion.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Session?'),
          content: Text(
            'Are you sure you want to delete session #${session.id} (${session.label})? '
            'All associated IMU sample records and feature windows will be permanently removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
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

    final count = _selectedSessionIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete $count Sessions?'),
          content: Text(
            'Are you sure you want to delete $count selected session(s)? '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete All'),
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

  String _formatDateTime(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedSessionIds.length} Selected'
              : 'History',
          style: AppTypography.h2For(brightness),
        ),
        centerTitle: false,
        actions: [
          if (_sessions.isNotEmpty && !_isLoading) ...[
            if (_isSelectionMode) ...[
              IconButton(
                icon: Icon(
                  _selectedSessionIds.length == _sessions.length
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                tooltip: _selectedSessionIds.length == _sessions.length
                    ? 'Deselect All'
                    : 'Select All',
                onPressed: _toggleSelectAll,
              ),
              TextButton(
                onPressed: _toggleSelectionMode,
                child: const Text('Done'),
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: 'Multi-select',
                onPressed: _toggleSelectionMode,
              ),
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
                          Icon(Icons.error_outline, size: 48, color: context.danger),
                          const SizedBox(height: AppSpacing.md),
                          Text(_errorMessage!, style: AppTypography.bodyFor(brightness)),
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
                    : RefreshIndicator(
                        onRefresh: _loadSessions,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          itemCount: _sessions.length,
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            final isSelected =
                                _selectedSessionIds.contains(session.id);

                            return _buildSessionCard(
                              session: session,
                              isSelected: isSelected,
                              brightness: brightness,
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
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: context.ink.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
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

  Widget _buildSessionCard({
    required Session session,
    required bool isSelected,
    required Brightness brightness,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: isSelected
            ? context.primaryAccent.withValues(alpha: 0.15)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isSelected ? context.primaryAccent : context.ink.withValues(alpha: 0.15),
          width: isSelected ? 2.0 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          if (_isSelectionMode) {
            _toggleSessionSelected(session.id);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SessionDetailScreen(sessionId: session.id),
              ),
            ).then((_) => _loadSessions());
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_isSelectionMode) ...[
                    Checkbox(
                      value: isSelected,
                      activeColor: context.primaryAccent,
                      onChanged: (_) => _toggleSessionSelected(session.id),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  // Activity icon badge
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: context.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.directions_walk,
                      color: context.ink,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.label,
                          style: AppTypography.h3For(brightness),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${session.participantId} • ${_formatDateTime(session.startTime)}',
                          style: AppTypography.captionFor(brightness).copyWith(
                            color: context.secondaryInfo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isSelectionMode) ...[
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (action) {
                        if (action == 'export') {
                          _shareSingleSession(session);
                        } else if (action == 'delete') {
                          _confirmDeleteSingleSession(session);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Share CSV'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: context.danger),
                              const SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: context.danger)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Metrics chips row
              Row(
                children: [
                  _buildMetricPill(
                    icon: Icons.timer_outlined,
                    label: _formatDuration(session.startTime, session.endTime),
                    brightness: brightness,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildMetricPill(
                    icon: Icons.analytics_outlined,
                    label: '${session.sampleCount} samples',
                    brightness: brightness,
                  ),
                ],
              ),
              if (session.notes != null && session.notes!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  session.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionFor(brightness).copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricPill({
    required IconData icon,
    required String label,
    required Brightness brightness,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: context.disabledSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.secondaryInfo),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.captionFor(brightness).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}