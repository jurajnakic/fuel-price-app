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

  group('fetchRecentPrices', () {
    // Shape confirmed against the live free-tier endpoint on 2026-08-24:
    // /v1/prices?by_code=X&past=24h returns {data: {prices: [...]}} with ~25
    // intraday points. The `past` parameter is ignored on the free tier, so
    // this never reaches further back than the last few hours — it is
    // redundancy against a single failed poll, not a backfill.
    Response recentResponse(List<Map<String, dynamic>> prices) => Response(
          data: {
            'status': 'success',
            'data': {'prices': prices},
          },
          statusCode: 200,
          headers: Headers.fromMap({
            'x-ratelimit-remaining': ['48'],
          }),
          requestOptions: RequestOptions(path: ''),
        );

    Map<String, dynamic> point(double price, String createdAt) => {
          'price': price,
          'code': 'GASOIL_USD',
          'created_at': createdAt,
          'synthetic': false,
        };

    test('parses every intraday point, newest first', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => recentResponse([
            point(1277.50, '2026-08-24T10:27:37.420Z'),
            point(1277.25, '2026-08-24T10:22:22.134Z'),
            point(1278.75, '2026-08-24T10:12:23.374Z'),
          ]));

      final result = await service.fetchRecentPrices('GASOIL_USD');
      expect(result, hasLength(3));
      expect(result.first.value, 1277.50);
      expect(result.last.value, 1278.75);
      expect(service.remainingRequests, 48);
    });

    test('skips synthetic points so fitted data never enters the DB', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => recentResponse([
            point(1277.50, '2026-08-24T10:27:37.420Z'),
            {...point(9999.0, '2026-08-24T10:22:22.134Z'), 'synthetic': true},
          ]));

      final result = await service.fetchRecentPrices('GASOIL_USD');
      expect(result, hasLength(1));
      expect(result.single.value, 1277.50);
    });

    test('drops malformed points instead of failing the whole fetch', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => recentResponse([
            point(1277.50, '2026-08-24T10:27:37.420Z'),
            {'price': null, 'created_at': '2026-08-24T10:22:22.134Z'},
            {'price': 1280.0, 'created_at': 'not-a-date'},
          ]));

      final result = await service.fetchRecentPrices('GASOIL_USD');
      expect(result, hasLength(1));
      expect(result.single.value, 1277.50);
    });

    test('returns empty list on transport error', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
            queryParameters: any(named: 'queryParameters'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionTimeout,
      ));

      expect(await service.fetchRecentPrices('GASOIL_USD'), isEmpty);
    });

    test('returns empty list when status is not success', () async {
      when(() => mockDio.get(
            any(),
            options: any(named: 'options'),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => Response(
            data: {'status': 'error', 'message': 'UPGRADE_REQUIRED'},
            statusCode: 402,
            requestOptions: RequestOptions(path: ''),
          ));

      expect(await service.fetchRecentPrices('GASOIL_USD'), isEmpty);
    });
  });

  group('latestPerDay', () {
    test('keeps the newest point of each calendar day', () {
      final points = [
        OilApiPrice(date: DateTime.utc(2026, 8, 24, 10, 27), value: 1277.5),
        OilApiPrice(date: DateTime.utc(2026, 8, 24, 6, 27), value: 1270.0),
        OilApiPrice(date: DateTime.utc(2026, 8, 23, 15, 0), value: 1296.75),
      ];

      final result = OilPriceApiService.latestPerDay(points);
      expect(result, hasLength(2));
      expect(result[DateTime.utc(2026, 8, 24)]!.value, 1277.5);
      expect(result[DateTime.utc(2026, 8, 23)]!.value, 1296.75);
    });

    test('returns empty map for empty input', () {
      expect(OilPriceApiService.latestPerDay([]), isEmpty);
    });
  });
}
