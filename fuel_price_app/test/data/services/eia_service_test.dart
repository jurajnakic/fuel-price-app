import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/eia_service.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

void main() {
  late EiaService service;
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
  });

  setUp(() {
    mockDio = MockDio();
    service = EiaService(dio: mockDio, apiKey: 'test-key');
  });

  test('parses daily spot prices from EIA API response', () async {
    final jsonData = {
      'response': {
        'data': [
          {
            'period': '2026-03-20',
            'series-description': 'NY Harbor Conventional Gasoline',
            'value': '2.45',
            'units': '\$/GAL',
          },
          {
            'period': '2026-03-19',
            'series-description': 'NY Harbor Conventional Gasoline',
            'value': '2.42',
            'units': '\$/GAL',
          },
        ],
      },
    };

    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchSpotPrices('EER_EPMRU_PF4_Y35NY_DPG', days: 30);
    expect(prices.length, 2);
    expect(prices.first.date, DateTime.utc(2026, 3, 20));
    expect(prices.first.value, 2.45);
    expect(prices.last.value, 2.42);
  });

  test('returns empty list on API error', () async {
    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionTimeout,
    ));

    final prices = await service.fetchSpotPrices('EER_EPMRU_PF4_Y35NY_DPG', days: 30);
    expect(prices, isEmpty);
  });

  test('skips entries with null or "." value', () async {
    final jsonData = {
      'response': {
        'data': [
          {'period': '2026-03-20', 'value': '2.45'},
          {'period': '2026-03-19', 'value': '.'},
          {'period': '2026-03-18', 'value': null},
          {'period': '2026-03-17', 'value': '2.40'},
        ],
      },
    };

    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchSpotPrices('EER_EPMRU_PF4_Y35NY_DPG', days: 30);
    expect(prices.length, 2);
    expect(prices.first.value, 2.45);
    expect(prices.last.value, 2.40);
  });
}
