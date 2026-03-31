import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Data integrity stress tests', () {
    test('partial source failure — successful sources have data', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [80.0, 81.0],
        fetchExchangeRates: () async => throw Exception('HNB down'),
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPrices, [80.0, 81.0]);
      expect(result.exchangeRates, isNull);
      expect(result.config, isNotNull);
      expect(result.failedSources, ['exchangeRates']);
    });

    test('corrupt API response (exception) treated as failure', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw FormatException('Invalid JSON'),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isFalse);
      expect(result.exchangeRatesOk, isTrue);
    });

    test('retry succeeds after initial failure', () async {
      int attempt = 0;
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async {
          attempt++;
          if (attempt == 1) throw Exception('transient');
          return [80.0];
        },
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.isFullSuccess, isTrue);
      expect(attempt, 2);
    });

    test('all sources fail after retry', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('fail'),
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => throw Exception('fail'),
        fetchEiaSpotPrices: () async => throw Exception('fail'),
        fetchOilApiPrices: () async => throw Exception('fail'),
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.isFullFailure, isTrue);
      expect(result.oilPrices, isNull);
      expect(result.exchangeRates, isNull);
      expect(result.config, isNull);
    });
  });
}
