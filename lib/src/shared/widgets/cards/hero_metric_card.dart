import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A large, prominent metric card for hero/dashboard metrics.
///
/// Uses Neo-Brutalist Bento design language: pastel sky blue fill (#B8E3FF),
/// 2px solid border, 4px crisp hard drop shadow, and high-contrast typography.
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

  /// Color for the value (defaults to high-contrast #1A1A1A on light).
  final Color? valueColor;

  /// Color for the label (defaults to high-contrast #1A1A1A on light).
  final Color? labelColor;

  /// Background color (defaults to AppColors.metricFill).
  final Color? backgroundColor;

  /// Border color (defaults to 2px solid outline #1A1A1A).
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

    final effectiveBgColor = backgroundColor ?? AppColors.metricFill(brightness);
    final effectiveBorderColor = borderColor ?? AppColors.surfaceOutline(brightness);
    final effectiveValueColor = valueColor ?? (isLight ? const Color(0xFF1A1A1A) : Colors.white);
    final effectiveLabelColor = labelColor ?? (isLight ? const Color(0xFF1A1A1A) : Colors.white70);

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
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?trailingAction,
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
                letterSpacing: -1.5,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  unit!,
                  style: AppTypography.h3For(brightness).copyWith(
                    color: effectiveValueColor.withValues(alpha: 0.85),
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
              color: isLight ? const Color(0xFF4A4A4A) : Colors.white70,
              fontWeight: FontWeight.w500,
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
          borderRadius: AppRadius.bentoCard,
          border: Border.all(color: effectiveBorderColor, width: 2.0),
          boxShadow: AppShadows.hard(brightness),
        ),
        child: cardContent,
      );
    } else {
      card = Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: effectiveBgColor,
          borderRadius: AppRadius.bentoCard,
          border: Border.all(color: effectiveBorderColor, width: 2.0),
          boxShadow: AppShadows.hard(brightness),
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
          borderRadius: AppRadius.bentoCard,
          child: card,
        ),
      );
    } else if (semanticsLabel != null) {
      card = Semantics(label: semanticsLabel!, child: card);
    }

    return card;
  }
}