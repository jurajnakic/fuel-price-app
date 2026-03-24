import 'package:equatable/equatable.dart';

sealed class DataSyncState extends Equatable {
  const DataSyncState();
}

class SyncIdle extends DataSyncState {
  const SyncIdle();
  @override
  List<Object?> get props => [];
}

class SyncInProgress extends DataSyncState {
  const SyncInProgress();
  @override
  List<Object?> get props => [];
}

class SyncSuccess extends DataSyncState {
  const SyncSuccess();
  @override
  List<Object?> get props => [];
}

class SyncPartial extends DataSyncState {
  final List<String> failedSources;
  const SyncPartial({required this.failedSources});
  @override
  List<Object?> get props => [failedSources];
}

class SyncFailure extends DataSyncState {
  final String message;
  const SyncFailure({required this.message});
  @override
  List<Object?> get props => [message];
}
