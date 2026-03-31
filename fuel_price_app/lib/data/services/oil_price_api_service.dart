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
}
