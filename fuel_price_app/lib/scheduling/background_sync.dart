import 'package:workmanager/workmanager.dart';

import 'package:fuel_price_app/data/app_logger.dart';
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
import 'package:fuel_price_app/scheduling/sync_lock.dart';

const dailySyncTaskName = 'dailyFuelPriceSync';

/// Initialize WorkManager for background data fetch at the user's configured
/// notification hour (Zagreb local time). If the user changes the hour via
/// settings, call this again with [replace] to re-register.
Future<void> initBackgroundSync({int targetLocalHour = 9, bool replace = false}) async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  final delay = initialFetchDelay(DateTime.now().toUtc(), targetLocalHour: targetLocalHour);

  await Workmanager().registerPeriodicTask(
    dailySyncTaskName,
    dailySyncTaskName,
    initialDelay: delay,
    frequency: const Duration(hours: 24),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: replace ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
  );
}

/// Top-level callback for WorkManager — must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != dailySyncTaskName) return false;

    final startedAt = DateTime.now();
    AppLogger? logger;
    bool lockHeld = false;
    try {
      // 1. Initialize database (isolate-safe — creates new instance)
      final db = AppDatabase();
      await db.init();

      final priceRepo = PriceRepository(db);
      final settingsRepo = SettingsRepository(db);
      final configRepo = ConfigRepository(db, RemoteConfigService());
      logger = AppLogger(db);

      // Single-flight: bail if another sync (bg or fg) holds the lock. Prevents
      // the 3×-parallel-WM-fire flooding seen in earlier logs.
      lockHeld = await SyncLock.tryAcquire();
      if (!lockHeld) {
        await logger.log('bg_sync', 'SKIP another sync in progress');
        await db.close();
        return true;
      }

      await logger.log('bg_sync',
          'START task=$task weekday=${startedAt.weekday} hour=${startedAt.hour}:${startedAt.minute.toString().padLeft(2, '0')}');

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

      // 3c. Fetch OilPriceAPI prices (daily — free tier allows ~50 req/month)
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

      // All historical rates — used to pick per-date rate for each window point
      // per NN 31/2025 (fixed-rate produced ~1c mismatch vs foreground predictions).
      final allRates = await priceRepo.getExchangeRates(days: 60);

      // Find exchange rate closest to (but not after) [date]; falls back to nearest.
      double findRate(DateTime date) {
        final dateOnly = DateTime(date.year, date.month, date.day);
        ExchangeRate? best;
        for (final r in allRates) {
          final rDate = DateTime(r.date.year, r.date.month, r.date.day);
          if (!rDate.isAfter(dateOnly)) best = r;
        }
        return (best ?? (allRates.isNotEmpty ? allRates.last : null))?.usdEur ?? usdEurRate;
      }

      // Filter prices to the NN 31/2025 settlement window (Mon-Sun × 2 ending
      // the Sunday before publication Monday).
      List<OilPrice> windowFilter(List<OilPrice> prices, DateTime anchor) {
        final w = settlementWindow(anchor, cycle);
        return prices
            .where((p) => !p.date.isBefore(w.start) && p.date.isBefore(w.end))
            .toList();
      }

      for (final fuelType in FuelType.values) {
        final weights = params.sourceWeights[fuelType.paramKey] ?? {'yahoo': 1.0};

        // Collect current + next period predictions
        final currentSourcePrices = <String, double>{};
        final nextSourcePrices = <String, double>{};

        // Helper: compute price for a source in a given window
        // cifMed = raw × factor + offset; rates are per-date (NN 31/2025).
        double? computeSource(List<OilPrice> prices, double factor, double offset, DateTime windowEnd, {int minPoints = 5}) {
          final window = windowFilter(prices, windowEnd);
          if (window.length < minPoints) return null;
          final cif = window.map((p) => p.cifMed * factor + offset).toList();
          final rates = window.map((p) => findRate(p.date)).toList();
          return engine.predictPrice(fuelType, cif, rates);
        }

        // Yahoo
        // Fall back to defaultParams when remote config predates this fuel,
        // so we use calibrated values instead of magic numbers.
        final defaults = FuelParams.defaultParams;
        final yahooSymbol = params.yahooSymbols[fuelType.paramKey] ??
            defaults.yahooSymbols[fuelType.paramKey] ?? 'BZ=F';
        final yahooFactor = params.cifMedFactors[fuelType.paramKey] ??
            defaults.cifMedFactors[fuelType.paramKey] ?? 0.0;
        final yahooOffset = params.cifMedOffsets[fuelType.paramKey] ??
            defaults.cifMedOffsets[fuelType.paramKey] ?? 0.0;
        final symbolPrices = await priceRepo.getOilPrices(yahooSymbol, days: 60);

        if (symbolPrices.isNotEmpty) {
          final yc = computeSource(symbolPrices, yahooFactor, yahooOffset, currentPeriodStart);
          if (yc != null) currentSourcePrices['yahoo'] = yc;
          final yn = computeSource(symbolPrices, yahooFactor, yahooOffset, nextChange, minPoints: 1);
          if (yn != null) nextSourcePrices['yahoo'] = yn;
        }

        // EIA
        final eiaSymbol = params.eiaSymbols[fuelType.paramKey];
        final eiaFactor = params.eiaCifMedFactors[fuelType.paramKey];
        final eiaOffset = params.eiaCifMedOffsets[fuelType.paramKey] ??
            defaults.eiaCifMedOffsets[fuelType.paramKey] ?? 0.0;
        if (eiaSymbol != null && eiaFactor != null) {
          final eiaPrices = await priceRepo.getOilPrices(eiaSymbol, days: 60);
          if (eiaPrices.isNotEmpty) {
            final ec = computeSource(eiaPrices, eiaFactor, eiaOffset, currentPeriodStart);
            if (ec != null) currentSourcePrices['eia'] = ec;
            final en = computeSource(eiaPrices, eiaFactor, eiaOffset, nextChange, minPoints: 1);
            if (en != null) nextSourcePrices['eia'] = en;
          }
        }

        // OilPriceAPI
        final oilApiSymbol = params.oilApiSymbols[fuelType.paramKey];
        final oilApiFactor = params.oilApiCifMedFactors[fuelType.paramKey];
        final oilApiOffset = params.oilApiCifMedOffsets[fuelType.paramKey] ??
            defaults.oilApiCifMedOffsets[fuelType.paramKey] ?? 0.0;
        if (oilApiSymbol != null && oilApiFactor != null) {
          final oilApiPrices = await priceRepo.getOilPrices(oilApiSymbol, days: 60);
          if (oilApiPrices.isNotEmpty) {
            final oc = computeSource(oilApiPrices, oilApiFactor, oilApiOffset, currentPeriodStart, minPoints: 1);
            if (oc != null) currentSourcePrices['oilapi'] = oc;
            final on_ = computeSource(oilApiPrices, oilApiFactor, oilApiOffset, nextChange, minPoints: 1);
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
        await logger.log('predict',
            '${fuelType.name}: current=${currentBlended?.toStringAsFixed(3) ?? "-"} '
            'predicted=${predictedBlended?.toStringAsFixed(3) ?? "-"} '
            'sources_cur=$currentSourcePrices sources_next=$nextSourcePrices');
      }

      // 6. (Re-)schedule next notification with fresh predictions.
      // Decoupled from WorkManager timing — exact alarm via flutter_local_notifications
      // fires under Doze regardless of when (or if) the next bg_sync runs.
      final notifSettings = await settingsRepo.getNotificationSettings();
      final notifEnabled = (notifSettings['enabled'] as int) == 1;

      if (notifEnabled) {
        final notifDay = notifSettings['day'] as String;
        final notifHour = (notifSettings['hour'] as int?) ?? 9;
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
        final scheduled = await notificationService.scheduleNextPriceNotification(
          notificationDay: notifDay,
          notifHour: notifHour,
          fuelPredictions: fuelPredictions,
        );
        await logger.log('notif',
            'SCHEDULE_NEXT day=$notifDay hour=$notifHour at=${scheduled?.toIso8601String() ?? "(none — no trend changes)"} '
            '(${fuelPredictions.length} fuels): ${_formatPredictions(fuelPredictions)}');
      }

      // 7. Clean old data (keep last 800 days for yearly charts)
      await priceRepo.cleanOldData(const Duration(days: 800));

      final duration = DateTime.now().difference(startedAt);
      await logger.log('bg_sync', 'END ok duration=${duration.inSeconds}s predictions=${predictions.length}');
      await db.close();
      return true;
    } catch (e, st) {
      try {
        await logger?.log('bg_sync', 'ERROR $e\n$st');
      } catch (_) {}
      return false;
    } finally {
      if (lockHeld) {
        try {
          await SyncLock.release();
        } catch (_) {}
      }
    }
  });
}

String _formatPredictions(Map<FuelType, ({double predicted, double? current})> m) {
  final parts = <String>[];
  for (final e in m.entries) {
    parts.add('${e.key.name}=${e.value.predicted.toStringAsFixed(2)}(cur=${e.value.current?.toStringAsFixed(2) ?? "-"})');
  }
  return parts.join(' ');
}
