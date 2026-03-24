import 'package:bloc/bloc.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

class DataSyncCubit extends Cubit<DataSyncState> {
  final DataSyncOrchestrator orchestrator;
  final Future<void> Function(SyncResult result) onSyncResult;
  bool _syncing = false;
  bool _hasData = false;
  DateTime? _lastSyncTime;

  DataSyncCubit({
    required this.orchestrator,
    required this.onSyncResult,
  }) : super(const SyncIdle());

  bool get hasData => _hasData;
  DateTime? get lastSyncTime => _lastSyncTime;

  void setHasData(bool value) => _hasData = value;

  Future<void> sync() async {
    if (_syncing) return; // prevent concurrent syncs
    _syncing = true;
    emit(const SyncInProgress());

    try {
      final result = await orchestrator.sync();
      await onSyncResult(result);

      if (!result.isFullFailure) {
        _hasData = true;
        _lastSyncTime = DateTime.now();
      }

      if (result.isFullSuccess) {
        emit(const SyncSuccess());
      } else if (result.isFullFailure) {
        emit(const SyncFailure(message: 'Svi izvori podataka su nedostupni.'));
      } else {
        emit(SyncPartial(failedSources: result.failedSources));
      }
    } catch (e) {
      emit(SyncFailure(message: e.toString()));
    } finally {
      _syncing = false;
    }
  }
}
