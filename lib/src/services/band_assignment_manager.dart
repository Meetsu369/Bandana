import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/ble_constants.dart';

/// Manages persistent assignment of BLE devices to body roles (wrist/ankle).
class BandAssignmentManager {
  static const _wristDeviceIdKey = 'bandana_wrist_device_id';
  static const _wristDeviceNameKey = 'bandana_wrist_device_name';
  static const _ankleDeviceIdKey = 'bandana_ankle_device_id';
  static const _ankleDeviceNameKey = 'bandana_ankle_device_name';

  final SharedPreferences _prefs;

  String? _wristDeviceId;
  String? _wristDeviceName;
  String? _ankleDeviceId;
  String? _ankleDeviceName;

  BandAssignmentManager._(this._prefs);

  static Future<BandAssignmentManager> create(SharedPreferences prefs) async {
    final manager = BandAssignmentManager._(prefs);
    await manager._load();
    return manager;
  }

  Future<void> _load() async {
    _wristDeviceId = _prefs.getString(_wristDeviceIdKey);
    _wristDeviceName = _prefs.getString(_wristDeviceNameKey);
    _ankleDeviceId = _prefs.getString(_ankleDeviceIdKey);
    _ankleDeviceName = _prefs.getString(_ankleDeviceNameKey);
  }

  /// Get the assigned wrist device ID.
  String? get wristDeviceId => _wristDeviceId;

  /// Get the assigned wrist device name.
  String? get wristDeviceName => _wristDeviceName;

  /// Get the assigned ankle device ID.
  String? get ankleDeviceId => _ankleDeviceId;

  /// Get the assigned ankle device name.
  String? get ankleDeviceName => _ankleDeviceName;

  /// Check if a device is assigned to a role.
  bool isAssigned(String deviceId) =>
      _wristDeviceId == deviceId || _ankleDeviceId == deviceId;

  /// Check if wrist role is assigned.
  bool get hasWristAssignment => _wristDeviceId != null;

  /// Check if ankle role is assigned.
  bool get hasAnkleAssignment => _ankleDeviceId != null;

  /// Assign a device to the wrist role.
  ///
  /// Returns `false` if the device is already assigned to ankle.
  Future<bool> assignWrist(String deviceId, String deviceName) async {
    if (_ankleDeviceId == deviceId) return false;
    await _prefs.setString(_wristDeviceIdKey, deviceId);
    await _prefs.setString(_wristDeviceNameKey, deviceName);
    _wristDeviceId = deviceId;
    _wristDeviceName = deviceName;
    return true;
  }

  /// Assign a device to the ankle role.
  ///
  /// Returns `false` if the device is already assigned to wrist.
  Future<bool> assignAnkle(String deviceId, String deviceName) async {
    if (_wristDeviceId == deviceId) return false;
    await _prefs.setString(_ankleDeviceIdKey, deviceId);
    await _prefs.setString(_ankleDeviceNameKey, deviceName);
    _ankleDeviceId = deviceId;
    _ankleDeviceName = deviceName;
    return true;
  }

  /// Remove wrist assignment.
  Future<void> clearWrist() async {
    await _prefs.remove(_wristDeviceIdKey);
    await _prefs.remove(_wristDeviceNameKey);
    _wristDeviceId = null;
    _wristDeviceName = null;
  }

  /// Remove ankle assignment.
  Future<void> clearAnkle() async {
    await _prefs.remove(_ankleDeviceIdKey);
    await _prefs.remove(_ankleDeviceNameKey);
    _ankleDeviceId = null;
    _ankleDeviceName = null;
  }

  /// Clear all assignments.
  Future<void> clearAll() async {
    await clearWrist();
    await clearAnkle();
  }

  /// Get the role for a given device ID, if assigned.
  BandRole? getRoleForDevice(String deviceId) {
    if (_wristDeviceId == deviceId) return BandRole.wrist;
    if (_ankleDeviceId == deviceId) return BandRole.ankle;
    return null;
  }

  /// Get all assigned devices as a map.
  Map<BandRole, ({String deviceId, String deviceName})> getAllAssignments() {
    final map = <BandRole, ({String deviceId, String deviceName})>{};
    if (_wristDeviceId != null && _wristDeviceName != null) {
      map[BandRole.wrist] = (deviceId: _wristDeviceId!, deviceName: _wristDeviceName!);
    }
    if (_ankleDeviceId != null && _ankleDeviceName != null) {
      map[BandRole.ankle] = (deviceId: _ankleDeviceId!, deviceName: _ankleDeviceName!);
    }
    return map;
  }
}