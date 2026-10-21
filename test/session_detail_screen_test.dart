import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/features/record/session_detail_screen.dart';
import 'package:bandana/src/services/activity_label_manager.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late ExportService exportService;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);

    db = DatabaseService.withExecutor(NativeDatabase.memory());
    getIt.registerSingleton<DatabaseService>(db);

    exportService = ExportService(db: db);
    getIt.registerSingleton<ExportService>(exportService);

    final labelManager = ActivityLabelManager(prefs: prefs);
    getIt.registerSingleton<ActivityLabelManager>(labelManager);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  testWidgets('SessionDetailScreen renders Bento layout, notes auto-save, collapsible schema pills, and minimal delete button', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sessionId = await db.createSession('Walking', participantId: 'participant_x');
    await db.endSession(sessionId, 420);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailScreen(sessionId: sessionId),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Header & Auto-save pill
    expect(find.text('Session $sessionId'), findsOneWidget);
    expect(find.text('Saved ✓'), findsOneWidget);

    // 2. Top notes input
    expect(find.text('Session Notes'), findsOneWidget);
    expect(find.text('Add optional notes about this session...'), findsOneWidget);

    // 3. Session overview bento metrics
    expect(find.text('Session Overview'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.text('Total Samples'), findsOneWidget);
    expect(find.text('420'), findsOneWidget);

    // 4. Export Raw Data Card
    expect(find.text('Export Raw Data'), findsOneWidget);
    expect(find.text('Export Raw CSV'), findsOneWidget);
    expect(find.text('Preview Data Schema (16 Columns - Synchronized)'), findsOneWidget);

    // 5. Expand collapsible schema disclosure widget
    await tester.tap(find.text('Preview Data Schema (16 Columns - Synchronized)'));
    await tester.pumpAndSettle();

    // Verify discrete badge pills are rendered
    expect(find.text('timestamp_phone_ms'), findsOneWidget);
    expect(find.text('sensor_tick_ms'), findsOneWidget);
    expect(find.text('seq'), findsOneWidget);
    expect(find.text('wrist_ax'), findsOneWidget);
    expect(find.text('ankle_ax'), findsOneWidget);
    expect(find.text('activity'), findsOneWidget);

    // 6. De-escalated minimal Delete Session button
    expect(find.text('Delete Session'), findsOneWidget);

    // Tap Delete Session and verify confirmation dialog
    await tester.tap(find.text('Delete Session'));
    await tester.pumpAndSettle();

    expect(find.text('Delete session $sessionId (Walking)? This will permanently remove all associated raw samples and feature windows. Cannot be undone.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
