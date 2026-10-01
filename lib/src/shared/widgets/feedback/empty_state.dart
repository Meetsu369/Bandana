import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// An empty state illustration with title, description, and optional CTA.
///
/// Used when there is no content to display (no sessions, no recordings, etc.).
class EmptyState extends StatelessWidget {
  /// The illustration icon.
  final IconData icon;

  /// The main title text.
  final String title;

  /// Optional description text.
  final String? description;

  /// Optional call-to-action button.
  final Widget? action;

  /// Icon color (defaults to onSurfaceVariant).
  final Color? iconColor;

  /// Icon size.
  final double iconSize;

  /// Title style.
  final TextStyle? titleStyle;

  /// Description style.
  final TextStyle? descriptionStyle;

  /// Spacing between elements.
  final double spacing;

  /// Cross-axis alignment.
  final CrossAxisAlignment alignment;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.iconColor,
    this.iconSize = 64,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  });

  /// Creates an empty state for "no sessions recorded".
  const EmptyState.noSessions({
    super.key,
    this.action,
    this.iconColor,
    this.iconSize = 64,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : icon = Icons.history,
       title = 'No sessions yet',
       description = 'Start recording to create your first session.';

  /// Creates an empty state for "no connected bands".
  const EmptyState.noBands({
    super.key,
    this.action,
    this.iconColor,
    this.iconSize = 64,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : icon = Icons.sensors_off,
       title = 'Your bands are taking a break',
       description = 'Connect your bands to start recording.';

  /// Creates an empty state for "no predictions available".
  const EmptyState.noPredictions({
    super.key,
    this.action,
    this.iconColor,
    this.iconSize = 64,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : icon = Icons.psychology_outlined,
       title = 'Nothing to predict yet',
       description = 'Record a session and BANDANA will analyze your movement.';

  /// Creates an empty state for "no data collected".
  const EmptyState.noData({
    super.key,
    this.action,
    this.iconColor,
    this.iconSize = 64,
    this.titleStyle,
    this.descriptionStyle,
    this.spacing = AppSpacing.md,
    this.alignment = CrossAxisAlignment.center,
  }) : icon = Icons.inbox_outlined,
       title = 'No data collected',
       description = 'Your movement story starts here. Record your first session.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Icon(
          icon,
          size: iconSize,
          color: iconColor ?? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
        if (description != null) ...[
          SizedBox(height: AppSpacing.xs),
          Text(
            description!,
            style: descriptionStyle ?? AppTypography.bodyMediumFor(brightness).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[
          SizedBox(height: spacing),
          action!,
        ],
      ],
    );
  }
}