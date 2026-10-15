import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/features/profile/profile_screen.dart';
import 'package:bandana/src/shared/widgets/buttons/primary_button.dart';
import 'package:bandana/src/services/activity_label_manager.dart';
import 'package:bandana/src/services/ble_service.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/export_service.dart';
import 'package:bandana/src/services/ml_service.dart';
import 'package:bandana/src/services/band_assignment_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late ActivityLabelManager labelManager;
  late BleService ble;
  late MlService ml;
  late ExportService exportService;
  late BandAssignmentManager assignmentManager;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({
      'bandana_participant_id': 'test_user_42',
      'bandana_participant_age': 28,
      'bandana_participant_height': 180.0,
      'bandana_participant_weight': 75.0,
      'bandana_goal_active_minutes': 45,
    });
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);

    db = DatabaseService.withExecutor(NativeDatabase.memory());
    getIt.registerSingleton<DatabaseService>(db);

    labelManager = ActivityLabelManager(prefs: prefs);
    getIt.registerSingleton<ActivityLabelManager>(labelManager);

    ble = BleService();
    getIt.registerSingleton<BleService>(ble);

    ml = MlService();
    await ml.initialize(prefs);
    getIt.registerSingleton<MlService>(ml);

    exportService = ExportService(db: db);
    getIt.registerSingleton<ExportService>(exportService);

    assignmentManager = await BandAssignmentManager.create(prefs);
    getIt.registerSingleton<BandAssignmentManager>(assignmentManager);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  testWidgets('ProfileScreen renders participant fields, metrics, and MET calories', (tester) async {
    // Insert a dummy session to verify calculation
    final sessionId = await db.createSession('Walking', participantId: 'test_user_42');
    final start = DateTime.now().subtract(const Duration(minutes: 30));
    final end = DateTime.now();
    await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        startTime: Value(start),
        endTime: Value(end),
      ),
    );

    // Set a large screen size so all widgets render without lazy list clipping
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify participant setup section
    expect(find.text('Fitness & Body'), findsOneWidget);
    expect(find.text('App Settings'), findsOneWidget);
    expect(find.text('Daily Movement Goal'), findsOneWidget);
    expect(find.text('Participant Demographics'), findsOneWidget);
    expect(find.text('test_user_42'), findsOneWidget);

    // Verify fitness metrics & MET estimation
    expect(find.text('Energy Expenditure Breakdown'), findsOneWidget);
    expect(find.textContaining('kcal'), findsWidgets);
    expect(find.textContaining('Scientific Disclaimer'), findsOneWidget);

    // Switch to Tab 2: App Settings and verify Google Drive
    await tester.tap(find.text('App Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Google Drive Sync'), findsOneWidget);
    expect(find.text('Continue with Google Drive'), findsOneWidget);
  });

  testWidgets('ProfileScreen allows updating participant details and persists to SharedPreferences', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Find participant field and enter new ID
    final participantFinder = find.widgetWithText(TextField, 'Participant ID');
    expect(participantFinder, findsOneWidget);

    await tester.enterText(participantFinder, 'dr_watson_01');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(PrimaryButton, 'Save Profile');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final prefs = getIt<SharedPreferences>();
    expect(prefs.getString('bandana_participant_id'), equals('dr_watson_01'));
  });

  testWidgets('ProfileScreen expands Developer & Custom API Settings accordion with security rule', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Tab 2: App Settings
    await tester.tap(find.text('App Settings'));
    await tester.pumpAndSettle();

    final devAccordion = find.text('Developer & Custom API Settings');
    expect(devAccordion, findsOneWidget);
    await tester.tap(devAccordion);
    await tester.pumpAndSettle();

    expect(find.text('Security & Credential Rule'), findsOneWidget);
    expect(find.textContaining('Client secrets must NEVER be embedded'), findsOneWidget);
  });
}
