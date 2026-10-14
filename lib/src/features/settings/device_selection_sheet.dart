import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/constants/ble_constants.dart';

/// Bottom sheet for selecting a BLE device during assignment.
class DeviceSelectionSheet extends StatefulWidget {
  final BandRole role;
  final List<ScanResult> discoveredDevices;
  final bool isScanning;
  final Future<void> Function(ScanResult device) onDeviceSelected;

  const DeviceSelectionSheet({
    super.key,
    required this.role,
    required this.discoveredDevices,
    required this.isScanning,
    required this.onDeviceSelected,
  });

  @override
  State<DeviceSelectionSheet> createState() => _DeviceSelectionSheetState();
}

class _DeviceSelectionSheetState extends State<DeviceSelectionSheet> {
  late List<ScanResult> _devices;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _devices = widget.discoveredDevices;
    _isScanning = widget.isScanning;
  }

  @override
  void didUpdateWidget(covariant DeviceSelectionSheet oldWidget) {
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
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 16, endIndent: 16),
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
                              device.device.platformName.isNotEmpty ? device.device.platformName : 'Unknown',
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