import 'package:flutter/material.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/ble_service.dart';
import '../status/status_pill.dart';

/// A card displaying the connection status for Wrist and/or Ankle bands.
///
/// Shows role, connection status, optional signal quality, and optional device name.
/// Gracefully handles unavailable information.
class BandStatusCard extends StatelessWidget {
  /// Wrist band connection state.
  final BandConnectionState? wristState;

  /// Ankle band connection state.
  final BandConnectionState? ankleState;

  /// Optional wrist device name.
  final String? wristDeviceName;

  /// Optional ankle device name.
  final String? ankleDeviceName;

  /// Optional wrist signal quality (RSSI or qualitative).
  final String? wristSignal;

  /// Optional ankle signal quality.
  final String? ankleSignal;

  /// Whether to show signal quality row.
  final bool showSignal;

  /// Whether to show device names.
  final bool showDeviceNames;

  /// Custom title for the card.
  final String? title;

  /// Callback when "Manage bands" or similar action is tapped.
  final VoidCallback? onManageTap;

  /// Label for the manage action.
  final String manageLabel;

  const BandStatusCard({
    super.key,
    this.wristState,
    this.ankleState,
    this.wristDeviceName,
    this.ankleDeviceName,
    this.wristSignal,
    this.ankleSignal,
    this.showSignal = true,
    this.showDeviceNames = true,
    this.title,
    this.onManageTap,
    this.manageLabel = 'Manage bands →',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isLight = brightness == Brightness.light;

    final effectiveTitle = title ?? 'Band Connection';
    final hasWrist = wristState != null;
    final hasAnkle = ankleState != null;

    if (!hasWrist && !hasAnkle) {
      return _buildEmptyState(context, brightness);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row
        Row(
          children: [
            Text(
              effectiveTitle,
              style: AppTypography.h3For(brightness).copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (onManageTap != null)
              TextButton(
                onPressed: onManageTap,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  manageLabel,
                  style: AppTypography.labelSmallFor(brightness).copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Band rows
        if (hasWrist) ...[
          _buildBandRow(
            context,
            brightness,
            role: BandRole.wrist,
            state: wristState!,
            deviceName: wristDeviceName,
            signal: wristSignal,
            showSignal: showSignal,
            showDeviceName: showDeviceNames,
          ),
        ],
        if (hasWrist && hasAnkle) const SizedBox(height: AppSpacing.md),
        if (hasAnkle) ...[
          _buildBandRow(
            context,
            brightness,
            role: BandRole.ankle,
            state: ankleState!,
            deviceName: ankleDeviceName,
            signal: ankleSignal,
            showSignal: showSignal,
            showDeviceName: showDeviceNames,
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, Brightness brightness) {
    final theme = Theme.of(context);
    final isLight = brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: isLight ? const Color(0xFF111111) : const Color(0xFFF5F3ED),
          width: 1.5,
        ),
        boxShadow: AppShadows.surface,
      ),
      child: Column(
        children: [
          Icon(
            Icons.sensors_off,
            size: AppSpacing.iconSizeXLarge,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No bands connected',
            style: AppTypography.bodyMediumFor(brightness).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Connect your Wrist and Ankle bands to get started',
            style: AppTypography.captionFor(brightness),
            textAlign: TextAlign.center,
          ),
          if (onManageTap != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onManageTap,
              child: Text(manageLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBandRow(
    BuildContext context,
    Brightness brightness, {
    required BandRole role,
    required BandConnectionState state,
    String? deviceName,
    String? signal,
    required bool showSignal,
    required bool showDeviceName,
  }) {
    final theme = Theme.of(context);
    final isLight = brightness == Brightness.light;

    final roleColor = role.color;
    final roleIcon = role.icon;
    final roleDisplayName = role.displayName;

    // Determine status pill variant
    final pillVariant = switch (state) {
      BandConnectionState.connected => StatusPillVariant.connected,
      BandConnectionState.connecting => StatusPillVariant.connecting,
      BandConnectionState.scanning => StatusPillVariant.connecting,
      BandConnectionState.disconnected => StatusPillVariant.disconnected,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: isLight ? 0.08 : 0.12),
        borderRadius: AppRadius.card,
        border: Border.all(color: roleColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: isLight ? 0.15 : 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(roleIcon, size: AppSpacing.iconSizeMedium, color: roleColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$roleDisplayName Band',
                style: AppTypography.h3For(brightness).copyWith(
                  color: roleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              StatusPill(variant: pillVariant),
            ],
          ),
          // Device name
          if (showDeviceName && deviceName != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  size: AppSpacing.iconSizeSmall,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    deviceName,
                    style: AppTypography.bodySmallFor(brightness),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else if (showDeviceName && deviceName == null && state == BandConnectionState.connected) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  size: AppSpacing.iconSizeSmall,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Connected (name unavailable)',
                  style: AppTypography.bodySmallFor(brightness).copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
          // Signal quality
          if (showSignal) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.signal_cellular_alt,
                  size: AppSpacing.iconSizeSmall,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  signal ?? _defaultSignalLabel(state, brightness),
                  style: AppTypography.bodySmallFor(brightness),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _defaultSignalLabel(BandConnectionState state, Brightness brightness) {
    return switch (state) {
      BandConnectionState.connected => 'Signal: Good',
      BandConnectionState.connecting => 'Connecting...',
      BandConnectionState.scanning => 'Scanning...',
      BandConnectionState.disconnected => 'Disconnected',
    };
  }
}