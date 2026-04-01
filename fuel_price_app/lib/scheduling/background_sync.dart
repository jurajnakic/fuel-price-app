import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/config_repository.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/data/services/eia_service.dart';
import 'package:fuel_price_app/data/services/hnb_service.dart';
import 'package:fuel_price_app/data/services/oil_price_api_service.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';
import 'package:fuel_price_app/data/services/yahoo_finance_service.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/domain/price_blender.dart';
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

      final today = DateTime.now();

      // 3b. Fetch EIA spot prices
      final eia = EiaService(apiKey: params.eiaApiKey);
      final eiaSeriesIds = params.eiaSymbols.values.toSet();
      for (final seriesId in eiaSeriesIds) {
        try {
          final eiaPrices = await eia.fetchSpotPrices(seriesId, days: 60);
          for (final p in eiaPrices) {
            await priceRepo.saveOilPrice(OilPrice(
              date: p.date, cifMed: p.value, source: seriesId,
            ));
          }
        } catch (_) {
          // Non-critical — continue with other sources
        }
      }

      // 3c. Fetch OilPriceAPI prices (rate-limited: every 2 days)
      final prefs = await SharedPreferences.getInstance();
      final lastOilApiFetch = prefs.getString('oilapi_last_fetch');
      final shouldFetchOilApi = lastOilApiFetch == null ||
          today.difference(DateTime.tryParse(lastOilApiFetch) ?? today).inHours >= 48;

      if (shouldFetchOilApi) {
        final oilApi = OilPriceApiService(apiKey: params.oilPriceApiKey);
        for (final code in params.oilApiSymbols.values.toSet()) {
          try {
            final price = await oilApi.fetchLatestPrice(code);
            if (price != null) {
              await priceRepo.saveOilPrice(OilPrice(
                date: price.date, cifMed: price.value, source: code,
              ));
            }
          } catch (_) {}
        }
        await prefs.setString('oilapi_last_fetch', today.toIso8601String());
      }

      // 4. Fetch exchange rates from HNB (historical + latest)
      final hnb = HnbService();
      final historicalRates = await hnb.fetchHistoricalRates(60);
      for (final h in historicalRates) {
        await priceRepo.saveExchangeRate(ExchangeRate(date: h.date, usdEur: h.rate));
      }
      final usdEurRate = await hnb.fetchUsdEurRate();
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

      // Find exchange rate from before current period for "current" price
      final allRates = await priceRepo.getExchangeRates(days: 60);
      final ratesBeforePeriod = allRates.where((r) => r.date.isBefore(currentPeriodStart)).toList();
      final currentRate = ratesBeforePeriod.isNotEmpty ? ratesBeforePeriod.last.usdEur : usdEurRate;

      // Helper: filter prices to a 14-calendar-day window per NN 31/2025.
      List<OilPrice> windowFilter(List<OilPrice> prices, DateTime windowEnd) {
        final windowStart = windowEnd.subtract(Duration(days: cycle));
        return prices
            .where((p) => !p.date.isBefore(windowStart) && p.date.isBefore(windowEnd))
            .toList();
      }

      for (final fuelType in FuelType.values) {
        final weights = params.sourceWeights[fuelType.paramKey] ?? {'yahoo': 1.0};

        // Collect current + next period predictions
        final currentSourcePrices = <String, double>{};
        final nextSourcePrices = <String, double>{};

        // Helper: compute price for a source in a given window
        // cifMed = raw × factor + offset
        double? computeSource(List<OilPrice> prices, double factor, double offset, DateTime windowEnd, double rate, {int minPoints = 5}) {
          final window = windowFilter(prices, windowEnd);
          if (window.length < minPoints) return null;
          final cif = window.map((p) => p.cifMed * factor + offset).toList();
          final rates = List.filled(cif.length, rate);
          return engine.predictPrice(fuelType, cif, rates);
        }

        // Yahoo
        final yahooSymbol = params.yahooSymbols[fuelType.paramKey] ?? 'BZ=F';
        final yahooFactor = params.cifMedFactors[fuelType.paramKey] ?? 369.0;
        final yahooOffset = params.cifMedOffsets[fuelType.paramKey] ?? 0.0;
        final symbolPrices = await priceRepo.getOilPrices(yahooSymbol, days: 60);

        if (symbolPrices.isNotEmpty) {
          final yc = computeSource(symbolPrices, yahooFactor, yahooOffset, currentPeriodStart, currentRate);
          if (yc != null) currentSourcePrices['yahoo'] = yc;
          final yn = computeSource(symbolPrices, yahooFactor, yahooOffset, nextChange, usdEurRate);
          if (yn != null) nextSourcePrices['yahoo'] = yn;
        }

        // EIA
        final eiaSymbol = params.eiaSymbols[fuelType.paramKey];
        final eiaFactor = params.eiaCifMedFactors[fuelType.paramKey];
        final eiaOffset = params.eiaCifMedOffsets[fuelType.paramKey] ?? 0.0;
        if (eiaSymbol != null && eiaFactor != null) {
          final eiaPrices = await priceRepo.getOilPrices(eiaSymbol, days: 60);
          if (eiaPrices.isNotEmpty) {
            final ec = computeSource(eiaPrices, eiaFactor, eiaOffset, currentPeriodStart, currentRate);
            if (ec != null) currentSourcePrices['eia'] = ec;
            final en = computeSource(eiaPrices, eiaFactor, eiaOffset, nextChange, usdEurRate);
            if (en != null) nextSourcePrices['eia'] = en;
          }
        }

        // OilPriceAPI
        final oilApiSymbol = params.oilApiSymbols[fuelType.paramKey];
        final oilApiFactor = params.oilApiCifMedFactors[fuelType.paramKey];
        if (oilApiSymbol != null && oilApiFactor != null) {
          final oilApiPrices = await priceRepo.getOilPrices(oilApiSymbol, days: 60);
          if (oilApiPrices.isNotEmpty) {
            final oc = computeSource(oilApiPrices, oilApiFactor, 0.0, currentPeriodStart, currentRate, minPoints: 1);
            if (oc != null) currentSourcePrices['oilapi'] = oc;
            final on_ = computeSource(oilApiPrices, oilApiFactor, 0.0, nextChange, usdEurRate, minPoints: 1);
            if (on_ != null) nextSourcePrices['oilapi'] = on_;
          }
        }

        // Blend and save
        final currentBlended = PriceBlender.blend(currentSourcePrices, weights);
        if (currentBlended != null) {
          await priceRepo.saveFuelPrice(FuelPrice(
            fuelType: fuelType, date: currentPeriodStart,
            price: FormulaEngine.roundPrice(currentBlended), isPrediction: false,
          ));
        }

        final predictedBlended = PriceBlender.blend(nextSourcePrices, weights);
        if (predictedBlended != null) {
          predictions[fuelType] = FormulaEngine.roundPrice(predictedBlended);
          await priceRepo.saveFuelPrice(FuelPrice(
            fuelType: fuelType, date: nextChange,
            price: FormulaEngine.roundPrice(predictedBlended), isPrediction: true,
          ));
        }
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
            if (!predictions.containsKey(fuelType)) continue;

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
