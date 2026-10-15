import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bandana/src/core/di/service_locator.dart';
import 'package:bandana/src/features/record/record_screen.dart';
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

  testWidgets('RecordScreen renders pre-recording setup with Bento tokens, unnested inputs, and device strip', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: RecordScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // App bar title & split device connectivity badge
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Wrist'), findsOneWidget);
    expect(find.text('Ankle'), findsOneWidget);

    // Direct canvas inputs
    expect(find.text('Participant ID'), findsOneWidget);
    final participantField = tester.widget<TextField>(find.byType(TextField).first);
    expect(participantField.controller?.text, anyOf('test_1', 'participant_1'));
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('+ Custom Activity'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.text('Session Notes (Optional)'), findsOneWidget);

    // 2-column device connection summary strip
    expect(find.text('Wrist Band'), findsOneWidget);
    expect(find.text('Ankle Band'), findsOneWidget);
    expect(find.text('Offline'), findsNWidgets(2));

    // Start Recording CTA & micro-caption
    expect(find.text('Connect at least one band to start recording.'), findsOneWidget);
    expect(find.text('Start Recording'), findsOneWidget);
  });

  testWidgets('RecordScreen live recording renders Bento hero card, split telemetry streams, waveform canvas, and stop button without overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Simulate connecting wrist band
    ble.wrist.updateStateForTesting(BandConnectionState.connected);

    await tester.pumpWidget(
      const MaterialApp(
        home: RecordScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify micro-caption is gone and band is ready
    expect(find.text('Connect at least one band to start recording.'), findsNothing);
    expect(find.text('Connected (Ready)'), findsOneWidget);

    // Tap Start Recording
    await tester.tap(find.text('Start Recording'));
    await tester.pumpAndSettle();

    // Verify Section B: Live Recording Hero Telemetry Card
    expect(find.text('REC'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.textContaining('Session #'), findsOneWidget);

    // Verify Section B: Split Telemetry Stream Bento
    expect(find.text('⌚ Wrist Band'), findsOneWidget);
    expect(find.text('🏃 Ankle Band'), findsOneWidget);

    // Verify Section B: Dual-Band Live Graph Waveforms with all 6 axes
    expect(find.text('6-AXIS REAL-TIME IMU STREAM'), findsNWidgets(2));
    expect(find.text('aX'), findsNWidgets(2));
    expect(find.text('aY'), findsNWidgets(2));
    expect(find.text('aZ'), findsNWidgets(2));
    expect(find.text('gX'), findsNWidgets(2));
    expect(find.text('gY'), findsNWidgets(2));
    expect(find.text('gZ'), findsNWidgets(2));

    // Verify Section B: Stop Action Button
    expect(find.text('Stop Recording'), findsOneWidget);

    // Tap Stop Recording
    await tester.tap(find.text('Stop Recording'));
    await tester.pumpAndSettle();
  });

  testWidgets('RecordScreen setup on narrow mobile screen (360x640) with both bands connected renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    ble.wrist.updateStateForTesting(BandConnectionState.connected);
    ble.ankle.updateStateForTesting(BandConnectionState.connected);

    await tester.pumpWidget(
      const MaterialApp(
        home: RecordScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Connected (Ready)'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
