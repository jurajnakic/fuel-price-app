import 'package:dio/dio.dart';

class EiaPrice {
  final DateTime date;
  final double value;

  EiaPrice({required this.date, required this.value});
}

class EiaService {
  final Dio dio;
  final String apiKey;

  static const _baseUrl = 'https://api.eia.gov/v2/petroleum/pri/spt/data/';

  EiaService({Dio? dio, required this.apiKey}) : dio = dio ?? Dio();

  // ignore: avoid_print
  static void _log(String msg) => print('[EIA] $msg');

  /// Parse a date string like '2026-03-20' as a UTC DateTime.
  static DateTime _parseUtcDate(String period) {
    final parts = period.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Fetch daily spot prices for an EIA series.
  Future<List<EiaPrice>> fetchSpotPrices(String seriesId, {int days = 60}) async {
    try {
      final start = DateTime.now().subtract(Duration(days: days + 7));
      final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

      _log('fetching $seriesId from $startStr');
      final response = await dio.get(
        _baseUrl,
        queryParameters: {
          'api_key': apiKey,
          'frequency': 'daily',
          'data[]': 'value',
          'facets[series][]': seriesId,
          'start': startStr,
          'sort[0][column]': 'period',
          'sort[0][direction]': 'asc',
          'length': '5000',
        },
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = response.data;
      final rows = (data['response']?['data'] as List?) ?? [];

      final prices = <EiaPrice>[];
      for (final row in rows) {
        final period = row['period'] as String?;
        final rawValue = row['value'];
        if (period == null) continue;

        final valueStr = rawValue?.toString();
        if (valueStr == null || valueStr == '.' || valueStr.isEmpty) continue;
        final value = double.tryParse(valueStr);
        if (value == null) continue;

        prices.add(EiaPrice(
          date: _parseUtcDate(period),
          value: value,
        ));
      }

      _log('got ${prices.length} prices for $seriesId');
      return prices;
    } catch (e) {
      _log('FAILED for $seriesId: $e');
      return [];
    }
  }
}
