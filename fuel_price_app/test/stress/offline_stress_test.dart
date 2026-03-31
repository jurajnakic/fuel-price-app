import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Offline / empty state stress tests', () {
    blocTest<DataSyncCubit, DataSyncState>(
      'first launch, no internet — emits SyncFailure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('No internet'),
          fetchExchangeRates: () async => throw Exception('No internet'),
          fetchConfig: () async => throw Exception('No internet'),
          fetchEiaSpotPrices: () async => throw Exception('No internet'),
          fetchOilApiPrices: () async => throw Exception('No internet'),
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        isA<SyncFailure>(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'first launch, success — emits SyncSuccess',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [80.0],
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'retry after failure then success',
      build: () {
        int attempt = 0;
        return DataSyncCubit(
          orchestrator: DataSyncOrchestrator(
            fetchOilPrices: () async {
              attempt++;
              if (attempt <= 2) throw Exception('fail');
              return [80.0];
            },
            fetchExchangeRates: () async => [0.92],
            fetchConfig: () async => {'version': '1'},
            timeout: const Duration(seconds: 2),
          ),
          onSyncResult: (_) async {},
        );
      },
      act: (cubit) async {
        await cubit.sync(); // first try — oil fails
        await cubit.sync(); // second try — oil succeeds
      },
      expect: () => [
        const SyncInProgress(),
        isA<SyncPartial>(),
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'multiple retries all fail — no crash or infinite loop',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => throw Exception('fail'),
          fetchConfig: () async => throw Exception('fail'),
          fetchEiaSpotPrices: () async => throw Exception('fail'),
          fetchOilApiPrices: () async => throw Exception('fail'),
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) async {
        await cubit.sync();
        await cubit.sync();
        await cubit.sync();
      },
      expect: () => [
        const SyncInProgress(),
        isA<SyncFailure>(),
        const SyncInProgress(),
        isA<SyncFailure>(),
        const SyncInProgress(),
        isA<SyncFailure>(),
      ],
    );
  });
}
