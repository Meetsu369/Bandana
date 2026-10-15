import 'package:flutter/material.dart';

/// BANDANA design system color tokens.
///
/// Light and dark palettes are explicitly defined rather than derived,
/// following the neo-brutalist / playful corporate minimalist visual language.
class AppColors {
  AppColors._();

  // ── Light Palette (--canvas-bg: #FAF8F5, --surface-card: #FFFFFF) ──

  /// Main app background — warm cream/paper tone (#FAF8F5).
  static const Color lightBackground = Color(0xFFFAF8F5);

  /// Cards and elevated surfaces — pure white (#FFFFFF).
  static const Color lightSurface = Color(0xFFFFFFFF);

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

  /// Wrist device pill & telemetry cell background (#BAE6FD).
  static const Color lightBadgeWristBg = Color(0xFFBAE6FD);
  /// Wrist metric text & glyphs (#0369A1).
  static const Color lightBadgeWristText = Color(0xFF0369A1);

  /// Metric Card Fill / Sky Blue alias.
  static const Color lightMetricFill = lightBadgeWristBg;
  static const Color lightSkyBlue = lightBadgeWristBg;

  /// Ankle device pill & telemetry cell background (#E2F952 - Volt Lime).
  static const Color lightBadgeAnkleBg = Color(0xFFE2F952);
  /// Ankle metric text & glyphs (#3F6212).
  static const Color lightBadgeAnkleText = Color(0xFF3F6212);

  /// Lime Yellow alias.
  static const Color lightLimeYellow = lightBadgeAnkleBg;

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

  /// Danger zone background / warning toasts (#FEF2F2).
  static const Color lightDangerBg = Color(0xFFFEF2F2);
  /// Danger text / delete buttons / offline labels (#DC2626 - Red 600).
  static const Color lightDangerText = Color(0xFFDC2626);
  /// Error / disconnected state alias.
  static const Color lightDanger = lightDangerText;

  /// Status Colors: Connected (Fill #D1FAE5, Text/Border #065F46)
  static const Color statusConnectedFill = Color(0xFFD1FAE5);
  static const Color statusConnectedText = Color(0xFF065F46);

  /// Status Colors: Disconnected (Fill #FEE2E2, Text/Border #991B1B)
  static const Color statusDisconnectedFill = Color(0xFFFEE2E2);
  static const Color statusDisconnectedText = Color(0xFF991B1B);

  /// Text on dark/high-contrast buttons / brand pink buttons (#FFFFFF).
  static const Color lightWhite = Color(0xFFFFFFFF);

  // ── Dark Palette (--canvas-bg: #121316, --surface-card: #1C1D22) ──

  /// Deep slate charcoal background (#121316).
  static const Color darkBackground = Color(0xFF121316);

  /// Elevated charcoal surfaces / cards (#1C1D22). Never pure #000000.
  static const Color darkSurface = Color(0xFF1C1D22);

  /// Primary text — high-contrast Zinc White (#F4F4F5).
  static const Color darkInk = Color(0xFFF4F4F5);

  /// Stroke / Border — Medium-High Slate (#383A42) for distinct card edges.
  static const Color darkStroke = Color(0xFF383A42);

  /// Secondary text for dark mode — Muted Zinc (#A1A1AA).
  static const Color darkSecondaryText = Color(0xFFA1A1AA);

  /// Pink remains primary accent (#FF3384).
  static const Color darkPink = Color(0xFFFF3384);

  /// Pink secondary surface — muted for dark.
  static const Color darkPinkSoft = Color(0xFF3D1F2D);

  /// Wrist device pill & telemetry cell background in dark mode (#1E3A5F - Deep Midnight Blue).
  static const Color darkBadgeWristBg = Color(0xFF1E3A5F);
  /// Wrist metric text & glyphs in dark mode (#93C5FD).
  static const Color darkBadgeWristText = Color(0xFF93C5FD);

  /// Sky Blue dark variant alias.
  static const Color darkMetricFill = darkBadgeWristBg;
  static const Color darkSkyBlue = darkBadgeWristBg;

  /// Ankle device pill & telemetry cell background in dark mode (#2A3A12 - Deep Forest Olive).
  static const Color darkBadgeAnkleBg = Color(0xFF2A3A12);
  /// Ankle metric text & glyphs in dark mode (#BEF264).
  static const Color darkBadgeAnkleText = Color(0xFFBEF264);

