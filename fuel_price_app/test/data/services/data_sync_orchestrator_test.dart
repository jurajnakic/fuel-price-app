import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('DataSyncOrchestrator', () {
    test('all sources succeed returns SyncResult with all success', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0, 2.0],
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.exchangeRatesOk, isTrue);
      expect(result.configOk, isTrue);
      expect(result.isFullSuccess, isTrue);
      expect(result.isFullFailure, isFalse);
    });

    test('one source fails, retries once, then partial', () async {
      int yahooAttempts = 0;
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async {
          yahooAttempts++;
          throw Exception('Network error');
        },
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(yahooAttempts, 2); // initial + 1 retry
      expect(result.oilPricesOk, isFalse);
      expect(result.exchangeRatesOk, isTrue);
      expect(result.configOk, isTrue);
      expect(result.isFullSuccess, isFalse);
      expect(result.isFullFailure, isFalse);
      expect(result.failedSources, ['oilPrices']);
    });

    test('all sources fail returns full failure', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('fail'),
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => throw Exception('fail'),
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.isFullFailure, isTrue);
    });

    test('source timeout triggers retry', () async {
      int attempts = 0;
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async {
          attempts++;
          if (attempts == 1) {
            await Future.delayed(const Duration(seconds: 5));
          }
          return [1.0];
        },
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(attempts, 2);
      expect(result.oilPricesOk, isTrue);
      expect(result.isFullSuccess, isTrue);
    });

    test('retry also fails keeps source as failed', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('always fails'),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isFalse);
      expect(result.failedSources, ['oilPrices']);
    });

    test('successful data is available via result even on partial failure', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0, 2.0],
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPrices, [1.0, 2.0]);
      expect(result.exchangeRates, isNull);
      expect(result.config, {'version': '1'});
    });
  });
}
