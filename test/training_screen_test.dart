import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/features/training/training_screen.dart';
import 'package:bandana/src/services/activity_label_manager.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late MlService ml;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);

    db = DatabaseService.withExecutor(NativeDatabase.memory());
    getIt.registerSingleton<DatabaseService>(db);

    final labelManager = ActivityLabelManager(prefs: prefs);
    getIt.registerSingleton<ActivityLabelManager>(labelManager);

    ml = MlService();
    await ml.initialize(prefs);
    getIt.registerSingleton<MlService>(ml);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  testWidgets('TrainingScreen renders config, algorithm choice, and empty session state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TrainingScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Active Models'), findsOneWidget);
    expect(find.text('Training Configuration'), findsOneWidget);
    expect(find.text('K-NN'), findsOneWidget);
    expect(find.text('Logistic Regression'), findsOneWidget);
    expect(find.text('Wrist (30)'), findsOneWidget);
    expect(find.text('Dual (60)'), findsOneWidget);
    expect(find.text('Dataset Readiness'), findsOneWidget);
    expect(find.text('Train Model'), findsOneWidget);
  });

  testWidgets('TrainingScreen displays sessions when available', (tester) async {
    final s1 = await db.createSession('Walking', participantId: 'p1');
    final s2 = await db.createSession('Running', participantId: 'p1');

    await tester.pumpWidget(
      const MaterialApp(
        home: TrainingScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Session #$s1: Walking'), findsOneWidget);
    expect(find.text('Session #$s2: Running'), findsOneWidget);
  });
}
