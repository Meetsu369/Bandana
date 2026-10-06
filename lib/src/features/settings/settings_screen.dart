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
import '../../shared/widgets/section_header.dart';
import '../settings/devices_screen.dart';

/// Settings screen – data management, app preferences, about.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWrist = _wristState == BandConnectionState.connected;
    final hasAnkle = _ankleState == BandConnectionState.connected;
    final bothConnected = hasWrist && hasAnkle;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [
          // ── Devices Section ──
          SectionHeader(
            title: 'Devices',
            subtitle: 'Manage your BANDANA bands',
            leadingIcon: Icons.bluetooth_connected,
            leadingIconColor: theme.colorScheme.primary,
            action: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DevicesScreen()),
                );
              },
              child: Text(
                'My Bands →',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                children: [
                  _buildBandSummaryRow(
                    theme,
                    role: BandRole.wrist,
                    deviceName: _assignment.wristDeviceName,
                    state: _wristState,
                    rssi: _wristRssi,
                  ),
                  const Divider(height: 24),
                  _buildBandSummaryRow(
                    theme,
                    role: BandRole.ankle,
                    deviceName: _assignment.ankleDeviceName,
                    state: _ankleState,
                    rssi: _ankleRssi,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLg),

          // ── Data Section ──
          SectionHeader(
            title: 'Data',
            subtitle: 'Export and manage your recordings',
            leadingIcon: Icons.storage_outlined,
            leadingIconColor: theme.colorScheme.primary,
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
                    value: _ml.isCombinedTrained
                        ? 'Dual-band trained (60 features)'
                        : _ml.isTrained
                            ? 'Single-band trained (30 features)'
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
          SectionHeader(
            title: 'About',
            subtitle: 'App information and version',
            leadingIcon: Icons.info_outline,
            leadingIconColor: theme.colorScheme.primary,
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
                  const Divider(height: 24),
                  _buildSettingsRow(
                    theme,
                    icon: Icons.developer_mode,
                    label: 'Firmware Baseline',
                    value: '71119af (40 Hz, dual-band)',
                  ),
                  const Divider(height: 24),
                  _buildSettingsRow(
                    theme,
                    icon: Icons.bluetooth,
                    label: 'BLE Service UUID',
                    value: BleConstants.serviceUuid,
                  ),
                  const Divider(height: 24),
                  _buildSettingsRow(
                    theme,
                    icon: Icons.bluetooth,
                    label: 'BLE Characteristic UUID',
                    value: BleConstants.characteristicUuid,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandSummaryRow(
    ThemeData theme, {
    required BandRole role,
    required String? deviceName,
    required BandConnectionState state,
    required int? rssi,
  }) {
    final isAssigned = deviceName != null;
    final isConnected = state == BandConnectionState.connected;

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
            color: isConnected ? Colors.green : theme.colorScheme.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        // RSSI if connected
        if (isConnected && rssi != null && rssi != 0)
          Text(
            '$rssi dBm',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
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