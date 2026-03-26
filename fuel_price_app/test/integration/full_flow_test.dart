import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/oil_price.dart';
import 'package:fuel_price_app/models/exchange_rate.dart';

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

  test('full flow: seed data → calculate → retrieve prediction', () async {
    // Seed 14 days of oil prices and exchange rates
    for (var i = 0; i < 14; i++) {
      final date = DateTime(2026, 3, 10 + i);
      await priceRepo.saveOilPrice(OilPrice(date: date, cifMed: 700.0, source: 'BZ=F'));
      await priceRepo.saveExchangeRate(ExchangeRate(date: date, usdEur: 0.92));
    }

    // Calculate prediction
    final engine = FormulaEngine(FuelParams.defaultParams);
    final prices = await priceRepo.getOilPrices('BZ=F', days: 30);
    final rates = await priceRepo.getExchangeRates(days: 30);
    final predicted = engine.predictPrice(
      FuelType.es95,
      prices.map((p) => p.cifMed).toList(),
      rates.map((r) => r.usdEur).toList(),
    );

    // Save prediction
    await priceRepo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95,
      date: DateTime(2026, 3, 25),
      price: predicted,
      isPrediction: true,
    ));

    // Retrieve
    final result = await priceRepo.getLatestPrice(FuelType.es95, prediction: true);
    expect(result, isNotNull);
    expect(result!.roundedPrice, predicted);

    // Verify fuel order defaults
    final order = await settingsRepo.getFuelOrder();
    expect(order, ['es95', 'es100', 'eurodizel', 'unp10kg']);
  });

  test('full flow: all fuel types produce valid predictions', () async {
    // Seed data
    for (var i = 0; i < 14; i++) {
      final date = DateTime(2026, 3, 10 + i);
      await priceRepo.saveOilPrice(OilPrice(date: date, cifMed: 700.0, source: 'BZ=F'));
      await priceRepo.saveExchangeRate(ExchangeRate(date: date, usdEur: 0.92));
    }

    final engine = FormulaEngine(FuelParams.defaultParams);
    final prices = await priceRepo.getOilPrices('BZ=F', days: 30);
    final rates = await priceRepo.getExchangeRates(days: 30);

    for (final fuelType in FuelType.values) {
      final predicted = engine.predictPrice(
        fuelType,
        prices.map((p) => p.cifMed).toList(),
        rates.map((r) => r.usdEur).toList(),
      );

      expect(predicted, greaterThan(0), reason: '${fuelType.name} should have positive price');

      await priceRepo.saveFuelPrice(FuelPrice(
        fuelType: fuelType,
        date: DateTime(2026, 3, 25),
        price: predicted,
        isPrediction: true,
      ));

      final result = await priceRepo.getLatestPrice(fuelType, prediction: true);
      expect(result, isNotNull, reason: '${fuelType.name} prediction should be retrievable');
      expect(result!.roundedPrice, predicted, reason: '${fuelType.name} stored price should match');
    }
  });

  test('settings: reorder fuels and toggle visibility', () async {
    // Default order
    final defaultOrder = await settingsRepo.getFuelOrder();
    expect(defaultOrder, ['es95', 'es100', 'eurodizel', 'unp10kg']);

    // Reorder
    await settingsRepo.saveFuelOrder(['eurodizel', 'es95', 'unp10kg', 'es100']);
    final newOrder = await settingsRepo.getFuelOrder();
    expect(newOrder, ['eurodizel', 'es95', 'unp10kg', 'es100']);

    // Toggle visibility
    await settingsRepo.setFuelVisibility('es100', false);
    final visibility = await settingsRepo.getFuelVisibility();
    expect(visibility['es100'], false);
    expect(visibility['es95'], true);
  });
}
