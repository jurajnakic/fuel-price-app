import 'package:dio/dio.dart';
import '../../models/station.dart';

class StationPriceService {
  final Dio dio;
  static const _url =
      'https://raw.githubusercontent.com/jurajnakic/fuel-price-app/main/config/station_prices.json';

  StationPriceService({Dio? dio}) : dio = dio ?? Dio();

  Future<StationsResponse?> fetchStations() async {
    try {
      final response = await dio.get(_url);
      final data = response.data as Map<String, dynamic>;
      return StationsResponse.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