  /// Lime Yellow dark variant alias.
  static const Color darkLimeYellow = darkBadgeAnkleBg;

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

  /// Danger zone background in dark mode (#2C1517 - Deep Wine Red).
  static const Color darkDangerBg = Color(0xFF2C1517);
  /// Danger text in dark mode (#F87171 - Red 400).
  static const Color darkDangerText = Color(0xFFF87171);
  /// Error — adjusted for dark alias.
  static const Color darkDanger = darkDangerText;

  /// Text on dark buttons.
  static const Color darkWhite = Color(0xFFFFFFFF);

  /// Live recording container (remains solid dark #18181B in both themes).
  static const Color liveTelemetry = Color(0xFF18181B);

  // ── Exact Design Token Map Aliases (CSS / Token parity) ──
  static const Color canvasBgLight = lightBackground; // #FAF8F5
  static const Color canvasBgDark = darkBackground;   // #121316
  static const Color surfaceCardLight = lightSurface; // #FFFFFF
  static const Color surfaceCardDark = darkSurface;   // #1C1D22
  static const Color borderColorLight = lightStroke;  // #18181B
  static const Color borderColorDark = darkStroke;    // #383A42
  static const Color shadowColorLight = Color(0xFF18181B);
  static const Color shadowColorDark = Color(0xA6000000); // rgba(0, 0, 0, 0.65)
  static const Color textPrimaryLight = lightInk;     // #18181B
  static const Color textPrimaryDark = darkInk;       // #F4F4F5
  static const Color textSecondaryLight = lightSecondaryText; // #52525B
  static const Color textSecondaryDark = darkSecondaryText;   // #A1A1AA
  static const Color brandPink = lightPink;           // #FF3384
  static const Color brandPinkText = lightWhite;      // #FFFFFF
  static const Color badgeWristBgLight = lightBadgeWristBg; // #BAE6FD
  static const Color badgeWristBgDark = darkBadgeWristBg;   // #1E3A5F
  static const Color badgeWristTxtLight = lightBadgeWristText; // #0369A1
  static const Color badgeWristTxtDark = darkBadgeWristText;   // #93C5FD
  static const Color badgeAnkleBgLight = lightBadgeAnkleBg;   // #E2F952
  static const Color badgeAnkleBgDark = darkBadgeAnkleBg;     // #2A3A12
  static const Color badgeAnkleTxtLight = lightBadgeAnkleText; // #3F6212
  static const Color badgeAnkleTxtDark = darkBadgeAnkleText;   // #BEF264
  static const Color liveTelemetryCard = liveTelemetry;        // #18181B
  static const Color dangerBgLight = lightDangerBg;   // #FEF2F2
  static const Color dangerBgDark = darkDangerBg;     // #2C1517
  static const Color dangerTextLight = lightDangerText; // #DC2626
  static const Color dangerTextDark = darkDangerText;   // #F87171

  // ── Bento Design System Aliases ──
  static const Color accentPink = lightPink; // #FF3384
  static const Color accentLime = Color(0xFFD6F865); // Success / Connected
  static const Color accentSkyBlue = Color(0xFFBAE6FD); // Info / Data
  static const Color accentSoftYellow = Color(0xFFFEF08A); // Warning / Notice
  static const Color accentDanger = Color(0xFFF87171); // Danger / Error
  static const Color lightCanvas = lightBackground;
  static const Color darkCanvas = darkBackground;
  static const Color lightCardSurface = lightSurface;
  static const Color darkCardSurface = darkSurface;
  static const Color lightBorder = lightStroke;
  static const Color darkBorder = darkStroke;
  static const Color lightTextPrimary = lightInk;
  static const Color darkTextPrimary = darkInk;
  static const Color lightTextSecondary = lightSecondaryText;
  static const Color darkTextSecondary = darkSecondaryText;

  // ── Semantic Color Helpers ──

  /// Returns the canvas/background color for the given brightness.
  static Color background(Brightness brightness) =>
      brightness == Brightness.light ? lightBackground : darkBackground;
  static Color canvasBg(Brightness brightness) => background(brightness);

  /// Returns the surface/card color for the given brightness. Never pure #000000 in dark mode (#1C1D22).
  static Color surface(Brightness brightness) =>
      brightness == Brightness.light ? lightSurface : darkSurface;
  static Color surfaceCard(Brightness brightness) => surface(brightness);

