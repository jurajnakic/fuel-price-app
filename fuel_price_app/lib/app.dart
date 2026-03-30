import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/blocs/settings_cubit.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/config_repository.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';
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
  late final Dio _dio;
  late final YahooFinanceService _yahooService;
  late final HnbService _hnbService;
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
    _remoteConfigService = RemoteConfigService(dio: _dio);

    // Repositories
    _priceRepo = PriceRepository(widget.database);
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
          final rate = await _hnbService.fetchUsdEurRate();
          return [rate];
        },
        fetchConfig: () async {
          final params = await _remoteConfigService.fetchParams();
          if (params == null) throw Exception('Config fetch failed');
          return <String, dynamic>{'version': params.version};
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

    _settingsCubit = SettingsCubit(settingsRepo: _settingsRepo);

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

  /// Seed realistic demo data when API is unavailable (e.g., emulator)
  Future<void> _seedDemoData() async {
    final now = DateTime.now();
    final random = Random();

    // Seed 20 days of Brent prices around 72 USD/barrel
    for (var i = 20; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final price = 70.0 + random.nextDouble() * 5; // 70-75 USD
      await _priceRepo.saveOilPrice(
        OilPrice(date: date, cifMed: price, source: 'BZ=F'),
      );
    }

    // Seed exchange rate (~0.92 EUR/USD)
    await _priceRepo.saveExchangeRate(
      ExchangeRate(date: now, usdEur: 0.92 + random.nextDouble() * 0.02),
    );

    // Seed some historical fuel prices
    for (final ft in FuelType.values) {
      final basePrice = switch (ft) {
        FuelType.es95 => 1.45,
        FuelType.es100 => 1.52,
        FuelType.eurodizel => 1.40,
        FuelType.unp10kg => 5.10,
      };
      // Current official price (last Tuesday)
      final lastTuesday = now.subtract(Duration(days: (now.weekday - DateTime.tuesday) % 7));
      await _priceRepo.saveFuelPrice(
        FuelPrice(fuelType: ft, date: lastTuesday, price: basePrice, isPrediction: false),
      );
      // A few historical prices
      for (var i = 1; i <= 4; i++) {
        await _priceRepo.saveFuelPrice(
          FuelPrice(
            fuelType: ft,
            date: lastTuesday.subtract(Duration(days: i * 14)),
            price: basePrice + (random.nextDouble() - 0.5) * 0.1,
            isPrediction: false,
          ),
        );
      }
    }
  }

  Future<void> _recalculatePredictions() async {
    final engine = FormulaEngine(_activeParams);
    final rates = await _priceRepo.getExchangeRates(days: 60);

    if (rates.isEmpty) {
      _log('SKIP prediction — no exchange rates');
      return;
    }

    final lastRate = rates.last.usdEur;
    final refDate = DateTime.parse(_activeParams.referenceDate);
    final cycle = _activeParams.cycleDays;
    final now = DateTime.now();
    final nextChange = nextPriceChangeDate(now, refDate, cycle);
    // Current period started one cycle before the next change
    final currentPeriodStart = nextChange.subtract(Duration(days: cycle));

    for (final ft in FuelType.values) {
      try {
        final symbol = _activeParams.yahooSymbols[ft.paramKey] ?? 'BZ=F';
        final factor = _activeParams.cifMedFactors[ft.paramKey] ?? 402.4;
        final oilPrices = await _priceRepo.getOilPrices(symbol, days: 60);

        if (oilPrices.isEmpty) {
          _log('SKIP ${ft.name} — no prices for $symbol');
          continue;
        }

        // Split prices into two windows:
        // "Current" window: prices BEFORE currentPeriodStart (determined current official price)
        // "Next" window: most recent 14 prices (will determine next price)
        final currentWindowPrices = oilPrices
            .where((p) => p.date.isBefore(currentPeriodStart))
            .toList();
        final nextWindowPrices = oilPrices;

        // --- Current period price (isPrediction=false) ---
        if (currentWindowPrices.length >= 10) {
          final count = currentWindowPrices.length < 14 ? currentWindowPrices.length : 14;
          final window = currentWindowPrices.reversed.take(count).toList().reversed.toList();
          final cifCurrent = window.map((p) => p.cifMed * factor).toList();
          final ratesCurrent = List.generate(cifCurrent.length, (_) => lastRate);
          final currentPrice = engine.predictPrice(ft, cifCurrent, ratesCurrent);
          _log('${ft.name}: current=${currentPrice.toStringAsFixed(4)} (window before $currentPeriodStart)');

          await _priceRepo.saveFuelPrice(
            FuelPrice(fuelType: ft, date: currentPeriodStart, price: currentPrice, isPrediction: false),
          );
        }

        // --- Next period price (isPrediction=true) ---
        final nextCount = nextWindowPrices.length < 14 ? nextWindowPrices.length : 14;
        final nextWindow = nextWindowPrices.reversed.take(nextCount).toList().reversed.toList();
        final cifNext = nextWindow.map((p) => p.cifMed * factor).toList();
        final ratesNext = List.generate(cifNext.length, (_) => lastRate);
        final predictedPrice = engine.predictPrice(ft, cifNext, ratesNext);
        _log('${ft.name}: predicted=${predictedPrice.toStringAsFixed(4)} (next=$nextChange)');

        await _priceRepo.saveFuelPrice(
          FuelPrice(fuelType: ft, date: nextChange, price: predictedPrice, isPrediction: true),
        );
      } catch (e) {
        _log('prediction FAILED for ${ft.name}: $e');
      }
    }
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

