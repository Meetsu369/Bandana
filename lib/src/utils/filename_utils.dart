import 'dart:io';
import 'package:path/path.dart' as p;

/// Utilities for generating standardized, safe, collision-resistant filenames
/// for BANDANA session exports.
///
/// Follows the specification pattern: `participant_activity_YYYYMMDD_HHmmss.csv`
/// e.g. `sumeet_walking_20261014_153000.csv`
class FilenameUtils {
  FilenameUtils._();

  /// Sanitize a string token (participant name or activity label) for filesystem safety.
  ///
  /// - Converts to lowercase.
  /// - Trims leading/trailing whitespace.
  /// - Replaces spaces and hyphens with underscores.
  /// - Strips any characters not in `[a-z0-9_]`.
  /// - Collapses multiple consecutive underscores into one.
  /// - Strips leading/trailing underscores.
  /// - If resulting string is empty, returns [fallback].
  static String sanitizeToken(String raw, {String fallback = 'unknown'}) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return fallback;

    // Replace whitespace and hyphens with underscores
    var normalized = trimmed.replaceAll(RegExp(r'[\s\-]+'), '_');

    // Remove any character that is not lowercase alphanumeric or underscore
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9_]'), '');

    // Collapse multiple consecutive underscores
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');

    // Strip leading/trailing underscores
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');

    return normalized.isEmpty ? fallback : normalized;
  }

  /// Format a DateTime timestamp into `YYYYMMDD_HHmmss` string format.
  static String formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }

  /// Generate the canonical base filename for a session export:
  /// `${participant}_${activity}_${timestamp}.csv`
  static String generateSessionCsvFilename({
    required String participantId,
    required String activityLabel,
    required DateTime timestamp,
  }) {
    final cleanParticipant = sanitizeToken(participantId, fallback: 'participant');
    final cleanActivity = sanitizeToken(activityLabel, fallback: 'activity');
    final tsStr = formatTimestamp(timestamp);
    return '${cleanParticipant}_${cleanActivity}_$tsStr.csv';
  }

  /// Resolve a unique file in [directory] avoiding collisions.
  ///
  /// If `foo.csv` exists, returns `foo_1.csv`, `foo_2.csv`, etc.
  static Future<File> resolveUniqueFile(Directory directory, String filename) async {
    final extension = p.extension(filename);
    final baseName = p.basenameWithoutExtension(filename);

    var candidate = File(p.join(directory.path, filename));
    var counter = 1;

    while (await candidate.exists()) {
      candidate = File(p.join(directory.path, '${baseName}_$counter$extension'));
      counter++;
    }

    return candidate;
  }
}
