import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/blocs/settings_cubit.dart';
import 'package:fuel_price_app/data/app_logger.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/config_repository.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';
import 'package:fuel_price_app/data/services/eia_service.dart';
import 'package:fuel_price_app/data/services/hnb_service.dart';
import 'package:fuel_price_app/data/services/oil_price_api_service.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';
import 'package:fuel_price_app/data/services/yahoo_finance_service.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/domain/price_blender.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';
import 'package:fuel_price_app/models/exchange_rate.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/oil_price.dart';
import 'package:fuel_price_app/notifications/notification_service.dart';
import 'package:fuel_price_app/scheduling/sync_lock.dart';
import 'package:fuel_price_app/blocs/stations_cubit.dart';
import 'package:fuel_price_app/data/services/station_price_service.dart';
import 'package:fuel_price_app/data/repositories/station_repository.dart';
import 'package:fuel_price_app/ui/screens/fuel_list_screen.dart';
import 'package:fuel_price_app/ui/screens/station_list_screen.dart';
import 'package:fuel_price_app/ui/screens/settings_screen.dart';
import 'package:fuel_price_app/ui/theme.dart';
import 'package:fuel_price_app/ui/widgets/disclaimer_dialog.dart';

class FuelPriceApp extends StatefulWidget {
  final AppDatabase database;

  const FuelPriceApp({super.key, required this.database});

  @override
  State<FuelPriceApp> createState() => _FuelPriceAppState();
}

class _FuelPriceAppState extends State<FuelPriceApp> {
  late final PriceRepository _priceRepo;
  late final SettingsRepository _settingsRepo;
  late final ConfigRepository _configRepo;
  late final AppLogger _logger;
  late final Dio _dio;
  late final YahooFinanceService _yahooService;
  late final HnbService _hnbService;
  late final EiaService _eiaService;
  late final OilPriceApiService _oilPriceApiService;
  late final RemoteConfigService _remoteConfigService;
  late final DataSyncCubit _syncCubit;
  late final FuelListCubit _fuelListCubit;
  late final SettingsCubit _settingsCubit;
  late final StationPriceService _stationPriceService;
  late final StationRepository _stationRepo;
  late final StationsCubit _stationsCubit;
  FuelParams _activeParams = FuelParams.defaultParams;

