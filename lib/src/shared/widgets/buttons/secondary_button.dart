import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A secondary/outlined button with the same touch-target principles as PrimaryButton.
///
/// Features:
/// - 56px height minimum touch target (configurable)
/// - Outlined style with theme-aware border
/// - Bold label with optional leading/trailing icons
/// - Disabled state
/// - Accessible semantics
/// - Subtle press animation
class SecondaryButton extends StatefulWidget {
  /// The button's label text.
  final String label;

  /// Callback when the button is pressed.
  final VoidCallback? onPressed;

  /// Optional leading icon.
  final IconData? leadingIcon;

  /// Optional trailing icon.
  final IconData? trailingIcon;

  /// Whether the button is disabled.
  final bool isDisabled;

  /// Whether the button is in a loading state.
  final bool isLoading;

  /// Custom border color (defaults to theme outline).
  final Color? borderColor;

  /// Custom foreground/text color (defaults to theme onSurface).
  final Color? foregroundColor;

  /// Custom background color when pressed/hovered.
  final Color? hoverColor;

  /// Custom border radius (defaults to AppRadius.button).
  final BorderRadius? borderRadius;

  /// Custom minimum height (defaults to AppSpacing.buttonHeight = 56px).
  final double? height;

  /// Custom horizontal padding.
  final EdgeInsetsGeometry? padding;

  /// Semantic label for accessibility.
  final String? semanticsLabel;

  /// Tooltip text.
  final String? tooltip;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.isDisabled = false,
    this.isLoading = false,
    this.borderColor,
    this.foregroundColor,
    this.hoverColor,
    this.borderRadius,
    this.height,
    this.padding,
    this.semanticsLabel,
    this.tooltip,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.isDisabled && !widget.isLoading && widget.onPressed != null) {
      setState(() => _isPressed = true);
      _pressController.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isPressed) {
      setState(() => _isPressed = false);
      _pressController.reverse();
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDisabled = widget.isDisabled || widget.isLoading || widget.onPressed == null;

    final borderColor = widget.borderColor ??
        (brightness == Brightness.light
            ? const Color(0xFF111111)
            : const Color(0xFFF5F3ED));
    final foregroundColor = widget.foregroundColor ?? theme.colorScheme.onSurface;
    final disabledBorderColor = brightness == Brightness.light
        ? const Color(0xFFDCE2E5)
        : const Color(0xFF2D3338);
    final disabledForegroundColor = brightness == Brightness.light
        ? const Color(0xFF8C9BA5)
        : const Color(0xFF9BA8B4);

    final effectiveBorderColor = isDisabled ? disabledBorderColor : borderColor;
    final effectiveForegroundColor = isDisabled ? disabledForegroundColor : foregroundColor;
    final effectiveHoverColor = widget.hoverColor ??
        effectiveBorderColor.withValues(alpha: 0.08);

    final borderRadius = widget.borderRadius ?? AppRadius.button;
    final height = widget.height ?? AppSpacing.buttonHeight;
    final padding = widget.padding ??
        EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md);

    Widget buttonChild = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leadingIcon != null) ...[
          Icon(widget.leadingIcon, size: AppSpacing.iconSizeMedium, color: effectiveForegroundColor),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (widget.isLoading)
          SizedBox(
            width: AppSpacing.iconSizeMedium,
            height: AppSpacing.iconSizeMedium,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(effectiveForegroundColor),
            ),
          )
        else
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelFor(brightness).copyWith(
                color: effectiveForegroundColor,
                fontSize: 14,
              ),
            ),
          ),
        if (!widget.isLoading && widget.trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(widget.trailingIcon, size: AppSpacing.iconSizeMedium, color: effectiveForegroundColor),
        ],
      ],
    );

    buttonChild = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _isPressed ? _scaleAnimation.value : 1.0,
        child: child,
      ),
      child: buttonChild,
    );

    Widget button = Semantics(
      label: widget.semanticsLabel ?? widget.label,
      button: true,
      enabled: !isDisabled,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 88, minHeight: height),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: padding,
          decoration: BoxDecoration(
            color: _isPressed && !isDisabled ? effectiveHoverColor : Colors.transparent,
            borderRadius: borderRadius,
            border: Border.all(
              color: effectiveBorderColor,
              width: 1.5,
            ),
            boxShadow: _isPressed && !isDisabled
                ? AppShadows.pressed
                : (isDisabled ? AppShadows.none : AppShadows.none),
          ),
          child: buttonChild,
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: isDisabled ? null : widget.onPressed,
      child: button,
    );
  }
}