import 'package:flutter/material.dart';

/// BANDANA design system color tokens.
///
/// Light and dark palettes are explicitly defined rather than derived,
/// following the neo-brutalist / playful corporate minimalist visual language.
class AppColors {
  AppColors._();

  // ── Light Palette ──

  /// Main app background — warm cream/paper tone (#FAF8F5).
  static const Color lightBackground = Color(0xFFFAF8F5);

  /// Cards and elevated surfaces — clean paper off-white.
  static const Color lightSurface = Color(0xFFFFFDF8);

  /// Primary text, borders, hard outlines — near-black (#18181B).
  static const Color lightInk = Color(0xFF18181B);

  /// Stroke / Border — #18181B in light mode.
  static const Color lightStroke = Color(0xFF18181B);

  /// Secondary text (#52525B). Meets WCAG AA contrast against light canvas.
  static const Color lightSecondaryText = Color(0xFF52525B);

  /// Primary CTA / key metrics — vibrant bubblegum pink (#FF3384).
  static const Color lightPink = Color(0xFFFF3384);

  /// Pink secondary surface / subtle backgrounds.
  static const Color lightPinkSoft = Color(0xFFFFD4E8);

  /// Metric Card Fill / Sky Blue — Pastel sky blue (#BAE6FD).
  static const Color lightMetricFill = Color(0xFFBAE6FD);
  static const Color lightSkyBlue = Color(0xFFBAE6FD);

  /// Lime Yellow (Activity/Movement) — #E2F952.
  static const Color lightLimeYellow = Color(0xFFE2F952);

  /// Soft Lavender (ML / Data) — #E9D5FF.
  static const Color lightSoftLavender = Color(0xFFE9D5FF);

  /// Soft Mint (Hardware Status) — #CCFBF1.
  static const Color lightSoftMint = Color(0xFFCCFBF1);

  /// Status / Accent Green — Vibrant lime green (#D6F865).
  static const Color statusLime = Color(0xFFD6F865);

  /// Success / active movement — moss green.
  static const Color lightMoss = Color(0xFF2E7D32);

  /// Strong secondary action — forest green.
  static const Color lightForest = Color(0xFF1B3B2B);

  /// Secondary information — slate (#52525B).
  static const Color lightSlate = Color(0xFF52525B);

  /// Disabled / secondary surface — slate soft.
  static const Color lightSlateSoft = Color(0xFFE2E0D8);

  /// Warning state.
  static const Color lightWarning = Color(0xFFF2B84B);

  /// Error / disconnected state (#991B1B).
  static const Color lightDanger = Color(0xFF991B1B);

  /// Status Colors: Connected (Fill #D1FAE5, Text/Border #065F46)
  static const Color statusConnectedFill = Color(0xFFD1FAE5);
  static const Color statusConnectedText = Color(0xFF065F46);

  /// Status Colors: Disconnected (Fill #FEE2E2, Text/Border #991B1B)
  static const Color statusDisconnectedFill = Color(0xFFFEE2E2);
  static const Color statusDisconnectedText = Color(0xFF991B1B);

  /// Text on dark/high-contrast buttons.
  static const Color lightWhite = Color(0xFFFFFFFF);

  // ── Dark Palette (intentionally designed, not inverted) ──

  /// Deep slate charcoal background (#121316).
  static const Color darkBackground = Color(0xFF121316);

  /// Dark charcoal surfaces / cards.
  static const Color darkSurface = Color(0xFF1E1E22);

  /// Primary text — high-contrast crisp white/cream (#FAF8F5).
  static const Color darkInk = Color(0xFFFAF8F5);

  /// Stroke / Border — #2E3038 in dark mode.
  static const Color darkStroke = Color(0xFF2E3038);

  /// Secondary text for dark mode (#A1A1AA).
  static const Color darkSecondaryText = Color(0xFFA1A1AA);

  /// Pink remains primary accent (#FF3384).
  static const Color darkPink = Color(0xFFFF3384);

  /// Pink secondary surface — muted for dark.
  static const Color darkPinkSoft = Color(0xFF3D1F2D);

  /// Sky Blue dark variant (#1E293B).
  static const Color darkMetricFill = Color(0xFF1E293B);
  static const Color darkSkyBlue = Color(0xFF1E293B);

  /// Lime Yellow dark variant (#243312).
  static const Color darkLimeYellow = Color(0xFF243312);

  /// Soft Lavender dark variant (#2E1B4E).
  static const Color darkSoftLavender = Color(0xFF2E1B4E);

  /// Soft Mint dark variant (#132E2B).
  static const Color darkSoftMint = Color(0xFF132E2B);

  /// Moss adjusted for dark contrast (#D6F865).
  static const Color darkMoss = Color(0xFFD6F865);

  /// Forest adjusted for dark contrast.
  static const Color darkForest = Color(0xFF4A7C3A);

  /// Muted slate for secondary text (#A1A1AA).
  static const Color darkSlate = Color(0xFFA1A1AA);

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
  static Color connected(Brightness brightness) =>
      brightness == Brightness.light ? statusConnectedText : const Color(0xFF6EE7B7);

  /// Disconnected/error state — uses danger color.
  static Color disconnected(Brightness brightness) =>
      brightness == Brightness.light ? statusDisconnectedText : const Color(0xFFFCA5A5);

  /// Connecting/pending state — uses warning color.
  static Color connecting(Brightness brightness) => warning(brightness);

  /// Recording state — uses primary accent (pink).
  static Color recording(Brightness brightness) => primaryAccent(brightness);

  /// Model ready state — uses secondary strong (forest).
  static Color modelReady(Brightness brightness) => secondaryStrong(brightness);

  /// Model unavailable state — uses disabled surface.
  static Color modelUnavailable(Brightness brightness) => disabledSurface(brightness);

  /// Surface outline / border stroke — #18181B on light, #2E3038 on dark.
  static Color surfaceOutline(Brightness brightness) =>
      brightness == Brightness.light ? lightStroke : darkStroke;

  /// Returns the sky blue pastel color for the given brightness (#BAE6FD on light).
  static Color skyBlue(Brightness brightness) =>
      brightness == Brightness.light ? lightSkyBlue : darkSkyBlue;

  /// Returns the lime yellow pastel color for the given brightness (#E2F952 on light).
  static Color limeYellow(Brightness brightness) =>
      brightness == Brightness.light ? lightLimeYellow : darkLimeYellow;

  /// Returns the soft lavender pastel color for the given brightness (#E9D5FF on light).
  static Color softLavender(Brightness brightness) =>
      brightness == Brightness.light ? lightSoftLavender : darkSoftLavender;

  /// Returns the soft mint pastel color for the given brightness (#CCFBF1 on light).
  static Color softMint(Brightness brightness) =>
      brightness == Brightness.light ? lightSoftMint : darkSoftMint;

  /// Returns the metric card fill color for the given brightness (#BAE6FD on light).
  static Color metricFill(Brightness brightness) =>
      brightness == Brightness.light ? lightMetricFill : darkMetricFill;

  /// Returns the secondary text color for the given brightness.
  static Color secondaryText(Brightness brightness) =>
      brightness == Brightness.light ? lightSecondaryText : darkSecondaryText;
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