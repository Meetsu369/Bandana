import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A large, prominent metric card for hero/dashboard metrics.
///
/// Intended for key metrics like "74 min active today" with large visual hierarchy.
/// Uses larger radius (28px), larger typography, and more generous padding.
class HeroMetricCard extends StatelessWidget {
  /// The metric label (e.g., "Active today", "Today's movement").
  final String label;

  /// The primary large metric value (e.g., "74", "82%").
  final String value;

  /// Optional unit suffix (e.g., "min", "%").
  final String? unit;

  /// Optional supporting description (e.g., "Walking 42 min, Standing 31 min").
  final String? description;

  /// Optional leading icon/illustration.
  final Widget? leading;

  /// Optional trailing action button.
  final Widget? trailingAction;

  /// Color for the value (defaults to primary accent).
  final Color? valueColor;

  /// Color for the label (defaults to onSurfaceVariant).
  final Color? labelColor;

  /// Background color (defaults to surface).
  final Color? backgroundColor;

  /// Border color (defaults to theme outline).
  final Color? borderColor;

  /// Gradient background (optional, overrides backgroundColor).
  final Gradient? gradient;

  /// Whether the card is tappable.
  final bool isTappable;

  /// Callback when card is tapped.
  final VoidCallback? onTap;

  /// Semantic label for accessibility.
  final String? semanticsLabel;

  const HeroMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.description,
    this.leading,
    this.trailingAction,
    this.valueColor,
    this.labelColor,
    this.backgroundColor,
    this.borderColor,
    this.gradient,
    this.isTappable = false,
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
    final effectiveValueColor = valueColor ?? theme.colorScheme.primary;
    final effectiveLabelColor = labelColor ?? theme.colorScheme.onSurfaceVariant;

    Widget cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top row: label + optional trailing action
        Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Text(
                label,
                style: AppTypography.h3For(brightness).copyWith(
                  color: effectiveLabelColor,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailingAction != null) trailingAction!,
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        // Large value
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: AppTypography.displayFor(brightness).copyWith(
                color: effectiveValueColor,
                fontWeight: FontWeight.w900,
                fontSize: 56,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit!,
                  style: AppTypography.h2For(brightness).copyWith(
                    color: effectiveValueColor.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            description!,
            style: AppTypography.bodyMediumFor(brightness).copyWith(
              color: effectiveLabelColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    Widget card;
    if (gradient != null) {
      card = Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: AppRadius.heroCard,
          boxShadow: AppShadows.raised,
        ),
        child: cardContent,
      );
    } else {
      card = Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: effectiveBgColor,
          borderRadius: AppRadius.heroCard,
          border: Border.all(color: effectiveBorderColor, width: 1.5),
          boxShadow: AppShadows.surface,
        ),
        child: cardContent,
      );
    }

    if (isTappable || onTap != null) {
      final effectiveSemantics = semanticsLabel ?? '$label: $value${unit != null ? ' $unit' : ''}';
      card = Semantics(
        label: effectiveSemantics,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.heroCard,
          child: card,
        ),
      );
    } else if (semanticsLabel != null) {
      card = Semantics(label: semanticsLabel!, child: card);
    }

    return card;
  }
}