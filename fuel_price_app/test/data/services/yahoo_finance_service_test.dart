import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/yahoo_finance_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late YahooFinanceService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = YahooFinanceService(dio: mockDio);
  });

  test('parses historical prices from CSV response', () async {
    const csvData = 'Date,Open,High,Low,Close,Adj Close,Volume\n'
        '2026-03-10,71.5,72.0,70.8,71.2,71.2,100000\n'
        '2026-03-11,71.3,71.8,70.5,71.0,71.0,120000\n';

    when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => Response(
      data: csvData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 2);
    expect(prices.first.close, 71.2);
    expect(prices.first.date, DateTime(2026, 3, 10));
  });

  test('handles null/zero close prices', () async {
    const csvData = 'Date,Open,High,Low,Close,Adj Close,Volume\n'
        '2026-03-10,71.5,72.0,70.8,null,71.2,100000\n'
        '2026-03-11,71.3,71.8,70.5,71.0,71.0,120000\n';

    when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => Response(
      data: csvData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 1);
  });

  test('empty CSV returns empty list', () async {
    const csvData = 'Date,Open,High,Low,Close,Adj Close,Volume\n';

    when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => Response(
      data: csvData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices, isEmpty);
  });
}
