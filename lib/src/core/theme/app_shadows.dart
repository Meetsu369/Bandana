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

  /// Static 3px neo-brutalist hard drop shadow.
  static const BoxShadow hardShadow = BoxShadow(
    color: Color(0xFF18181B),
    offset: Offset(3, 3),
    blurRadius: 0,
    spreadRadius: 0,
  );

  /// Static 2px neo-brutalist hard drop shadow.
  static const BoxShadow hardShadowSm = BoxShadow(
    color: Color(0xFF18181B),
    offset: Offset(2, 2),
    blurRadius: 0,
    spreadRadius: 0,
  );

  /// Hard drop shadow — crisp 3px 3px neo-brutalist offset (0px blur).
  /// Light mode: #18181B (Pitch Dark). Dark mode: rgba(0, 0, 0, 0.65) = Color(0xA6000000).
  static List<BoxShadow> hard(Brightness brightness) => <BoxShadow>[
        BoxShadow(
          color: brightness == Brightness.light
              ? const Color(0xFF18181B)
              : const Color(0xA6000000),
          offset: const Offset(3, 3),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ];

  /// Compact hard drop shadow — crisp 2px 2px neo-brutalist offset.
  static List<BoxShadow> hardSm(Brightness brightness) => <BoxShadow>[
        BoxShadow(
          color: brightness == Brightness.light
              ? const Color(0xFF18181B)
              : const Color(0xA6000000),
          offset: const Offset(2, 2),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ];

  /// Helper for 3px hard drop shadow with isDark boolean.
  static List<BoxShadow> bento(bool isDark) =>
      hard(isDark ? Brightness.dark : Brightness.light);

  /// Helper for 2px compact hard drop shadow with isDark boolean.
  static List<BoxShadow> bentoSm(bool isDark) =>
      hardSm(isDark ? Brightness.dark : Brightness.light);

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
  /// Solid 2px border (#18181B in light, #383A42 in dark).
  static Border cardBorder(Brightness brightness, {double width = 2.0}) => Border.all(
        color: brightness == Brightness.light
            ? const Color(0xFF18181B)
            : const Color(0xFF383A42),
        width: width,
      );

  /// Button border — for outlined/secondary buttons.
  static Border buttonBorder(Brightness brightness, {Color? customColor, double width = 2.0}) => Border.all(
        color: customColor ??
            (brightness == Brightness.light
                ? const Color(0xFF18181B)
                : const Color(0xFF383A42)),
        width: width,
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