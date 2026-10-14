import 'package:flutter/material.dart';

import 'package:bandana/src/core/theme/app_spacing.dart';
import 'package:bandana/src/core/theme/app_typography.dart';

/// A consistent section header with optional subtitle and trailing action.
///
/// Used to introduce content sections with clear visual hierarchy.
class SectionHeader extends StatelessWidget {
  /// The main section title.
  final String title;

  /// Optional subtitle/description.
  final String? subtitle;

  /// Optional trailing action (e.g., "View all", "Manage").
  final Widget? action;

  /// Optional leading icon.
  final IconData? leadingIcon;

  /// Color for the leading icon (defaults to primary accent).
  final Color? leadingIconColor;

  /// Whether to show a bottom divider.
  final bool showDivider;

  /// Custom title style.
  final TextStyle? titleStyle;

  /// Custom subtitle style.
  final TextStyle? subtitleStyle;

  /// Cross-axis alignment for the row.
  final CrossAxisAlignment crossAxisAlignment;

  /// Spacing between title/subtitle and action.
  final double actionSpacing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.leadingIcon,
    this.leadingIconColor,
    this.showDivider = false,
    this.titleStyle,
    this.subtitleStyle,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.actionSpacing = AppSpacing.md,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final defaultTitleStyle = AppTypography.h2For(brightness);
    final defaultSubtitleStyle = AppTypography.bodySmallFor(brightness);

    Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: crossAxisAlignment,
          children: [
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: AppSpacing.iconSizeLarge,
                color: leadingIconColor ?? theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: titleStyle ?? defaultTitleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: subtitleStyle ?? defaultSubtitleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              SizedBox(width: actionSpacing),
              action!,
            ],
          ],
        ),
        if (showDivider) ...[
          const SizedBox(height: AppSpacing.sm),
          Divider(
            height: 1,
            thickness: 1,
            color: brightness == Brightness.light
                ? const Color(0xFFDCE2E5)
                : const Color(0xFF2D3338),
          ),
        ],
      ],
    );

    return header;
  }
}