import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/blocs/fuel_detail_cubit.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

void main() {
  late AppDatabase db;
  late PriceRepository priceRepo;
  final params = FuelParams.defaultParams;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    priceRepo = PriceRepository(db);
  });

  tearDown(() async => await db.close());

  test('load with empty DB does not crash — emits non-loading state', () async {
    final cubit = FuelDetailCubit(
      fuelType: FuelType.es95,
      priceRepo: priceRepo,
      params: params,
      referenceDate: DateTime(2026, 3, 24),
      cycleDays: 14,
    );

    await cubit.load();

    expect(cubit.state.isLoading, false);
    expect(cubit.state.predictedPrice, isNull);
    expect(cubit.state.priceHistory, isEmpty);
    expect(cubit.state.nextChangeDate, isNotNull);

    await cubit.close();
  });

  test('load with prediction data populates state correctly', () async {
    await priceRepo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95,
      date: DateTime(2026, 3, 25),
      price: 1.48,
      isPrediction: true,
    ));

    final cubit = FuelDetailCubit(
      fuelType: FuelType.es95,
      priceRepo: priceRepo,
      params: params,
      referenceDate: DateTime(2026, 3, 24),
      cycleDays: 14,
    );

    await cubit.load();

    expect(cubit.state.isLoading, false);
    expect(cubit.state.predictedPrice, 1.48);

    await cubit.close();
  });

  test('setChartPeriod does not crash with empty history', () async {
    final cubit = FuelDetailCubit(
      fuelType: FuelType.eurodizel,
      priceRepo: priceRepo,
      params: params,
      referenceDate: DateTime(2026, 3, 24),
      cycleDays: 14,
    );

    await cubit.load();
    await cubit.setChartPeriod(7);
    expect(cubit.state.chartDays, 7);
    expect(cubit.state.priceHistory, isEmpty);

    await cubit.setChartPeriod(365);
    expect(cubit.state.chartDays, 365);

    await cubit.close();
  });

  test('close during load does not throw', () async {
    final cubit = FuelDetailCubit(
      fuelType: FuelType.es95,
      priceRepo: priceRepo,
      params: params,
      referenceDate: DateTime(2026, 3, 24),
      cycleDays: 14,
    );

    // Start load and immediately close
    final loadFuture = cubit.load();
    await cubit.close();
    // Should complete without error
    await loadFuture;
  });

  test('all fuel types can load without crash', () async {
    for (final ft in FuelType.values) {
      final cubit = FuelDetailCubit(
        fuelType: ft,
        priceRepo: priceRepo,
        params: params,
        referenceDate: DateTime(2026, 3, 24),
        cycleDays: 14,
      );

      await cubit.load();
      expect(cubit.state.isLoading, false, reason: '${ft.name} should finish loading');
      expect(cubit.state.fuelType, ft);

      await cubit.close();
    }
  });
}
