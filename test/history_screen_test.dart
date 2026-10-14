import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/features/history/history_screen.dart';
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

  testWidgets('HistoryScreen shows empty state when no sessions exist', (tester) async {
    var startRecordingTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          onStartRecording: () => startRecordingTapped = true,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('Start Recording'), findsOneWidget);

    await tester.tap(find.text('Start Recording'));
    expect(startRecordingTapped, isTrue);
  });

  testWidgets('HistoryScreen renders session cards when sessions exist', (tester) async {
    final s1 = await db.createSession('Walking', participantId: 'sumeet');
    await db.endSession(s1, 160);

    final s2 = await db.createSession('Running', participantId: 'sumeet');
    await db.endSession(s2, 320);

    await tester.pumpWidget(
      const MaterialApp(
        home: HistoryScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Walking'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('160 samples'), findsOneWidget);
    expect(find.text('320 samples'), findsOneWidget);
  });

  testWidgets('HistoryScreen supports multi-select mode', (tester) async {
    final s1 = await db.createSession('Walking', participantId: 'sumeet');
    await db.endSession(s1, 100);

    await tester.pumpWidget(
      const MaterialApp(
        home: HistoryScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Tap multi-select icon
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    expect(find.text('0 Selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);

    // Toggle checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('1 Selected'), findsOneWidget);
    expect(find.text('Share ZIP'), findsOneWidget);
  });
}
