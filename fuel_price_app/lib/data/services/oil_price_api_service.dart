import 'package:dio/dio.dart';

class OilApiPrice {
  final DateTime date;
  final double value;

  OilApiPrice({required this.date, required this.value});
}

class OilPriceApiService {
  final Dio dio;
  final String apiKey;
  int? _remainingRequests;

  static const _baseUrl = 'https://api.oilpriceapi.com/v1/prices/latest';
  static const _recentUrl = 'https://api.oilpriceapi.com/v1/prices';

  OilPriceApiService({Dio? dio, required this.apiKey}) : dio = dio ?? Dio();

  int? get remainingRequests => _remainingRequests;

  // ignore: avoid_print
  static void _log(String msg) => print('[OilPriceAPI] $msg');

  /// Fetch latest price for a commodity code.
  Future<OilApiPrice?> fetchLatestPrice(String commodityCode) async {
    try {
      _log('fetching $commodityCode');
      final response = await dio.get(
        _baseUrl,
        options: Options(
          headers: {
            'Authorization': 'Token $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 10),
        ),
        queryParameters: {
          'by_code': commodityCode,
        },
      );

      // Track rate limit from headers
      final remaining = response.headers.value('x-ratelimit-remaining');
      if (remaining != null) {
        _remainingRequests = int.tryParse(remaining);
        _log('remaining requests: $_remainingRequests');
      }

      final data = response.data;
      if (data['status'] != 'success') {
        _log('non-success status: ${data['status']}');
        return null;
      }

      final priceData = data['data'];
      final price = (priceData['price'] as num?)?.toDouble();
      final createdAt = priceData['created_at'] as String?;
      if (price == null || createdAt == null) return null;

      final date = DateTime.parse(createdAt);
      _log('got $commodityCode = $price at $date');

      return OilApiPrice(date: date, value: price);
    } catch (e) {
      _log('FAILED for $commodityCode: $e');
      return null;
    }
  }

  /// Fetch every recent point for a commodity code, newest first.
  ///
  /// Uses /v1/prices, which returns ~25 intraday points instead of the single
  /// point /prices/latest gives. The `past` parameter is accepted but ignored
  /// on the free tier (verified 2026-08-24: past=1w and past=24h both return
  /// only the last few hours), so this is redundancy against one failed poll,
  /// NOT a backfill — a day the app never polls is still lost for good.
  ///
  /// Returns an empty list on any failure; callers treat empty as "no data"
  /// rather than as an error, and must not persist a throttle marker for it.
  Future<List<OilApiPrice>> fetchRecentPrices(String commodityCode) async {
    try {
      _log('fetching recent $commodityCode');
      final response = await dio.get(
        _recentUrl,
        options: Options(
          headers: {
            'Authorization': 'Token $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 10),
        ),
        queryParameters: {
          'by_code': commodityCode,
          'past': '24h',
        },
      );

      final remaining = response.headers.value('x-ratelimit-remaining');
      if (remaining != null) {
        _remainingRequests = int.tryParse(remaining);
      }

      final data = response.data;
      if (data['status'] != 'success') {
        _log('recent non-success status: ${data['status']}');
        return [];
      }

      final raw = data['data']?['prices'];
      if (raw is! List) {
        _log('recent payload has no prices list');
        return [];
      }

      final prices = <OilApiPrice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        // Synthetic points are the API's own interpolation. Storing them would
        // silently feed fitted values into the LS calibration.
        if (entry['synthetic'] == true) continue;
        final value = (entry['price'] as num?)?.toDouble();
        final createdAt = entry['created_at'] as String?;
        if (value == null || createdAt == null) continue;
        final date = DateTime.tryParse(createdAt);
        if (date == null) continue;
        prices.add(OilApiPrice(date: date, value: value));
      }

      _log('got ${prices.length} recent points for $commodityCode '
          '(remaining: $_remainingRequests)');
      return prices;
    } catch (e) {
      _log('FAILED recent for $commodityCode: $e');
      return [];
    }
  }

  /// Collapse intraday points to one per calendar day, keeping the newest.
  ///
  /// The DB holds at most one row per (day, source), so without this the row
  /// written would depend on iteration order rather than on recency.
  static Map<DateTime, OilApiPrice> latestPerDay(List<OilApiPrice> prices) {
    final byDay = <DateTime, OilApiPrice>{};
    for (final p in prices) {
      final day = DateTime.utc(p.date.year, p.date.month, p.date.day);
      final existing = byDay[day];
      if (existing == null || p.date.isAfter(existing.date)) {
        byDay[day] = p;
      }
    }
    return byDay;
  }
}
