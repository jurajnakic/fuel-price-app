import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/stations_cubit.dart';
import 'package:fuel_price_app/data/repositories/station_repository.dart';
import 'package:fuel_price_app/data/services/station_price_service.dart';
import 'package:fuel_price_app/models/station.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:dio/dio.dart';

void main() {
  late AppDatabase db;
  late StationRepository repo;
  late StationsCubit cubit;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    repo = StationRepository(db);

    // Save test stations
    await repo.saveStations(StationsResponse(
      updated: '2026-03-25',
      stations: [
        Station(id: 'a', name: 'Postaja A', url: '', updated: '2026-03-25', fuels: const []),
        Station(id: 'b', name: 'Postaja B', url: '', updated: '2026-03-25', fuels: const []),
        Station(id: 'c', name: 'Postaja C', url: '', updated: '2026-03-25', fuels: const []),
      ],
    ));

    cubit = StationsCubit(
      service: StationPriceService(dio: Dio()),
      repository: repo,
    );

    // Load stations into cubit state
    final stations = await repo.getStations();
    cubit.emit(StationsState(stations: stations));
  });

  tearDown(() async {
    await cubit.close();
    await db.close();
  });

  test('reorder moves station correctly', () async {
    expect(cubit.state.stations.map((s) => s.id).toList(), ['a', 'b', 'c']);

    await cubit.reorder(0, 2);
    expect(cubit.state.stations.map((s) => s.id).toList(), ['b', 'a', 'c']);
  });

  test('reorder persists to DB', () async {
    await cubit.reorder(2, 0);
    expect(cubit.state.stations.first.id, 'c');

    // Verify DB order
    final fromDb = await repo.getStations();
    expect(fromDb.map((s) => s.id).toList(), ['c', 'a', 'b']);
  });

  test('reorder with invalid indices is safe', () async {
    final before = cubit.state.stations.map((s) => s.id).toList();

    await cubit.reorder(-1, 0);
    expect(cubit.state.stations.map((s) => s.id).toList(), before);

    await cubit.reorder(0, 100);
    expect(cubit.state.stations.map((s) => s.id).toList(), before);
  });

  test('reorder on empty list does not crash', () async {
    cubit.emit(const StationsState(stations: []));
    await cubit.reorder(0, 1);
    expect(cubit.state.stations, isEmpty);
  });
}
