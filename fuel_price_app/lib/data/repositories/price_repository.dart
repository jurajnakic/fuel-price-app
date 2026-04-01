import '../database.dart';
import '../../models/oil_price.dart';
import '../../models/exchange_rate.dart';
import '../../models/fuel_price.dart';
import '../../models/fuel_type.dart';
import '../../models/fuel_params.dart';
import '../../domain/formula_engine.dart';

class PriceRepository {
  final AppDatabase db;

  PriceRepository(this.db);

  Future<void> saveOilPrice(OilPrice price) async {
    // Upsert: delete existing for same date+source, then insert
    final dateStr = price.date.toIso8601String().substring(0, 10);
    await db.delete('oil_prices',
        where: 'date LIKE ? AND source = ?',
        whereArgs: ['$dateStr%', price.source]);
    await db.insert('oil_prices', price.toMap());
  }

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

  Future<void> saveExchangeRate(ExchangeRate rate) async {
    final dateStr = rate.date.toIso8601String().substring(0, 10);
    await db.delete('exchange_rates',
        where: 'date LIKE ?', whereArgs: ['$dateStr%']);
    await db.insert('exchange_rates', rate.toMap());
  }

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

  Future<void> saveFuelPrice(FuelPrice price) async {
    // Upsert: delete existing for same fuel type + prediction type, then insert fresh
    await db.delete('fuel_prices',
        where: 'fuel_type = ? AND is_prediction = ?',
        whereArgs: [price.fuelType.name, price.isPrediction ? 1 : 0]);
    await db.insert('fuel_prices', price.toMap());
  }

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

  /// Calculate historical fuel prices from commodity prices + exchange rates using the formula.
  /// Uses the correct Yahoo symbol per fuel type (RB=F for gasoline, HO=F for diesel, BZ=F for LPG).
  Future<List<FuelPrice>> getCalculatedHistory(
    FuelType fuelType, {
    required int days,
    required FuelParams params,
    int windowSize = 14,
  }) async {
    final symbol = params.yahooSymbols[fuelType.paramKey] ?? 'BZ=F';
    final factor = params.cifMedFactors[fuelType.paramKey] ?? 399.0;

    final oilPrices = await getOilPrices(symbol, days: days + windowSize);
    final rates = await getExchangeRates(days: days + windowSize);
    if (oilPrices.length < windowSize || rates.isEmpty) return [];

    final engine = FormulaEngine(params);
    final lastRate = rates.last.usdEur;
    final result = <FuelPrice>[];

    // Calculate a price for every data point (sliding window)
    for (var i = windowSize; i <= oilPrices.length; i++) {
      final window = oilPrices.sublist(i - windowSize, i);
      // Convert raw Yahoo price → CIF Med USD/tonne
      final cifValues = window.map((p) => p.cifMed * factor).toList();
      final rateValues = List.generate(cifValues.length, (_) => lastRate);

      try {
        final price = engine.predictPrice(fuelType, cifValues, rateValues);
        result.add(FuelPrice(
          fuelType: fuelType,
          date: window.last.date,
          price: price,
          isPrediction: false,
        ));
      } catch (_) {
        // skip if calculation fails
      }
    }
    return result;
  }

  Future<void> cleanOldData(Duration maxAge) async {
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String().substring(0, 10);
    await db.delete('oil_prices', where: 'date < ?', whereArgs: [cutoff]);
    await db.delete('exchange_rates', where: 'date < ?', whereArgs: [cutoff]);
    await db.delete('fuel_prices', where: 'date < ?', whereArgs: [cutoff]);
  }
}
