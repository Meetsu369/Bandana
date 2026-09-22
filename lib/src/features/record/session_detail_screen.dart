import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/ble_constants.dart';
import '../../services/database_service.dart';

/// Screen showing detailed information about a recorded session
/// with option to export raw CSV data.
class SessionDetailScreen extends StatefulWidget {
  final int sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _db = getIt<DatabaseService>();

  Session? _session;
  int _totalSamples = 0;
  int _wristSamples = 0;
  int _ankleSamples = 0;
  int _wristWindows = 0;
  int _ankleWindows = 0;
  String _notes = '';
  bool _isLoading = true;
  bool _isExporting = false;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _loadSessionDetails();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionDetails() async {
    setState(() => _isLoading = true);

    final sessions = await _db.getAllSessions();
    final session = sessions.cast<Session?>().firstWhere(
      (s) => s?.id == widget.sessionId,
      orElse: () => null,
    );

    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session not found'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    final sampleCounts = await _db.getSampleCountsByRole(session.id);
    final totalSamples = await _db.getSampleCount(session.id);

    final wristWindows = await _getWindowCount(session.id, BandRole.wrist);
    final ankleWindows = await _getWindowCount(session.id, BandRole.ankle);

    if (mounted) {
      setState(() {
        _session = session;
        _totalSamples = totalSamples;
        _wristSamples = sampleCounts[BandRole.wrist] ?? 0;
        _ankleSamples = sampleCounts[BandRole.ankle] ?? 0;
        _wristWindows = wristWindows;
        _ankleWindows = ankleWindows;
        _notes = session.notes ?? '';
        _notesController.text = _notes;
        _isLoading = false;
      });
    }
  }

  Future<int> _getWindowCount(int sessionId, BandRole role) async {
    return _db.getWindowCount(sessionId, role);
  }

  Future<void> _saveNotes() async {
    if (_session == null) return;
    await _db.updateSessionNotes(_session!.id, _notesController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notes saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportCsv() async {
    if (_session == null) return;

    setState(() => _isExporting = true);

    try {
      final filePath = await _db.exportSessionCsv(_session!.id);
      await Share.shareXFiles([XFile(filePath)], text: 'Bandana Session ${_session!.id} Raw Data');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${filePath.split('/').last}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session Details')),
        body: const Center(child: Text('Session not found')),
      );
    }

    final session = _session!;
    final duration = session.endTime != null
        ? session.endTime!.difference(session.startTime)
        : DateTime.now().difference(session.startTime);

    return Scaffold(
      appBar: AppBar(
        title: Text('Session ${session.id}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveNotes,
            tooltip: 'Save notes',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Session Header ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.fiber_manual_record,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Session Details',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    _buildDetailRow('Session ID', session.id.toString()),
                    _buildDetailRow('Activity', session.label),
                    _buildDetailRow('Start Time', _formatDateTime(session.startTime)),
                    _buildDetailRow(
                      'End Time',
                      session.endTime != null ? _formatDateTime(session.endTime!) : 'Ongoing',
                    ),
                    _buildDetailRow('Duration', _formatDuration(duration)),
                    _buildDetailRow('Total Raw Samples', '$_totalSamples'),
                    _buildDetailRow(
                      'Wrist Samples',
                      '$_wristSamples',
                      color: BandRole.wrist.color,
                    ),
                    _buildDetailRow(
                      'Ankle Samples',
                      '$_ankleSamples',
                      color: BandRole.ankle.color,
                    ),
                    if (_wristWindows > 0 || _ankleWindows > 0) ...[
                      const Divider(height: 24),
                      _buildDetailRow('Wrist Windows', '$_wristWindows', color: BandRole.wrist.color),
                      _buildDetailRow('Ankle Windows', '$_ankleWindows', color: BandRole.ankle.color),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Notes ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notes, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Session Notes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    TextField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Add optional notes about this session...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        contentPadding: const EdgeInsets.all(AppTheme.spacingMd),
                      ),
                      onChanged: (value) => _notes = value,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Export ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.download, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Export Raw Data',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Text(
                      'Exports all raw IMU samples (accelerometer + gyroscope) '
                      'with timestamps and band roles as CSV.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isExporting ? null : _exportCsv,
                        icon: _isExporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.file_download),
                        label: Text(_isExporting ? 'Exporting...' : 'Export Raw CSV'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Text(
                      'CSV Columns: timestamp,bandRole,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),

            // ── Danger Zone ──
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Danger Zone',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                    Text(
                      'Deleting this session will permanently remove all associated '
                      'raw samples and feature windows.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _confirmDeleteSession,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Delete Session'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                        ),
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

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text(
          'Delete session ${_session!.id} (${_session!.label})? '
          'This will remove all raw samples and feature windows. Cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _session != null && mounted) {
      await _db.deleteSession(_session!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }
}