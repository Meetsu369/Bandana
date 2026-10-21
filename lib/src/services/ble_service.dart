import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/ble_constants.dart';
import '../models/imu_sample.dart';

/// Connection state for a single band.
enum BandConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
}

/// @deprecated Use [BandConnectionState] instead.
@Deprecated('Use BandConnectionState instead')
typedef BleConnectionState = BandConnectionState;

/// Holds the BLE connection state and streams for a single band.
class BandConnection {
  final BandRole role;

  BandConnectionState _state = BandConnectionState.disconnected;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _controlCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  final _sensorController = StreamController<ImuSample>.broadcast();
  final _stateController = StreamController<BandConnectionState>.broadcast();
  final _offlineSyncSampleController = StreamController<ImuSample>.broadcast();
  final _offlineSyncCompleteController = StreamController<int>.broadcast();

  // Connection health tracking
  DateTime? _lastPacketTime;
  int _packetCount = 0;

  // Offline Sync State
  bool _isOfflineSyncing = false;
  int _offlineSyncedPacketCount = 0;

  BandConnection({required this.role});

  /// Stream of parsed IMU samples from this band.
  Stream<ImuSample> get sensorStream => _sensorController.stream;

  /// Stream of connection state changes for this band.
  Stream<BandConnectionState> get stateStream => _stateController.stream;

  /// Stream of historical IMU samples received during offline sync.
  Stream<ImuSample> get offlineSyncSampleStream => _offlineSyncSampleController.stream;

  /// Emits the total sample count when an offline catch-up sync finishes.
  Stream<int> get offlineSyncCompleteStream => _offlineSyncCompleteController.stream;

  /// Whether this band is actively receiving offline catch-up data.
  bool get isOfflineSyncing => _isOfflineSyncing;

  /// Current connection state (synchronous access).
  BandConnectionState get currentState => _state;

  /// For testing/mocking connection state transitions.
  void updateStateForTesting(BandConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  /// The connected device's platform name, if any.
  String? get deviceName => _device?.platformName;

  /// The connected device's remote ID (MAC on Android).
  String? get deviceId => _device?.remoteId.str;

  /// Time of last received packet, or null if no packets received.
  DateTime? get lastPacketTime => _lastPacketTime;

  /// Total number of packets received since connection.
  int get packetCount => _packetCount;

  /// Whether the connection is considered stale (no packets for 5 seconds).
  bool get isStale => _lastPacketTime != null &&
      DateTime.now().difference(_lastPacketTime!).inSeconds > 5;

  /// RSSI of the connected device.
  Future<int?> get rssi async {
    if (_state != BandConnectionState.connected || _device == null) return null;
    try {
      return await _device!.readRssi();
    } catch (_) {
      return null;
    }
  }

  /// Start scanning for this band's assigned device.
  Future<void> startScan() async {
    if (_state == BandConnectionState.scanning ||
        _state == BandConnectionState.connected) {
      return;
    }

    _updateState(BandConnectionState.scanning);
    await _scanSubscription?.cancel();

    final assignedId = await _getAssignedDeviceId();
    if (assignedId == null) {
      _updateState(BandConnectionState.disconnected);
      return;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.remoteId.str == assignedId) {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          return;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: BleConstants.scanTimeout);
    } catch (_) {
      // Silently handle if Bluetooth is off or permissions not yet granted
    }

    if (_state == BandConnectionState.scanning) {
      _updateState(BandConnectionState.disconnected);
    }
  }

