import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart' as model;
import '../utils/filename_utils.dart';

part 'database_service.g.dart';

// ── Table Definitions ──

/// Recording sessions table.
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  TextColumn get participantId => text().withDefault(const Constant('participant_1'))();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  IntColumn get sampleCount => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

/// Individual IMU samples stored for each band during recording.
/// This replaces the SensorWindows table for raw data storage.
class ImuSampleRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id)();
  TextColumn get bandRole => text()(); // 'wrist' or 'ankle'
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();
  RealColumn get ax => real()();
  RealColumn get ay => real()();
  RealColumn get az => real()();
  RealColumn get gx => real()();
  RealColumn get gy => real()();
  RealColumn get gz => real()();
  RealColumn get accelMagnitude => real()();
  RealColumn get gyroMagnitude => real()();
  IntColumn get captureTimestampMs => integer().withDefault(const Constant(-1))();
  DateTimeColumn get timestamp => dateTime()();
}

/// Feature windows extracted from sensor data during recording (for ML training).
class SensorWindows extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id)();
  TextColumn get bandRole => text()(); // 'wrist', 'ankle', or 'combined'
  TextColumn get features => text()(); // JSON-encoded list of doubles
  TextColumn get label => text()();
  DateTimeColumn get timestamp => dateTime()();
}

/// User feedback on predictions for supervised candidate model improvement.
class PredictionFeedbacks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get predictedLabel => text()();
  TextColumn get userFeedback => text()(); // 'correct' or 'incorrect'
  TextColumn get correctedLabel => text().nullable()();
  TextColumn get modelVersion => text()(); // e.g. 'knn_30_v1', 'softmax_60_v1'
  RealColumn get confidence => real().nullable()();
  IntColumn get sessionId => integer().nullable().references(Sessions, #id)();
  DateTimeColumn get timestamp => dateTime()();
  BoolColumn get isReviewed => boolean().withDefault(const Constant(false))();
}

// ── Database ──

@DriftDatabase(tables: [Sessions, ImuSampleRecords, SensorWindows, PredictionFeedbacks])
class DatabaseService extends _$DatabaseService {
  DatabaseService() : super(_openConnection());

  /// Creates a DatabaseService instance with a custom executor for testing.
  DatabaseService.withExecutor(super.executor);

  @override
  int get schemaVersion => 5;

