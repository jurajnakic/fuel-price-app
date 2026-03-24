import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('DataSyncCubit', () {
    blocTest<DataSyncCubit, DataSyncState>(
      'emits [SyncInProgress, SyncSuccess] on full success',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [1.0],
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
      'emits [SyncInProgress, SyncPartial] on partial failure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        const SyncPartial(failedSources: ['oilPrices']),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'emits [SyncInProgress, SyncFailure] on full failure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => throw Exception('fail'),
          fetchConfig: () async => throw Exception('fail'),
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
      'ignores concurrent sync calls (no double fetch)',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async {
            await Future.delayed(const Duration(milliseconds: 500));
            return [1.0];
          },
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) {
        cubit.sync(); // first
        cubit.sync(); // should be ignored
        cubit.sync(); // should be ignored
      },
      wait: const Duration(seconds: 3),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'sets hasData to true after partial success',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [1.0],
          fetchExchangeRates: () async => throw Exception('fail'),
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      verify: (cubit) {
        expect(cubit.hasData, isTrue);
        expect(cubit.lastSyncTime, isNotNull);
      },
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'hasData stays false on full failure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => throw Exception('fail'),
          fetchConfig: () async => throw Exception('fail'),
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      verify: (cubit) {
        expect(cubit.hasData, isFalse);
        expect(cubit.lastSyncTime, isNull);
      },
    );
  });
}
