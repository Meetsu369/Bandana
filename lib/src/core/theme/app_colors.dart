import 'package:flutter/material.dart';

/// BANDANA design system color tokens.
///
/// Light and dark palettes are explicitly defined rather than derived,
/// following the neo-brutalist / playful corporate minimalist visual language.
class AppColors {
  AppColors._();

  // ── Light Palette ──

  /// Main app background — warm cream.
  static const Color lightBackground = Color(0xFFF5F3ED);

  /// Cards and elevated surfaces — off-white.
  static const Color lightSurface = Color(0xFFFFFDF8);

  /// Primary text, borders, near-black.
  static const Color lightInk = Color(0xFF111111);

  /// Primary CTA / key metrics — pink accent.
  static const Color lightPink = Color(0xFFFF69B4);

  /// Pink secondary surface / subtle backgrounds.
  static const Color lightPinkSoft = Color(0xFFFFD4E8);

  /// Success / active movement — moss green.
  static const Color lightMoss = Color(0xFF6B8E23);

  /// Strong secondary action — forest green.
  static const Color lightForest = Color(0xFF1B3B2B);

  /// Secondary information — slate.
  static const Color lightSlate = Color(0xFF8C9BA5);

  /// Disabled / secondary surface — slate soft.
  static const Color lightSlateSoft = Color(0xFFDCE2E5);

  /// Warning state.
  static const Color lightWarning = Color(0xFFF2B84B);

  /// Error / disconnected state.
  static const Color lightDanger = Color(0xFFD94A4A);

  /// Text on dark/high-contrast buttons.
  static const Color lightWhite = Color(0xFFFFFFFF);

  // ── Dark Palette (intentionally designed, not inverted) ──

  /// Near-black background.
  static const Color darkBackground = Color(0xFF121212);

  /// Dark charcoal surfaces / cards.
  static const Color darkSurface = Color(0xFF1E1E1E);

  /// Primary text — cream/white.
  static const Color darkInk = Color(0xFFF5F3ED);

  /// Pink remains primary accent.
  static const Color darkPink = Color(0xFFFF69B4);

  /// Pink secondary surface — muted for dark.
  static const Color darkPinkSoft = Color(0xFF3D2A36);

  /// Moss adjusted for dark contrast.
  static const Color darkMoss = Color(0xFF8DB63B);

  /// Forest adjusted for dark contrast.
  static const Color darkForest = Color(0xFF4A7C3A);

  /// Muted slate for secondary text.
  static const Color darkSlate = Color(0xFF9BA8B4);

  /// Disabled / secondary surface — dark slate.
  static const Color darkSlateSoft = Color(0xFF2D3338);

  /// Warning — adjusted for dark.
  static const Color darkWarning = Color(0xFFF2B84B);

  /// Error — adjusted for dark.
  static const Color darkDanger = Color(0xFFE57373);

  /// Text on dark buttons.
  static const Color darkWhite = Color(0xFFFFFFFF);

  // ── Semantic Color Helpers ──

  /// Returns the background color for the given brightness.
  static Color background(Brightness brightness) =>
      brightness == Brightness.light ? lightBackground : darkBackground;

  /// Returns the surface color for the given brightness.
  static Color surface(Brightness brightness) =>
      brightness == Brightness.light ? lightSurface : darkSurface;

  /// Returns the primary text/border color for the given brightness.
  static Color ink(Brightness brightness) =>
      brightness == Brightness.light ? lightInk : darkInk;

  /// Returns the primary accent (pink) for the given brightness.
  static Color primaryAccent(Brightness brightness) =>
      brightness == Brightness.light ? lightPink : darkPink;

  /// Returns the success/active color for the given brightness.
  static Color success(Brightness brightness) =>
      brightness == Brightness.light ? lightMoss : darkMoss;

  /// Returns the strong secondary color for the given brightness.
  static Color secondaryStrong(Brightness brightness) =>
      brightness == Brightness.light ? lightForest : darkForest;

  /// Returns the secondary info color for the given brightness.
  static Color secondaryInfo(Brightness brightness) =>
      brightness == Brightness.light ? lightSlate : darkSlate;

  /// Returns the disabled/secondary surface color for the given brightness.
  static Color disabledSurface(Brightness brightness) =>
      brightness == Brightness.light ? lightSlateSoft : darkSlateSoft;

  /// Returns the warning color for the given brightness.
  static Color warning(Brightness brightness) =>
      brightness == Brightness.light ? lightWarning : darkWarning;

  /// Returns the error/danger color for the given brightness.
  static Color danger(Brightness brightness) =>
      brightness == Brightness.light ? lightDanger : darkDanger;

  /// Returns the on-accent text color (white).
  static Color onAccent(Brightness brightness) =>
      brightness == Brightness.light ? lightWhite : darkWhite;

  // ── Status-specific colors (brightness-aware) ──

  /// Connected/active state — uses success color.
  static Color connected(Brightness brightness) => success(brightness);

  /// Disconnected/error state — uses danger color.
  static Color disconnected(Brightness brightness) => danger(brightness);

  /// Connecting/pending state — uses warning color.
  static Color connecting(Brightness brightness) => warning(brightness);

  /// Recording state — uses primary accent (pink).
  static Color recording(Brightness brightness) => primaryAccent(brightness);

  /// Model ready state — uses secondary strong (forest).
  static Color modelReady(Brightness brightness) => secondaryStrong(brightness);

  /// Model unavailable state — uses secondary info (slate).
  static Color modelUnavailable(Brightness brightness) => secondaryInfo(brightness);
}

/// Extension for easier access from BuildContext.
extension AppColorsContext on BuildContext {
  AppColors get colors => AppColors._();

  Color get background => AppColors.background(Theme.of(this).brightness);
  Color get surface => AppColors.surface(Theme.of(this).brightness);
  Color get ink => AppColors.ink(Theme.of(this).brightness);
  Color get primaryAccent => AppColors.primaryAccent(Theme.of(this).brightness);
  Color get success => AppColors.success(Theme.of(this).brightness);
  Color get secondaryStrong => AppColors.secondaryStrong(Theme.of(this).brightness);
  Color get secondaryInfo => AppColors.secondaryInfo(Theme.of(this).brightness);
  Color get disabledSurface => AppColors.disabledSurface(Theme.of(this).brightness);
  Color get warning => AppColors.warning(Theme.of(this).brightness);
  Color get danger => AppColors.danger(Theme.of(this).brightness);
  Color get onAccent => AppColors.onAccent(Theme.of(this).brightness);

  Color get connected => AppColors.connected(Theme.of(this).brightness);
  Color get disconnected => AppColors.disconnected(Theme.of(this).brightness);
  Color get connecting => AppColors.connecting(Theme.of(this).brightness);
  Color get recording => AppColors.recording(Theme.of(this).brightness);
  Color get modelReady => AppColors.modelReady(Theme.of(this).brightness);
  Color get modelUnavailable => AppColors.modelUnavailable(Theme.of(this).brightness);
}