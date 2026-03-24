import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Concurrent operation stress tests', () {
    blocTest<DataSyncCubit, DataSyncState>(
      'rapid retry (5x) — only one sync runs at a time',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async {
            await Future.delayed(const Duration(milliseconds: 200));
            return [80.0];
          },
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) {
        for (int i = 0; i < 5; i++) {
          cubit.sync();
        }
      },
      wait: const Duration(seconds: 2),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'sequential syncs after completion work correctly',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [80.0],
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) async {
        await cubit.sync();
        await cubit.sync();
      },
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );
  });
}
