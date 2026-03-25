import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/station_repository.dart';
import 'package:fuel_price_app/models/station.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late StationRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    repo = StationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('saveStations and getStations roundtrip', () async {
    final response = StationsResponse(
      updated: '2026-03-25T08:00:00Z',
      stations: [
        Station(
          id: 'ina',
          name: 'INA',
          url: 'https://www.ina.hr',
          updated: '2026-03-25',
          fuels: [
            StationFuel(name: 'Eurosuper 95', type: 'es95', price: 1.45),
            StationFuel(name: 'Eurodizel', type: 'eurodizel', price: 1.42),
          ],
        ),
      ],
    );

    await repo.saveStations(response);
    final stations = await repo.getStations();
    expect(stations.length, 1);
    expect(stations.first.id, 'ina');
    expect(stations.first.fuels.length, 2);
  });

  test('saveStations replaces old data', () async {
    await repo.saveStations(StationsResponse(
      updated: '2026-03-24T08:00:00Z',
      stations: [
        Station(id: 'ina', name: 'INA', url: '', updated: '2026-03-24', fuels: [
          StationFuel(name: 'ES95', type: 'es95', price: 1.40),
        ]),
        Station(id: 'shell', name: 'Shell', url: '', updated: '2026-03-24', fuels: [
          StationFuel(name: 'ES95', type: 'es95', price: 1.50),
        ]),
      ],
    ));

    await repo.saveStations(StationsResponse(
      updated: '2026-03-25T08:00:00Z',
      stations: [
        Station(id: 'ina', name: 'INA', url: '', updated: '2026-03-25', fuels: [
          StationFuel(name: 'ES95', type: 'es95', price: 1.45),
        ]),
      ],
    ));

    final stations = await repo.getStations();
    expect(stations.length, 1);
    expect(stations.first.fuels.first.price, 1.45);
  });

  test('shouldFetch returns true when never fetched', () async {
    expect(await repo.shouldFetch(), true);
  });

  test('shouldFetch returns false after recent fetch', () async {
    await repo.recordFetchTime();
    expect(await repo.shouldFetch(), false);
  });
}
