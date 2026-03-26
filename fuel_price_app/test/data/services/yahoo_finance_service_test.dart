import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/yahoo_finance_service.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

void main() {
  late YahooFinanceService service;
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
  });

  setUp(() {
    mockDio = MockDio();
    service = YahooFinanceService(dio: mockDio);
  });

  test('parses historical prices from v8 chart API JSON response', () async {
    final jsonData = {
      'chart': {
        'result': [
          {
            'timestamp': [1741564800, 1741651200],
            'indicators': {
              'quote': [
                {
                  'close': [71.2, 71.0],
                }
              ]
            }
          }
        ]
      }
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

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 2);
    expect(prices.first.close, 71.2);
  });

  test('handles null close prices in v8 response', () async {
    final jsonData = {
      'chart': {
        'result': [
          {
            'timestamp': [1741564800, 1741651200],
            'indicators': {
              'quote': [
                {
                  'close': [null, 71.0],
                }
              ]
            }
          }
        ]
      }
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

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 1);
    expect(prices.first.close, 71.0);
  });

  test('falls back to next endpoint when first fails', () async {
    final jsonData = {
      'chart': {
        'result': [
          {
            'timestamp': [1741564800],
            'indicators': {
              'quote': [
                {'close': [71.2]}
              ]
            }
          }
        ]
      }
    };

    var callCount = 0;
    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenAnswer((_) async {
      callCount++;
      if (callCount == 1) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
        );
      }
      return Response(
        data: jsonData,
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      );
    });

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 1);
    expect(prices.first.close, 71.2);
    expect(callCount, 2);
  });

  test('empty v8 response returns empty list', () async {
    final jsonData = {
      'chart': {
        'result': [
          {
            'timestamp': <int>[],
            'indicators': {
              'quote': [
                {
                  'close': <double?>[],
                }
              ]
            }
          }
        ]
      }
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

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices, isEmpty);
  });
}
