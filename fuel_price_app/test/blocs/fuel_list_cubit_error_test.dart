import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';

void main() {
  late AppDatabase db;
  late PriceRepository priceRepo;
  late SettingsRepository settingsRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    priceRepo = PriceRepository(db);
    settingsRepo = SettingsRepository(db);
  });

  tearDown(() async => await db.close());

  test('load with empty DB returns empty list without crash', () async {
    final cubit = FuelListCubit(
      priceRepo: priceRepo,
      settingsRepo: settingsRepo,
      formulaEngine: FormulaEngine(FuelParams.defaultParams),
    );

    await cubit.load();

    expect(cubit.state.isLoading, false);
    // Default visibility is true for all, so all 4 fuels show (with null prices)
    expect(cubit.state.fuels.length, 4);
    for (final item in cubit.state.fuels) {
      expect(item.currentPrice, isNull);
      expect(item.predictedPrice, isNull);
    }

    await cubit.close();
  });

  test('load with data returns correct items', () async {
    for (final ft in FuelType.values) {
      await priceRepo.saveFuelPrice(FuelPrice(
        fuelType: ft,
        date: DateTime(2026, 3, 20),
        price: 1.45,
        isPrediction: false,
      ));
    }

    final cubit = FuelListCubit(
      priceRepo: priceRepo,
      settingsRepo: settingsRepo,
      formulaEngine: FormulaEngine(FuelParams.defaultParams),
    );

    await cubit.load();

    expect(cubit.state.fuels.length, 4);
    for (final item in cubit.state.fuels) {
      expect(item.currentPrice, 1.45);
    }

    await cubit.close();
  });

  test('reorder handles boundary indices', () async {
    final cubit = FuelListCubit(
      priceRepo: priceRepo,
      settingsRepo: settingsRepo,
      formulaEngine: FormulaEngine(FuelParams.defaultParams),
    );

    await cubit.load();
    final originalOrder = cubit.state.fuels.map((f) => f.fuelType).toList();

    // Move first to last
    await cubit.reorder(0, 4);
    expect(cubit.state.fuels.first.fuelType, originalOrder[1]);

    await cubit.close();
  });

  test('reorder with same index is no-op', () async {
    final cubit = FuelListCubit(
      priceRepo: priceRepo,
      settingsRepo: settingsRepo,
      formulaEngine: FormulaEngine(FuelParams.defaultParams),
    );

    await cubit.load();
    final before = cubit.state.fuels.map((f) => f.fuelType).toList();

    await cubit.reorder(1, 1);
    final after = cubit.state.fuels.map((f) => f.fuelType).toList();
    expect(after, before);

    await cubit.close();
  });

  test('close during load does not throw', () async {
    final cubit = FuelListCubit(
      priceRepo: priceRepo,
      settingsRepo: settingsRepo,
      formulaEngine: FormulaEngine(FuelParams.defaultParams),
    );

    final loadFuture = cubit.load();
    await cubit.close();
    await loadFuture;
  });

  test('visibility toggle hides fuel from list', () async {
    final cubit = FuelListCubit(
      priceRepo: priceRepo,
      settingsRepo: settingsRepo,
      formulaEngine: FormulaEngine(FuelParams.defaultParams),
    );

    await cubit.load();
    expect(cubit.state.fuels.length, 4);

    // Hide es100
    await settingsRepo.setFuelVisibility('es100', false);
    await cubit.load();
    expect(cubit.state.fuels.length, 3);
    expect(
      cubit.state.fuels.any((f) => f.fuelType == FuelType.es100),
      false,
    );

    await cubit.close();
  });
}