  /// Stop scanning for this band.
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSubscription?.cancel();
    if (_state == BandConnectionState.scanning) {
      _updateState(BandConnectionState.disconnected);
    }
  }

  /// Connect to a specific device (used when user manually assigns).
  Future<void> connectToDevice(BluetoothDevice device) async {
    await _scanSubscription?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _connectToDevice(device);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _device = device;
    _updateState(BandConnectionState.connecting);

    try {
      await device.connect(
        license: License.nonprofit,
        autoConnect: false,
        mtu: 512,
      );

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      await _discoverAndSubscribe(device);
      _updateState(BandConnectionState.connected);
    } catch (e) {
      _handleDisconnect();
    }
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    final services = await device.discoverServices();
    _controlCharacteristic = null;

    for (final service in services) {
      if (service.uuid.toString().toLowerCase() ==
          BleConstants.serviceUuid.toLowerCase()) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == BleConstants.characteristicUuid.toLowerCase()) {
            await char.setNotifyValue(true);
            _notifySubscription = char.lastValueStream.listen(_onDataReceived);
            device.cancelWhenDisconnected(_notifySubscription!);
          } else if (uuid == BleConstants.controlCharacteristicUuid.toLowerCase()) {
            _controlCharacteristic = char;
          }
        }
      }
    }

    // Fallback: first notify characteristic and writable characteristic
    if (_notifySubscription == null) {
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.notify && _notifySubscription == null) {
            await char.setNotifyValue(true);
            _notifySubscription = char.lastValueStream.listen(_onDataReceived);
            device.cancelWhenDisconnected(_notifySubscription!);
          }
          if ((char.properties.write || char.properties.writeWithoutResponse) &&
              _controlCharacteristic == null) {
            _controlCharacteristic = char;
          }
        }
      }
    }
  }

  void _onDataReceived(List<int> value) {
    if (value.isEmpty) return;
    try {
      final receiveTimestamp = DateTime.now();

      // Check for 4-byte EOF notification marker (0xFFFFFFFF) from firmware
      if (value.length == 4 &&
          value[0] == 0xFF &&
          value[1] == 0xFF &&
          value[2] == 0xFF &&
          value[3] == 0xFF) {
        if (_isOfflineSyncing) {
          _isOfflineSyncing = false;
          final count = _offlineSyncedPacketCount;
          _offlineSyncCompleteController.add(count);
          // Automatically clear offline storage on the band after successful download
          clearOfflineStorage();
        }
        return;
      }

      // Priority Path: 20-byte packed binary payload (Choice B)
      if (value.length >= 20 && value.length % 20 == 0) {
        for (var offset = 0; offset < value.length; offset += 20) {
          final chunk = value.sublist(offset, offset + 20);
          final sample = ImuSample.fromBinary(
            chunk,
            bandRole: role,
            deviceId: _device?.remoteId.str ?? '',
            deviceName: _device?.platformName ?? 'Unknown',
            timestamp: receiveTimestamp,
          );
          if (_isOfflineSyncing) {
            _offlineSyncedPacketCount++;
            _offlineSyncSampleController.add(sample);
          } else {
            _sensorController.add(sample);
          }
        }
      } else {
        // Fallback: Legacy CSV string splitting
        final csv = utf8.decode(value).trim();
        if (csv.isEmpty) return;

        final lines = csv.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            final sample = ImuSample.tryParseCsv(
              csv: trimmed,
              bandRole: role,
              deviceId: _device?.remoteId.str ?? '',
              deviceName: _device?.platformName ?? 'Unknown',
              timestamp: receiveTimestamp,
            );
            if (sample != null) {
              _sensorController.add(sample);
            }
          }
        }
      }

      // Update connection health metrics (BLE receive time)
      _lastPacketTime = receiveTimestamp;
      _packetCount++;
    } catch (_) {
      // Silently skip malformed packets
    }
  }

  Future<void> disconnect() async {
    try {
      await _notifySubscription?.cancel();
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _device = null;
    _controlCharacteristic = null;
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _lastPacketTime = null;
    _packetCount = 0;
    _isOfflineSyncing = false;
    _offlineSyncedPacketCount = 0;
    _updateState(BandConnectionState.disconnected);
  }

  /// Send raw byte command to the band's control characteristic.
  Future<bool> sendControlCommand(List<int> bytes) async {
    if (_controlCharacteristic == null) return false;
    try {
      await _controlCharacteristic!.write(
        bytes,
        withoutResponse: _controlCharacteristic!.properties.writeWithoutResponse,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends OP_START_RECORDING (0x01) with optional activity label marker.
  Future<bool> startRecording({String label = ''}) async {
    final payload = <int>[BleConstants.opcodeStartRecording, ...utf8.encode(label)];
    return sendControlCommand(payload);
  }

  /// Sends OP_STOP_RECORDING (0x02) to flush and seal SD storage.
  Future<bool> stopRecording() async {
    return sendControlCommand([BleConstants.opcodeStopRecording]);
  }

  /// Sends OP_START_OFFLINE_SYNC (0x03) to trigger batch catch-up of /raw_imu.bin.
  Future<bool> startOfflineSync() async {
    _isOfflineSyncing = true;
    _offlineSyncedPacketCount = 0;
    return sendControlCommand([BleConstants.opcodeStartOfflineSync]);
  }

  /// Sends OP_CLEAR_OFFLINE_STORAGE (0x04) to truncate/erase /raw_imu.bin after download.
  Future<bool> clearOfflineStorage() async {
    return sendControlCommand([BleConstants.opcodeClearOfflineStorage]);
  }

  void _updateState(BandConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  Future<String?> _getAssignedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return role == BandRole.wrist
        ? prefs.getString('bandana_wrist_device_id')
        : prefs.getString('bandana_ankle_device_id');
  }

  Future<void> dispose() async {
    await disconnect();
    await _scanSubscription?.cancel();
    await _sensorController.close();
    await _stateController.close();
    await _offlineSyncSampleController.close();
    await _offlineSyncCompleteController.close();
  }
}

/// Singleton BLE service managing two simultaneous Bandana band connections
/// (Wrist + Ankle).
class BleService {
  final BandConnection wrist;
  final BandConnection ankle;

  BleService._internal()
      : wrist = BandConnection(role: BandRole.wrist),
        ankle = BandConnection(role: BandRole.ankle);

  static final BleService _instance = BleService._internal();

  factory BleService() => _instance;

  /// Stream of all IMU samples from both bands.
  Stream<ImuSample> get sensorStream async* {
    yield* wrist.sensorStream;
    yield* ankle.sensorStream;
  }

  /// Get connection for a specific role.
  BandConnection getConnection(BandRole role) => role == BandRole.wrist ? wrist : ankle;

  /// Start scanning for both assigned devices.
  Future<void> startScanAll() async {
    await Future.wait([wrist.startScan(), ankle.startScan()]);
  }

  /// Stop all scans.
  Future<void> stopScanAll() async {
    await Future.wait([wrist.stopScan(), ankle.stopScan()]);
  }

  /// Disconnect both bands.
  Future<void> disconnectAll() async {
    await Future.wait([wrist.disconnect(), ankle.disconnect()]);
  }

  /// Disconnect a specific band.
  Future<void> disconnectBand(BandRole role) async {
    await getConnection(role).disconnect();
  }

  /// Connect a specific band to a device (for manual assignment).
  Future<void> connectBand(BandRole role, BluetoothDevice device) async {
    await getConnection(role).connectToDevice(device);
  }

  /// Broadcast recording start command with activity label to connected bands.
  Future<bool> startRecording({String label = ''}) async {
    final w = await wrist.startRecording(label: label);
    final a = await ankle.startRecording(label: label);
    return w || a;
  }

  /// Broadcast recording stop command to connected bands.
  Future<bool> stopRecording() async {
    final w = await wrist.stopRecording();
    final a = await ankle.stopRecording();
    return w || a;
  }

  /// Request offline sync from specified band.
  Future<bool> startOfflineSync(BandRole role) async {
    return getConnection(role).startOfflineSync();
  }

  /// Erase offline SD storage on specified band.
  Future<bool> clearOfflineStorage(BandRole role) async {
    return getConnection(role).clearOfflineStorage();
  }

  /// Release all resources.
  Future<void> dispose() async {
    await wrist.dispose();
    await ankle.dispose();
  }
}