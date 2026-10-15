import 'package:flutter/material.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/theme/app_colors.dart';
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

    final hasTitle = title != null && title!.isNotEmpty;
    final hasWrist = wristState != null;
    final hasAnkle = ankleState != null;

    if (!hasWrist && !hasAnkle) {
      return _buildEmptyState(context, brightness);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row (only if explicit title provided)
        if (hasTitle || onManageTap != null) ...[
          Row(
            children: [
              if (hasTitle)
                Text(
                  title!,
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
          const SizedBox(height: AppSpacing.sm),
        ],
        // Side-by-side compact split row when both are present
        if (hasWrist && hasAnkle)
          _buildCompactSplitRow(context, brightness)
        else ...[
          if (hasWrist)
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
          if (hasAnkle)
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

  Widget _buildCompactSplitRow(BuildContext context, Brightness brightness) {
    return Row(
      children: [
        Expanded(
          child: _buildSplitChip(
            context,
            brightness,
            role: BandRole.wrist,
            state: wristState ?? BandConnectionState.disconnected,
            label: 'Wrist',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildSplitChip(
            context,
            brightness,
            role: BandRole.ankle,
            state: ankleState ?? BandConnectionState.disconnected,
            label: 'Ankle',
          ),
        ),
      ],
    );
  }

  Widget _buildSplitChip(
    BuildContext context,
    Brightness brightness, {
    required BandRole role,
    required BandConnectionState state,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isLight = brightness == Brightness.light;
    final isConnected = state == BandConnectionState.connected;
    final roleColor = role.color;

    return InkWell(
      onTap: onManageTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.borderColor(brightness),
            width: 2.0,
          ),
          boxShadow: AppShadows.hardSm(brightness),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: isLight ? 0.15 : 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(role.icon, size: 18, color: roleColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMediumFor(brightness).copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: -0.2,
                  color: isLight ? const Color(0xFF18181B) : Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StatusPill(
              variant: isConnected ? StatusPillVariant.connected : StatusPillVariant.disconnected,
              text: isConnected ? 'Connected' : 'Offline',
              showIcon: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Brightness brightness) {
    final theme = Theme.of(context);
    final isLight = brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : theme.colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hardSm(brightness),
      ),
      child: Column(
        children: [
          Icon(
            Icons.sensors_off,
            size: AppSpacing.iconSizeXLarge,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No bands connected',
            style: AppTypography.bodyMediumFor(brightness).copyWith(
              fontWeight: FontWeight.w700,
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

    final isConnected = state == BandConnectionState.connected;

    // Determine status pill variant
    final pillVariant = switch (state) {
      BandConnectionState.connected => StatusPillVariant.connected,
      BandConnectionState.connecting => StatusPillVariant.connecting,
      BandConnectionState.scanning => StatusPillVariant.connecting,
      BandConnectionState.disconnected => StatusPillVariant.disconnected,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : theme.colorScheme.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: isConnected ? roleColor : AppColors.borderColor(brightness),
          width: 2.0,
        ),
        boxShadow: AppShadows.hardSm(brightness),
      ),
      child: Row(
        children: [
          // Left Glyph
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: roleColor.withValues(alpha: isLight ? 0.15 : 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(roleIcon, size: 22, color: roleColor),
          ),
          const SizedBox(width: AppSpacing.md),
          // Device Name & Status (no duplicated hardware strings)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$roleDisplayName Band',
                  style: AppTypography.h3For(brightness).copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isConnected
                      ? (signal ?? (deviceName != null ? 'Connected · $deviceName' : 'Signal: Good'))
                      : 'Offline',
                  style: AppTypography.bodySmallFor(brightness).copyWith(
                    color: isConnected
                        ? (isLight ? const Color(0xFF2E7D32) : const Color(0xFF81C784))
                        : (isLight ? const Color(0xFF757575) : Colors.white60),
                    fontWeight: isConnected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Center/Right: Single Status Badge
          StatusPill(variant: pillVariant),
        ],
      ),
    );
  }
}