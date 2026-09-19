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
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  final _sensorController = StreamController<ImuSample>.broadcast();
  final _stateController = StreamController<BandConnectionState>.broadcast();

  // Connection health tracking
  DateTime? _lastPacketTime;
  int _packetCount = 0;

  BandConnection({required this.role});

  /// Stream of parsed IMU samples from this band.
  Stream<ImuSample> get sensorStream => _sensorController.stream;

  /// Stream of connection state changes for this band.
  Stream<BandConnectionState> get stateStream => _stateController.stream;

  /// Current connection state (synchronous access).
  BandConnectionState get currentState => _state;

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

    await FlutterBluePlus.startScan(timeout: BleConstants.scanTimeout);

    if (_state == BandConnectionState.scanning) {
      _updateState(BandConnectionState.disconnected);
    }
  }

  /// Stop scanning for this band.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    if (_state == BandConnectionState.scanning) {
      _updateState(BandConnectionState.disconnected);
    }
  }

  /// Connect to a specific device (used when user manually assigns).
  Future<void> connectToDevice(BluetoothDevice device) async {
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
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

    for (final service in services) {
      if (service.uuid.toString().toLowerCase() ==
          BleConstants.serviceUuid.toLowerCase()) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              BleConstants.characteristicUuid.toLowerCase()) {
            await char.setNotifyValue(true);
            _notifySubscription = char.lastValueStream.listen(_onDataReceived);
            device.cancelWhenDisconnected(_notifySubscription!);
            return;
          }
        }
      }
    }

    // Fallback: first notify characteristic
    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.properties.notify) {
          await char.setNotifyValue(true);
          _notifySubscription = char.lastValueStream.listen(_onDataReceived);
          device.cancelWhenDisconnected(_notifySubscription!);
          return;
        }
      }
    }
  }

  void _onDataReceived(List<int> value) {
    if (value.isEmpty) return;
    try {
      final csv = utf8.decode(value).trim();
      if (csv.isEmpty) return;

      // Use a single timestamp for all lines in this packet
      final packetTimestamp = DateTime.now();

      final lines = csv.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          final sample = ImuSample.tryParseCsv(
            csv: trimmed,
            bandRole: role,
            deviceId: _device?.remoteId.str ?? '',
            deviceName: _device?.platformName ?? 'Unknown',
            timestamp: packetTimestamp,
          );
          if (sample != null) {
            _sensorController.add(sample);
          }
        }
      }

      // Update connection health metrics
      _lastPacketTime = packetTimestamp;
      _packetCount++;
    } catch (_) {
      // Silently skip malformed packets
    }
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    await _device?.disconnect();
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _device = null;
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _lastPacketTime = null;
    _packetCount = 0;
    _updateState(BandConnectionState.disconnected);
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

  /// Release all resources.
  Future<void> dispose() async {
    await wrist.dispose();
    await ankle.dispose();
  }
}