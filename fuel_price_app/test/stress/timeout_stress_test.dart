import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Timeout stress tests', () {
    test('all sources timeout — result is full failure within reasonable time', () async {
      final sw = Stopwatch()..start();
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () => Future.delayed(const Duration(seconds: 15), () => [1.0]),
        fetchExchangeRates: () => Future.delayed(const Duration(seconds: 15), () => [0.92]),
        fetchConfig: () => Future.delayed(const Duration(seconds: 15), () => <String, dynamic>{}),
        fetchEiaSpotPrices: () => Future.delayed(const Duration(seconds: 15), () => [1.0]),
        fetchOilApiPrices: () => Future.delayed(const Duration(seconds: 15), () => [1.0]),
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      sw.stop();
      expect(result.isFullFailure, isTrue);
      // First attempt 2s (parallel) + retry 2s (parallel) = ~4s max
      expect(sw.elapsedMilliseconds, lessThan(10000));
    });

    test('one source timeout, others instant — partial result', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () => Future.delayed(const Duration(seconds: 15), () => [1.0]),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isFalse);
      expect(result.exchangeRatesOk, isTrue);
      expect(result.configOk, isTrue);
    });

    test('repeated timeouts do not accumulate state', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('fail'),
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => throw Exception('fail'),
        fetchEiaSpotPrices: () async => throw Exception('fail'),
        fetchOilApiPrices: () async => throw Exception('fail'),
        timeout: const Duration(seconds: 1),
      );
      for (int i = 0; i < 3; i++) {
        final result = await orchestrator.sync();
        expect(result.isFullFailure, isTrue);
      }
    });

    test('source responds just before timeout succeeds', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () => Future.delayed(const Duration(milliseconds: 900), () => [1.0]),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.isFullSuccess, isTrue);
    });
  });
}
