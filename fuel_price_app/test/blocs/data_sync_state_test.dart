import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';

void main() {
  test('SyncIdle is initial state', () {
    const state = SyncIdle();
    expect(state, isA<DataSyncState>());
  });

  test('SyncInProgress is distinct from SyncIdle', () {
    expect(const SyncIdle() == const SyncInProgress(), isFalse);
  });

  test('SyncSuccess is distinct', () {
    expect(const SyncSuccess(), isA<DataSyncState>());
  });

  test('SyncPartial contains list of failed source names', () {
    const state = SyncPartial(failedSources: ['yahoo', 'hnb']);
    expect(state.failedSources, ['yahoo', 'hnb']);
  });

  test('SyncFailure contains message', () {
    const state = SyncFailure(message: 'No internet');
    expect(state.message, 'No internet');
  });

  test('two SyncPartial with same failures are equal', () {
    const a = SyncPartial(failedSources: ['yahoo']);
    const b = SyncPartial(failedSources: ['yahoo']);
    expect(a, equals(b));
  });
}
