import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/ble_constants.dart';
import '../../services/band_assignment_manager.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/ml_service.dart';

/// Settings screen – device info, BLE controls, data management.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ble = getIt<BleService>();
  final _db = getIt<DatabaseService>();
  final _ml = getIt<MlService>();
  final _assignment = getIt<BandAssignmentManager>();

  StreamSubscription<BandConnectionState>? _wristSub;
  StreamSubscription<BandConnectionState>? _ankleSub;
  BandConnectionState _wristState = BandConnectionState.disconnected;
  BandConnectionState _ankleState = BandConnectionState.disconnected;
  int? _wristRssi;
  int? _ankleRssi;
  bool _isClearing = false;

  // Scanning for device assignment
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanningForAssignment = false;
  BandRole? _assigningRole;
  final List<ScanResult> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _wristState = _ble.wrist.currentState;
    _ankleState = _ble.ankle.currentState;

    _wristSub = _ble.wrist.stateStream.listen((state) {
      if (mounted) setState(() => _wristState = state);
      if (state == BandConnectionState.connected) _refreshWristRssi();
    });
    _ankleSub = _ble.ankle.stateStream.listen((state) {
      if (mounted) setState(() => _ankleState = state);
      if (state == BandConnectionState.connected) _refreshAnkleRssi();
    });

    if (_wristState == BandConnectionState.connected) _refreshWristRssi();
    if (_ankleState == BandConnectionState.connected) _refreshAnkleRssi();
  }

  @override
  void dispose() {
    _wristSub?.cancel();
    _ankleSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshWristRssi() async {
    final rssi = await _ble.wrist.rssi;
    if (mounted) setState(() => _wristRssi = rssi);
  }

  Future<void> _refreshAnkleRssi() async {
    final rssi = await _ble.ankle.rssi;
    if (mounted) setState(() => _ankleRssi = rssi);
  }

  Future<void> _toggleBandConnection(BandRole role) async {
    final conn = _ble.getConnection(role);
    if (conn.currentState == BandConnectionState.connected) {
      await conn.disconnect();
    } else if (conn.currentState == BandConnectionState.disconnected) {
      await conn.startScan();
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will delete all recorded sessions, training data, '
          'and reset the ML model. This action cannot be undone.',
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
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearing = true);
    await _db.clearAll();
    _ml.reset();
    setState(() => _isClearing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data cleared.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Device Assignment Scanning ──

  Future<bool> _requestBlePermissions() async {
    // Android 12+ needs BLUETOOTH_SCAN, BLUETOOTH_CONNECT
    // Android 11 and below needs ACCESS_FINE_LOCATION
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final results = await permissions.request();
    return results.values.every((status) => status.isGranted);
  }

  Future<void> _startAssignmentScan(BandRole role) async {
    if (_isScanningForAssignment) return;

    // Request permissions first
    final granted = await _requestBlePermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth and Location permissions are required for scanning.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _isScanningForAssignment = true;
      _assigningRole = role;
      _discoveredDevices.clear();
    });

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        // Debug: log all found devices
        for (final r in results) {
          debugPrint('BLE: Found device: ${r.device.platformName} (${r.device.remoteId.str}), RSSI: ${r.rssi}');
        }
        
        setState(() {
          _discoveredDevices.clear();
          _discoveredDevices.addAll(results.where(
            (r) => r.device.platformName?.startsWith('BANDANA-') ?? false,
          ));
          debugPrint('BLE: Filtered BANDANA-* devices: ${_discoveredDevices.length}');
        });
      }
    });

    await FlutterBluePlus.startScan(timeout: BleConstants.scanTimeout);

    // Debug: print scan status
    debugPrint('BLE: Scan started for ${role.displayName}, timeout: ${BleConstants.scanTimeout}');

    if (!mounted) return;

    // Show device selection bottom sheet
    await _showDeviceSelectionSheet(role);

    // Scan stops automatically when sheet closes or timeout
    await _stopAssignmentScan();
  }

  Future<void> _stopAssignmentScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (mounted) setState(() => _isScanningForAssignment = false);
  }

  Future<void> _showDeviceSelectionSheet(BandRole role) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            _stopAssignmentScan();
          }
        },
        child: _DeviceSelectionSheet(
          role: role,
          discoveredDevices: _discoveredDevices,
          isScanning: _isScanningForAssignment,
          onDeviceSelected: (device) async {
            await _assignDevice(role, device);
            if (context.mounted) Navigator.pop(context);
          },
          onScanComplete: () {
            // Called when scan timeout completes
          },
        ),
      ),
    );
  }

  Future<void> _assignDevice(BandRole role, ScanResult device) async {
    bool success;
    if (role == BandRole.wrist) {
      success = await _assignment.assignWrist(device.device.remoteId.str, device.device.platformName ?? 'Unknown');
    } else {
      success = await _assignment.assignAnkle(device.device.remoteId.str, device.device.platformName ?? 'Unknown');
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${role.displayName} assigned to ${device.device.platformName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {}); // Refresh assignment display
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device already assigned to the other band.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearAssignment(BandRole role) async {
    if (role == BandRole.wrist) {
      await _assignment.clearWrist();
    } else {
      await _assignment.clearAnkle();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Band Assignment Section ──
          Text(
            'Band Assignment',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                children: [
                  _buildBandAssignmentRow(
                    theme,
                    role: BandRole.wrist,
                    deviceName: _assignment.wristDeviceName,
                    state: _wristState,
                    rssi: _wristRssi,
                    onTapAssign: _assignment.hasWristAssignment
                        ? null
                        : () => _startAssignmentScan(BandRole.wrist),
                    onTapClear: _assignment.hasWristAssignment
                        ? () => _clearAssignment(BandRole.wrist)
                        : null,
                    onTapConnect: () => _toggleBandConnection(BandRole.wrist),
                  ),
                  const Divider(height: 24),
                  _buildBandAssignmentRow(
                    theme,
                    role: BandRole.ankle,
                    deviceName: _assignment.ankleDeviceName,
                    state: _ankleState,
                    rssi: _ankleRssi,
                    onTapAssign: _assignment.hasAnkleAssignment
                        ? null
                        : () => _startAssignmentScan(BandRole.ankle),
                    onTapClear: _assignment.hasAnkleAssignment
                        ? () => _clearAssignment(BandRole.ankle)
                        : null,
                    onTapConnect: () => _toggleBandConnection(BandRole.ankle),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── BLE Device Section (Legacy single-band) ──
          Text(
            'Legacy Single-Band Mode',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                children: [
                  _buildSettingsRow(
                    theme,
                    icon: Icons.bluetooth,
                    label: 'Device Name',
                    value: _ble.wrist.deviceName ?? 'BANDANA_HAR',
                  ),
                  const Divider(height: 24),
                  _buildSettingsRow(
                    theme,
                    icon: Icons.signal_cellular_alt,
                    label: 'Wrist Status',
                    valueWidget: _buildStateChip(theme, _wristState),
                  ),
                  if (_wristRssi != null &&
                      _wristState == BandConnectionState.connected) ...[
                    const Divider(height: 24),
                    _buildSettingsRow(
                      theme,
                      icon: Icons.signal_wifi_4_bar,
                      label: 'Wrist RSSI',
                      value: '$_wristRssi dBm',
                    ),
                  ],
                  const Divider(height: 24),
                  _buildSettingsRow(
                    theme,
                    icon: Icons.signal_cellular_alt,
                    label: 'Ankle Status',
                    valueWidget: _buildStateChip(theme, _ankleState),
                  ),
                  if (_ankleRssi != null &&
                      _ankleState == BandConnectionState.connected) ...[
                    const Divider(height: 24),
                    _buildSettingsRow(
                      theme,
                      icon: Icons.signal_wifi_4_bar,
                      label: 'Ankle RSSI',
                      value: '$_ankleRssi dBm',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Data Section ──
          Text(
            'Data Management',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                children: [
                  _buildSettingsRow(
                    theme,
                    icon: Icons.model_training,
                    label: 'ML Model',
                    value: _ml.isTrained
                        ? 'Trained (${_ml.trainedClassCount} classes)'
                        : 'Not trained',
                  ),
                  const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: _isClearing
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _clearAllData,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Clear All Data'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── About Section ──
          Text(
            'About',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                children: [
                  _buildSettingsRow(
                    theme,
                    icon: Icons.info_outline,
                    label: 'App Version',
                    value: '1.0.0',
                  ),
                  const Divider(height: 24),
                  _buildSettingsRow(
                    theme,
                    icon: Icons.memory,
                    label: 'ML Engine',
                    value: 'KNN (ml_algo)',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandAssignmentRow(
    ThemeData theme, {
    required BandRole role,
    required String? deviceName,
    required BandConnectionState state,
    required int? rssi,
    required VoidCallback? onTapAssign,
    required VoidCallback? onTapClear,
    required VoidCallback onTapConnect,
  }) {
    final isAssigned = deviceName != null;
    final stateColor = switch (state) {
      BandConnectionState.connected => Colors.green,
      BandConnectionState.scanning => Colors.blue,
      BandConnectionState.connecting => Colors.orange,
      BandConnectionState.disconnected => Colors.red,
    };

    return Row(
      children: [
        // Role indicator
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: role.color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(role.icon, color: role.color, size: 20),
        ),
        const SizedBox(width: 12),
        // Role info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${role.displayName} Band',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isAssigned)
                Text(
                  deviceName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  'Not assigned',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // Status dot
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: stateColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        // Actions
        if (!isAssigned) ...[
          if (_isScanningForAssignment && _assigningRole == role)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton.icon(
              onPressed: onTapAssign,
              icon: Icon(role.icon, size: 16),
              label: Text('Assign ${role.displayName}'),
            ),
        ] else ...[
          if (state == BandConnectionState.disconnected)
            TextButton(
              onPressed: onTapConnect,
              child: const Text('Connect'),
            )
          else if (state == BandConnectionState.scanning ||
              state == BandConnectionState.connecting)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: onTapConnect,
              child: const Text('Disconnect'),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onTapClear,
            icon: const Icon(Icons.clear, size: 18),
            tooltip: 'Clear assignment',
          ),
        ],
      ],
    );
  }

  Widget _buildStateChip(ThemeData theme, BandConnectionState state) {
    final (color, label) = switch (state) {
      BandConnectionState.connected => (Colors.green, 'Connected'),
      BandConnectionState.scanning => (Colors.blue, 'Scanning'),
      BandConnectionState.connecting => (Colors.orange, 'Connecting'),
      BandConnectionState.disconnected => (Colors.red, 'Disconnected'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildSettingsRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        valueWidget ??
            Text(
              value ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      ],
    );
  }
}

/// Bottom sheet for selecting a BLE device during assignment.
class _DeviceSelectionSheet extends StatefulWidget {
  final BandRole role;
  final List<ScanResult> discoveredDevices;
  final bool isScanning;
  final Future<void> Function(ScanResult device) onDeviceSelected;
  final VoidCallback onScanComplete;

  const _DeviceSelectionSheet({
    required this.role,
    required this.discoveredDevices,
    required this.isScanning,
    required this.onDeviceSelected,
    required this.onScanComplete,
  });

  @override
  State<_DeviceSelectionSheet> createState() => _DeviceSelectionSheetState();
}

class _DeviceSelectionSheetState extends State<_DeviceSelectionSheet> {
  late List<ScanResult> _devices;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _devices = widget.discoveredDevices;
    _isScanning = widget.isScanning;
  }

  @override
  void didUpdateWidget(covariant _DeviceSelectionSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (mounted) {
      setState(() {
        _devices = widget.discoveredDevices;
        _isScanning = widget.isScanning;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.role.color;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.role.icon, color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assign ${widget.role.displayName} Band',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _isScanning
                                ? 'Scanning for devices...'
                                : '${_devices.length} device${_devices.length != 1 ? 's' : ''} found',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isScanning)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: color),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Device list
              Flexible(
                child: _devices.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_searching,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _isScanning
                                    ? 'Searching for BANDANA-* devices...'
                                    : 'No BANDANA-* devices found',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Make sure your ESP32 is powered on and advertising.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          final rssi = device.rssi;
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(widget.role.icon, color: color, size: 20),
                            ),
                            title: Text(
                              device.device.platformName ?? 'Unknown',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'RSSI: ${rssi}dBm  •  ${device.device.remoteId.str}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: color),
                            onTap: () => widget.onDeviceSelected(device),
                          );
                        },
                      ),
              ),
              // Close button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}