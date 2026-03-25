import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/stations_cubit.dart';
import 'package:fuel_price_app/data/repositories/station_repository.dart';
import 'package:fuel_price_app/data/services/station_price_service.dart';
import 'package:fuel_price_app/models/station.dart';
import 'package:mocktail/mocktail.dart';

class MockStationPriceService extends Mock implements StationPriceService {}
class MockStationRepository extends Mock implements StationRepository {}

void main() {
  late MockStationPriceService mockService;
  late MockStationRepository mockRepo;

  setUp(() {
    mockService = MockStationPriceService();
    mockRepo = MockStationRepository();
  });

  setUpAll(() {
    registerFallbackValue(StationsResponse(updated: '', stations: []));
  });

  final testResponse = StationsResponse(
    updated: '2026-03-25T08:00:00Z',
    stations: [
      Station(id: 'ina', name: 'INA', url: '', updated: '2026-03-25', fuels: [
        StationFuel(name: 'ES95', type: 'es95', price: 1.45),
      ]),
    ],
  );

  group('load', () {
    blocTest<StationsCubit, StationsState>(
      'fetches from network when shouldFetch is true',
      setUp: () {
        when(() => mockRepo.shouldFetch()).thenAnswer((_) async => true);
        when(() => mockService.fetchStations()).thenAnswer((_) async => testResponse);
        when(() => mockRepo.saveStations(any())).thenAnswer((_) async {});
        when(() => mockRepo.recordFetchTime()).thenAnswer((_) async {});
        when(() => mockRepo.getStations()).thenAnswer((_) async => testResponse.stations);
      },
      build: () => StationsCubit(service: mockService, repository: mockRepo),
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<StationsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<StationsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.stations.length, 'stations.length', 1),
      ],
    );

    blocTest<StationsCubit, StationsState>(
      'uses cache when shouldFetch is false',
      setUp: () {
        when(() => mockRepo.shouldFetch()).thenAnswer((_) async => false);
        when(() => mockRepo.getStations()).thenAnswer((_) async => testResponse.stations);
      },
      build: () => StationsCubit(service: mockService, repository: mockRepo),
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<StationsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<StationsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.stations.length, 'stations.length', 1),
      ],
      verify: (_) {
        verifyNever(() => mockService.fetchStations());
      },
    );

    blocTest<StationsCubit, StationsState>(
      'shows error when fetch fails and no cache',
      setUp: () {
        when(() => mockRepo.shouldFetch()).thenAnswer((_) async => true);
        when(() => mockService.fetchStations()).thenAnswer((_) async => null);
        when(() => mockRepo.getStations()).thenAnswer((_) async => []);
      },
      build: () => StationsCubit(service: mockService, repository: mockRepo),
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<StationsState>().having((s) => s.isLoading, 'isLoading', true),
        isA<StationsState>()
            .having((s) => s.isLoading, 'isLoading', false)
            .having((s) => s.hasError, 'hasError', true),
      ],
    );
  });
}