  @override
  void initState() {
    super.initState();

    // Services
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _yahooService = YahooFinanceService(dio: _dio);
    _hnbService = HnbService(dio: _dio);
    _eiaService = EiaService(dio: _dio, apiKey: _activeParams.eiaApiKey);
    _oilPriceApiService = OilPriceApiService(dio: _dio, apiKey: _activeParams.oilPriceApiKey);
    _remoteConfigService = RemoteConfigService(dio: _dio);

    // Repositories
    _priceRepo = PriceRepository(widget.database);
    _logger = AppLogger(widget.database);
    _settingsRepo = SettingsRepository(widget.database);
    _configRepo = ConfigRepository(widget.database, _remoteConfigService);

    // Station services
    _stationPriceService = StationPriceService(dio: _dio);
    _stationRepo = StationRepository(widget.database);
    _stationsCubit = StationsCubit(
      service: _stationPriceService,
      repository: _stationRepo,
    );

    // Sync orchestrator with real services
    _syncCubit = DataSyncCubit(
      orchestrator: DataSyncOrchestrator(
        fetchOilPrices: () async {
          // Fetch all commodity symbols in parallel (400 days for yearly charts)
          final symbols = ['BZ=F', 'RB=F', 'HO=F'];
          final results = await Future.wait(
            symbols.map((s) => _yahooService.fetchHistoricalPrices(s, 400)),
          );
          // Save all symbols with actual Yahoo Finance dates
          for (var si = 0; si < symbols.length; si++) {
            for (final p in results[si]) {
              await _priceRepo.saveOilPrice(
                OilPrice(date: p.date, cifMed: p.close, source: symbols[si]),
              );
            }
          }
          _log('fetched ${results.map((r) => r.length).toList()} prices for $symbols');
          // Return BZ=F count as indicator of success
          return results[0].map((p) => p.close).toList();
        },
        fetchExchangeRates: () async {
          // Fetch daily historical rates from ECB (60 days)
          final historical = await _hnbService.fetchHistoricalRates(60);
          if (historical.isNotEmpty) {
            for (final h in historical) {
              await _priceRepo.saveExchangeRate(
                ExchangeRate(date: h.date, usdEur: h.rate),
              );
            }
            _log('fetched ${historical.length} daily ECB rates');
          }
          // Also fetch latest as fallback
          final rate = await _hnbService.fetchUsdEurRate();
          return [rate];
        },
        fetchConfig: () async {
          final params = await _remoteConfigService.fetchParams();
          // Return current version even if fetch fails (config is optional)
          return <String, dynamic>{'version': params?.version ?? _activeParams.version};
        },
        fetchEiaSpotPrices: () async {
          final seriesIds = _activeParams.eiaSymbols.values.toSet();
          for (final seriesId in seriesIds) {
            final prices = await _eiaService.fetchSpotPrices(seriesId, days: 60);
            for (final p in prices) {
              await _priceRepo.saveOilPrice(
                OilPrice(date: p.date, cifMed: p.value, source: seriesId),
              );
            }
            _log('EIA: fetched ${prices.length} prices for $seriesId');
          }
          return [1.0]; // success indicator
        },
        fetchOilApiPrices: () async {
          final prefs = await SharedPreferences.getInstance();
          final lastFetch = prefs.getString('oilapi_last_fetch');
          final now = DateTime.now();

          // Rate limit is 50 requests per DAY (x-ratelimit-window: daily,
          // verified 2026-08-24) — not 200/month as previously recorded. We
          // poll 2 distinct codes, so a 4h throttle costs at most 12 req/day,
          // well inside the limit.
          //
          // The throttle used to be 20h, which left exactly one attempt per
          // day. Since the API has no free backfill (see fetchRecentPrices), a
          // single failed attempt lost that day permanently, and GASOIL_USD
          // coverage fell to 69% of business days while PROPANE_MONT_BELVIEU
          // sat at 21%. Several attempts per day is the only defence.
          const throttle = Duration(hours: 4);
          if (lastFetch != null) {
            final last = DateTime.tryParse(lastFetch);
            if (last != null && now.difference(last) < throttle) {
              final mins = now.difference(last).inMinutes;
              _log('OilPriceAPI: skipping, last fetch ${mins}min ago');
              return [1.0]; // success — using cached data
            }
          }

          final symbols = _activeParams.oilApiSymbols.values.toSet();
          var savedAny = false;
          for (final code in symbols) {
            // Prefer the multi-point endpoint; fall back to the single latest
            // price so a change in the recent-prices payload cannot leave us
            // with no data at all.
            var points = OilPriceApiService.latestPerDay(
              await _oilPriceApiService.fetchRecentPrices(code),
            ).values.toList();
            if (points.isEmpty) {
              final single = await _oilPriceApiService.fetchLatestPrice(code);
              if (single != null) points = [single];
            }

            for (final p in points) {
              await _priceRepo.saveOilPrice(
                OilPrice(date: p.date, cifMed: p.value, source: code),
              );
            }
            if (points.isNotEmpty) savedAny = true;
            await _logger.log('oilapi',
                '$code: saved ${points.length} day(s), '
                'remaining=${_oilPriceApiService.remainingRequests}');
          }

          // Only start the throttle when something was actually stored.
          // Persisting it unconditionally (the old behaviour) meant a network
          // blip silently blocked the source for the rest of the window.
          if (savedAny) {
            await prefs.setString('oilapi_last_fetch', now.toIso8601String());
          } else {
            await _logger.log('oilapi', 'no data saved — throttle NOT started');
          }
          return [1.0];
        },
      ),
      onSyncResult: _handleSyncResult,
    );

    // Cubits
    _fuelListCubit = FuelListCubit(
      priceRepo: _priceRepo,
      settingsRepo: _settingsRepo,
      formulaEngine: FormulaEngine(_activeParams),
    );

    _settingsCubit = SettingsCubit(settingsRepo: _settingsRepo)
      ..onNotificationSettingsChanged = _scheduleNotificationIfEnabled;

    _initApp();
  }

  // ignore: avoid_print
  static void _log(String msg) => print('[AppInit] $msg');