  /// Store DateTime as text (ISO-8601) to preserve millisecond precision.
  /// Default is false which stores as unix timestamps (seconds only).
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // Create new tables for dual-band support
            await m.createTable(imuSampleRecords);
            await m.addColumn(sensorWindows, sensorWindows.bandRole);
          }
          if (from < 3) {
            // Add notes column to sessions table
            await m.addColumn(sessions, sessions.notes);
          }
          if (from < 4) {
            // Migrate DateTime storage from INTEGER (unix seconds) to TEXT (ISO-8601).
            // This is required because storeDateTimeAsText was enabled.
            // Use TableMigration with DateTimeExpressions.fromUnixEpoch to convert.
            // Cast columns to int since they were stored as unix timestamps.
            await m.alterTable(TableMigration(
              sessions,
              columnTransformer: {
                sessions.startTime:
                    DateTimeExpressions.fromUnixEpoch(sessions.startTime.cast<int>()),
                sessions.endTime:
                    DateTimeExpressions.fromUnixEpoch(sessions.endTime.cast<int>()),
              },
            ));
            await m.alterTable(TableMigration(
              imuSampleRecords,
              columnTransformer: {
                imuSampleRecords.timestamp:
                    DateTimeExpressions.fromUnixEpoch(imuSampleRecords.timestamp.cast<int>()),
              },
            ));
            await m.alterTable(TableMigration(
              sensorWindows,
              columnTransformer: {
                sensorWindows.timestamp:
                    DateTimeExpressions.fromUnixEpoch(sensorWindows.timestamp.cast<int>()),
              },
            ));
          }
          if (from < 5) {
            await m.addColumn(sessions, sessions.participantId);
            await m.addColumn(imuSampleRecords, imuSampleRecords.captureTimestampMs);
            await m.createTable(predictionFeedbacks);
          }
        },
      );

  // ── Sessions ──

  /// Create a new recording session and return its ID.
  Future<int> createSession(
    String label, {
    String participantId = 'participant_1',
  }) async {
    final id = await into(sessions).insert(
      SessionsCompanion.insert(
        label: label,
        participantId: Value(participantId),
        startTime: DateTime.now(),
      ),
    );
    return id;
  }

  /// End a session by setting its endTime and final sample count.
  Future<void> endSession(int sessionId, int sampleCount) async {
    await (update(sessions)..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        endTime: Value(DateTime.now()),
        sampleCount: Value(sampleCount),
      ),
    );
  }

  /// Update session notes.
  Future<void> updateSessionNotes(int sessionId, String notes) async {
    await (update(sessions)..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(notes: Value(notes)),
    );
  }

  /// Get all sessions, most recent first.
  Future<List<Session>> getAllSessions() async {
    return (select(sessions)
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .get();
  }

  /// Get session summaries grouped by label.
  Future<Map<String, ({int sessionCount, int totalSamples})>>
      getSessionSummaries() async {
    final allSessions = await getAllSessions();
    final map = <String, ({int sessionCount, int totalSamples})>{};
    for (final session in allSessions) {
      final existing = map[session.label];
      map[session.label] = (
        sessionCount: (existing?.sessionCount ?? 0) + 1,
        totalSamples: (existing?.totalSamples ?? 0) + session.sampleCount,
      );
    }
    return map;
  }

  /// Delete a session and its associated data.
  Future<void> deleteSession(int sessionId) async {
    await (delete(imuSampleRecords)..where((w) => w.sessionId.equals(sessionId))).go();
    await (delete(sensorWindows)..where((w) => w.sessionId.equals(sessionId))).go();
    await (delete(sessions)..where((s) => s.id.equals(sessionId))).go();
  }

  // ── IMU Samples (raw data) ──

  /// Insert a batch of IMU samples for a session.
  Future<void> insertImuSamples({
    required int sessionId,
    required List<model.ImuSample> samples,
  }) async {
    if (samples.isEmpty) return;
    await transaction(() async {
      for (final sample in samples) {
        await into(imuSampleRecords).insert(
          ImuSampleRecordsCompanion(
            sessionId: Value(sessionId),
            bandRole: Value(sample.bandRole.name),
            deviceId: Value(sample.deviceId),
            deviceName: Value(sample.deviceName),
            ax: Value(sample.ax),
            ay: Value(sample.ay),
            az: Value(sample.az),
            gx: Value(sample.gx),
            gy: Value(sample.gy),
            gz: Value(sample.gz),
            accelMagnitude: Value(sample.accelMagnitude),
            gyroMagnitude: Value(sample.gyroMagnitude),
            captureTimestampMs: Value(sample.captureTimestampMs),
            timestamp: Value(sample.timestamp),
          ),
        );
      }
    });
  }

  /// Get all IMU samples for a session, optionally filtered by band role.
  Future<List<ImuSampleData>> getImuSamples({
    required int sessionId,
    BandRole? bandRole,
  }) async {
    final query = select(imuSampleRecords)..where((w) => w.sessionId.equals(sessionId));
    if (bandRole != null) {
      query.where((w) => w.bandRole.equals(bandRole.name));
    }
    query.orderBy([(w) => OrderingTerm.asc(w.timestamp)]);
    final rows = await query.get();
    return rows.map((r) => ImuSampleData(
      id: r.id,
      sessionId: r.sessionId,
      bandRole: BandRole.values.byName(r.bandRole),
      deviceId: r.deviceId,
      deviceName: r.deviceName,
      ax: r.ax,
      ay: r.ay,
      az: r.az,
      gx: r.gx,
      gy: r.gy,
      gz: r.gz,
      accelMagnitude: r.accelMagnitude,
      gyroMagnitude: r.gyroMagnitude,
      captureTimestampMs: r.captureTimestampMs,
      timestamp: r.timestamp,
    )).toList();
  }

  /// Get sample count for a session (across both bands).
  Future<int> getSampleCount(int sessionId) async {
    final count = countAll();
    final query = selectOnly(imuSampleRecords)..addColumns([count]);
    query.where(imuSampleRecords.sessionId.equals(sessionId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Get sample counts per band role for a session.
  Future<Map<BandRole, int>> getSampleCountsByRole(int sessionId) async {
    final map = <BandRole, int>{};
    for (final role in BandRole.values) {
      final count = countAll();
      final query = selectOnly(imuSampleRecords)..addColumns([count]);
      query.where(imuSampleRecords.sessionId.equals(sessionId));
      query.where(imuSampleRecords.bandRole.equals(role.name));
      final result = await query.getSingle();
      map[role] = result.read(count) ?? 0;
    }
    return map;
  }

  /// Get window count for a session and band role.
  Future<int> getWindowCount(int sessionId, BandRole role) async {
    final count = countAll();
    final query = selectOnly(sensorWindows)..addColumns([count]);
    query.where(sensorWindows.sessionId.equals(sessionId));
    query.where(sensorWindows.bandRole.equals(role.name));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Export raw IMU samples for a session as CSV.
  ///
  /// Returns the path to the exported CSV file.
  /// Generates standardized filename: `participant_activity_YYYYMMDD_HHmmss.csv`
  Future<String> exportSessionCsv(int sessionId) async {
    final samples = await getImuSamples(sessionId: sessionId);
    if (samples.isEmpty) {
      throw StateError('No samples to export for session $sessionId');
    }

    // Fetch session details for activity and participant metadata
    final sessions = await getAllSessions();
    final session = sessions.cast<Session?>().firstWhere(
      (s) => s?.id == sessionId,
      orElse: () => null,
    );
    final participant = session?.participantId ?? 'participant_1';
    final activity = session?.label ?? 'activity';
    final startTime = session?.startTime ?? DateTime.now();

    final directory = await getApplicationDocumentsDirectory();
    final fileName = FilenameUtils.generateSessionCsvFilename(
      participantId: participant,
      activityLabel: activity,
      timestamp: startTime,
    );
    final file = await FilenameUtils.resolveUniqueFile(directory, fileName);

    final buffer = StringBuffer();
    // Metadata comments header
    buffer.writeln('# BANDANA IMU Session Export');
    buffer.writeln('# Schema Version: 2');
    buffer.writeln('# Session ID: $sessionId');
    buffer.writeln('# Participant ID: $participant');
    buffer.writeln('# Activity: $activity');
    buffer.writeln('# Start Time: ${startTime.toIso8601String()}');
    if (session?.notes != null && session!.notes!.isNotEmpty) {
      buffer.writeln('# Notes: ${session.notes!.replaceAll('\n', ' ')}');
    }
    buffer.writeln('sessionId,participantId,activity,bandRole,captureTimestampMs,receiveTimestamp,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag');

    for (final sample in samples) {
      buffer.write(
        '$sessionId,'
        '"$participant",'
        '"$activity",'
        '${sample.bandRole.name},'
        '${sample.captureTimestampMs},'
        '${sample.timestamp.toIso8601String()},'
        '"${sample.deviceId}",'
        '"${sample.deviceName}",'
        '${sample.ax.toStringAsFixed(6)},'
        '${sample.ay.toStringAsFixed(6)},'
        '${sample.az.toStringAsFixed(6)},'
        '${sample.gx.toStringAsFixed(6)},'
        '${sample.gy.toStringAsFixed(6)},'
        '${sample.gz.toStringAsFixed(6)},'
        '${sample.accelMagnitude.toStringAsFixed(6)},'
        '${sample.gyroMagnitude.toStringAsFixed(6)}',
      );
      buffer.writeln();
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }

  // ── Sensor Windows (for ML training) ──

  /// Insert a feature window for a session.
  Future<void> insertWindow({
    required int sessionId,
    required List<double> featureVector,
    required String label,
    required BandRole bandRole,
  }) async {
    await into(sensorWindows).insert(
      SensorWindowsCompanion.insert(
        sessionId: sessionId,
        bandRole: bandRole.name,
        features: jsonEncode(featureVector),
        label: label,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Load all feature windows for ML training.
  Future<List<({List<double> features, String label, BandRole bandRole})>>
      getAllWindowsForTraining() async {
    final rows = await select(sensorWindows).get();
    return rows.map((row) {
      final featureList =
          (jsonDecode(row.features) as List).cast<num>().map((n) => n.toDouble()).toList();
      return (
        features: featureList,
        label: row.label,
        bandRole: BandRole.values.byName(row.bandRole),
      );
    }).toList();
  }

  /// Get windows for a specific band role.
  Future<List<({List<double> features, String label})>>
      getWindowsForTraining({required BandRole bandRole}) async {
    final rows = await (select(sensorWindows)
          ..where((w) => w.bandRole.equals(bandRole.name)))
        .get();
    return rows.map((row) {
      final featureList =
          (jsonDecode(row.features) as List).cast<num>().map((n) => n.toDouble()).toList();
      return (features: featureList, label: row.label);
    }).toList();
  }

  /// Get windows for training filtered by session IDs and band role.
  Future<List<({List<double> features, String label})>>
      getWindowsForTrainingBySessions({
    required List<int> sessionIds,
    required BandRole bandRole,
  }) async {
    if (sessionIds.isEmpty) return [];
    final rows = await (select(sensorWindows)
          ..where((w) => w.bandRole.equals(bandRole.name))
          ..where((w) => w.sessionId.isIn(sessionIds)))
        .get();
    return rows.map((row) {
      final featureList =
          (jsonDecode(row.features) as List).cast<num>().map((n) => n.toDouble()).toList();
      return (features: featureList, label: row.label);
    }).toList();
  }

  /// Get windows for combined dual-band training filtered by session IDs.
  /// Returns pairs of (wrist features, ankle features, label) for sessions that have both.
  Future<List<({List<double> wristFeatures, List<double> ankleFeatures, String label})>>
      getCombinedWindowsForTrainingBySessions({
    required List<int> sessionIds,
  }) async {
    if (sessionIds.isEmpty) return [];

    // Get wrist windows for these sessions
    final wristRows = await (select(sensorWindows)
          ..where((w) => w.bandRole.equals(BandRole.wrist.name))
          ..where((w) => w.sessionId.isIn(sessionIds)))
        .get();

    // Get ankle windows for these sessions
    final ankleRows = await (select(sensorWindows)
          ..where((w) => w.bandRole.equals(BandRole.ankle.name))
          ..where((w) => w.sessionId.isIn(sessionIds)))
        .get();

    // Group by session ID and label - store lists to preserve all windows
    final wristMap = <String, List<({List<double> features, String label})>>{};
    final ankleMap = <String, List<({List<double> features, String label})>>{};

    for (final row in wristRows) {
      final featureList =
          (jsonDecode(row.features) as List).cast<num>().map((n) => n.toDouble()).toList();
      final key = '${row.sessionId}_${row.label}';
      wristMap.putIfAbsent(key, () => []).add((features: featureList, label: row.label));
    }

    for (final row in ankleRows) {
      final featureList =
          (jsonDecode(row.features) as List).cast<num>().map((n) => n.toDouble()).toList();
      final key = '${row.sessionId}_${row.label}';
      ankleMap.putIfAbsent(key, () => []).add((features: featureList, label: row.label));
    }

    // Combine pairs - pair each wrist window with each ankle window for the same session+label
    final combined = <({List<double> wristFeatures, List<double> ankleFeatures, String label})>[];
    for (final entry in wristMap.entries) {
      final ankleList = ankleMap[entry.key];
      if (ankleList != null) {
        for (final wristEntry in entry.value) {
          for (final ankleEntry in ankleList) {
            combined.add((
              wristFeatures: wristEntry.features,
              ankleFeatures: ankleEntry.features,
              label: wristEntry.label,
            ));
          }
        }
      }
    }

    return combined;
  }

  /// Total number of stored windows across all sessions.
  Future<int> get totalWindowCount async {
    final count = countAll();
    final query = selectOnly(sensorWindows)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Number of distinct labels that have training data.
  Future<int> get distinctLabelCount async {
    final rows = await (selectOnly(sensorWindows, distinct: true)
          ..addColumns([sensorWindows.label]))
        .get();
    return rows.length;
  }

  /// Get window counts grouped by band role.
  Future<Map<BandRole, int>> getWindowCountsByRole() async {
    final map = <BandRole, int>{};
    for (final role in BandRole.values) {
      final count = countAll();
      final query = selectOnly(sensorWindows)..addColumns([count]);
      query.where(sensorWindows.bandRole.equals(role.name));
      final result = await query.getSingle();
      map[role] = result.read(count) ?? 0;
    }
    return map;
  }

  // ── Prediction Feedbacks ──

  /// Record user feedback on an activity prediction.
  Future<int> insertPredictionFeedback({
    required String predictedLabel,
    required String userFeedback,
    String? correctedLabel,
    required String modelVersion,
    double? confidence,
    int? sessionId,
  }) async {
    return into(predictionFeedbacks).insert(
      PredictionFeedbacksCompanion.insert(
        predictedLabel: predictedLabel,
        userFeedback: userFeedback,
        correctedLabel: Value(correctedLabel),
        modelVersion: modelVersion,
        confidence: Value(confidence),
        sessionId: Value(sessionId),
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Get all prediction feedback records, newest first.
  Future<List<PredictionFeedback>> getAllPredictionFeedbacks() {
    return (select(predictionFeedbacks)
          ..orderBy([(f) => OrderingTerm.desc(f.timestamp)]))
        .get();
  }

  /// Get pending unreviewed feedback records.
  Future<List<PredictionFeedback>> getUnreviewedFeedbacks() {
    return (select(predictionFeedbacks)
          ..where((f) => f.isReviewed.equals(false))
          ..orderBy([(f) => OrderingTerm.desc(f.timestamp)]))
        .get();
  }

  /// Mark a feedback item as reviewed.
  Future<void> markFeedbackReviewed(int feedbackId) async {
    await (update(predictionFeedbacks)..where((f) => f.id.equals(feedbackId)))
        .write(const PredictionFeedbacksCompanion(isReviewed: Value(true)));
  }

  // ── Danger zone ──

  /// Delete all sessions and associated data.
  Future<void> clearAll() async {
    await delete(predictionFeedbacks).go();
    await delete(imuSampleRecords).go();
    await delete(sensorWindows).go();
    await delete(sessions).go();
  }
}

// ── Data Classes ──

/// Lightweight data class for IMU samples from database.
class ImuSampleData {
  final int id;
  final int sessionId;
  final BandRole bandRole;
  final String deviceId;
  final String deviceName;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final double accelMagnitude;
  final double gyroMagnitude;
  final int captureTimestampMs;
  final DateTime timestamp;

  const ImuSampleData({
    required this.id,
    required this.sessionId,
    required this.bandRole,
    required this.deviceId,
    required this.deviceName,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.accelMagnitude,
    required this.gyroMagnitude,
    this.captureTimestampMs = -1,
    required this.timestamp,
  });

  List<double> toList() => [ax, ay, az, gx, gy, gz];

  model.ImuSample toModelImuSample() => model.ImuSample(
        ax: ax,
        ay: ay,
        az: az,
        gx: gx,
        gy: gy,
        gz: gz,
        captureTimestampMs: captureTimestampMs,
        timestamp: timestamp,
        bandRole: bandRole,
        deviceId: deviceId,
        deviceName: deviceName,
      );
}

// ── Connection helper ──

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'bandana.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}