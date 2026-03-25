import 'package:bloc/bloc.dart';
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
  bool _loaded = false;

  StationsCubit({
    required this.service,
    required this.repository,
  }) : super(const StationsState());

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, hasError: false));

    try {
      final shouldFetch = await repository.shouldFetch();

      if (shouldFetch) {
        final response = await service.fetchStations();
        if (response != null) {
          await repository.saveStations(response);
          await repository.recordFetchTime();
        }
      }

      final stations = await repository.getStations();
      _loaded = true;
      emit(state.copyWith(isLoading: false, stations: stations, hasError: stations.isEmpty));
    } catch (_) {
      emit(state.copyWith(isLoading: false, hasError: true));
    }
  }

  Future<void> refresh() async {
    emit(state.copyWith(isLoading: true, hasError: false));

    try {
      final response = await service.fetchStations();
      if (response != null) {
        await repository.saveStations(response);
        await repository.recordFetchTime();
      }

      final stations = await repository.getStations();
      emit(state.copyWith(isLoading: false, stations: stations, hasError: stations.isEmpty));
    } catch (_) {
      emit(state.copyWith(isLoading: false, hasError: true));
    }
  }
}