  Future<void> _initApp() async {
    try {
      await _settingsCubit.load();

      // Check for any existing data (even partial)
      final brentPrices = await _priceRepo.getOilPrices('BZ=F', days: 30);
      final rbobPrices = await _priceRepo.getOilPrices('RB=F', days: 30);
      final hoPrices = await _priceRepo.getOilPrices('HO=F', days: 30);
      _log('existing: BZ=${brentPrices.length} RB=${rbobPrices.length} HO=${hoPrices.length}');

      final hasAnyData = brentPrices.isNotEmpty || rbobPrices.isNotEmpty || hoPrices.isNotEmpty;

      if (hasAnyData) {
        // Show cached data immediately
        _syncCubit.setHasData(true);
        await _recalculatePredictions();
        await _fuelListCubit.load();
        // Then refresh in background (don't await)
        _syncCubit.sync();
      } else {
        _log('no existing data — starting sync');
        // First launch — auto-sync immediately
        await _syncCubit.sync();

        final afterSync = await _priceRepo.getOilPrices('RB=F', days: 30);
        _log('RB=F after sync: ${afterSync.length}');
        if (afterSync.isNotEmpty) {
          _syncCubit.setHasData(true);
          await _recalculatePredictions();
          await _fuelListCubit.load();
        }
      }

      // Sync remote config
      final newParams = await _configRepo.syncConfig();
      if (newParams != null) {
        _activeParams = newParams;
        _eiaService = EiaService(dio: _dio, apiKey: _activeParams.eiaApiKey);
        _oilPriceApiService = OilPriceApiService(dio: _dio, apiKey: _activeParams.oilPriceApiKey);
      }
    } catch (e) {
      _log('INIT ERROR: $e');
      // Ensure app is usable even if init partially fails
      await _fuelListCubit.load();
    }
  }

  Future<void> _handleSyncResult(dynamic result) async {
    if (result is! SyncResult) return;
    final syncResult = result;
    _log('sync result: oil=${syncResult.oilPricesOk} rates=${syncResult.exchangeRatesOk} config=${syncResult.configOk}');
    if (syncResult.failedSources.isNotEmpty) {
      _log('FAILED sources: ${syncResult.failedSources}');
    }

    // Oil prices are already saved in the fetchOilPrices callback with actual dates

    // Save exchange rate
    if (syncResult.exchangeRates != null && syncResult.exchangeRates!.isNotEmpty) {
      await _priceRepo.saveExchangeRate(
        ExchangeRate(date: DateTime.now(), usdEur: syncResult.exchangeRates!.first),
      );
    }

    // Recalculate predictions even with partial data
    await _recalculatePredictions();

    // Reload fuel list
    await _fuelListCubit.load();

    // Cleanup old data
    await _priceRepo.cleanOldData(const Duration(days: 730));
  }

  Future<void> _recalculatePredictions() async {
    await _runRecalculate();
    await _scheduleNotificationIfEnabled();
  }

  Future<void> _runRecalculate() async {
    // Single-flight: bail if a bg_sync is mid-flight to avoid partial-state DB
    // read by UI while bg_sync writes are still in progress.
    final acquired = await SyncLock.tryAcquire(ttl: const Duration(minutes: 2));
    if (!acquired) {
      await _logger.log('fg_recalc', 'SKIP another sync in progress');
      return;
    }
    try {
      await _runRecalculateLocked();
    } finally {
      await SyncLock.release();
    }
  }

