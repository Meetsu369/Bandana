// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_service.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
    'end_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sampleCountMeta = const VerificationMeta(
    'sampleCount',
  );
  @override
  late final GeneratedColumn<int> sampleCount = GeneratedColumn<int>(
    'sample_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    startTime,
    endTime,
    sampleCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    }
    if (data.containsKey('sample_count')) {
      context.handle(
        _sampleCountMeta,
        sampleCount.isAcceptableOrUnknown(
          data['sample_count']!,
          _sampleCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_time'],
      ),
      sampleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_count'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final int id;
  final String label;
  final DateTime startTime;
  final DateTime? endTime;
  final int sampleCount;
  const Session({
    required this.id,
    required this.label,
    required this.startTime,
    this.endTime,
    required this.sampleCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['label'] = Variable<String>(label);
    map['start_time'] = Variable<DateTime>(startTime);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    map['sample_count'] = Variable<int>(sampleCount);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      label: Value(label),
      startTime: Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      sampleCount: Value(sampleCount),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<int>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      sampleCount: serializer.fromJson<int>(json['sampleCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'label': serializer.toJson<String>(label),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'sampleCount': serializer.toJson<int>(sampleCount),
    };
  }

  Session copyWith({
    int? id,
    String? label,
    DateTime? startTime,
    Value<DateTime?> endTime = const Value.absent(),
    int? sampleCount,
  }) => Session(
    id: id ?? this.id,
    label: label ?? this.label,
    startTime: startTime ?? this.startTime,
    endTime: endTime.present ? endTime.value : this.endTime,
    sampleCount: sampleCount ?? this.sampleCount,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      sampleCount: data.sampleCount.present
          ? data.sampleCount.value
          : this.sampleCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('sampleCount: $sampleCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, label, startTime, endTime, sampleCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.label == this.label &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.sampleCount == this.sampleCount);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<int> id;
  final Value<String> label;
  final Value<DateTime> startTime;
  final Value<DateTime?> endTime;
  final Value<int> sampleCount;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.sampleCount = const Value.absent(),
  });
  SessionsCompanion.insert({
    this.id = const Value.absent(),
    required String label,
    required DateTime startTime,
    this.endTime = const Value.absent(),
    this.sampleCount = const Value.absent(),
  }) : label = Value(label),
       startTime = Value(startTime);
  static Insertable<Session> custom({
    Expression<int>? id,
    Expression<String>? label,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<int>? sampleCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (sampleCount != null) 'sample_count': sampleCount,
    });
  }

  SessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? label,
    Value<DateTime>? startTime,
    Value<DateTime?>? endTime,
    Value<int>? sampleCount,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sampleCount: sampleCount ?? this.sampleCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (sampleCount.present) {
      map['sample_count'] = Variable<int>(sampleCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('sampleCount: $sampleCount')
          ..write(')'))
        .toString();
  }
}

class $ImuSampleRecordsTable extends ImuSampleRecords
    with TableInfo<$ImuSampleRecordsTable, ImuSampleRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImuSampleRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _bandRoleMeta = const VerificationMeta(
    'bandRole',
  );
  @override
  late final GeneratedColumn<String> bandRole = GeneratedColumn<String>(
    'band_role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _axMeta = const VerificationMeta('ax');
  @override
  late final GeneratedColumn<double> ax = GeneratedColumn<double>(
    'ax',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ayMeta = const VerificationMeta('ay');
  @override
  late final GeneratedColumn<double> ay = GeneratedColumn<double>(
    'ay',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _azMeta = const VerificationMeta('az');
  @override
  late final GeneratedColumn<double> az = GeneratedColumn<double>(
    'az',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gxMeta = const VerificationMeta('gx');
  @override
  late final GeneratedColumn<double> gx = GeneratedColumn<double>(
    'gx',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gyMeta = const VerificationMeta('gy');
  @override
  late final GeneratedColumn<double> gy = GeneratedColumn<double>(
    'gy',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gzMeta = const VerificationMeta('gz');
  @override
  late final GeneratedColumn<double> gz = GeneratedColumn<double>(
    'gz',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accelMagnitudeMeta = const VerificationMeta(
    'accelMagnitude',
  );
  @override
  late final GeneratedColumn<double> accelMagnitude = GeneratedColumn<double>(
    'accel_magnitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gyroMagnitudeMeta = const VerificationMeta(
    'gyroMagnitude',
  );
  @override
  late final GeneratedColumn<double> gyroMagnitude = GeneratedColumn<double>(
    'gyro_magnitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    bandRole,
    deviceId,
    deviceName,
    ax,
    ay,
    az,
    gx,
    gy,
    gz,
    accelMagnitude,
    gyroMagnitude,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imu_sample_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImuSampleRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('band_role')) {
      context.handle(
        _bandRoleMeta,
        bandRole.isAcceptableOrUnknown(data['band_role']!, _bandRoleMeta),
      );
    } else if (isInserting) {
      context.missing(_bandRoleMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('ax')) {
      context.handle(_axMeta, ax.isAcceptableOrUnknown(data['ax']!, _axMeta));
    } else if (isInserting) {
      context.missing(_axMeta);
    }
    if (data.containsKey('ay')) {
      context.handle(_ayMeta, ay.isAcceptableOrUnknown(data['ay']!, _ayMeta));
    } else if (isInserting) {
      context.missing(_ayMeta);
    }
    if (data.containsKey('az')) {
      context.handle(_azMeta, az.isAcceptableOrUnknown(data['az']!, _azMeta));
    } else if (isInserting) {
      context.missing(_azMeta);
    }
    if (data.containsKey('gx')) {
      context.handle(_gxMeta, gx.isAcceptableOrUnknown(data['gx']!, _gxMeta));
    } else if (isInserting) {
      context.missing(_gxMeta);
    }
    if (data.containsKey('gy')) {
      context.handle(_gyMeta, gy.isAcceptableOrUnknown(data['gy']!, _gyMeta));
    } else if (isInserting) {
      context.missing(_gyMeta);
    }
    if (data.containsKey('gz')) {
      context.handle(_gzMeta, gz.isAcceptableOrUnknown(data['gz']!, _gzMeta));
    } else if (isInserting) {
      context.missing(_gzMeta);
    }
    if (data.containsKey('accel_magnitude')) {
      context.handle(
        _accelMagnitudeMeta,
        accelMagnitude.isAcceptableOrUnknown(
          data['accel_magnitude']!,
          _accelMagnitudeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accelMagnitudeMeta);
    }
    if (data.containsKey('gyro_magnitude')) {
      context.handle(
        _gyroMagnitudeMeta,
        gyroMagnitude.isAcceptableOrUnknown(
          data['gyro_magnitude']!,
          _gyroMagnitudeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_gyroMagnitudeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImuSampleRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImuSampleRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      bandRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}band_role'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      ax: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ax'],
      )!,
      ay: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ay'],
      )!,
      az: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}az'],
      )!,
      gx: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gx'],
      )!,
      gy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gy'],
      )!,
      gz: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gz'],
      )!,
      accelMagnitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accel_magnitude'],
      )!,
      gyroMagnitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gyro_magnitude'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $ImuSampleRecordsTable createAlias(String alias) {
    return $ImuSampleRecordsTable(attachedDatabase, alias);
  }
}

class ImuSampleRecord extends DataClass implements Insertable<ImuSampleRecord> {
  final int id;
  final int sessionId;
  final String bandRole;
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
  const ImuSampleRecord({
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
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['band_role'] = Variable<String>(bandRole);
    map['device_id'] = Variable<String>(deviceId);
    map['device_name'] = Variable<String>(deviceName);
    map['ax'] = Variable<double>(ax);
    map['ay'] = Variable<double>(ay);
    map['az'] = Variable<double>(az);
    map['gx'] = Variable<double>(gx);
    map['gy'] = Variable<double>(gy);
    map['gz'] = Variable<double>(gz);
    map['accel_magnitude'] = Variable<double>(accelMagnitude);
    map['gyro_magnitude'] = Variable<double>(gyroMagnitude);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  ImuSampleRecordsCompanion toCompanion(bool nullToAbsent) {
    return ImuSampleRecordsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      bandRole: Value(bandRole),
      deviceId: Value(deviceId),
      deviceName: Value(deviceName),
      ax: Value(ax),
      ay: Value(ay),
      az: Value(az),
      gx: Value(gx),
      gy: Value(gy),
      gz: Value(gz),
      accelMagnitude: Value(accelMagnitude),
      gyroMagnitude: Value(gyroMagnitude),
      timestamp: Value(timestamp),
    );
  }

  factory ImuSampleRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImuSampleRecord(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      bandRole: serializer.fromJson<String>(json['bandRole']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      ax: serializer.fromJson<double>(json['ax']),
      ay: serializer.fromJson<double>(json['ay']),
      az: serializer.fromJson<double>(json['az']),
      gx: serializer.fromJson<double>(json['gx']),
      gy: serializer.fromJson<double>(json['gy']),
      gz: serializer.fromJson<double>(json['gz']),
      accelMagnitude: serializer.fromJson<double>(json['accelMagnitude']),
      gyroMagnitude: serializer.fromJson<double>(json['gyroMagnitude']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'bandRole': serializer.toJson<String>(bandRole),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceName': serializer.toJson<String>(deviceName),
      'ax': serializer.toJson<double>(ax),
      'ay': serializer.toJson<double>(ay),
      'az': serializer.toJson<double>(az),
      'gx': serializer.toJson<double>(gx),
      'gy': serializer.toJson<double>(gy),
      'gz': serializer.toJson<double>(gz),
      'accelMagnitude': serializer.toJson<double>(accelMagnitude),
      'gyroMagnitude': serializer.toJson<double>(gyroMagnitude),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  ImuSampleRecord copyWith({
    int? id,
    int? sessionId,
    String? bandRole,
    String? deviceId,
    String? deviceName,
    double? ax,
    double? ay,
    double? az,
    double? gx,
    double? gy,
    double? gz,
    double? accelMagnitude,
    double? gyroMagnitude,
    DateTime? timestamp,
  }) => ImuSampleRecord(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    bandRole: bandRole ?? this.bandRole,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    ax: ax ?? this.ax,
    ay: ay ?? this.ay,
    az: az ?? this.az,
    gx: gx ?? this.gx,
    gy: gy ?? this.gy,
    gz: gz ?? this.gz,
    accelMagnitude: accelMagnitude ?? this.accelMagnitude,
    gyroMagnitude: gyroMagnitude ?? this.gyroMagnitude,
    timestamp: timestamp ?? this.timestamp,
  );
  ImuSampleRecord copyWithCompanion(ImuSampleRecordsCompanion data) {
    return ImuSampleRecord(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      bandRole: data.bandRole.present ? data.bandRole.value : this.bandRole,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      ax: data.ax.present ? data.ax.value : this.ax,
      ay: data.ay.present ? data.ay.value : this.ay,
      az: data.az.present ? data.az.value : this.az,
      gx: data.gx.present ? data.gx.value : this.gx,
      gy: data.gy.present ? data.gy.value : this.gy,
      gz: data.gz.present ? data.gz.value : this.gz,
      accelMagnitude: data.accelMagnitude.present
          ? data.accelMagnitude.value
          : this.accelMagnitude,
      gyroMagnitude: data.gyroMagnitude.present
          ? data.gyroMagnitude.value
          : this.gyroMagnitude,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImuSampleRecord(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('bandRole: $bandRole, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('ax: $ax, ')
          ..write('ay: $ay, ')
          ..write('az: $az, ')
          ..write('gx: $gx, ')
          ..write('gy: $gy, ')
          ..write('gz: $gz, ')
          ..write('accelMagnitude: $accelMagnitude, ')
          ..write('gyroMagnitude: $gyroMagnitude, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    bandRole,
    deviceId,
    deviceName,
    ax,
    ay,
    az,
    gx,
    gy,
    gz,
    accelMagnitude,
    gyroMagnitude,
    timestamp,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImuSampleRecord &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.bandRole == this.bandRole &&
          other.deviceId == this.deviceId &&
          other.deviceName == this.deviceName &&
          other.ax == this.ax &&
          other.ay == this.ay &&
          other.az == this.az &&
          other.gx == this.gx &&
          other.gy == this.gy &&
          other.gz == this.gz &&
          other.accelMagnitude == this.accelMagnitude &&
          other.gyroMagnitude == this.gyroMagnitude &&
          other.timestamp == this.timestamp);
}

class ImuSampleRecordsCompanion extends UpdateCompanion<ImuSampleRecord> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<String> bandRole;
  final Value<String> deviceId;
  final Value<String> deviceName;
  final Value<double> ax;
  final Value<double> ay;
  final Value<double> az;
  final Value<double> gx;
  final Value<double> gy;
  final Value<double> gz;
  final Value<double> accelMagnitude;
  final Value<double> gyroMagnitude;
  final Value<DateTime> timestamp;
  const ImuSampleRecordsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.bandRole = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.ax = const Value.absent(),
    this.ay = const Value.absent(),
    this.az = const Value.absent(),
    this.gx = const Value.absent(),
    this.gy = const Value.absent(),
    this.gz = const Value.absent(),
    this.accelMagnitude = const Value.absent(),
    this.gyroMagnitude = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  ImuSampleRecordsCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required String bandRole,
    required String deviceId,
    required String deviceName,
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double accelMagnitude,
    required double gyroMagnitude,
    required DateTime timestamp,
  }) : sessionId = Value(sessionId),
       bandRole = Value(bandRole),
       deviceId = Value(deviceId),
       deviceName = Value(deviceName),
       ax = Value(ax),
       ay = Value(ay),
       az = Value(az),
       gx = Value(gx),
       gy = Value(gy),
       gz = Value(gz),
       accelMagnitude = Value(accelMagnitude),
       gyroMagnitude = Value(gyroMagnitude),
       timestamp = Value(timestamp);
  static Insertable<ImuSampleRecord> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<String>? bandRole,
    Expression<String>? deviceId,
    Expression<String>? deviceName,
    Expression<double>? ax,
    Expression<double>? ay,
    Expression<double>? az,
    Expression<double>? gx,
    Expression<double>? gy,
    Expression<double>? gz,
    Expression<double>? accelMagnitude,
    Expression<double>? gyroMagnitude,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (bandRole != null) 'band_role': bandRole,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (ax != null) 'ax': ax,
      if (ay != null) 'ay': ay,
      if (az != null) 'az': az,
      if (gx != null) 'gx': gx,
      if (gy != null) 'gy': gy,
      if (gz != null) 'gz': gz,
      if (accelMagnitude != null) 'accel_magnitude': accelMagnitude,
      if (gyroMagnitude != null) 'gyro_magnitude': gyroMagnitude,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  ImuSampleRecordsCompanion copyWith({
    Value<int>? id,
    Value<int>? sessionId,
    Value<String>? bandRole,
    Value<String>? deviceId,
    Value<String>? deviceName,
    Value<double>? ax,
    Value<double>? ay,
    Value<double>? az,
    Value<double>? gx,
    Value<double>? gy,
    Value<double>? gz,
    Value<double>? accelMagnitude,
    Value<double>? gyroMagnitude,
    Value<DateTime>? timestamp,
  }) {
    return ImuSampleRecordsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      bandRole: bandRole ?? this.bandRole,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ax: ax ?? this.ax,
      ay: ay ?? this.ay,
      az: az ?? this.az,
      gx: gx ?? this.gx,
      gy: gy ?? this.gy,
      gz: gz ?? this.gz,
      accelMagnitude: accelMagnitude ?? this.accelMagnitude,
      gyroMagnitude: gyroMagnitude ?? this.gyroMagnitude,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (bandRole.present) {
      map['band_role'] = Variable<String>(bandRole.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (ax.present) {
      map['ax'] = Variable<double>(ax.value);
    }
    if (ay.present) {
      map['ay'] = Variable<double>(ay.value);
    }
    if (az.present) {
      map['az'] = Variable<double>(az.value);
    }
    if (gx.present) {
      map['gx'] = Variable<double>(gx.value);
    }
    if (gy.present) {
      map['gy'] = Variable<double>(gy.value);
    }
    if (gz.present) {
      map['gz'] = Variable<double>(gz.value);
    }
    if (accelMagnitude.present) {
      map['accel_magnitude'] = Variable<double>(accelMagnitude.value);
    }
    if (gyroMagnitude.present) {
      map['gyro_magnitude'] = Variable<double>(gyroMagnitude.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImuSampleRecordsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('bandRole: $bandRole, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceName: $deviceName, ')
          ..write('ax: $ax, ')
          ..write('ay: $ay, ')
          ..write('az: $az, ')
          ..write('gx: $gx, ')
          ..write('gy: $gy, ')
          ..write('gz: $gz, ')
          ..write('accelMagnitude: $accelMagnitude, ')
          ..write('gyroMagnitude: $gyroMagnitude, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $SensorWindowsTable extends SensorWindows
    with TableInfo<$SensorWindowsTable, SensorWindow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SensorWindowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _bandRoleMeta = const VerificationMeta(
    'bandRole',
  );
  @override
  late final GeneratedColumn<String> bandRole = GeneratedColumn<String>(
    'band_role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _featuresMeta = const VerificationMeta(
    'features',
  );
  @override
  late final GeneratedColumn<String> features = GeneratedColumn<String>(
    'features',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    bandRole,
    features,
    label,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sensor_windows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SensorWindow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('band_role')) {
      context.handle(
        _bandRoleMeta,
        bandRole.isAcceptableOrUnknown(data['band_role']!, _bandRoleMeta),
      );
    } else if (isInserting) {
      context.missing(_bandRoleMeta);
    }
    if (data.containsKey('features')) {
      context.handle(
        _featuresMeta,
        features.isAcceptableOrUnknown(data['features']!, _featuresMeta),
      );
    } else if (isInserting) {
      context.missing(_featuresMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SensorWindow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SensorWindow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      bandRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}band_role'],
      )!,
      features: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}features'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $SensorWindowsTable createAlias(String alias) {
    return $SensorWindowsTable(attachedDatabase, alias);
  }
}

class SensorWindow extends DataClass implements Insertable<SensorWindow> {
  final int id;
  final int sessionId;
  final String bandRole;
  final String features;
  final String label;
  final DateTime timestamp;
  const SensorWindow({
    required this.id,
    required this.sessionId,
    required this.bandRole,
    required this.features,
    required this.label,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['band_role'] = Variable<String>(bandRole);
    map['features'] = Variable<String>(features);
    map['label'] = Variable<String>(label);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  SensorWindowsCompanion toCompanion(bool nullToAbsent) {
    return SensorWindowsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      bandRole: Value(bandRole),
      features: Value(features),
      label: Value(label),
      timestamp: Value(timestamp),
    );
  }

  factory SensorWindow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SensorWindow(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      bandRole: serializer.fromJson<String>(json['bandRole']),
      features: serializer.fromJson<String>(json['features']),
      label: serializer.fromJson<String>(json['label']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'bandRole': serializer.toJson<String>(bandRole),
      'features': serializer.toJson<String>(features),
      'label': serializer.toJson<String>(label),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  SensorWindow copyWith({
    int? id,
    int? sessionId,
    String? bandRole,
    String? features,
    String? label,
    DateTime? timestamp,
  }) => SensorWindow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    bandRole: bandRole ?? this.bandRole,
    features: features ?? this.features,
    label: label ?? this.label,
    timestamp: timestamp ?? this.timestamp,
  );
  SensorWindow copyWithCompanion(SensorWindowsCompanion data) {
    return SensorWindow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      bandRole: data.bandRole.present ? data.bandRole.value : this.bandRole,
      features: data.features.present ? data.features.value : this.features,
      label: data.label.present ? data.label.value : this.label,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SensorWindow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('bandRole: $bandRole, ')
          ..write('features: $features, ')
          ..write('label: $label, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, bandRole, features, label, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SensorWindow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.bandRole == this.bandRole &&
          other.features == this.features &&
          other.label == this.label &&
          other.timestamp == this.timestamp);
}

class SensorWindowsCompanion extends UpdateCompanion<SensorWindow> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<String> bandRole;
  final Value<String> features;
  final Value<String> label;
  final Value<DateTime> timestamp;
  const SensorWindowsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.bandRole = const Value.absent(),
    this.features = const Value.absent(),
    this.label = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  SensorWindowsCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required String bandRole,
    required String features,
    required String label,
    required DateTime timestamp,
  }) : sessionId = Value(sessionId),
       bandRole = Value(bandRole),
       features = Value(features),
       label = Value(label),
       timestamp = Value(timestamp);
  static Insertable<SensorWindow> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<String>? bandRole,
    Expression<String>? features,
    Expression<String>? label,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (bandRole != null) 'band_role': bandRole,
      if (features != null) 'features': features,
      if (label != null) 'label': label,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  SensorWindowsCompanion copyWith({
    Value<int>? id,
    Value<int>? sessionId,
    Value<String>? bandRole,
    Value<String>? features,
    Value<String>? label,
    Value<DateTime>? timestamp,
  }) {
    return SensorWindowsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      bandRole: bandRole ?? this.bandRole,
      features: features ?? this.features,
      label: label ?? this.label,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (bandRole.present) {
      map['band_role'] = Variable<String>(bandRole.value);
    }
    if (features.present) {
      map['features'] = Variable<String>(features.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SensorWindowsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('bandRole: $bandRole, ')
          ..write('features: $features, ')
          ..write('label: $label, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

abstract class _$DatabaseService extends GeneratedDatabase {
  _$DatabaseService(QueryExecutor e) : super(e);
  $DatabaseServiceManager get managers => $DatabaseServiceManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $ImuSampleRecordsTable imuSampleRecords = $ImuSampleRecordsTable(
    this,
  );
  late final $SensorWindowsTable sensorWindows = $SensorWindowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sessions,
    imuSampleRecords,
    sensorWindows,
  ];
}

typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      Value<int> id,
      required String label,
      required DateTime startTime,
      Value<DateTime?> endTime,
      Value<int> sampleCount,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<int> id,
      Value<String> label,
      Value<DateTime> startTime,
      Value<DateTime?> endTime,
      Value<int> sampleCount,
    });

final class $$SessionsTableReferences
    extends BaseReferences<_$DatabaseService, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ImuSampleRecordsTable, List<ImuSampleRecord>>
  _imuSampleRecordsRefsTable(_$DatabaseService db) =>
      MultiTypedResultKey.fromTable(
        db.imuSampleRecords,
        aliasName: 'sessions__id__imu_sample_records__session_id',
      );

  $$ImuSampleRecordsTableProcessedTableManager get imuSampleRecordsRefs {
    final manager = $$ImuSampleRecordsTableTableManager(
      $_db,
      $_db.imuSampleRecords,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _imuSampleRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SensorWindowsTable, List<SensorWindow>>
  _sensorWindowsRefsTable(_$DatabaseService db) =>
      MultiTypedResultKey.fromTable(
        db.sensorWindows,
        aliasName: 'sessions__id__sensor_windows__session_id',
      );

  $$SensorWindowsTableProcessedTableManager get sensorWindowsRefs {
    final manager = $$SensorWindowsTableTableManager(
      $_db,
      $_db.sensorWindows,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_sensorWindowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$DatabaseService, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> imuSampleRecordsRefs(
    Expression<bool> Function($$ImuSampleRecordsTableFilterComposer f) f,
  ) {
    final $$ImuSampleRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.imuSampleRecords,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImuSampleRecordsTableFilterComposer(
            $db: $db,
            $table: $db.imuSampleRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sensorWindowsRefs(
    Expression<bool> Function($$SensorWindowsTableFilterComposer f) f,
  ) {
    final $$SensorWindowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sensorWindows,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SensorWindowsTableFilterComposer(
            $db: $db,
            $table: $db.sensorWindows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$DatabaseService, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$DatabaseService, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => column,
  );

  Expression<T> imuSampleRecordsRefs<T extends Object>(
    Expression<T> Function($$ImuSampleRecordsTableAnnotationComposer a) f,
  ) {
    final $$ImuSampleRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.imuSampleRecords,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ImuSampleRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.imuSampleRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sensorWindowsRefs<T extends Object>(
    Expression<T> Function($$SensorWindowsTableAnnotationComposer a) f,
  ) {
    final $$SensorWindowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sensorWindows,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SensorWindowsTableAnnotationComposer(
            $db: $db,
            $table: $db.sensorWindows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$DatabaseService,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({
            bool imuSampleRecordsRefs,
            bool sensorWindowsRefs,
          })
        > {
  $$SessionsTableTableManager(_$DatabaseService db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<DateTime> startTime = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                Value<int> sampleCount = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                label: label,
                startTime: startTime,
                endTime: endTime,
                sampleCount: sampleCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String label,
                required DateTime startTime,
                Value<DateTime?> endTime = const Value.absent(),
                Value<int> sampleCount = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                label: label,
                startTime: startTime,
                endTime: endTime,
                sampleCount: sampleCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({imuSampleRecordsRefs = false, sensorWindowsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (imuSampleRecordsRefs) db.imuSampleRecords,
                    if (sensorWindowsRefs) db.sensorWindows,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (imuSampleRecordsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          ImuSampleRecord
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._imuSampleRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).imuSampleRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sensorWindowsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          SensorWindow
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._sensorWindowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sensorWindowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$DatabaseService,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({
        bool imuSampleRecordsRefs,
        bool sensorWindowsRefs,
      })
    >;
typedef $$ImuSampleRecordsTableCreateCompanionBuilder =
    ImuSampleRecordsCompanion Function({
      Value<int> id,
      required int sessionId,
      required String bandRole,
      required String deviceId,
      required String deviceName,
      required double ax,
      required double ay,
      required double az,
      required double gx,
      required double gy,
      required double gz,
      required double accelMagnitude,
      required double gyroMagnitude,
      required DateTime timestamp,
    });
typedef $$ImuSampleRecordsTableUpdateCompanionBuilder =
    ImuSampleRecordsCompanion Function({
      Value<int> id,
      Value<int> sessionId,
      Value<String> bandRole,
      Value<String> deviceId,
      Value<String> deviceName,
      Value<double> ax,
      Value<double> ay,
      Value<double> az,
      Value<double> gx,
      Value<double> gy,
      Value<double> gz,
      Value<double> accelMagnitude,
      Value<double> gyroMagnitude,
      Value<DateTime> timestamp,
    });

final class $$ImuSampleRecordsTableReferences
    extends
        BaseReferences<
          _$DatabaseService,
          $ImuSampleRecordsTable,
          ImuSampleRecord
        > {
  $$ImuSampleRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$DatabaseService db) =>
      db.sessions.createAlias('imu_sample_records__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ImuSampleRecordsTableFilterComposer
    extends Composer<_$DatabaseService, $ImuSampleRecordsTable> {
  $$ImuSampleRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bandRole => $composableBuilder(
    column: $table.bandRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ax => $composableBuilder(
    column: $table.ax,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ay => $composableBuilder(
    column: $table.ay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get az => $composableBuilder(
    column: $table.az,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gx => $composableBuilder(
    column: $table.gx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gy => $composableBuilder(
    column: $table.gy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gz => $composableBuilder(
    column: $table.gz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accelMagnitude => $composableBuilder(
    column: $table.accelMagnitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gyroMagnitude => $composableBuilder(
    column: $table.gyroMagnitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImuSampleRecordsTableOrderingComposer
    extends Composer<_$DatabaseService, $ImuSampleRecordsTable> {
  $$ImuSampleRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bandRole => $composableBuilder(
    column: $table.bandRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ax => $composableBuilder(
    column: $table.ax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ay => $composableBuilder(
    column: $table.ay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get az => $composableBuilder(
    column: $table.az,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gx => $composableBuilder(
    column: $table.gx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gy => $composableBuilder(
    column: $table.gy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gz => $composableBuilder(
    column: $table.gz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accelMagnitude => $composableBuilder(
    column: $table.accelMagnitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gyroMagnitude => $composableBuilder(
    column: $table.gyroMagnitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImuSampleRecordsTableAnnotationComposer
    extends Composer<_$DatabaseService, $ImuSampleRecordsTable> {
  $$ImuSampleRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bandRole =>
      $composableBuilder(column: $table.bandRole, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ax =>
      $composableBuilder(column: $table.ax, builder: (column) => column);

  GeneratedColumn<double> get ay =>
      $composableBuilder(column: $table.ay, builder: (column) => column);

  GeneratedColumn<double> get az =>
      $composableBuilder(column: $table.az, builder: (column) => column);

  GeneratedColumn<double> get gx =>
      $composableBuilder(column: $table.gx, builder: (column) => column);

  GeneratedColumn<double> get gy =>
      $composableBuilder(column: $table.gy, builder: (column) => column);

  GeneratedColumn<double> get gz =>
      $composableBuilder(column: $table.gz, builder: (column) => column);

  GeneratedColumn<double> get accelMagnitude => $composableBuilder(
    column: $table.accelMagnitude,
    builder: (column) => column,
  );

  GeneratedColumn<double> get gyroMagnitude => $composableBuilder(
    column: $table.gyroMagnitude,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ImuSampleRecordsTableTableManager
    extends
        RootTableManager<
          _$DatabaseService,
          $ImuSampleRecordsTable,
          ImuSampleRecord,
          $$ImuSampleRecordsTableFilterComposer,
          $$ImuSampleRecordsTableOrderingComposer,
          $$ImuSampleRecordsTableAnnotationComposer,
          $$ImuSampleRecordsTableCreateCompanionBuilder,
          $$ImuSampleRecordsTableUpdateCompanionBuilder,
          (ImuSampleRecord, $$ImuSampleRecordsTableReferences),
          ImuSampleRecord,
          PrefetchHooks Function({bool sessionId})
        > {
  $$ImuSampleRecordsTableTableManager(
    _$DatabaseService db,
    $ImuSampleRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImuSampleRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImuSampleRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImuSampleRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<String> bandRole = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<double> ax = const Value.absent(),
                Value<double> ay = const Value.absent(),
                Value<double> az = const Value.absent(),
                Value<double> gx = const Value.absent(),
                Value<double> gy = const Value.absent(),
                Value<double> gz = const Value.absent(),
                Value<double> accelMagnitude = const Value.absent(),
                Value<double> gyroMagnitude = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => ImuSampleRecordsCompanion(
                id: id,
                sessionId: sessionId,
                bandRole: bandRole,
                deviceId: deviceId,
                deviceName: deviceName,
                ax: ax,
                ay: ay,
                az: az,
                gx: gx,
                gy: gy,
                gz: gz,
                accelMagnitude: accelMagnitude,
                gyroMagnitude: gyroMagnitude,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sessionId,
                required String bandRole,
                required String deviceId,
                required String deviceName,
                required double ax,
                required double ay,
                required double az,
                required double gx,
                required double gy,
                required double gz,
                required double accelMagnitude,
                required double gyroMagnitude,
                required DateTime timestamp,
              }) => ImuSampleRecordsCompanion.insert(
                id: id,
                sessionId: sessionId,
                bandRole: bandRole,
                deviceId: deviceId,
                deviceName: deviceName,
                ax: ax,
                ay: ay,
                az: az,
                gx: gx,
                gy: gy,
                gz: gz,
                accelMagnitude: accelMagnitude,
                gyroMagnitude: gyroMagnitude,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ImuSampleRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$ImuSampleRecordsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$ImuSampleRecordsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ImuSampleRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$DatabaseService,
      $ImuSampleRecordsTable,
      ImuSampleRecord,
      $$ImuSampleRecordsTableFilterComposer,
      $$ImuSampleRecordsTableOrderingComposer,
      $$ImuSampleRecordsTableAnnotationComposer,
      $$ImuSampleRecordsTableCreateCompanionBuilder,
      $$ImuSampleRecordsTableUpdateCompanionBuilder,
      (ImuSampleRecord, $$ImuSampleRecordsTableReferences),
      ImuSampleRecord,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$SensorWindowsTableCreateCompanionBuilder =
    SensorWindowsCompanion Function({
      Value<int> id,
      required int sessionId,
      required String bandRole,
      required String features,
      required String label,
      required DateTime timestamp,
    });
typedef $$SensorWindowsTableUpdateCompanionBuilder =
    SensorWindowsCompanion Function({
      Value<int> id,
      Value<int> sessionId,
      Value<String> bandRole,
      Value<String> features,
      Value<String> label,
      Value<DateTime> timestamp,
    });

final class $$SensorWindowsTableReferences
    extends
        BaseReferences<_$DatabaseService, $SensorWindowsTable, SensorWindow> {
  $$SensorWindowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$DatabaseService db) =>
      db.sessions.createAlias('sensor_windows__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<int>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SensorWindowsTableFilterComposer
    extends Composer<_$DatabaseService, $SensorWindowsTable> {
  $$SensorWindowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bandRole => $composableBuilder(
    column: $table.bandRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get features => $composableBuilder(
    column: $table.features,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SensorWindowsTableOrderingComposer
    extends Composer<_$DatabaseService, $SensorWindowsTable> {
  $$SensorWindowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bandRole => $composableBuilder(
    column: $table.bandRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get features => $composableBuilder(
    column: $table.features,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SensorWindowsTableAnnotationComposer
    extends Composer<_$DatabaseService, $SensorWindowsTable> {
  $$SensorWindowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bandRole =>
      $composableBuilder(column: $table.bandRole, builder: (column) => column);

  GeneratedColumn<String> get features =>
      $composableBuilder(column: $table.features, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SensorWindowsTableTableManager
    extends
        RootTableManager<
          _$DatabaseService,
          $SensorWindowsTable,
          SensorWindow,
          $$SensorWindowsTableFilterComposer,
          $$SensorWindowsTableOrderingComposer,
          $$SensorWindowsTableAnnotationComposer,
          $$SensorWindowsTableCreateCompanionBuilder,
          $$SensorWindowsTableUpdateCompanionBuilder,
          (SensorWindow, $$SensorWindowsTableReferences),
          SensorWindow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SensorWindowsTableTableManager(
    _$DatabaseService db,
    $SensorWindowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SensorWindowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SensorWindowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SensorWindowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<String> bandRole = const Value.absent(),
                Value<String> features = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => SensorWindowsCompanion(
                id: id,
                sessionId: sessionId,
                bandRole: bandRole,
                features: features,
                label: label,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sessionId,
                required String bandRole,
                required String features,
                required String label,
                required DateTime timestamp,
              }) => SensorWindowsCompanion.insert(
                id: id,
                sessionId: sessionId,
                bandRole: bandRole,
                features: features,
                label: label,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SensorWindowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$SensorWindowsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$SensorWindowsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SensorWindowsTableProcessedTableManager =
    ProcessedTableManager<
      _$DatabaseService,
      $SensorWindowsTable,
      SensorWindow,
      $$SensorWindowsTableFilterComposer,
      $$SensorWindowsTableOrderingComposer,
      $$SensorWindowsTableAnnotationComposer,
      $$SensorWindowsTableCreateCompanionBuilder,
      $$SensorWindowsTableUpdateCompanionBuilder,
      (SensorWindow, $$SensorWindowsTableReferences),
      SensorWindow,
      PrefetchHooks Function({bool sessionId})
    >;

class $DatabaseServiceManager {
  final _$DatabaseService _db;
  $DatabaseServiceManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$ImuSampleRecordsTableTableManager get imuSampleRecords =>
      $$ImuSampleRecordsTableTableManager(_db, _db.imuSampleRecords);
  $$SensorWindowsTableTableManager get sensorWindows =>
      $$SensorWindowsTableTableManager(_db, _db.sensorWindows);
}
