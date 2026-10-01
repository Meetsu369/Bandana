import 'package:flutter/material.dart';

/// BANDANA design system shadow tokens.
///
/// Subtle, tactile neo-brutalist shadows — short offset, minimal blur.
/// Avoids large floating Material-style elevation shadows.
class AppShadows {
  AppShadows._();

  /// No shadow.
  static const List<BoxShadow> none = <BoxShadow>[];

  /// Subtle surface shadow — for cards at rest.
  ///
  /// Offset: (0, 2), Blur: 0, Opacity: ~0.08 (ink at 8%)
  static const List<BoxShadow> surface = <BoxShadow>[
    BoxShadow(
      color: Color(0x14111111), // #111111 at 8%
      offset: Offset(0, 2),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  /// Raised card shadow — for interactive/hovered cards.
  ///
  /// Offset: (0, 4), Blur: 0, Opacity: ~0.12 (ink at 12%)
  static const List<BoxShadow> raised = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F111111), // #111111 at 12%
      offset: Offset(0, 4),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  /// Pressed/active shadow — for button press states.
  ///
  /// Offset: (0, 1), Blur: 0, Opacity: ~0.15 (ink at 15%)
  static const List<BoxShadow> pressed = <BoxShadow>[
    BoxShadow(
      color: Color(0x26111111), // #111111 at 15%
      offset: Offset(0, 1),
      blurRadius: 0,
      spreadRadius: 0,
    ),
  ];

  /// Floating shadow — for FABs, bottom sheets, modals.
  ///
  /// Offset: (0, 8), Blur: 16, Opacity: ~0.1 (ink at 10%)
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A111111), // #111111 at 10%
      offset: Offset(0, 8),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  /// Focus ring shadow — for accessibility focus states.
  ///
  /// Offset: (0, 0), Blur: 0, Spread: 2, Color: primary accent
  static List<BoxShadow> focusRing(Color accentColor) => <BoxShadow>[
    BoxShadow(
      color: accentColor,
      offset: Offset.zero,
      blurRadius: 0,
      spreadRadius: 2,
    ),
  ];

  /// Card border — used with surface shadow for neo-brutalist card look.
  ///
  /// 1.5px near-black border, combined with surface shadow.
  static Border cardBorder(Brightness brightness) => Border.all(
        color: brightness == Brightness.light
            ? const Color(0xFF111111)
            : const Color(0xFFF5F3ED),
        width: 1.5,
      );

  /// Button border — for outlined/secondary buttons.
  static Border buttonBorder(Brightness brightness, {Color? customColor}) => Border.all(
        color: customColor ??
            (brightness == Brightness.light
                ? const Color(0xFF111111)
                : const Color(0xFFF5F3ED)),
        width: 1.5,
      );

  /// Input field border.
  static Border inputBorder(Brightness brightness, {bool isFocused = false, bool hasError = false}) =>
      Border.all(
        color: hasError
            ? (brightness == Brightness.light ? const Color(0xFFD94A4A) : const Color(0xFFE57373))
            : isFocused
                ? (brightness == Brightness.light ? const Color(0xFFFF69B4) : const Color(0xFFFF69B4))
                : (brightness == Brightness.light
                    ? const Color(0xFF8C9BA5)
                    : const Color(0xFF9BA8B4)),
        width: isFocused || hasError ? 2 : 1.5,
      );
}