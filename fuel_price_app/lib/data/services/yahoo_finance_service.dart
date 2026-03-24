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
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days + 7)); // buffer for weekends
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
