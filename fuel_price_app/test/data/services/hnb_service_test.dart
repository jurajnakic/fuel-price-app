import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/hnb_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late HnbService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = HnbService(dio: mockDio);
  });

  test('fetches USD/EUR rate', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: [
        {'srednji_tecaj': '0,920000', 'valuta': 'USD'}
      ],
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final rate = await service.fetchUsdEurRate();
    expect(rate, closeTo(0.92, 0.001));
  });

  test('throws on empty response', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: [],
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    expect(() => service.fetchUsdEurRate(), throwsException);
  });

  test('fetches rate for specific date', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: [
        {'srednji_tecaj': '0,930000', 'valuta': 'USD'}
      ],
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final rate = await service.fetchUsdEurRateForDate(DateTime(2026, 3, 20));
    expect(rate, closeTo(0.93, 0.001));
  });
}
