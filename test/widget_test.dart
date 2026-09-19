import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandana/main.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/ml_service.dart';
import 'package:bandana/src/services/ble_service.dart';
import 'package:bandana/src/services/band_assignment_manager.dart';

void main() {
  setUpAll(() async {
    // Initialize service locator for tests
    SharedPreferences.setMockInitialValues({});
    await setupServiceLocator();
    
    // Register test doubles for services that need special handling
    getIt.allowReassignment = true;
    getIt.registerSingleton<DatabaseService>(DatabaseService());
    getIt.registerSingleton<MlService>(MlService());
    getIt.registerSingleton<BleService>(BleService());
    getIt.registerSingleton<BandAssignmentManager>(
      await BandAssignmentManager.create(await SharedPreferences.getInstance()),
    );
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  testWidgets('App shell renders bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BandanaApp()));

    // Verify bottom navigation bar exists with all 4 destinations.
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
