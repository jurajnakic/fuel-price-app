import 'package:dio/dio.dart';
import '../../models/fuel_params.dart';

class RemoteConfigService {
  final Dio dio;
  static const _configUrl =
      'https://raw.githubusercontent.com/iersegovic/fuel-price-app/main/config/fuel_params.json';

  RemoteConfigService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch remote config. Returns null on any failure.
  Future<FuelParams?> fetchParams() async {
    try {
      final response = await dio.get(_configUrl);
      final data = response.data as Map<String, dynamic>;
      return FuelParams.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
