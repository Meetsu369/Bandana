import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/activity_label_manager.dart';
import '../../services/band_assignment_manager.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/export_service.dart';
import '../../services/laptop_training_service.dart';
import '../../services/ml_service.dart';
import '../theme/theme_provider.dart';

/// Global service locator instance.
final getIt = GetIt.instance;

/// Register all singleton services.
/// Must be called before [runApp].
Future<void> setupServiceLocator() async {
  // SharedPreferences for device assignment persistence
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // Initialize theme mode manager
  themeModeManager.init(prefs);

  // Initialize band assignment manager
  final assignmentManager = await BandAssignmentManager.create(prefs);
  getIt.registerSingleton<BandAssignmentManager>(assignmentManager);

  // Database – initialise first since other services may depend on it.
  final db = DatabaseService();
  getIt.registerSingleton<DatabaseService>(db);

  // Export & Sharing
  final exportService = ExportService(db: db);
  getIt.registerSingleton<ExportService>(exportService);

  // BLE
  getIt.registerLazySingleton<BleService>(() => BleService());

  // Activity Labels
  final labelManager = ActivityLabelManager(prefs: prefs);
  getIt.registerSingleton<ActivityLabelManager>(labelManager);

  // ML
  final ml = MlService();
  await ml.initialize(prefs);
  getIt.registerSingleton<MlService>(ml);

  // Laptop-Assisted Training Service
  final laptopTraining = LaptopTrainingService(ml: ml, prefs: prefs);
  getIt.registerSingleton<LaptopTrainingService>(laptopTraining);
}
