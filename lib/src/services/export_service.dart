import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'database_service.dart';
import '../utils/filename_utils.dart';

/// Service responsible for single-session CSV export, multi-session batch export,
/// ZIP packaging with manifest, and Android system share integration.
class ExportService {
  ExportService({required DatabaseService db}) : _db = db;

  final DatabaseService _db;

  /// Export a single session to CSV.
  Future<File> exportSessionCsv(int sessionId) async {
    final path = await _db.exportSessionCsv(sessionId);
    return File(path);
  }

  /// Share a single session via the Android system share sheet.
  Future<ShareResult> shareSingleSession(int sessionId) async {
    final csvFile = await exportSessionCsv(sessionId);
    final xfile = XFile(csvFile.path, mimeType: 'text/csv');
    return await Share.shareXFiles(
      [xfile],
      text: 'BANDANA Activity Session CSV Export',
    );
  }

  /// Export multiple sessions and package them into a single ZIP file containing:
  /// - Individual session CSVs named according to `participant_activity_YYYYMMDD_HHmmss.csv`
  /// - A comprehensive `manifest.json` describing all included sessions.
  Future<File> exportSessionsAsZip(List<int> sessionIds) async {
    if (sessionIds.isEmpty) {
      throw ArgumentError('sessionIds cannot be empty for ZIP export');
    }

    final allSessions = await _db.getAllSessions();
    final sessionsMap = {for (final s in allSessions) s.id: s};

    final tempDir = await getTemporaryDirectory();
    final timestampStr = FilenameUtils.formatTimestamp(DateTime.now());
    final exportDir = Directory(p.join(tempDir.path, 'bandana_batch_$timestampStr'));
    await exportDir.create(recursive: true);

    final archive = Archive();
    final manifestSessions = <Map<String, dynamic>>[];

    try {
      for (final id in sessionIds) {
        final session = sessionsMap[id];
        if (session == null) continue;

        final csvPath = await _db.exportSessionCsv(id);
        final csvFile = File(csvPath);
        final csvBytes = await csvFile.readAsBytes();
        final fileName = p.basename(csvPath);

        archive.addFile(ArchiveFile(fileName, csvBytes.length, csvBytes));

        manifestSessions.add({
          'sessionId': id,
          'participantId': session.participantId,
          'activity': session.label,
          'startTime': session.startTime.toIso8601String(),
          'endTime': session.endTime?.toIso8601String(),
          'sampleCount': session.sampleCount,
          'notes': session.notes,
          'filename': fileName,
        });
      }

      // Generate manifest.json
      final manifestData = {
        'generator': 'BANDANA Wearable HAR System',
        'schemaVersion': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'sessionCount': manifestSessions.length,
        'sessions': manifestSessions,
      };

      final manifestBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(manifestData),
      );
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      // Encode ZIP
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final docsDir = await getApplicationDocumentsDirectory();
      final zipFile = File(p.join(docsDir.path, 'bandana_export_$timestampStr.zip'));
      await zipFile.writeAsBytes(zipBytes);

      return zipFile;
    } finally {
      // Clean up temporary directory
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true).catchError((_) => exportDir);
      }
    }
  }

  /// Share multiple sessions using the system share sheet.
  /// When [asZip] is true, generates and shares a single ZIP with manifest.
  /// When [asZip] is false, exports and shares individual CSV files directly.
  Future<ShareResult> shareMultipleSessions(
    List<int> sessionIds, {
    bool asZip = true,
  }) async {
    if (sessionIds.isEmpty) {
      throw ArgumentError('sessionIds cannot be empty');
    }

    if (asZip) {
      final zipFile = await exportSessionsAsZip(sessionIds);
      final xfile = XFile(zipFile.path, mimeType: 'application/zip');
      return await Share.shareXFiles(
        [xfile],
        text: 'BANDANA Multi-Session Export (ZIP with manifest)',
      );
    } else {
      final xfiles = <XFile>[];
      for (final id in sessionIds) {
        final csvFile = await exportSessionCsv(id);
        xfiles.add(XFile(csvFile.path, mimeType: 'text/csv'));
      }
      return await Share.shareXFiles(
        xfiles,
        text: 'BANDANA Multi-Session CSVs',
      );
    }
  }
}
