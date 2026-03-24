import 'package:dio/dio.dart';

class HnbService {
  final Dio dio;
  static const _baseUrl = 'https://api.hnb.hr/tecajn-eur/v3';

  HnbService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch current USD/EUR middle rate (1 USD = X EUR)
  Future<double> fetchUsdEurRate() async {
    final response = await dio.get('$_baseUrl?valuta=USD');
    final data = response.data as List;
    if (data.isEmpty) throw Exception('No USD rate from HNB');
    final rateStr = data[0]['srednji_tecaj'] as String;
    return double.parse(rateStr.replaceAll(',', '.'));
  }

  /// Fetch USD/EUR rate for a specific date
  Future<double> fetchUsdEurRateForDate(DateTime date) async {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final response = await dio.get('$_baseUrl?valuta=USD&datum-primjene=$dateStr');
    final data = response.data as List;
    if (data.isEmpty) throw Exception('No USD rate from HNB for $dateStr');
    final rateStr = data[0]['srednji_tecaj'] as String;
    return double.parse(rateStr.replaceAll(',', '.'));
  }
}
