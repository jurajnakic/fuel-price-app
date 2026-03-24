import '../database.dart';
import '../../models/oil_price.dart';
import '../../models/exchange_rate.dart';
import '../../models/fuel_price.dart';
import '../../models/fuel_type.dart';

class PriceRepository {
  final AppDatabase db;

  PriceRepository(this.db);

  Future<void> saveOilPrice(OilPrice price) async =>
      await db.insert('oil_prices', price.toMap());

  Future<List<OilPrice>> getOilPrices(String source, {required int days}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.query(
      'oil_prices',
      where: 'source = ? AND date >= ?',
      whereArgs: [source, cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'date ASC',
    );
    return rows.map(OilPrice.fromMap).toList();
  }

  Future<void> saveExchangeRate(ExchangeRate rate) async =>
      await db.insert('exchange_rates', rate.toMap());

  Future<List<ExchangeRate>> getExchangeRates({required int days}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.query(
      'exchange_rates',
      where: 'date >= ?',
      whereArgs: [cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'date ASC',
    );
    return rows.map(ExchangeRate.fromMap).toList();
  }

  Future<void> saveFuelPrice(FuelPrice price) async =>
      await db.insert('fuel_prices', price.toMap());

  Future<FuelPrice?> getLatestPrice(FuelType fuelType, {required bool prediction}) async {
    final rows = await db.query(
      'fuel_prices',
      where: 'fuel_type = ? AND is_prediction = ?',
      whereArgs: [fuelType.name, prediction ? 1 : 0],
      orderBy: 'date DESC',
    );
    if (rows.isEmpty) return null;
    return FuelPrice.fromMap(rows.first);
  }

  Future<List<FuelPrice>> getPriceHistory(FuelType fuelType, {required int days}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.query(
      'fuel_prices',
      where: 'fuel_type = ? AND is_prediction = 0 AND date >= ?',
      whereArgs: [fuelType.name, cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'date ASC',
    );
    return rows.map(FuelPrice.fromMap).toList();
  }

  Future<void> cleanOldData(Duration maxAge) async {
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String().substring(0, 10);
    await db.delete('oil_prices', where: 'date < ?', whereArgs: [cutoff]);
    await db.delete('exchange_rates', where: 'date < ?', whereArgs: [cutoff]);
    await db.delete('fuel_prices', where: 'date < ?', whereArgs: [cutoff]);
  }
}