  Future<void> _runRecalculateLocked() async {
    final engine = FormulaEngine(_activeParams);
    final rates = await _priceRepo.getExchangeRates(days: 60);

    await _logger.log('fg_recalc',
        'START activeParams.version=${_activeParams.version} '
        'ES95=${_activeParams.cifMedFactors['es95']}/${_activeParams.cifMedOffsets['es95']} '
        'ED=${_activeParams.cifMedFactors['eurodizel']}/${_activeParams.cifMedOffsets['eurodizel']} '
        'edSym=${_activeParams.yahooSymbols['eurodizel']} '
        'edWeights=${_activeParams.sourceWeights['eurodizel']} '
        'rates=${rates.length}');

    if (rates.isEmpty) {
      _log('SKIP prediction — no exchange rates');
      await _logger.log('fg_recalc', 'SKIP no rates');
      return;
    }

    final refDate = DateTime.parse(_activeParams.referenceDate);
    final cycle = _activeParams.cycleDays;
    final now = DateTime.now();
    final nextChange = nextPriceChangeDate(now, refDate, cycle);
    // Current period started one cycle before the next change
    final currentPeriodStart = nextChange.subtract(Duration(days: cycle));

    final latestRate = rates.last.usdEur;
    _log('rates: ${rates.length} in DB, latest=$latestRate');

    for (final ft in FuelType.values) {
      try {
        final weights = _activeParams.sourceWeights[ft.paramKey] ?? {'yahoo': 1.0};

        // Collect predictions from each source
        // Yahoo
        // Fall back to defaultParams when remote config predates this fuel.
        final defaults = FuelParams.defaultParams;
        final yahooSymbol = _activeParams.yahooSymbols[ft.paramKey] ??
            defaults.yahooSymbols[ft.paramKey] ?? 'BZ=F';
        final yahooFactor = _activeParams.cifMedFactors[ft.paramKey] ??
            defaults.cifMedFactors[ft.paramKey] ?? 0.0;
        final yahooOffset = _activeParams.cifMedOffsets[ft.paramKey] ??
            defaults.cifMedOffsets[ft.paramKey] ?? 0.0;
        final yahooPrices = await _priceRepo.getOilPrices(yahooSymbol, days: 60);

        // EIA
        final eiaSymbol = _activeParams.eiaSymbols[ft.paramKey];
        final eiaFactor = _activeParams.eiaCifMedFactors[ft.paramKey];
        final eiaOffset = _activeParams.eiaCifMedOffsets[ft.paramKey] ??
            defaults.eiaCifMedOffsets[ft.paramKey] ?? 0.0;
        final eiaPrices = eiaSymbol != null
            ? await _priceRepo.getOilPrices(eiaSymbol, days: 60)
            : <OilPrice>[];

        // OilPriceAPI
        final oilApiSymbol = _activeParams.oilApiSymbols[ft.paramKey];
        final oilApiFactor = _activeParams.oilApiCifMedFactors[ft.paramKey];
        final oilApiOffset = _activeParams.oilApiCifMedOffsets[ft.paramKey] ??
            defaults.oilApiCifMedOffsets[ft.paramKey] ?? 0.0;
        final oilApiPrices = oilApiSymbol != null
            ? await _priceRepo.getOilPrices(oilApiSymbol, days: 60)
            : <OilPrice>[];

        // Helper to compute price from a source's prices.
        // Settlement window per NN 31/2025: 14 days Mon-Sun × 2 ending the
        // Sunday before the publication Monday. In our half-open form the
        // window is [nextChange - 15 days, nextChange - 1 day).
        // cifMed = raw × factor + offset (offset captures fixed CIF Med costs).
        double? computePrice(List<OilPrice> prices, double factor, double offset, bool isCurrent, {int minPoints = 5}) {
          if (prices.isEmpty) return null;
          final anchor = isCurrent ? currentPeriodStart : nextChange;
          final w = settlementWindow(anchor, cycle);
          final window = prices
              .where((p) => !p.date.isBefore(w.start) && p.date.isBefore(w.end))
              .toList();
          if (window.length < minPoints) return null;
          final cifMed = window.map((p) => p.cifMed * factor + offset).toList();
          final ratesList = window.map((p) => _findRate(rates, p.date)).toList();
          return engine.predictPrice(ft, cifMed, ratesList);
        }

        // --- Current period price ---
        final currentSourcePrices = <String, double>{};
        final yc = computePrice(yahooPrices, yahooFactor, yahooOffset, true);
        if (yc != null) currentSourcePrices['yahoo'] = yc;
        final ec = eiaFactor != null ? computePrice(eiaPrices, eiaFactor, eiaOffset, true) : null;
        if (ec != null) currentSourcePrices['eia'] = ec;
        final oc = oilApiFactor != null ? computePrice(oilApiPrices, oilApiFactor!, oilApiOffset, true, minPoints: 1) : null;
        if (oc != null) currentSourcePrices['oilapi'] = oc;

        final currentPrice = PriceBlender.blend(currentSourcePrices, weights);
        if (currentPrice != null) {
          final rounded = FormulaEngine.roundPrice(currentPrice);
          _log('${ft.name}: current=$rounded (sources: $currentSourcePrices)');
          await _priceRepo.saveFuelPrice(
            FuelPrice(fuelType: ft, date: currentPeriodStart, price: rounded, isPrediction: false),
          );
        }

        // --- Next period prediction ---
        // minPoints: 1 for predictions — direction is correct even with few data points,
        // and accuracy improves daily as more data arrives.
        final nextSourcePrices = <String, double>{};
        final yn = computePrice(yahooPrices, yahooFactor, yahooOffset, false, minPoints: 1);
        if (yn != null) nextSourcePrices['yahoo'] = yn;
        final en = eiaFactor != null ? computePrice(eiaPrices, eiaFactor, eiaOffset, false, minPoints: 1) : null;
        if (en != null) nextSourcePrices['eia'] = en;
        final on_ = oilApiFactor != null ? computePrice(oilApiPrices, oilApiFactor!, oilApiOffset, false, minPoints: 1) : null;
        if (on_ != null) nextSourcePrices['oilapi'] = on_;

        final predictedPrice = PriceBlender.blend(nextSourcePrices, weights);
        if (predictedPrice != null) {
          final rounded = FormulaEngine.roundPrice(predictedPrice);
          _log('${ft.name}: predicted=$rounded (sources: $nextSourcePrices)');
          await _priceRepo.saveFuelPrice(
            FuelPrice(fuelType: ft, date: nextChange, price: rounded, isPrediction: true),
          );
        }
        await _logger.log('fg_predict',
            '${ft.name} sym=${yahooSymbol} f=$yahooFactor o=$yahooOffset '
            'weights=$weights ypts=${yahooPrices.length} epts=${eiaPrices.length} opts=${oilApiPrices.length} '
            'nextSources=$nextSourcePrices currentSources=$currentSourcePrices '
            'predicted=${predictedPrice?.toStringAsFixed(3) ?? "-"}');
      } catch (e) {
        _log('prediction FAILED for ${ft.name}: $e');
        await _logger.log('fg_predict', '${ft.name} ERROR $e');
      }
    }
  }

