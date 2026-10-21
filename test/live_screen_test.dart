import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/features/live/live_screen.dart';
import 'package:bandana/src/services/activity_label_manager.dart';
import 'package:bandana/src/services/ble_service.dart';
import 'package:bandana/src/services/database_service.dart';
import 'package:bandana/src/services/ml_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;
  late ActivityLabelManager labelManager;
  late BleService ble;
  late MlService ml;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
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
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  testWidgets('LiveScreen displays educational preview bento card and record CTA when 0 sessions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiveScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // App bar title & split device pill
    expect(find.text('Live Recognition'), findsOneWidget);
    expect(find.text('Wrist'), findsOneWidget);
    expect(find.text('Ankle'), findsOneWidget);

    // Hero Preview Bento Card
    expect(find.text('PREVIEW MODE'), findsOneWidget);
    expect(find.text('Walking • 1.2 m/s'), findsOneWidget);
    expect(find.text('98.4% Confidence'), findsOneWidget);
    expect(find.text('SIMULATED 6-AXIS IMU STREAM (50Hz)'), findsOneWidget);

    // Onboarding Guide Block
    expect(find.text('Ready to analyze your movement?'), findsOneWidget);
    expect(find.text('Collect motion data from your bands to train your personal AI recognition model.'), findsOneWidget);
    expect(find.text('Bands Connected'), findsOneWidget);
    expect(find.text('Baseline Data'), findsOneWidget);
    expect(find.text('At least 1 recorded session needed'), findsOneWidget);

    // Action CTAs for 0 sessions
    expect(find.text('Record First Session'), findsOneWidget);
    expect(find.text('Manage & Train Models'), findsOneWidget);
  });

  testWidgets('LiveScreen displays Train Movement Model CTA when sessions exist but model untrained', (tester) async {
    // Insert a dummy session into database
    final sessionId = await db.createSession('Walking');
    await db.endSession(sessionId, 100);

    await tester.pumpWidget(
      const MaterialApp(
        home: LiveScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Train Movement Model'), findsOneWidget);
    expect(find.text('Record Another Session'), findsOneWidget);
    expect(find.text('1 recorded session ready'), findsOneWidget);
  });

  testWidgets('LiveScreen displays hero card and single status bar when model is trained', (tester) async {
    // Train a minimal single band model in ML service
    final trainingData = [
      (features: List.filled(30, 1.0), label: 'Walking'),
      (features: List.filled(30, 1.1), label: 'Walking'),
      (features: List.filled(30, 5.0), label: 'Running'),
      (features: List.filled(30, 5.1), label: 'Running'),
    ];
    await ml.trainSingleBand(trainingData);

    await tester.pumpWidget(
      const MaterialApp(
        home: LiveScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('30-feat Single Model'), findsOneWidget);
    expect(find.text('Ready for Live Recognition'), findsOneWidget);
    expect(find.text('Start Recognition'), findsOneWidget);
    expect(find.text('Prediction Timeline'), findsOneWidget);
  });
}
