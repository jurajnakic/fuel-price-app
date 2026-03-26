import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/config_repository.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/data/services/hnb_service.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';
import 'package:fuel_price_app/data/services/yahoo_finance_service.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/models/exchange_rate.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/oil_price.dart';
import 'package:fuel_price_app/notifications/notification_service.dart';
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
    if (task != dailySyncTaskName) return false;

    try {
      // 1. Initialize database (isolate-safe — creates new instance)
      final db = AppDatabase();
      await db.init();

      final priceRepo = PriceRepository(db);
      final settingsRepo = SettingsRepository(db);
      final configRepo = ConfigRepository(db, RemoteConfigService());

      // 2. Sync remote config — update params if version changed
      final updatedParams = await configRepo.syncConfig();
      final params = updatedParams ?? FuelParams.defaultParams;

      // 3. Fetch oil prices from Yahoo Finance (Brent — BZ=F)
      final yahoo = YahooFinanceService();
      final brentPrices = await yahoo.fetchHistoricalPrices('BZ=F', 30);

      // Save to DB
      for (final p in brentPrices) {
        await priceRepo.saveOilPrice(OilPrice(
          date: p.date,
          cifMed: p.close,
          source: 'BZ=F',
        ));
      }

      // 4. Fetch exchange rates from HNB
      final hnb = HnbService();
      final usdEurRate = await hnb.fetchUsdEurRate();
      final today = DateTime.now();
      await priceRepo.saveExchangeRate(ExchangeRate(
        date: today,
        usdEur: usdEurRate,
      ));

      // 5. Calculate predictions for each fuel type
      // Use the last 14 days of Brent prices and current exchange rate
      final recentBrent = brentPrices.length > 14
          ? brentPrices.sublist(brentPrices.length - 14)
          : brentPrices;

      if (recentBrent.isEmpty) {
        await db.close();
        return true; // No data to calculate, but sync succeeded
      }

      final cifValues = recentBrent.map((p) => p.close).toList();
      final rateValues = List.filled(cifValues.length, usdEurRate);

      final engine = FormulaEngine(params);
      final predictions = <FuelType, double>{};

      for (final fuelType in FuelType.values) {
        final predicted = engine.predictPrice(fuelType, cifValues, rateValues);
        predictions[fuelType] = predicted;

        await priceRepo.saveFuelPrice(FuelPrice(
          fuelType: fuelType,
          date: today,
          price: predicted,
          isPrediction: true,
        ));
      }

      // 6. Check notification settings and send if enabled
      final notifSettings = await settingsRepo.getNotificationSettings();
      final notifEnabled = (notifSettings['enabled'] as int) == 1;

      if (notifEnabled) {
        final notifDay = notifSettings['day'] as String;
        final todayWeekday = today.weekday; // 1=Mon, 6=Sat, 7=Sun

        final shouldNotify = (notifDay == 'monday' && todayWeekday == DateTime.monday) ||
            (notifDay == 'sunday' && todayWeekday == DateTime.sunday) ||
            (notifDay == 'saturday' && todayWeekday == DateTime.saturday);

        if (shouldNotify) {
          // Check which fuels are enabled for notifications
          final notifFuels = await settingsRepo.getNotificationFuels();

          final fuelPredictions =
              <FuelType, ({double predicted, double? current})>{};

          for (final fuelType in FuelType.values) {
            if (notifFuels[fuelType.name] != true) continue;

            final currentPrice =
                await priceRepo.getLatestPrice(fuelType, prediction: false);
            fuelPredictions[fuelType] = (
              predicted: predictions[fuelType]!,
              current: currentPrice?.price,
            );
          }

          final notificationService = NotificationService();
          await notificationService.init();
          await notificationService.showPriceNotification(
            notificationDay: notifDay,
            fuelPredictions: fuelPredictions,
          );
        }
      }

      // 7. Clean old data (keep last 400 days)
      await priceRepo.cleanOldData(const Duration(days: 400));

      await db.close();
      return true;
    } catch (_) {
      return false;
    }
  });
}
