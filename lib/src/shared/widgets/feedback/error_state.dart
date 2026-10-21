import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A friendly but explicit error state with retry/action.
///
/// Shows title, description, and optional retry/primary action buttons.
class ErrorState extends StatelessWidget {
  /// The error title (e.g., "Couldn't connect").
  final String title;

  /// The error description (e.g., "Check that the band is powered on and nearby.").
  final String description;

  /// Optional primary action (e.g., "Try again").
  final Widget? primaryAction;

  /// Optional secondary action (e.g., "Open settings").
  final Widget? secondaryAction;

  /// Optional icon (defaults to error outline).
  final IconData? icon;

  /// Icon color (defaults to danger color).
  final Color? iconColor;

  /// Icon size.
  final double iconSize;

  /// Whether to show in a card container.
  final bool inCard;

  /// Custom background color for card.
  final Color? cardBackgroundColor;

  /// Title style.
  final TextStyle? titleStyle;

  /// Description style.
  final TextStyle? descriptionStyle;

  /// Spacing between elements.
  final double spacing;

  /// Cross-axis alignment.
  final CrossAxisAlignment alignment;

  const ErrorState({
    super.key,
    required this.title,
    required this.description,
    this.primaryAction,
    this.secondaryAction,
    this.icon,
    this.iconColor,
    this.iconSize = 48,
    this.inCard = true,
    this.cardBackgroundColor,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  });

  /// Creates an error state for BLE connection failures.
  const ErrorState.connectionFailed({
    super.key,
    required String deviceName,
    this.primaryAction,
    this.secondaryAction,
    this.icon,
    this.iconColor,
    this.iconSize = 48,
    this.inCard = true,
    this.cardBackgroundColor,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : title = 'Couldn\'t connect to $deviceName',
       description = 'Check that the band is powered on and nearby.';

  /// Creates an error state for generic failures.
  const ErrorState.generic({
    super.key,
    required String message,
    this.primaryAction,
    this.secondaryAction,
    this.icon,
    this.iconColor,
    this.iconSize = 48,
    this.inCard = true,
    this.cardBackgroundColor,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : title = 'Something went wrong',
       description = message;

  /// Creates an error state for data export failures.
  const ErrorState.exportFailed({
    super.key,
    this.primaryAction,
    this.secondaryAction,
    this.icon,
    this.iconColor,
    this.iconSize = 48,
    this.inCard = true,
    this.cardBackgroundColor,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : title = 'Export failed',
       description = 'We couldn\'t save the file. Check storage permissions and try again.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isLight = brightness == Brightness.light;

    final dangerColor = isLight ? const Color(0xFFD94A4A) : const Color(0xFFE57373);
    final effectiveIconColor = iconColor ?? dangerColor;
    final effectiveCardBg = cardBackgroundColor ??
        (isLight ? const Color(0xFFFFEBEE) : const Color(0xFF3D2A2A));

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Icon(
          icon ?? Icons.error_outline,
          size: iconSize,
          color: effectiveIconColor,
        ),
        SizedBox(height: spacing),
        Text(
          title,
          style: titleStyle ?? AppTypography.h3For(brightness).copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          description,
          style: descriptionStyle ?? AppTypography.bodyMediumFor(brightness).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (primaryAction != null || secondaryAction != null) ...[
          SizedBox(height: spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (secondaryAction != null) ...[
                secondaryAction!,
                const SizedBox(width: AppSpacing.sm),
              ],
              ?primaryAction,
            ],
          ),
        ],
      ],
    );

    if (inCard) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: effectiveCardBg,
          borderRadius: AppRadius.card,
          border: Border.all(color: dangerColor.withValues(alpha: 0.3), width: 1.5),
          boxShadow: AppShadows.surface,
        ),
        child: content,
      );
    }

    return content;
  }
}