import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late RemoteConfigService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = RemoteConfigService(dio: mockDio);
  });

  test('fetches and parses remote config', () async {
    final json = {
      'version': '2025-02-26',
      'price_cycle': {
        'reference_date': '2026-03-24',
        'cycle_days': 14,
      },
      'price_regulation': {
        'name': 'Test',
        'nn_reference': 'NN 31/2025',
        'effective_date': '2025-02-26',
      },
      'excise_regulation': {
        'name': 'Test',
        'nn_reference': 'NN 156/2022',
        'effective_date': '2023-01-01',
      },
      'premiums': {'es95': 0.1545},
      'excise_duties': {'es95': 0.456},
      'density': {'es95': 0.755},
      'vat_rate': 0.25,
    };

    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: json,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final params = await service.fetchParams();
    expect(params, isNotNull);
    expect(params!.version, '2025-02-26');
    expect(params.vatRate, 0.25);
    expect(params.cycleDays, 14);
  });

  test('returns null on fetch failure', () async {
    when(() => mockDio.get(any())).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionTimeout,
    ));

    final params = await service.fetchParams();
    expect(params, isNull);
  });
}
