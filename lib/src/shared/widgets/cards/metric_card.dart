import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A metric display card with label, large value, and optional supporting content.
///
/// Variants:
/// - Standard: label + value + optional unit/trend
/// - Compact: smaller padding for dense layouts
class MetricCard extends StatelessWidget {
  /// The metric label (e.g., "Steps", "Active Minutes").
  final String label;

  /// The primary metric value (e.g., "6,842", "74").
  final String value;

  /// Optional unit suffix (e.g., "min", "sessions", "%").
  final String? unit;

  /// Optional supporting text (e.g., "+12% from yesterday", "Walking").
  final String? supportingText;

  /// Optional leading icon.
  final IconData? leadingIcon;

  /// Optional trailing icon (e.g., trend arrow).
  final IconData? trailingIcon;

  /// Color for the value (defaults to theme onSurface).
  final Color? valueColor;

  /// Color for the label (defaults to onSurfaceVariant).
  final Color? labelColor;

  /// Color for supporting text (defaults to onSurfaceVariant).
  final Color? supportingTextColor;

  /// Background color (defaults to surface).
  final Color? backgroundColor;

  /// Border color (defaults to theme outline).
  final Color? borderColor;

  /// Whether to use compact padding.
  final bool compact;

  /// Callback when card is tapped.
  final VoidCallback? onTap;

  /// Semantic label for accessibility.
  final String? semanticsLabel;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.supportingText,
    this.leadingIcon,
    this.trailingIcon,
    this.valueColor,
    this.labelColor,
    this.supportingTextColor,
    this.backgroundColor,
    this.borderColor,
    this.compact = false,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isLight = brightness == Brightness.light;

    final effectiveBgColor = backgroundColor ?? theme.colorScheme.surface;
    final effectiveBorderColor = borderColor ??
        (isLight ? const Color(0xFF111111) : const Color(0xFFF5F3ED));
    final effectiveValueColor = valueColor ?? theme.colorScheme.onSurface;
    final effectiveLabelColor = labelColor ?? theme.colorScheme.onSurfaceVariant;
    final effectiveSupportingColor = supportingTextColor ?? theme.colorScheme.onSurfaceVariant;

    final horizontalPadding = compact ? AppSpacing.sm : AppSpacing.md;
    final verticalPadding = compact ? AppSpacing.sm : AppSpacing.md;
    final gap = compact ? AppSpacing.xs : AppSpacing.sm;

    Widget cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label row with optional leading icon
        Row(
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: AppSpacing.iconSizeMedium, color: effectiveLabelColor),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelSmallFor(brightness).copyWith(
                  color: effectiveLabelColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingIcon != null)
              Icon(trailingIcon, size: AppSpacing.iconSizeSmall, color: effectiveSupportingColor),
          ],
        ),
        SizedBox(height: gap),
        // Value row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: AppTypography.h3For(brightness).copyWith(
                color: effectiveValueColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                unit!,
                style: AppTypography.bodyMediumFor(brightness).copyWith(
                  color: effectiveSupportingColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        if (supportingText != null) ...[
          SizedBox(height: gap),
          Text(
            supportingText!,
            style: AppTypography.captionFor(brightness).copyWith(
              color: effectiveSupportingColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    Widget card = Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: AppRadius.card,
        border: Border.all(color: effectiveBorderColor, width: 1.5),
        boxShadow: AppShadows.surface,
      ),
      child: cardContent,
    );

    if (onTap != null) {
      card = Semantics(
        label: semanticsLabel ?? '$label: $value${unit != null ? ' $unit' : ''}',
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: card,
        ),
      );
    } else if (semanticsLabel != null) {
      card = Semantics(
        label: semanticsLabel!,
        child: card,
      );
    }

    return card;
  }
}