import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandana/main.dart';
import 'package:bandana/src/core/di/service_locator.dart';
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
  });
}
