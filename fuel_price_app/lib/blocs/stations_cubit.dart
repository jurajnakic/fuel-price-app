import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:fuel_price_app/data/repositories/station_repository.dart';
import 'package:fuel_price_app/data/services/station_price_service.dart';
import 'package:fuel_price_app/models/station.dart';

class StationsState {
  final List<Station> stations;
  final bool isLoading;
  final bool hasError;

  const StationsState({
    this.stations = const [],
    this.isLoading = false,
    this.hasError = false,
  });

  StationsState copyWith({
    List<Station>? stations,
    bool? isLoading,
    bool? hasError,
  }) =>
      StationsState(
        stations: stations ?? this.stations,
        isLoading: isLoading ?? this.isLoading,
        hasError: hasError ?? this.hasError,
      );
}

class StationsCubit extends Cubit<StationsState> {
  final StationPriceService service;
  final StationRepository repository;

  StationsCubit({
    required this.service,
    required this.repository,
  }) : super(const StationsState());

  void _safeEmit(StationsState newState) {
    if (!isClosed) emit(newState);
  }

  Future<void> load() async {
    debugPrint('StationsCubit: load() called');
    _safeEmit(state.copyWith(isLoading: true, hasError: false));

    try {
      final shouldFetch = await repository.shouldFetch();
      debugPrint('StationsCubit: shouldFetch=$shouldFetch');

      if (shouldFetch) {
        final response = await service.fetchStations();
        debugPrint('StationsCubit: fetch response=${response != null ? "${response.stations.length} stations" : "null"}');
        if (response != null) {
          await repository.saveStations(response);
          await repository.recordFetchTime();
          debugPrint('StationsCubit: saved to DB');
        }
      }

      final stations = await repository.getStations();
      debugPrint('StationsCubit: loaded ${stations.length} stations from DB');
      _safeEmit(state.copyWith(isLoading: false, stations: stations, hasError: stations.isEmpty));
    } catch (e) {
      debugPrint('StationsCubit: ERROR $e');
      _safeEmit(state.copyWith(isLoading: false, hasError: true));
    }
  }

  Future<void> refresh() async {
    _safeEmit(state.copyWith(isLoading: true, hasError: false));

    try {
      final response = await service.fetchStations();
      if (response != null) {
        await repository.saveStations(response);
        await repository.recordFetchTime();
      }

      final stations = await repository.getStations();
      _safeEmit(state.copyWith(isLoading: false, stations: stations, hasError: stations.isEmpty));
    } catch (_) {
      _safeEmit(state.copyWith(isLoading: false, hasError: true));
    }
  }
}
