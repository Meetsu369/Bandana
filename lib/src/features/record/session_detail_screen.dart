import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/ble_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../services/database_service.dart';

/// Screen showing detailed information about a recorded session
/// with option to export raw CSV data and manage session notes.
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
  bool _isSchemaExpanded = false;
  bool _isNotesSaving = false;

  Timer? _notesDebounce;
  late TextEditingController _notesController;

  static const List<String> _csvColumns = [
    'sessionId',
    'activity',
    'timestamp',
    'bandRole',
    'deviceId',
    'deviceName',
    'ax',
    'ay',
    'az',
    'gx',
    'gy',
    'gz',
    'accelMag',
    'gyroMag',
  ];

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _loadSessionDetails();
  }

  @override
  void dispose() {
    _notesDebounce?.cancel();
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
    final rawSamplesCount = await _db.getSampleCount(session.id);
    final totalSamples = rawSamplesCount > 0 ? rawSamplesCount : session.sampleCount;

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

  void _onNotesChanged(String text) {
    setState(() {
      _isNotesSaving = true;
      _notes = text;
    });

    _notesDebounce?.cancel();
    _notesDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (_session == null) return;
      await _db.updateSessionNotes(_session!.id, text);
      if (mounted) {
        setState(() {
          _isNotesSaving = false;
        });
      }
    });
  }

  Future<void> _exportCsv() async {
    if (_session == null) return;

    setState(() => _isExporting = true);

    try {
      final filePath = await _db.exportSessionCsv(_session!.id);
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Bandana Session ${_session!.id} Raw Data',
      );
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
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkCanvas : AppColors.lightCanvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Session Details',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.accentPink),
        ),
      );
    }

    if (_session == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkCanvas : AppColors.lightCanvas,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Session Details',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
        ),
        body: Center(
          child: Text(
            'Session not found',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ),
      );
    }

    final session = _session!;
    final duration = session.endTime != null
        ? session.endTime!.difference(session.startTime)
        : DateTime.now().difference(session.startTime);

    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = isDark ? AppColors.darkCardSurface : AppColors.lightCardSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkCanvas : AppColors.lightCanvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Session ${session.id}',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: textColor,
          ),
        ),
        actions: [
          // Auto-save indicator in top right instead of a plain disk icon
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isNotesSaving
                  ? (isDark ? const Color(0xFF2E1B4E) : const Color(0xFFE9D5FF))
                  : (isDark ? const Color(0xFF132E2B) : const Color(0xFFD1FAE5)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isNotesSaving
                    ? AppColors.accentPink
                    : (isDark ? const Color(0xFF065F46) : const Color(0xFF34D399)),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isNotesSaving) ...[
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.accentPink,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Saving...',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.accentPink : const Color(0xFF9D174D),
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.check,
                    size: 12,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Saved ✓',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Top Notes Input (Clean single textarea with persistent label) ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: isDark ? null : [AppShadows.hardShadowSm],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notes_rounded, size: 18, color: textColor),
                          const SizedBox(width: 6),
                          Text(
                            'Session Notes',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _isNotesSaving ? 'Saving…' : 'Saved to DB',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131417) : const Color(0xFFFAF8F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF383B46) : const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: _notesController,
                      maxLines: 3,
                      style: TextStyle(fontSize: 14, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Add optional notes about this session...',
                        hintStyle: TextStyle(color: mutedColor, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      onChanged: _onNotesChanged,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 2. Session Summary Bento Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: isDark ? null : [AppShadows.hardShadowSm],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Session Overview',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2E1B4E) : const Color(0xFFE9D5FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Text(
                          session.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF581C87),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Bento 2x2 grid metrics
                  Row(
                    children: [
                      Expanded(
                        child: _buildBentoMetricTile(
                          label: 'Duration',
                          value: _formatDuration(duration),
                          icon: Icons.timer_outlined,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildBentoMetricTile(
                          label: 'Total Samples',
                          value: '$_totalSamples',
                          icon: Icons.layers_outlined,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildBentoMetricTile(
                          label: 'Wrist Stream',
                          value: '$_wristSamples',
                          subValue: '$_wristWindows windows',
                          icon: Icons.watch,
                          accentColor: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildBentoMetricTile(
                          label: 'Ankle Stream',
                          value: '$_ankleSamples',
                          subValue: '$_ankleWindows windows',
                          icon: Icons.directions_run,
                          accentColor: isDark ? const Color(0xFFA3E635) : const Color(0xFF65A30D),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Timestamps
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131417) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Start: ${_formatDateTime(session.startTime).substring(11)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: mutedColor,
                          ),
                        ),
                        Text(
                          session.endTime != null
                              ? 'End: ${_formatDateTime(session.endTime!).substring(11)}'
                              : 'Ongoing',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 3. Export Raw Data Card (Bento Polish) ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: isDark ? null : [AppShadows.hardShadowSm],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2E1B4E) : const Color(0xFFFCE7F3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.download_rounded,
                          size: 18,
                          color: AppColors.accentPink,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Export Raw Data',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Exports all raw IMU samples (accelerometer + gyroscope) with timestamps and band roles as CSV.',
                    style: TextStyle(fontSize: 13, color: mutedColor, height: 1.3),
                  ),
                  const SizedBox(height: 14),

                  // Primary Export CTA Button
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isDark ? null : const [
                        BoxShadow(
                          color: Color(0xFF18181B),
                          offset: Offset(3, 3),
                          blurRadius: 0,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isExporting ? null : _exportCsv,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: borderColor, width: 2),
                        ),
                        shadowColor: Colors.transparent,
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: _isExporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.file_download_outlined, size: 18, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Export Raw CSV',
                                    style: TextStyle(
                                      fontSize: 15,
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
                  const SizedBox(height: 14),

                  // Collapsible Disclosure: Preview Data Schema (14 Columns)
                  GestureDetector(
                    onTap: () {
                      setState(() => _isSchemaExpanded = !_isSchemaExpanded);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131417) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Preview Data Schema (14 Columns)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          Icon(
                            _isSchemaExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            color: textColor,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Discrete Badge Pills when expanded
                  if (_isSchemaExpanded) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _csvColumns.map((col) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            col,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFD4D4D8) : const Color(0xFF3F3F46),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 4. De-escalate "Danger Zone" (Minimal destructive button at bottom) ──
            Center(
              child: OutlinedButton.icon(
                onPressed: _confirmDeleteSession,
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                label: const Text(
                  'Delete Session',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF2A1616) : const Color(0xFFFEF2F2),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5),
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoMetricTile({
    required String label,
    required String value,
    String? subValue,
    required IconData icon,
    Color? accentColor,
    required bool isDark,
  }) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final tileBg = isDark ? AppColors.darkSurface : const Color(0xFFF8FAFC);
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor ?? mutedColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: mutedColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: accentColor ?? textColor,
              letterSpacing: -0.3,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue,
              style: TextStyle(fontSize: 10, color: mutedColor),
            ),
          ],
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
          'This will permanently remove all associated raw samples and feature windows. Cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
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