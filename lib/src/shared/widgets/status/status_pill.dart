import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A pill-shaped status indicator with icon + text.
///
/// Never relies on color alone to communicate status — always pairs
/// an icon with descriptive text. Supports semantic status variants.
class StatusPill extends StatelessWidget {
  /// The status variant determining color and default icon.
  final StatusPillVariant variant;

  /// Custom text to display (overrides variant default).
  final String? text;

  /// Custom icon (overrides variant default).
  final IconData? icon;

  /// Whether to show the icon.
  final bool showIcon;

  /// Custom text style.
  final TextStyle? textStyle;

  /// Custom background color.
  final Color? backgroundColor;

  /// Custom foreground (icon/text) color.
  final Color? foregroundColor;

  /// Custom border.
  final Border? border;

  /// Padding inside the pill.
  final EdgeInsetsGeometry? padding;

  /// Semantic label for accessibility (defaults to variant + text).
  final String? semanticsLabel;

  const StatusPill({
    super.key,
    required this.variant,
    this.text,
    this.icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  });

  /// Creates a connected status pill.
  const StatusPill.connected({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.connected,
       text = text,
       icon = icon;

  /// Creates a disconnected status pill.
  const StatusPill.disconnected({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.disconnected,
       text = text,
       icon = icon;

  /// Creates a connecting/scanning status pill.
  const StatusPill.connecting({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.connecting,
       text = text,
       icon = icon;

  /// Creates a recording status pill.
  const StatusPill.recording({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.recording,
       text = text,
       icon = icon;

  /// Creates a ready/active status pill.
  const StatusPill.ready({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.ready,
       text = text,
       icon = icon;

  /// Creates an unavailable/not ready status pill.
  const StatusPill.unavailable({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.unavailable,
       text = text,
       icon = icon;

  /// Creates a warning status pill.
  const StatusPill.warning({
    super.key,
    String? text,
    IconData? icon,
    this.showIcon = true,
    this.textStyle,
    this.backgroundColor,
    this.foregroundColor,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.warning,
       text = text,
       icon = icon;

  /// Creates a custom status pill with explicit colors.
  const StatusPill.custom({
    super.key,
    required String text,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    this.showIcon = true,
    this.textStyle,
    this.border,
    this.padding,
    this.semanticsLabel,
  }) : variant = StatusPillVariant.custom,
       text = text,
       icon = icon,
       backgroundColor = backgroundColor,
       foregroundColor = foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final (resolvedBgColor, resolvedFgColor, defaultIcon, defaultText) = _resolveVariant(brightness);

    final effectiveBgColor = backgroundColor ?? resolvedBgColor;
    final effectiveFgColor = foregroundColor ?? resolvedFgColor;
    final effectiveIcon = showIcon ? (icon ?? defaultIcon) : null;
    final effectiveText = text ?? defaultText;
    final effectiveSemantics = semanticsLabel ?? '$effectiveText, ${variant.name}';

    return Semantics(
      label: effectiveSemantics,
      child: Container(
        padding: padding ??
            EdgeInsets.symmetric(
              horizontal: AppSpacing.chipHorizontalPadding,
              vertical: AppSpacing.chipVerticalPadding,
            ),
        decoration: BoxDecoration(
          color: effectiveBgColor,
          borderRadius: AppRadius.pillRadius,
          border: border ??
              (variant == StatusPillVariant.custom
                  ? null
                  : Border.all(
                      color: effectiveFgColor.withValues(alpha: 0.5),
                      width: 1.5,
                    )),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (effectiveIcon != null) ...[
              Icon(effectiveIcon, size: AppSpacing.iconSizeSmall, color: effectiveFgColor),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              effectiveText,
              style: (textStyle ?? AppTypography.labelSmallFor(brightness)).copyWith(
                color: effectiveFgColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, Color, IconData?, String) _resolveVariant(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    return switch (variant) {
      StatusPillVariant.connected => (
          isLight ? const Color(0x1A6B8E23) : const Color(0x1A8DB63B), // moss 10%
          isLight ? const Color(0xFF6B8E23) : const Color(0xFF8DB63B),
          Icons.check_circle,
          'Connected',
        ),
      StatusPillVariant.disconnected => (
          isLight ? const Color(0x1AD94A4A) : const Color(0x1AE57373), // danger 10%
          isLight ? const Color(0xFFD94A4A) : const Color(0xFFE57373),
          Icons.radio_button_unchecked,
          'Disconnected',
        ),
      StatusPillVariant.connecting => (
          isLight ? const Color(0x1AF2B84B) : const Color(0x1AF2B84B), // warning 10%
          isLight ? const Color(0xFFF2B84B) : const Color(0xFFF2B84B),
          Icons.bluetooth_searching,
          'Connecting...',
        ),
      StatusPillVariant.recording => (
          isLight ? const Color(0x1AFF69B4) : const Color(0x1AFF69B4), // pink 10%
          isLight ? const Color(0xFFFF69B4) : const Color(0xFFFF69B4),
          Icons.fiber_manual_record,
          'Recording',
        ),
      StatusPillVariant.ready => (
          isLight ? const Color(0x1A1B3B2B) : const Color(0x1A4A7C3A), // forest 10%
          isLight ? const Color(0xFF1B3B2B) : const Color(0xFF4A7C3A),
          Icons.check_circle_outline,
          'Ready',
        ),
      StatusPillVariant.unavailable => (
          isLight ? const Color(0x1A8C9BA5) : const Color(0x1A9BA8B4), // slate 10%
          isLight ? const Color(0xFF8C9BA5) : const Color(0xFF9BA8B4),
          Icons.help_outline,
          'Unavailable',
        ),
      StatusPillVariant.warning => (
          isLight ? const Color(0x1AF2B84B) : const Color(0x1AF2B84B), // warning 10%
          isLight ? const Color(0xFFF2B84B) : const Color(0xFFF2B84B),
          Icons.warning_amber_rounded,
          'Warning',
        ),
      StatusPillVariant.custom => (
          backgroundColor ?? (isLight ? const Color(0xFF111111) : const Color(0xFFF5F3ED)),
          foregroundColor ?? (isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111111)),
          icon,
          text ?? '',
        ),
    };
  }
}

/// Semantic status variants for StatusPill.
enum StatusPillVariant {
  /// Green — connected, active, success.
  connected,

  /// Red — disconnected, error, inactive.
  disconnected,

  /// Amber — connecting, scanning, pending.
  connecting,

  /// Pink — recording, live capture.
  recording,

  /// Forest — ready, model trained, armed.
  ready,

  /// Slate — unavailable, not trained, unknown.
  unavailable,

  /// Amber — warning, degraded.
  warning,

  /// Custom colors provided explicitly.
  custom,
}