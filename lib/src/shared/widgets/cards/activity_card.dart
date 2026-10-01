import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A card showing summary stats for a recorded activity.
///
/// Used on the Dashboard to display activity summaries.
/// Includes static utility methods for icon/color mapping used by Live screen.
class ActivityCard extends StatelessWidget {
  /// The activity label (e.g., "Walking", "Sitting").
  final String label;

  /// Number of sessions for this activity.
  final int sessionCount;

  /// Total sample/window count for this activity.
  final int totalSamples;

  /// Callback when card is tapped.
  final VoidCallback? onTap;

  const ActivityCard({
    super.key,
    required this.label,
    required this.sessionCount,
    required this.totalSamples,
    this.onTap,
  });

  /// Map activity labels to icons.
  static IconData iconForLabel(String label) {
    return switch (label.toLowerCase()) {
      'walking' => Icons.directions_walk,
      'running' => Icons.directions_run,
      'sitting' => Icons.chair,
      'standing' => Icons.accessibility_new,
      'climbing stairs' => Icons.stairs,
      'descending stairs' => Icons.trending_down,
      _ => Icons.fitness_center,
    };
  }

  /// Map activity labels to gradient colors (light theme).
  static List<Color> colorsForLabel(String label) {
    return switch (label.toLowerCase()) {
      'walking' => [const Color(0xFF26A69A), const Color(0xFF80CBC4)],
      'running' => [const Color(0xFFEF5350), const Color(0xFFEF9A9A)],
      'sitting' => [const Color(0xFF42A5F5), const Color(0xFF90CAF9)],
      'standing' => [const Color(0xFFAB47BC), const Color(0xFFCE93D8)],
      'climbing stairs' => [const Color(0xFFFFA726), const Color(0xFFFFCC80)],
      'descending stairs' => [const Color(0xFF66BB6A), const Color(0xFFA5D6A7)],
      _ => [const Color(0xFF78909C), const Color(0xFFB0BEC5)],
    };
  }

  /// Map activity labels to gradient colors for a specific brightness.
  static List<Color> colorsForLabelWithBrightness(String label, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final baseColors = colorsForLabel(label);

    if (isLight) {
      return baseColors.map((c) => c.withValues(alpha: 0.12)).toList();
    } else {
      return baseColors.map((c) => c.withValues(alpha: 0.2)).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final colors = colorsForLabelWithBrightness(label, brightness);
    final primaryColor = colorsForLabel(label)[0];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: AppShadows.cardBorder(brightness).top,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: brightness == Brightness.dark ? 0.3 : 0.15),
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(
                  iconForLabel(label),
                  color: primaryColor,
                  size: AppSpacing.iconSizeMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Label
              Text(
                label,
                style: AppTypography.labelSmallFor(brightness).copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              // Stats
              Text(
                '$sessionCount session${sessionCount != 1 ? 's' : ''}',
                style: AppTypography.bodySmallFor(brightness),
              ),
              Text(
                '$totalSamples samples',
                style: AppTypography.bodySmallFor(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }
}