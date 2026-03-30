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
import 'package:fuel_price_app/domain/price_cycle_service.dart';
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

      // 3. Fetch commodity prices from Yahoo Finance
      final yahoo = YahooFinanceService();
      final symbols = ['BZ=F', 'RB=F', 'HO=F'];
      final allPrices = await Future.wait(
        symbols.map((s) => yahoo.fetchHistoricalPrices(s, 400)),
      );

      // Save all symbols to DB with actual dates
      for (var si = 0; si < symbols.length; si++) {
        for (final p in allPrices[si]) {
          await priceRepo.saveOilPrice(OilPrice(
            date: p.date,
            cifMed: p.close,
            source: symbols[si],
          ));
        }
      }

      // 4. Fetch exchange rates from HNB
      final hnb = HnbService();
      final usdEurRate = await hnb.fetchUsdEurRate();
      final today = DateTime.now();
      await priceRepo.saveExchangeRate(ExchangeRate(
        date: today,
        usdEur: usdEurRate,
      ));

      // 5. Calculate current + predicted prices for each fuel type
      final engine = FormulaEngine(params);
      final predictions = <FuelType, double>{};
      final refDate = DateTime.parse(params.referenceDate);
      final cycle = params.cycleDays;
      final nextChange = nextPriceChangeDate(today, refDate, cycle);
      final currentPeriodStart = nextChange.subtract(Duration(days: cycle));

      for (final fuelType in FuelType.values) {
        final symbol = params.yahooSymbols[fuelType.paramKey] ?? 'BZ=F';
        final factor = params.cifMedFactors[fuelType.paramKey] ?? 402.4;

        final symbolPrices = await priceRepo.getOilPrices(symbol, days: 60);
        if (symbolPrices.isEmpty) continue;

        // Current period price (using prices before currentPeriodStart)
        final currentWindow = symbolPrices
            .where((p) => p.date.isBefore(currentPeriodStart))
            .toList();
        if (currentWindow.length >= 10) {
          final count = currentWindow.length < 14 ? currentWindow.length : 14;
          final window = currentWindow.reversed.take(count).toList().reversed.toList();
          final cifCurrent = window.map((p) => p.cifMed * factor).toList();
          final ratesCurrent = List.filled(cifCurrent.length, usdEurRate);
          final currentPrice = engine.predictPrice(fuelType, cifCurrent, ratesCurrent);
          await priceRepo.saveFuelPrice(FuelPrice(
            fuelType: fuelType, date: currentPeriodStart, price: currentPrice, isPrediction: false,
          ));
        }

        // Next period prediction (using most recent prices)
        final nextCount = symbolPrices.length < 14 ? symbolPrices.length : 14;
        final nextWindow = symbolPrices.reversed.take(nextCount).toList().reversed.toList();
        final cifNext = nextWindow.map((p) => p.cifMed * factor).toList();
        final ratesNext = List.filled(cifNext.length, usdEurRate);
        final predicted = engine.predictPrice(fuelType, cifNext, ratesNext);
        predictions[fuelType] = predicted;

        await priceRepo.saveFuelPrice(FuelPrice(
          fuelType: fuelType, date: nextChange, price: predicted, isPrediction: true,
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

      // 7. Clean old data (keep last 800 days for yearly charts)
      await priceRepo.cleanOldData(const Duration(days: 800));

      await db.close();
      return true;
    } catch (_) {
      return false;
    }
  });
}
