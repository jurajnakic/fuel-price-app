import 'dart:convert';
import 'package:dio/dio.dart';

class YahooFinancePrice {
  final DateTime date;
  final double close;

  YahooFinancePrice({required this.date, required this.close});
}

class YahooFinanceService {
  final Dio dio;

  YahooFinanceService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch historical closing prices for a symbol.
  /// [symbol]: 'BZ=F' (Brent), 'RB=F' (RBOB), 'HO=F' (Heating Oil)
  /// [days]: number of calendar days to look back
  Future<List<YahooFinancePrice>> fetchHistoricalPrices(String symbol, int days) async {
    // Try v8 chart API first (no auth required), fall back to v7 CSV
    try {
      return await _fetchFromChartApi(symbol, days);
    } catch (_) {
      return await _fetchFromCsvApi(symbol, days);
    }
  }

  /// v8 chart API — JSON, no auth required
  Future<List<YahooFinancePrice>> _fetchFromChartApi(String symbol, int days) async {
    final response = await dio.get(
      'https://query1.finance.yahoo.com/v8/finance/chart/$symbol',
      queryParameters: {
        'range': '${days}d',
        'interval': '1d',
      },
      options: Options(headers: {
        'User-Agent': 'Mozilla/5.0',
      }),
    );

    final data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;

    final result = data['chart']['result'][0];
    final timestamps = (result['timestamp'] as List).cast<int>();
    final closes = (result['indicators']['quote'][0]['close'] as List);

    final prices = <YahooFinancePrice>[];
    for (var i = 0; i < timestamps.length; i++) {
      final close = closes[i];
      if (close == null) continue;
      prices.add(YahooFinancePrice(
        date: DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000, isUtc: true),
        close: (close as num).toDouble(),
      ));
    }
    return prices;
  }

  /// v7 CSV download API — may require cookie/crumb
  Future<List<YahooFinancePrice>> _fetchFromCsvApi(String symbol, int days) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days + 7));
    final period1 = from.millisecondsSinceEpoch ~/ 1000;
    final period2 = now.millisecondsSinceEpoch ~/ 1000;

    final response = await dio.get(
      'https://query1.finance.yahoo.com/v7/finance/download/$symbol',
      queryParameters: {
        'period1': period1,
        'period2': period2,
        'interval': '1d',
        'events': 'history',
      },
      options: Options(headers: {
        'User-Agent': 'Mozilla/5.0',
      }),
    );

    return _parseCsv(response.data as String);
  }

  List<YahooFinancePrice> _parseCsv(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.length < 2) return [];

    return lines.skip(1).where((line) => line.trim().isNotEmpty).map((line) {
      final cols = line.split(',');
      final date = DateTime.parse(cols[0]);
      final close = double.tryParse(cols[4]) ?? 0;
      return YahooFinancePrice(date: date, close: close);
    }).where((p) => p.close > 0).toList();
  }
}
