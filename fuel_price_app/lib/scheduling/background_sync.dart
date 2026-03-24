import 'package:workmanager/workmanager.dart';
import 'package:fuel_price_app/scheduling/schedule_helper.dart';

const dailySyncTaskName = 'dailyFuelPriceSync';

/// Initialize WorkManager for background data fetch at 18:00 CET.
Future<void> initBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  final delay = initialFetchDelay(DateTime.now().toUtc());

  await Workmanager().registerPeriodicTask(
    dailySyncTaskName,
    dailySyncTaskName,
    initialDelay: delay,
    frequency: const Duration(hours: 24),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

/// Top-level callback for WorkManager — must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == dailySyncTaskName) {
      // In a real implementation, this would:
      // 1. Initialize database
      // 2. Fetch data from Yahoo Finance + HNB
      // 3. Save to SQLite
      // 4. Recalculate predictions
      // 5. Show notification if it's a notification day
      //
      // For now, return true to indicate success.
      // Full implementation requires isolate-safe DI setup.
      return true;
    }
    return false;
  });
}
