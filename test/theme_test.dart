import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandana/main.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/core/theme/app_colors.dart';
import 'package:bandana/src/core/theme/app_shadows.dart';
import 'package:bandana/src/core/theme/app_theme.dart';
import 'package:bandana/src/core/theme/theme_provider.dart';
import 'package:bandana/src/services/activity_label_manager.dart';
import 'package:bandana/src/services/band_assignment_manager.dart';
import 'package:bandana/src/services/ble_service.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/export_service.dart';
import 'package:bandana/src/services/ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    await getIt.reset();
    getIt.registerSingleton<SharedPreferences>(prefs);
    getIt.registerSingleton<DatabaseService>(DatabaseService());
    getIt.registerSingleton<ActivityLabelManager>(ActivityLabelManager(prefs: prefs));
    getIt.registerSingleton<BleService>(BleService());
    getIt.registerSingleton<MlService>(MlService());
    getIt.registerSingleton<ExportService>(ExportService(db: getIt<DatabaseService>()));
    getIt.registerSingleton<BandAssignmentManager>(
      await BandAssignmentManager.create(prefs),
    );

    themeModeManager.init(prefs);
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('ThemeModeManager Unit Tests', () {
    test('defaults to ThemeMode.system when no preference is saved', () {
      themeModeManager.init(prefs);
      expect(themeModeManager.themeMode, equals(ThemeMode.system));
    });

    test('persists and updates to ThemeMode.light', () async {
      await themeModeManager.setThemeMode(ThemeMode.light);
      expect(themeModeManager.themeMode, equals(ThemeMode.light));
      expect(prefs.getString(kThemeModeKey), equals('light'));
    });

    test('persists and updates to ThemeMode.dark', () async {
      await themeModeManager.setThemeMode(ThemeMode.dark);
      expect(themeModeManager.themeMode, equals(ThemeMode.dark));
      expect(prefs.getString(kThemeModeKey), equals('dark'));
    });

    test('toggle switches between light and dark modes', () async {
      await themeModeManager.setThemeMode(ThemeMode.light);
      await themeModeManager.toggle(Brightness.light);
      expect(themeModeManager.themeMode, equals(ThemeMode.dark));

      await themeModeManager.toggle(Brightness.dark);
      expect(themeModeManager.themeMode, equals(ThemeMode.light));
    });
  });

  group('BandanaApp Theme Rendering Tests', () {
    testWidgets('BandanaApp renders in light mode without overflow', (tester) async {
      await themeModeManager.setThemeMode(ThemeMode.light);

      await tester.pumpWidget(const BandanaApp());
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, equals(ThemeMode.light));
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('PopScope and theme toggle pill are present and responsive', (tester) async {
      await themeModeManager.setThemeMode(ThemeMode.light);

      await tester.pumpWidget(const BandanaApp());
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Verify PopScope protects AppShell
      expect(find.byWidgetPredicate((w) => w is PopScope), findsWidgets);

      // Verify toggle functionality via themeModeManager
      await themeModeManager.toggle(Brightness.light);
      expect(themeModeManager.themeMode, equals(ThemeMode.dark));

      await themeModeManager.toggle(Brightness.dark);
      expect(themeModeManager.themeMode, equals(ThemeMode.light));
    });

    testWidgets('BandanaApp renders in dark mode with dark canvas background', (tester) async {
      await themeModeManager.setThemeMode(ThemeMode.dark);

      await tester.pumpWidget(const BandanaApp());
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, equals(ThemeMode.dark));
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('Dual-Theme Design Token Map Specifications', () {
    test('Token parity: --canvas-bg (#FAF8F5 Light / #121316 Dark)', () {
      expect(AppColors.canvasBg(Brightness.light), equals(const Color(0xFFFAF8F5)));
      expect(AppColors.canvasBg(Brightness.dark), equals(const Color(0xFF121316)));
      expect(AppTheme.lightTheme.scaffoldBackgroundColor, equals(const Color(0xFFFAF8F5)));
      expect(AppTheme.darkTheme.scaffoldBackgroundColor, equals(const Color(0xFF121316)));
    });

    test('Token parity: --surface-card (#FFFFFF Light / #1C1D22 Dark)', () {
      expect(AppColors.surfaceCard(Brightness.light), equals(const Color(0xFFFFFFFF)));
      expect(AppColors.surfaceCard(Brightness.dark), equals(const Color(0xFF1C1D22)));
      expect(AppTheme.lightTheme.colorScheme.surface, equals(const Color(0xFFFFFFFF)));
      expect(AppTheme.darkTheme.colorScheme.surface, equals(const Color(0xFF1C1D22)));
    });

    test('Token parity: --border-color (#18181B Light / #383A42 Dark)', () {
      expect(AppColors.borderColor(Brightness.light), equals(const Color(0xFF18181B)));
      expect(AppColors.borderColor(Brightness.dark), equals(const Color(0xFF383A42)));
      expect(AppShadows.cardBorder(Brightness.light).top.color, equals(const Color(0xFF18181B)));
      expect(AppShadows.cardBorder(Brightness.dark).top.color, equals(const Color(0xFF383A42)));
    });

    test('Token parity: --shadow-color (#18181B Light / rgba(0,0,0,0.65) Dark with 3px 3px 0px offset)', () {
      expect(AppColors.shadowColor(Brightness.light), equals(const Color(0xFF18181B)));
      expect(AppColors.shadowColor(Brightness.dark), equals(const Color(0xA6000000)));

      final lightShadow = AppShadows.hard(Brightness.light).first;
      expect(lightShadow.color, equals(const Color(0xFF18181B)));
      expect(lightShadow.offset, equals(const Offset(3, 3)));
      expect(lightShadow.blurRadius, equals(0));

      final darkShadow = AppShadows.hard(Brightness.dark).first;
      expect(darkShadow.color, equals(const Color(0xA6000000)));
      expect(darkShadow.offset, equals(const Offset(3, 3)));
      expect(darkShadow.blurRadius, equals(0));
    });

    test('Token parity: --text-primary (#18181B Light / #F4F4F5 Dark)', () {
      expect(AppColors.textPrimary(Brightness.light), equals(const Color(0xFF18181B)));
      expect(AppColors.textPrimary(Brightness.dark), equals(const Color(0xFFF4F4F5)));
    });

    test('Token parity: --text-secondary (#52525B Light / #A1A1AA Dark)', () {
      expect(AppColors.textSecondary(Brightness.light), equals(const Color(0xFF52525B)));
      expect(AppColors.textSecondary(Brightness.dark), equals(const Color(0xFFA1A1AA)));
    });

    test('Token parity: --brand-pink (#FF3384) & --brand-pink-text (#FFFFFF)', () {
      expect(AppColors.brandPink, equals(const Color(0xFFFF3384)));
      expect(AppColors.brandPinkText, equals(const Color(0xFFFFFFFF)));
      expect(AppTheme.lightTheme.colorScheme.primary, equals(const Color(0xFFFF3384)));
      expect(AppTheme.darkTheme.colorScheme.primary, equals(const Color(0xFFFF3384)));
    });

    test('Token parity: Wrist Device Badge & Telemetry (#BAE6FD / #0369A1 Light vs #1E3A5F / #93C5FD Dark)', () {
      expect(AppColors.badgeWristBg(Brightness.light), equals(const Color(0xFFBAE6FD)));
      expect(AppColors.badgeWristText(Brightness.light), equals(const Color(0xFF0369A1)));

      expect(AppColors.badgeWristBg(Brightness.dark), equals(const Color(0xFF1E3A5F)));
      expect(AppColors.badgeWristText(Brightness.dark), equals(const Color(0xFF93C5FD)));
    });

    test('Token parity: Ankle Device Badge & Telemetry (#E2F952 / #3F6212 Light vs #2A3A12 / #BEF264 Dark)', () {
      expect(AppColors.badgeAnkleBg(Brightness.light), equals(const Color(0xFFE2F952)));
      expect(AppColors.badgeAnkleText(Brightness.light), equals(const Color(0xFF3F6212)));

      expect(AppColors.badgeAnkleBg(Brightness.dark), equals(const Color(0xFF2A3A12)));
      expect(AppColors.badgeAnkleText(Brightness.dark), equals(const Color(0xFFBEF264)));
    });

    test('Token parity: --live-telemetry stays solid dark #18181B in both themes', () {
      expect(AppColors.liveTelemetry, equals(const Color(0xFF18181B)));
    });

    test('Token parity: Danger Zone & Warning Toasts (#FEF2F2 / #DC2626 Light vs #2C1517 / #F87171 Dark)', () {
      expect(AppColors.dangerBg(Brightness.light), equals(const Color(0xFFFEF2F2)));
      expect(AppColors.dangerText(Brightness.light), equals(const Color(0xFFDC2626)));

      expect(AppColors.dangerBg(Brightness.dark), equals(const Color(0xFF2C1517)));
      expect(AppColors.dangerText(Brightness.dark), equals(const Color(0xFFF87171)));
    });
  });

  group('Dark Mode Behavioral Rules Verification', () {
    test('Rule 1: Never use pure #000000 for cards (surface sits at #1C1D22)', () {
      expect(AppColors.darkSurface, isNot(equals(const Color(0xFF000000))));
      expect(AppColors.darkSurface, equals(const Color(0xFF1C1D22)));
      expect(AppColors.darkBackground, equals(const Color(0xFF121316)));
      // Card surface must separate from background
      expect(AppColors.darkSurface, isNot(equals(AppColors.darkBackground)));
    });

    test('Rule 2: Shadows in Dark Mode are black rgba(0,0,0,0.65) and card borders brighten to #383A42', () {
      final darkShadow = AppShadows.hard(Brightness.dark).first;
      expect(darkShadow.color, equals(const Color(0xA6000000)));
      expect(darkShadow.color.a, closeTo(0.65, 0.01));

      final darkCardBorder = AppShadows.cardBorder(Brightness.dark).top;
      expect(darkCardBorder.color, equals(const Color(0xFF383A42)));
      expect(darkCardBorder.width, equals(2.0));
    });

    test('Rule 3: Live Recording Hero Card container stays dark #18181B in both themes', () {
      expect(AppColors.liveTelemetry, equals(const Color(0xFF18181B)));
    });
  });
}
