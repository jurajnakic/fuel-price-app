import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/station_price_service.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late StationPriceService service;

  setUp(() {
    mockDio = MockDio();
    service = StationPriceService(dio: mockDio);
  });

  test('fetchStations returns parsed stations on success', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'updated': '2026-03-25T08:00:00Z',
            'stations': [
              {
                'id': 'ina',
                'name': 'INA',
                'url': 'https://www.ina.hr',
                'updated': '2026-03-25',
                'fuels': [
                  {'name': 'Eurosuper 95', 'type': 'es95', 'price': 1.45},
                ],
              },
            ],
          },
        ));

    final result = await service.fetchStations();
    expect(result, isNotNull);
    expect(result!.stations.length, 1);
    expect(result.stations.first.id, 'ina');
  });

  test('fetchStations returns null on failure', () async {
    when(() => mockDio.get(any())).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
    ));

    final result = await service.fetchStations();
    expect(result, isNull);
  });
}
