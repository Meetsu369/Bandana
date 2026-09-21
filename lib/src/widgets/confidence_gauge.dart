import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated circular gauge that displays prediction confidence (0.0–1.0).
///
/// Transitions smoothly between values and shifts color from red → yellow → green.
/// If confidence is null, displays "N/A" instead of a percentage.
class ConfidenceGauge extends StatelessWidget {
  /// Confidence value between 0.0 and 1.0, or null if unavailable.
  final double? confidence;

  /// Diameter of the gauge.
  final double size;

  /// Stroke width of the arc.
  final double strokeWidth;

  /// Optional child widget rendered in the center (e.g., activity icon).
  final Widget? child;

  const ConfidenceGauge({
    super.key,
    this.confidence,
    this.size = 160,
    this.strokeWidth = 10,
    this.child,
  });

  /// Interpolate color based on confidence: red → yellow → green.
  Color _colorForConfidence(double value) {
    if (value < 0.5) {
      // Red → Yellow
      return Color.lerp(
        const Color(0xFFEF5350),
        const Color(0xFFFFC107),
        value * 2,
      )!;
    } else {
      // Yellow → Green
      return Color.lerp(
        const Color(0xFFFFC107),
        const Color(0xFF66BB6A),
        (value - 0.5) * 2,
      )!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasConfidence = confidence != null;
    final clampedConfidence = hasConfidence ? confidence!.clamp(0.0, 1.0) : 0.0;
    final color = hasConfidence ? _colorForConfidence(clampedConfidence) : theme.colorScheme.onSurfaceVariant;
    final percent = hasConfidence ? (clampedConfidence * 100).round() : null;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox.expand(
            child: CustomPaint(
              painter: _GaugePainter(
                progress: hasConfidence ? 1.0 : 0.0,
                color: theme.colorScheme.surfaceContainerHighest,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
          // Animated foreground arc (only shown when confidence is available)
          if (hasConfidence)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: clampedConfidence),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return SizedBox.expand(
                  child: CustomPaint(
                    painter: _GaugePainter(
                      progress: value,
                      color: _colorForConfidence(value),
                      strokeWidth: strokeWidth,
                    ),
                  ),
                );
              },
            ),
          // Center content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (child != null) ...[
                child!,
                const SizedBox(height: 4),
              ],
              Text(
                percent != null ? '$percent%' : 'N/A',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                'Confidence',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom painter that draws a circular arc for the gauge.
class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start from the top (-90°), sweep clockwise.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}
