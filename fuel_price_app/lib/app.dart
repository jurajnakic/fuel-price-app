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
import 'package:fuel_price_app/ui/screens/fuel_list_screen.dart';
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
  FuelParams _activeParams = FuelParams.defaultParams;

  @override
  void initState() {
    super.initState();

    // Services
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    _yahooService = YahooFinanceService(dio: _dio);
    _hnbService = HnbService(dio: _dio);
    _remoteConfigService = RemoteConfigService(dio: _dio);

    // Repositories
    _priceRepo = PriceRepository(widget.database);
    _settingsRepo = SettingsRepository(widget.database);
    _configRepo = ConfigRepository(widget.database, _remoteConfigService);

    // Sync orchestrator with real services
    _syncCubit = DataSyncCubit(
      orchestrator: DataSyncOrchestrator(
        fetchOilPrices: () async {
          final prices = await _yahooService.fetchHistoricalPrices('BZ=F', 30);
          return prices.map((p) => p.close).toList();
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

  Future<void> _initApp() async {
    await _settingsCubit.load();

    // Check for existing data
    final prices = await _priceRepo.getOilPrices('BZ=F', days: 30);
    if (prices.isNotEmpty) {
      _syncCubit.setHasData(true);
      await _recalculatePredictions();
      await _fuelListCubit.load();
    } else {
      // First launch — try sync, if fails seed demo data for testing
      await _fuelListCubit.load();
      await _syncCubit.sync();

      // If sync failed (no data), seed demo data so app is usable
      final afterSync = await _priceRepo.getOilPrices('BZ=F', days: 30);
      if (afterSync.isEmpty) {
        await _seedDemoData();
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
  }

  Future<void> _handleSyncResult(dynamic result) async {
    final syncResult = result as SyncResult;

    // Save oil prices
    if (syncResult.oilPrices != null && syncResult.oilPrices!.isNotEmpty) {
      final now = DateTime.now();
      final prices = syncResult.oilPrices!;
      for (var i = 0; i < prices.length; i++) {
        final date = now.subtract(Duration(days: prices.length - 1 - i));
        await _priceRepo.saveOilPrice(
          OilPrice(date: date, cifMed: prices[i], source: 'BZ=F'),
        );
      }
    }

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
    final oilPrices = await _priceRepo.getOilPrices('BZ=F', days: 30);
    final rates = await _priceRepo.getExchangeRates(days: 30);

    if (oilPrices.isEmpty || rates.isEmpty) return;

    // Take up to 14 calendar days of oil prices (use what we have)
    final count = oilPrices.length < 14 ? oilPrices.length : 14;
    final recentOil = oilPrices.reversed.take(count).toList().reversed.toList();
    final lastRate = rates.last.usdEur;

    final cifValues = recentOil.map((p) => p.cifMed).toList();
    final rateValues = List.generate(cifValues.length, (_) => lastRate);

    for (final ft in FuelType.values) {
      try {
        final price = engine.predictPrice(ft, cifValues, rateValues);
        final nextChangeDate = nextPriceChangeDate(
          DateTime.now(),
          DateTime.parse(_activeParams.referenceDate),
          _activeParams.cycleDays,
        );
        await _priceRepo.saveFuelPrice(
          FuelPrice(
            fuelType: ft,
            date: nextChangeDate,
            price: price,
            isPrediction: true,
          ),
        );
      } catch (_) {
        // Skip fuel types that can't be calculated
      }
    }
  }

  @override
  void dispose() {
    _syncCubit.close();
    _fuelListCubit.close();
    _settingsCubit.close();
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
            title: 'Cijene Goriva',
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDisclaimerIfNeeded(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const FuelListScreen();
  }
}

