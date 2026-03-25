import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/station.dart';

class StationPriceService {
  final Dio dio;
  static const _url =
      'https://raw.githubusercontent.com/jurajnakic/fuel-price-app/main/config/station_prices.json';

  StationPriceService({Dio? dio}) : dio = dio ?? Dio();

  Future<StationsResponse?> fetchStations() async {
    try {
      final response = await dio.get(_url);
      // raw.githubusercontent.com returns text/plain, so Dio may not auto-decode
      final Map<String, dynamic> data;
      if (response.data is String) {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else {
        data = response.data as Map<String, dynamic>;
      }
      final result = StationsResponse.fromJson(data);
      debugPrint('StationPriceService: loaded ${result.stations.length} stations');
      return result;
    } catch (e) {
      debugPrint('StationPriceService: ERROR $e');
      return null;
    }
  }
}
