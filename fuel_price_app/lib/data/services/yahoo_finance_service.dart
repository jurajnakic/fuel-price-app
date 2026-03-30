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

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Fetch historical closing prices for a symbol.
  /// Tries multiple endpoints for resilience.
  Future<List<YahooFinancePrice>> fetchHistoricalPrices(String symbol, int days) async {
    // Try multiple endpoints — Yahoo rotates availability
    final attempts = [
      () => _fetchFromChartApi('query2.finance.yahoo.com', symbol, days),
      () => _fetchFromChartApi('query1.finance.yahoo.com', symbol, days),
      () => _fetchFromCsvApi(symbol, days),
    ];

    for (var i = 0; i < attempts.length; i++) {
      try {
        _log('trying endpoint ${i + 1}/${attempts.length} for $symbol');
        final result = await attempts[i]();
        if (result.isNotEmpty) {
          _log('got ${result.length} prices for $symbol from endpoint ${i + 1}');
          return result;
        }
        _log('endpoint ${i + 1} returned empty for $symbol');
      } catch (e) {
        _log('endpoint ${i + 1} failed for $symbol — $e');
      }
    }

    _log('ALL attempts failed for $symbol');
    return [];
  }

  // ignore: avoid_print
  static void _log(String msg) => print('[YahooFinance] $msg');

  /// v8 chart API — JSON, no auth required
  Future<List<YahooFinancePrice>> _fetchFromChartApi(String host, String symbol, int days) async {
    final url = 'https://$host/v8/finance/chart/$symbol';
    _log('GET $url?range=${days}d&interval=1d');
    final response = await dio.get(
      url,
      queryParameters: {
        'range': '${days}d',
        'interval': '1d',
      },
      options: Options(
        headers: {'User-Agent': _userAgent},
        responseType: ResponseType.json,
      ),
    );

    _log('response status=${response.statusCode} type=${response.data.runtimeType}');
    final data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;

    final result = data['chart']['result'][0];
    final timestamps = result['timestamp'] as List?;
    if (timestamps == null || timestamps.isEmpty) return [];

    final closes = result['indicators']['quote'][0]['close'] as List;

    final prices = <YahooFinancePrice>[];
    for (var i = 0; i < timestamps.length; i++) {
      final close = closes[i];
      if (close == null) continue;
      prices.add(YahooFinancePrice(
        date: DateTime.fromMillisecondsSinceEpoch(
          (timestamps[i] as int) * 1000,
          isUtc: true,
        ),
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
      options: Options(
        headers: {'User-Agent': _userAgent},
      ),
    );

    final body = response.data;
    if (body is! String) throw FormatException('Expected CSV string, got ${body.runtimeType}');
    return _parseCsv(body);
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
