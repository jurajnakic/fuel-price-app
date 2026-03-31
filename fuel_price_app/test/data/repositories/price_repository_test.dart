import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/oil_price.dart';
import 'package:fuel_price_app/models/exchange_rate.dart';

void main() {
  late AppDatabase db;
  late PriceRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    repo = PriceRepository(db);
  });

  tearDown(() async => await db.close());

  test('saves and retrieves oil prices', () async {
    final price = OilPrice(date: DateTime(2026, 3, 20), cifMed: 700.5, source: 'BZ=F');
    await repo.saveOilPrice(price);
    final prices = await repo.getOilPrices('BZ=F', days: 30);
    expect(prices.length, 1);
    expect(prices.first.cifMed, 700.5);
  });

  test('saves and retrieves exchange rates', () async {
    final rate = ExchangeRate(date: DateTime(2026, 3, 20), usdEur: 0.92);
    await repo.saveExchangeRate(rate);
    final rates = await repo.getExchangeRates(days: 30);
    expect(rates.length, 1);
    expect(rates.first.usdEur, 0.92);
  });

  test('saves and retrieves fuel prices', () async {
    final fp = FuelPrice(
      fuelType: FuelType.es95,
      date: DateTime(2026, 3, 25),
      price: 1.48,
      isPrediction: true,
    );
    await repo.saveFuelPrice(fp);
    final latest = await repo.getLatestPrice(FuelType.es95, prediction: true);
    expect(latest?.price, 1.48);
  });

  test('getLatestPrice returns null when empty', () async {
    final result = await repo.getLatestPrice(FuelType.es95, prediction: false);
    expect(result, isNull);
  });

  test('getPriceHistory reflects upsert — latest non-prediction wins', () async {
    await repo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95, date: DateTime(2026, 3, 10), price: 1.45, isPrediction: false));
    // saveFuelPrice upserts by (fuelType, isPrediction), so this replaces the previous row
    await repo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95, date: DateTime(2026, 3, 24), price: 1.48, isPrediction: false));
    final history = await repo.getPriceHistory(FuelType.es95, days: 30);
    expect(history.length, 1);
    expect(history.first.price, 1.48);
  });

  test('deletes old records', () async {
    final old = OilPrice(date: DateTime(2023, 1, 1), cifMed: 500, source: 'BZ=F');
    await repo.saveOilPrice(old);
    await repo.cleanOldData(const Duration(days: 730));
    final prices = await repo.getOilPrices('BZ=F', days: 9999);
    expect(prices, isEmpty);
  });
}
