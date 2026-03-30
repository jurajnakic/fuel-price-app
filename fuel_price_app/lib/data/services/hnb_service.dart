import 'package:dio/dio.dart';

class HnbService {
  final Dio dio;

  // ECB provides daily USD/EUR reference rates (more reliable than HNB for historical data)
  static const _ecbUrl = 'https://data-api.ecb.europa.eu/service/data/EXR/D.USD.EUR.SP00.A';
  static const _hnbUrl = 'https://api.hnb.hr/tecajn-eur/v3';

  HnbService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch current USD/EUR rate (1 EUR = X USD).
  /// Tries ECB first, falls back to HNB.
  Future<double> fetchUsdEurRate() async {
    try {
      return await _fetchEcbLatest();
    } catch (_) {
      return await _fetchHnbRate();
    }
  }

  /// Fetch daily USD/EUR rates for the last [days] days from ECB.
  /// Returns list of (date, rate) pairs sorted by date.
  /// Rate is EUR/USD (1 EUR = X USD).
  Future<List<({DateTime date, double rate})>> fetchHistoricalRates(int days) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    final startStr = _fmtDate(start);
    final endStr = _fmtDate(end);

    try {
      final response = await dio.get(
        '$_ecbUrl?startPeriod=$startStr&endPeriod=$endStr&format=csvdata',
      );
      final csv = response.data as String;
      final results = <({DateTime date, double rate})>[];

      for (final line in csv.split('\n').skip(1)) {
        if (line.trim().isEmpty) continue;
        final cols = line.split(',');
        if (cols.length < 8) continue;
        final dateStr = cols[6]; // TIME_PERIOD
        final rateStr = cols[7]; // OBS_VALUE
        try {
          final date = DateTime.parse(dateStr);
          final rate = double.parse(rateStr);
          results.add((date: date, rate: rate));
        } catch (_) {
          continue;
        }
      }

      results.sort((a, b) => a.date.compareTo(b.date));
      return results;
    } catch (e) {
      // ignore: avoid_print
      print('[HnbService] ECB historical fetch failed: $e');
      return [];
    }
  }

  Future<double> _fetchEcbLatest() async {
    final response = await dio.get(
      '$_ecbUrl?lastNObservations=1&format=csvdata',
    );
    final csv = response.data as String;
    final lines = csv.split('\n');
    if (lines.length < 2) throw Exception('Empty ECB response');
    final cols = lines[1].split(',');
    if (cols.length < 8) throw Exception('Invalid ECB CSV');
    return double.parse(cols[7]);
  }

  Future<double> _fetchHnbRate() async {
    final response = await dio.get('$_hnbUrl?valuta=USD');
    final data = response.data as List;
    if (data.isEmpty) throw Exception('No USD rate from HNB');
    final rateStr = data[0]['srednji_tecaj'] as String;
    return double.parse(rateStr.replaceAll(',', '.'));
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