  /// Returns the primary text/ink color for the given brightness.
  static Color ink(Brightness brightness) =>
      brightness == Brightness.light ? lightInk : darkInk;
  static Color textPrimary(Brightness brightness) => ink(brightness);

  /// Returns the secondary text color for the given brightness.
  static Color secondaryText(Brightness brightness) =>
      brightness == Brightness.light ? lightSecondaryText : darkSecondaryText;
  static Color textSecondary(Brightness brightness) => secondaryText(brightness);

  /// Returns the stroke/border color for the given brightness (2px #18181B in light, #383A42 in dark).
  static Color borderColor(Brightness brightness) =>
      brightness == Brightness.light ? lightStroke : darkStroke;

  /// Returns the hard shadow color (Pitch Dark #18181B in light, rgba(0,0,0,0.65) in dark).
  static Color shadowColor(Brightness brightness) =>
      brightness == Brightness.light ? shadowColorLight : shadowColorDark;

  /// Returns the primary accent (pink) for the given brightness.
  static Color primaryAccent(Brightness brightness) =>
      brightness == Brightness.light ? lightPink : darkPink;

  /// Wrist badge background color.
  static Color badgeWristBg(Brightness brightness) =>
      brightness == Brightness.light ? lightBadgeWristBg : darkBadgeWristBg;

  /// Wrist badge text and glyph color.
  static Color badgeWristText(Brightness brightness) =>
      brightness == Brightness.light ? lightBadgeWristText : darkBadgeWristText;
  static Color badgeWristTxt(Brightness brightness) => badgeWristText(brightness);

  /// Ankle badge background color.
  static Color badgeAnkleBg(Brightness brightness) =>
      brightness == Brightness.light ? lightBadgeAnkleBg : darkBadgeAnkleBg;

  /// Ankle badge text and glyph color.
  static Color badgeAnkleText(Brightness brightness) =>
      brightness == Brightness.light ? lightBadgeAnkleText : darkBadgeAnkleText;
  static Color badgeAnkleTxt(Brightness brightness) => badgeAnkleText(brightness);

  /// Danger background color.
  static Color dangerBg(Brightness brightness) =>
      brightness == Brightness.light ? lightDangerBg : darkDangerBg;

  /// Danger text color.
  static Color dangerText(Brightness brightness) =>
      brightness == Brightness.light ? lightDangerText : darkDangerText;

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

  /// Surface outline / border stroke — #18181B on light, #383A42 on dark.
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

  Color get canvasBg => AppColors.canvasBg(Theme.of(this).brightness);
  Color get surfaceCard => AppColors.surfaceCard(Theme.of(this).brightness);
  Color get borderColor => AppColors.borderColor(Theme.of(this).brightness);
  Color get shadowColor => AppColors.shadowColor(Theme.of(this).brightness);
  Color get textPrimary => AppColors.textPrimary(Theme.of(this).brightness);
  Color get textSecondary => AppColors.textSecondary(Theme.of(this).brightness);
  Color get brandPink => AppColors.brandPink;
  Color get brandPinkText => AppColors.brandPinkText;
  Color get badgeWristBg => AppColors.badgeWristBg(Theme.of(this).brightness);
  Color get badgeWristText => AppColors.badgeWristText(Theme.of(this).brightness);
  Color get badgeAnkleBg => AppColors.badgeAnkleBg(Theme.of(this).brightness);
  Color get badgeAnkleText => AppColors.badgeAnkleText(Theme.of(this).brightness);
  Color get liveTelemetry => AppColors.liveTelemetry;
  Color get dangerBg => AppColors.dangerBg(Theme.of(this).brightness);
  Color get dangerText => AppColors.dangerText(Theme.of(this).brightness);

  Color get connected => AppColors.connected(Theme.of(this).brightness);
  Color get disconnected => AppColors.disconnected(Theme.of(this).brightness);
  Color get connecting => AppColors.connecting(Theme.of(this).brightness);
  Color get recording => AppColors.recording(Theme.of(this).brightness);
  Color get modelReady => AppColors.modelReady(Theme.of(this).brightness);
  Color get modelUnavailable => AppColors.modelUnavailable(Theme.of(this).brightness);
}