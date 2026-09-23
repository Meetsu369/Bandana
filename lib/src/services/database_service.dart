import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart' as model;

part 'database_service.g.dart';

// ── Table Definitions ──

/// Recording sessions table.
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
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

// ── Database ──

@DriftDatabase(tables: [Sessions, ImuSampleRecords, SensorWindows])
class DatabaseService extends _$DatabaseService {
  DatabaseService() : super(_openConnection());

  @override
  int get schemaVersion => 3;

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
        },
      );

  // ── Sessions ──

  /// Create a new recording session and return its ID.
  Future<int> createSession(String label) async {
    final id = await into(sessions).insert(
      SessionsCompanion.insert(
        label: label,
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
  /// CSV header: sessionId,activity,timestamp,bandRole,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag
  Future<String> exportSessionCsv(int sessionId) async {
    final samples = await getImuSamples(sessionId: sessionId);
    if (samples.isEmpty) {
      throw StateError('No samples to export for session $sessionId');
    }

    // Fetch session details for activity label
    final sessions = await getAllSessions();
    final session = sessions.cast<Session?>().firstWhere(
      (s) => s?.id == sessionId,
      orElse: () => null,
    );
    final activity = session?.label ?? 'Unknown';

    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'session_${sessionId}_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
    final file = File(p.join(directory.path, fileName));

    final buffer = StringBuffer();
    // Header with sessionId and activity
    buffer.writeln('sessionId,activity,timestamp,bandRole,deviceId,deviceName,ax,ay,az,gx,gy,gz,accelMag,gyroMag');

    for (final sample in samples) {
      buffer.write(
        '${sessionId},'
        '${activity},'
        '${sample.timestamp.toIso8601String()},'
        '${sample.bandRole.name},'
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

  // ── Danger zone ──

  /// Delete all sessions and associated data.
  Future<void> clearAll() async {
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