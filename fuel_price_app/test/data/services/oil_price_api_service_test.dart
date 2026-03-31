// test/data/services/oil_price_api_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/oil_price_api_service.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

void main() {
  late OilPriceApiService service;
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
  });

  setUp(() {
    mockDio = MockDio();
    service = OilPriceApiService(dio: mockDio, apiKey: 'test-token');
  });

  test('parses latest price from OilPriceAPI response', () async {
    final jsonData = {
      'status': 'success',
      'data': {
        'price': 720.50,
        'formatted': '\$720.50',
        'currency': 'USD',
        'code': 'MGO_05S_NLRTM_USD',
        'created_at': '2026-03-28T14:30:00Z',
      },
    };

    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
      queryParameters: any(named: 'queryParameters'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      headers: Headers.fromMap({
        'x-ratelimit-remaining': ['45'],
      }),
      requestOptions: RequestOptions(path: ''),
    ));

    final result = await service.fetchLatestPrice('MGO_05S_NLRTM_USD');
    expect(result, isNotNull);
    expect(result!.value, 720.50);
    expect(result.date.year, 2026);
    expect(service.remainingRequests, 45);
  });

  test('returns null on API error', () async {
    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
      queryParameters: any(named: 'queryParameters'),
    )).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionTimeout,
    ));

    final result = await service.fetchLatestPrice('MGO_05S_NLRTM_USD');
    expect(result, isNull);
  });

  test('returns null when status is not success', () async {
    final jsonData = {
      'status': 'error',
      'message': 'Invalid API key',
    };

    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
      queryParameters: any(named: 'queryParameters'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 401,
      requestOptions: RequestOptions(path: ''),
    ));

    final result = await service.fetchLatestPrice('MGO_05S_NLRTM_USD');
    expect(result, isNull);
  });
}
