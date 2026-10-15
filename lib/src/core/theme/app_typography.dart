import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// BANDANA design system typography tokens.
///
/// Uses Manrope as the primary font family via google_fonts.
/// Falls back to system sans-serif if unavailable.
class AppTypography {
  AppTypography._();

  static const String _fontFamily = 'Manrope';

  // ── Font Weights ──

  static const FontWeight weightDisplay = FontWeight.w900;
  static const FontWeight weightH1 = FontWeight.w800;
  static const FontWeight weightH2 = FontWeight.w800;
  static const FontWeight weightH3 = FontWeight.w700;
  static const FontWeight weightBody = FontWeight.w400;
  static const FontWeight weightBodyMedium = FontWeight.w500;
  static const FontWeight weightLabel = FontWeight.w600;
  static const FontWeight weightLabelBold = FontWeight.w700;
  static const FontWeight weightCaption = FontWeight.w500;

  // ── Light Theme Text Styles (--text-primary: #18181B, --text-secondary: #52525B) ──

  /// Display — largest headline, e.g. "82%".
  static TextStyle get display => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 56,
        fontWeight: weightDisplay,
        height: 1.1,
        letterSpacing: -1.5,
        color: const Color(0xFF18181B),
      );

  /// H1 — Screen title, e.g. "Your activity today".
  static TextStyle get h1 => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 32,
        fontWeight: weightH1,
        height: 1.2,
        letterSpacing: -0.5,
        color: const Color(0xFF18181B),
      );

  /// H2 — Section heading, e.g. "Your bands are ready".
  static TextStyle get h2 => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 24,
        fontWeight: weightH2,
        height: 1.3,
        letterSpacing: 0,
        color: const Color(0xFF18181B),
      );

  /// H3 — Card title / activity label, e.g. "Walking".
  static TextStyle get h3 => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 20,
        fontWeight: weightH3,
        height: 1.3,
        letterSpacing: 0,
        color: const Color(0xFF18181B),
      );

  /// Body — Supporting information, paragraph text.
  static TextStyle get body => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 16,
        fontWeight: weightBody,
        height: 1.5,
        letterSpacing: 0.15,
        color: const Color(0xFF18181B),
      );

  /// Body medium — Slightly emphasized body text.
  static TextStyle get bodyMedium => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 16,
        fontWeight: weightBodyMedium,
        height: 1.5,
        letterSpacing: 0.15,
        color: const Color(0xFF18181B),
      );

  /// Body small — Secondary supporting text (#52525B).
  static TextStyle get bodySmall => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 14,
        fontWeight: weightBody,
        height: 1.4,
        letterSpacing: 0.2,
        color: const Color(0xFF52525B),
      );

  /// Label — Button labels, chip text, e.g. "WRIST BAND".
  static TextStyle get label => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 14,
        fontWeight: weightLabel,
        height: 1.4,
        letterSpacing: 0.5,
        color: const Color(0xFF18181B),
      );

  /// Label small — Compact labels.
  static TextStyle get labelSmall => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 12,
        fontWeight: weightLabel,
        height: 1.3,
        letterSpacing: 0.5,
        color: const Color(0xFF18181B),
      );

  /// Caption — Secondary metadata, timestamps (#52525B).
  static TextStyle get caption => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 12,
        fontWeight: weightCaption,
        height: 1.3,
        letterSpacing: 0.4,
        color: const Color(0xFF52525B),
      );

  /// Monospace — For session IDs, technical values.
  static TextStyle get mono => GoogleFonts.getFont(
        _fontFamily,
        fontSize: 12,
        fontWeight: weightBody,
        height: 1.4,
        letterSpacing: 0.5,
        color: const Color(0xFF18181B),
      ).copyWith(fontFamily: 'monospace');

  // ── Dark Theme Text Styles (--text-primary: #F4F4F5, --text-secondary: #A1A1AA) ──

  static TextStyle get displayDark => display.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get h1Dark => h1.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get h2Dark => h2.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get h3Dark => h3.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get bodyDark => body.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get bodyMediumDark => bodyMedium.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get bodySmallDark => bodySmall.copyWith(color: const Color(0xFFA1A1AA));
  static TextStyle get labelDark => label.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get labelSmallDark => labelSmall.copyWith(color: const Color(0xFFF4F4F5));
  static TextStyle get captionDark => caption.copyWith(color: const Color(0xFFA1A1AA));
  static TextStyle get monoDark => mono.copyWith(color: const Color(0xFFF4F4F5));

  // ── Theme-aware getters ──

  static TextStyle textStyleFor(
    Brightness brightness, {
    required TextStyle light,
    required TextStyle dark,
  }) =>
      brightness == Brightness.light ? light : dark;

  static TextStyle displayFor(Brightness b) => textStyleFor(b, light: display, dark: displayDark);
  static TextStyle h1For(Brightness b) => textStyleFor(b, light: h1, dark: h1Dark);
  static TextStyle h2For(Brightness b) => textStyleFor(b, light: h2, dark: h2Dark);
  static TextStyle h3For(Brightness b) => textStyleFor(b, light: h3, dark: h3Dark);
  static TextStyle bodyFor(Brightness b) => textStyleFor(b, light: body, dark: bodyDark);
  static TextStyle bodyMediumFor(Brightness b) =>
      textStyleFor(b, light: bodyMedium, dark: bodyMediumDark);
  static TextStyle bodySmallFor(Brightness b) => textStyleFor(b, light: bodySmall, dark: bodySmallDark);
  static TextStyle labelFor(Brightness b) => textStyleFor(b, light: label, dark: labelDark);
  static TextStyle labelSmallFor(Brightness b) => textStyleFor(b, light: labelSmall, dark: labelSmallDark);
  static TextStyle captionFor(Brightness b) => textStyleFor(b, light: caption, dark: captionDark);
  static TextStyle monoFor(Brightness b) => textStyleFor(b, light: mono, dark: monoDark);
}

/// Extension for easier access from BuildContext.
extension AppTypographyContext on BuildContext {
  AppTypography get typography => AppTypography._();
  Brightness get _brightness => Theme.of(this).brightness;

  TextStyle get display => AppTypography.displayFor(_brightness);
  TextStyle get h1 => AppTypography.h1For(_brightness);
  TextStyle get h2 => AppTypography.h2For(_brightness);
  TextStyle get h3 => AppTypography.h3For(_brightness);
  TextStyle get body => AppTypography.bodyFor(_brightness);
  TextStyle get bodyMedium => AppTypography.bodyMediumFor(_brightness);
  TextStyle get bodySmall => AppTypography.bodySmallFor(_brightness);
  TextStyle get label => AppTypography.labelFor(_brightness);
  TextStyle get labelSmall => AppTypography.labelSmallFor(_brightness);
  TextStyle get caption => AppTypography.captionFor(_brightness);
  TextStyle get mono => AppTypography.monoFor(_brightness);
}