  /// Re-schedule the next price-change notification using predictions from the
  /// DB. Called after every foreground recalc and whenever notification
  /// settings change, so the body reflects latest data even if WorkManager
  /// never runs in the background.
  Future<void> _scheduleNotificationIfEnabled() async {
    try {
      final notifSettings = await _settingsRepo.getNotificationSettings();
      final enabled = (notifSettings['enabled'] as int) == 1;
      if (!enabled) {
        await NotificationService().cancelAll();
        await _logger.log('notif', 'CANCEL — notifications disabled');
        return;
      }
      final notifDay = notifSettings['day'] as String;
      final notifHour = (notifSettings['hour'] as int?) ?? 9;
      final notifFuels = await _settingsRepo.getNotificationFuels();

      final fuelPredictions =
          <FuelType, ({double predicted, double? current})>{};
      for (final ft in FuelType.values) {
        if (notifFuels[ft.name] != true) continue;
        final predicted = await _priceRepo.getLatestPrice(ft, prediction: true);
        if (predicted == null) continue;
        final currentPrice = await _priceRepo.getLatestPrice(ft, prediction: false);
        fuelPredictions[ft] = (
          predicted: predicted.price,
          current: currentPrice?.price,
        );
      }

      final svc = NotificationService();
      await svc.init();
      final scheduled = await svc.scheduleNextPriceNotification(
        notificationDay: notifDay,
        notifHour: notifHour,
        fuelPredictions: fuelPredictions,
      );
      await _logger.log('notif',
          'SCHEDULE_NEXT(fg) day=$notifDay hour=$notifHour at=${scheduled?.toIso8601String() ?? "(none)"} (${fuelPredictions.length} fuels)');
    } catch (e) {
      _log('schedule notification failed: $e');
      await _logger.log('notif', 'SCHEDULE_NEXT ERROR $e');
    }
  }

  /// Find the exchange rate closest to (but not after) the given date.
  /// Falls back to the nearest available rate.
  static double _findRate(List<ExchangeRate> rates, DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    // Find rates on or before this date
    ExchangeRate? best;
    for (final r in rates) {
      final rDate = DateTime(r.date.year, r.date.month, r.date.day);
      if (!rDate.isAfter(dateOnly)) {
        best = r;
      }
    }
    return (best ?? rates.last).usdEur;
  }

  @override
  void dispose() {
    _syncCubit.close();
    _fuelListCubit.close();
    _settingsCubit.close();
    _stationsCubit.close();
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _syncCubit),
        BlocProvider.value(value: _fuelListCubit),
        BlocProvider.value(value: _settingsCubit),
        BlocProvider.value(value: _stationsCubit),
        RepositoryProvider.value(value: _priceRepo),
        RepositoryProvider.value(value: _settingsRepo),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settingsState) {
          final brightness = MediaQuery.platformBrightnessOf(context);
          setupEdgeToEdge(settingsState.themeMode == ThemeMode.dark
              ? Brightness.dark
              : settingsState.themeMode == ThemeMode.light
                  ? Brightness.light
                  : brightness);

          return MaterialApp(
            title: 'FuelLens',
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: settingsState.themeMode,
            home: const _AppHome(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class _AppHome extends StatefulWidget {
  const _AppHome();

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> {
  int _currentIndex = 0;
  bool _stationsTabVisited = false;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDisclaimerIfNeeded(context);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    // Lazy load station data only when Cijene tab is first visited
    if (index == 1 && !_stationsTabVisited) {
      _stationsTabVisited = true;
      context.read<StationsCubit>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: const [
          FuelListScreen(),
          StationListScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up),
            label: 'Procjena',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_gas_station_outlined),
            selectedIcon: Icon(Icons.local_gas_station),
            label: 'Cijene',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Postavke',
          ),
        ],
      ),
    );
  }
}

