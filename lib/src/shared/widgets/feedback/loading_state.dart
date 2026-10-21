import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A subtle, friendly loading indicator with optional message.
///
/// Avoids long blocking spinners; shows progress when possible.
/// Accessible loading semantics included.
class LoadingState extends StatelessWidget {
  /// The loading message (e.g., "Finding your bands...").
  final String? message;

  /// Optional secondary message.
  final String? secondaryMessage;

  /// Color of the indicator (defaults to primary accent).
  final Color? color;

  /// Size of the indicator.
  final double size;

  /// Stroke width of the circular indicator.
  final double strokeWidth;

  /// Whether to show as a full-screen overlay.
  final bool fullScreen;

  /// Background color for full-screen mode.
  final Color? fullScreenBackground;

  /// Message style.
  final TextStyle? messageStyle;

  /// Secondary message style.
  final TextStyle? secondaryMessageStyle;

  /// Spacing between indicator and message.
  final double spacing;

  const LoadingState({
    super.key,
    this.message,
    this.secondaryMessage,
    this.color,
    this.size = 32,
    this.strokeWidth = 3,
    this.fullScreen = false,
    this.fullScreenBackground,
    this.messageStyle,
    this.secondaryMessageStyle,
    this.spacing = AppSpacing.md,
  });

  /// Creates a loading state for "finding bands".
  const LoadingState.findingBands({
    super.key,
    this.color,
    this.size = 32,
    this.strokeWidth = 3,
    this.fullScreen = false,
    this.fullScreenBackground,
    this.messageStyle,
    this.secondaryMessageStyle,
    this.spacing = AppSpacing.md,
  }) : message = 'Finding your bands…',
       secondaryMessage = 'This may take a few seconds.';

  /// Creates a loading state for "connecting".
  const LoadingState.connecting({
    super.key,
    this.color,
    this.size = 32,
    this.strokeWidth = 3,
    this.fullScreen = false,
    this.fullScreenBackground,
    this.messageStyle,
    this.secondaryMessageStyle,
    this.spacing = AppSpacing.md,
  }) : message = 'Connecting…',
       secondaryMessage = null;

  /// Creates a loading state for "training model".
  const LoadingState.training({
    super.key,
    this.color,
    this.size = 32,
    this.strokeWidth = 3,
    this.fullScreen = false,
    this.fullScreenBackground,
    this.messageStyle,
    this.secondaryMessageStyle,
    this.spacing = AppSpacing.md,
  }) : message = 'Training model…',
       secondaryMessage = 'This may take a moment.';

  /// Creates a loading state for "exporting data".
  const LoadingState.exporting({
    super.key,
    this.color,
    this.size = 32,
    this.strokeWidth = 3,
    this.fullScreen = false,
    this.fullScreenBackground,
    this.messageStyle,
    this.secondaryMessageStyle,
    this.spacing = AppSpacing.md,
  }) : message = 'Exporting data…',
       secondaryMessage = 'Preparing your CSV file.';

  /// Creates a loading state for generic operations.
  const LoadingState.generic({
    super.key,
    required this.message,
    this.secondaryMessage,
    this.color,
    this.size = 32,
    this.strokeWidth = 3,
    this.fullScreen = false,
    this.fullScreenBackground,
    this.messageStyle,
    this.secondaryMessageStyle,
    this.spacing = AppSpacing.md,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final effectiveColor = color ?? theme.colorScheme.primary;

    Widget indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
      ),
    );

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        indicator,
        if (message != null) ...[
          SizedBox(height: spacing),
          Text(
            message!,
            style: messageStyle ?? AppTypography.bodyMediumFor(brightness).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (secondaryMessage != null) ...[
          SizedBox(height: AppSpacing.xs),
          Text(
            secondaryMessage!,
            style: secondaryMessageStyle ?? AppTypography.captionFor(brightness),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    content = Semantics(
      label: message ?? 'Loading',
      liveRegion: true,
      child: content,
    );

    if (fullScreen) {
      final bgColor = fullScreenBackground ??
          (brightness == Brightness.light
              ? const Color(0xFFF5F3ED)
              : const Color(0xFF121212));

      return Container(
        color: bgColor,
        alignment: Alignment.center,
        child: content,
      );
    }

    return Center(child: content);
  }
}