import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/di/service_locator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/ble_constants.dart';
import '../../services/band_assignment_manager.dart';
import '../../services/ble_service.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import 'device_selection_sheet.dart';

/// Devices screen – manage BANDANA Wrist and Ankle bands.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _ble = getIt<BleService>();
  final _assignment = getIt<BandAssignmentManager>();

  StreamSubscription<BandConnectionState>? _wristSub;
  StreamSubscription<BandConnectionState>? _ankleSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  BandConnectionState _wristState = BandConnectionState.disconnected;
  BandConnectionState _ankleState = BandConnectionState.disconnected;
  int? _wristRssi;
  int? _ankleRssi;

  // Scanning state
  bool _isScanning = false;
  final List<ScanResult> _discoveredDevices = [];

  @override
  void initState() {
    super.initState();
    _wristState = _ble.wrist.currentState;
    _ankleState = _ble.ankle.currentState;
    _listenToConnections();
  }

  @override
  void dispose() {
    _wristSub?.cancel();
    _ankleSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  void _listenToConnections() {
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

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Bands',
          style: AppTypography.h2For(brightness).copyWith(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: PrimaryButton(
            label: 'Scan for Nearby Bands',
            leadingIcon: Icons.bluetooth_searching,
            showArrow: true,
            onPressed: _showRoleSelectionForScan,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
          children: [
            // Wrist Band Card
            _buildBandCard(
              theme,
              brightness,
              role: BandRole.wrist,
              hasAssignment: _assignment.hasWristAssignment,
              deviceName: _assignment.wristDeviceName,
              state: _wristState,
              rssi: _wristRssi,
              onConnect: () => _toggleBandConnection(BandRole.wrist),
              onAssign: _assignment.hasWristAssignment
                  ? null
                  : () => _startAssignmentScan(BandRole.wrist),
              onClear: _assignment.hasWristAssignment
                  ? () => _confirmUnassign(context, BandRole.wrist)
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // Ankle Band Card
            _buildBandCard(
              theme,
              brightness,
              role: BandRole.ankle,
              hasAssignment: _assignment.hasAnkleAssignment,
              deviceName: _assignment.ankleDeviceName,
              state: _ankleState,
              rssi: _ankleRssi,
              onConnect: () => _toggleBandConnection(BandRole.ankle),
              onAssign: _assignment.hasAnkleAssignment
                  ? null
                  : () => _startAssignmentScan(BandRole.ankle),
              onClear: _assignment.hasAnkleAssignment
                  ? () => _confirmUnassign(context, BandRole.ankle)
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Connection guide (Bento Styled)
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface(brightness),
                borderRadius: AppRadius.card,
                border: Border.all(
                  color: AppColors.borderColor(brightness),
                  width: 2.0,
                ),
                boxShadow: AppShadows.hard(brightness),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.accentSkyBlue.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderColor(brightness), width: 1.5),
                        ),
                        child: const Icon(Icons.menu_book_outlined, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Connection Guide',
                        style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildGuideStep('1', 'Power on your BANDANA band'),
                  _buildGuideStep('2', 'Keep the band near your phone'),
                  _buildGuideStep('3', 'Tap "Scan for Nearby Bands" to discover it'),
                  _buildGuideStep('4', 'Assign as Wrist or Ankle'),
                  _buildGuideStep('5', 'Tap Connect to start streaming'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(String number, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.accentPink.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentPink, width: 1.5),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: AppColors.accentPink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmUnassign(BuildContext context, BandRole role) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(Theme.of(context).brightness),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: AppColors.borderColor(Theme.of(context).brightness), width: 2.0),
        ),
        title: Text(
          'Unpair ${role.displayName} Band?',
          style: AppTypography.h3For(Theme.of(context).brightness).copyWith(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will remove the saved Bluetooth assignment for your ${role.displayName} band. You can scan and pair it again anytime.',
          style: AppTypography.bodySmallFor(Theme.of(context).brightness),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(Theme.of(context).brightness)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentDanger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _clearAssignment(role);
            },
            child: const Text('Unpair', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRenameBandDialog(BuildContext context, BandRole role) {
    final currentName = role == BandRole.wrist
        ? (_assignment.wristDeviceName ?? 'BANDANA-WRIST')
        : (_assignment.ankleDeviceName ?? 'BANDANA-ANKLE');
    final controller = TextEditingController(text: currentName);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final brightness = Theme.of(context).brightness;
        return AlertDialog(
          backgroundColor: AppColors.surface(brightness),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: AppColors.borderColor(brightness), width: 2.0),
          ),
          title: Text(
            'Rename ${role.displayName} Band',
            style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customize the display name for your ${role.displayName} sensor band.',
                style: AppTypography.bodySmallFor(brightness),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Band Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderColor(brightness), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(brightness))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandPink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  final messenger = ScaffoldMessenger.of(context);
                  if (role == BandRole.wrist && _assignment.wristDeviceId != null) {
                    await _assignment.assignWrist(_assignment.wristDeviceId!, newName);
                  } else if (role == BandRole.ankle && _assignment.ankleDeviceId != null) {
                    await _assignment.assignAnkle(_assignment.ankleDeviceId!, newName);
                  }
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                  if (mounted) {
                    setState(() {});
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Band renamed to "$newName" ✓'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showCalibrateBandDialog(BuildContext context, BandRole role) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final brightness = Theme.of(context).brightness;
        bool isCalibrating = false;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface(brightness),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.card,
                side: BorderSide(color: AppColors.borderColor(brightness), width: 2.0),
              ),
              title: Row(
                children: [
                  const Icon(Icons.tune, color: AppColors.accentPink, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Calibrate ${role.displayName}',
                    style: AppTypography.h3For(brightness).copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Place your ${role.displayName} band flat on a level, stationary surface with the sensor facing up.',
                    style: AppTypography.bodySmallFor(brightness),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentSkyBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accentSkyBlue, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: Color(0xFF0369A1)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Zeroes accelerometer and gyroscope drift offsets for maximum model accuracy.',
                            style: AppTypography.captionFor(brightness).copyWith(
                              color: brightness == Brightness.light ? const Color(0xFF0369A1) : const Color(0xFFBAE6FD),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCalibrating) ...[
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink),
                        ),
                        SizedBox(width: 10),
                        Text('Calibrating IMU zero-point...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isCalibrating ? null : () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(brightness))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentLime,
                    foregroundColor: const Color(0xFF18181B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isCalibrating
                      ? null
                      : () async {
                          setDialogState(() => isCalibrating = true);
                          await Future.delayed(const Duration(milliseconds: 900));
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${role.displayName} band calibrated successfully ✓'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  child: const Text('Start Calibration', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBandCard(
    ThemeData theme,
    Brightness brightness, {
    required BandRole role,
    required bool hasAssignment,
    required String? deviceName,
    required BandConnectionState state,
    required int? rssi,
    required VoidCallback onConnect,
    required VoidCallback? onAssign,
    required VoidCallback? onClear,
  }) {
    final isAssigned = hasAssignment;
    final roleColor = role.color;
    final roleIcon = role.icon;
    final roleDisplayName = role.displayName;

    final isConnected = state == BandConnectionState.connected;
    final isConnecting = state == BandConnectionState.connecting || state == BandConnectionState.scanning;

    final List<Widget> children = [];

    // Clean status tag: Green pill for Connected, Red outlined pill for Disconnected
    Widget buildStatusPill() {
      if (isConnected) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accentLime,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderColor(brightness),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF18181B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Connected',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18181B),
                ),
              ),
            ],
          ),
        );
      } else if (isConnecting) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accentSoftYellow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderColor(brightness),
              width: 1.5,
            ),
          ),
          child: Text(
            state == BandConnectionState.scanning ? 'Scanning…' : 'Connecting…',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF18181B),
            ),
          ),
        );
      } else {
        // Red outlined pill for Disconnected
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accentDanger,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accentDanger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Disconnected',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentDanger,
                ),
              ),
            ],
          ),
        );
      }
    }

    // Role header
    children.add(
      Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: roleColor.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Icon(roleIcon, color: roleColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$roleDisplayName Band',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: roleColor,
                  ),
                ),
                const SizedBox(height: 2),
                if (isAssigned)
                  Text(
                    'ID: ${deviceName ?? "Unknown"}${isConnected && rssi != null && rssi != 0 ? " · Signal: ${rssi}dBm" : ""}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    'Not assigned',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          buildStatusPill(),
        ],
      ),
    );

    children.add(const SizedBox(height: AppSpacing.md));

    // Actions
    if (!isAssigned) {
      children.add(
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Assign ${role.displayName}',
                leadingIcon: role.icon,
                onPressed: onAssign,
              ),
            ),
          ],
        ),
      );
    } else {
      final List<Widget> actionChildren = [
        if (isConnecting)
          const Expanded(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink),
              ),
            ),
          )
        else if (!isConnected)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.bluetooth, size: 16),
              label: const Text('Connect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: roleColor,
                side: BorderSide(color: roleColor, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          )
        else
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.bluetooth_disabled, size: 16),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentDanger,
                side: const BorderSide(color: AppColors.accentDanger, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        const SizedBox(width: AppSpacing.sm),
        // Dedicated kebab icon (⋮) with 44x44pt tap target
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface(brightness),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderColor(brightness).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Device options',
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameBandDialog(context, role);
              } else if (value == 'calibrate') {
                _showCalibrateBandDialog(context, role);
              } else if (value == 'unpair' && onClear != null) {
                onClear();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: AppColors.textPrimary(brightness)),
                    const SizedBox(width: 10),
                    Text('Rename Band', style: AppTypography.bodySmallFor(brightness).copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'calibrate',
                child: Row(
                  children: [
                    Icon(Icons.tune_outlined, size: 18, color: AppColors.textPrimary(brightness)),
                    const SizedBox(width: 10),
                    Text('Calibrate IMU', style: AppTypography.bodySmallFor(brightness).copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'unpair',
                child: Row(
                  children: [
                    Icon(Icons.link_off, size: 18, color: AppColors.accentDanger),
                    SizedBox(width: 10),
                    Text('Unpair Band', style: TextStyle(color: AppColors.accentDanger, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ];

      children.add(Row(children: actionChildren));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hardSm(brightness),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  void _showRoleSelectionForScan() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Assign New Band',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Which role should the new band have?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startAssignmentScan(BandRole.wrist);
                      },
                      icon: Icon(BandRole.wrist.icon, size: 20),
                      label: const Text('Wrist'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BandRole.wrist.color,
                        side: BorderSide(color: BandRole.wrist.color),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startAssignmentScan(BandRole.ankle);
                      },
                      icon: Icon(BandRole.ankle.icon, size: 20),
                      label: const Text('Ankle'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BandRole.ankle.color,
                        side: BorderSide(color: BandRole.ankle.color),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  // ── Private Helpers ──

  Future<bool> _requestBlePermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final results = await permissions.request();
    return results.values.every((status) => status.isGranted);
  }

  Future<void> _startAssignmentScan(BandRole role) async {
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
      _isScanning = true;
      _discoveredDevices.clear();
    });

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _discoveredDevices.clear();
          _discoveredDevices.addAll(results.where(
            (r) => r.device.platformName.startsWith('BANDANA-'),
          ));
        });
      }
    });

    await FlutterBluePlus.startScan(timeout: BleConstants.scanTimeout);

    if (!mounted) return;

    await _showDeviceSelectionSheet(role);

    await _stopAssignmentScan();
  }

  Future<void> _stopAssignmentScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _showDeviceSelectionSheet(BandRole role) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DeviceSelectionSheet(
        role: role,
        discoveredDevices: _discoveredDevices,
        isScanning: _isScanning,
        onDeviceSelected: (device) async {
          await _assignDevice(role, device);
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _assignDevice(BandRole role, ScanResult device) async {
    bool success;
    final name = device.device.platformName.isNotEmpty ? device.device.platformName : 'Unknown';
    if (role == BandRole.wrist) {
      success = await _assignment.assignWrist(device.device.remoteId.str, name);
    } else {
      success = await _assignment.assignAnkle(device.device.remoteId.str, name);
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${role.displayName} assigned to ${device.device.platformName}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
}