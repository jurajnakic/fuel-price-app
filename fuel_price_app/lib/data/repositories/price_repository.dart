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

  /// Calculate historical fuel prices from commodity prices + exchange rates.
  /// For each day in the output range, applies the NN 31/2025 formula using a
  /// 14-calendar-day observation window ending on that day.
  /// Uses the primary data source per fuel type based on sourceWeights.
  Future<List<FuelPrice>> getCalculatedHistory(
    FuelType fuelType, {
    required int days,
    required FuelParams params,
    int windowSize = 14,
  }) async {
    // Determine primary source from sourceWeights
    final weights = params.sourceWeights[fuelType.paramKey] ?? {'yahoo': 1.0};
    String primarySource = 'yahoo';
    double maxWeight = 0;
    for (final entry in weights.entries) {
      if (entry.value > maxWeight) {
        maxWeight = entry.value;
        primarySource = entry.key;
      }
    }

    // Resolve symbol, factor, offset for the primary source
    late final String symbol;
    late final double factor;
    late final double offset;

    switch (primarySource) {
      case 'eia':
        symbol = params.eiaSymbols[fuelType.paramKey] ?? '';
        factor = params.eiaCifMedFactors[fuelType.paramKey] ?? 1.0;
        offset = params.eiaCifMedOffsets[fuelType.paramKey] ?? 0.0;
      case 'oilapi':
        symbol = params.oilApiSymbols[fuelType.paramKey] ?? '';
        factor = params.oilApiCifMedFactors[fuelType.paramKey] ?? 1.0;
        offset = params.oilApiCifMedOffsets[fuelType.paramKey] ?? 0.0;
      default: // yahoo
        symbol = params.yahooSymbols[fuelType.paramKey] ?? 'BZ=F';
        factor = params.cifMedFactors[fuelType.paramKey] ?? 399.0;
        offset = params.cifMedOffsets[fuelType.paramKey] ?? 0.0;
    }

    if (symbol.isEmpty) return [];

    // Fetch extra data for the lookback window
    final oilPrices = await getOilPrices(symbol, days: days + windowSize + 7);
    final rates = await getExchangeRates(days: days + windowSize + 7);
    if (oilPrices.isEmpty || rates.isEmpty) return [];

    // Build date → rate lookup for per-date exchange rates
    final rateByDate = <String, double>{};
    for (final r in rates) {
      rateByDate[r.date.toIso8601String().substring(0, 10)] = r.usdEur;
    }
    final fallbackRate = rates.last.usdEur;

    // Find nearest rate on or before a given date
    double findRate(DateTime date) {
      // Try exact date first
      final key = date.toIso8601String().substring(0, 10);
      if (rateByDate.containsKey(key)) return rateByDate[key]!;
      // Walk backwards up to 5 days (weekends/holidays)
      for (var d = 1; d <= 5; d++) {
        final prev = date.subtract(Duration(days: d)).toIso8601String().substring(0, 10);
        if (rateByDate.containsKey(prev)) return rateByDate[prev]!;
      }
      return fallbackRate;
    }

    final engine = FormulaEngine(params);
    final result = <FuelPrice>[];
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days));

    // For each day in the display range, compute: "what would the retail price
    // be if the price cycle ended on this day?" using a 14-calendar-day window.
    for (var d = 0; d <= days; d++) {
      final windowEnd = startDate.add(Duration(days: d + 1)); // exclusive end
      final windowStart = windowEnd.subtract(Duration(days: windowSize));

      // Gather all data points within the calendar window
      final window = oilPrices
          .where((p) => !p.date.isBefore(windowStart) && p.date.isBefore(windowEnd))
          .toList();

      if (window.isEmpty) continue;

      final cifValues = window.map((p) => p.cifMed * factor + offset).toList();
      final rateValues = window.map((p) => findRate(p.date)).toList();

      try {
        final price = engine.predictPrice(fuelType, cifValues, rateValues);
        result.add(FuelPrice(
          fuelType: fuelType,
          date: windowEnd.subtract(const Duration(days: 1)),
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
