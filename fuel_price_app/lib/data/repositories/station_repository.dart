import '../database.dart';
import '../../models/station.dart';

class StationRepository {
  final AppDatabase db;

  StationRepository(this.db);

  Future<void> saveStations(StationsResponse response) async {
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.delete('station_fuels');
      await txn.delete('stations');

      for (final station in response.stations) {
        await txn.insert('stations', {
          'id': station.id,
          'name': station.name,
          'url': station.url,
          'updated': station.updated,
        });
        for (final fuel in station.fuels) {
          await txn.insert('station_fuels', {
            'station_id': station.id,
            'name': fuel.name,
            'type': fuel.type,
            'price': fuel.price,
          });
        }
      }
    });
  }

  Future<List<Station>> getStations() async {
    final stationRows = await db.query('stations', orderBy: 'name ASC');
    final stations = <Station>[];

    for (final row in stationRows) {
      final fuelRows = await db.query(
        'station_fuels',
        where: 'station_id = ?',
        whereArgs: [row['id']],
      );
      stations.add(Station(
        id: row['id'] as String,
        name: row['name'] as String,
        url: row['url'] as String,
        updated: row['updated'] as String,
        fuels: fuelRows
            .map((f) => StationFuel(
                  name: f['name'] as String,
                  type: f['type'] as String,
                  price: f['price'] as double,
                ))
            .toList(),
      ));
    }
    return stations;
  }

  Future<bool> shouldFetch() async {
    final rows = await db.query('station_fetch_time');
    if (rows.isEmpty) return true;
    final lastFetch = DateTime.parse(rows.first['fetched_at'] as String);
    return DateTime.now().difference(lastFetch).inHours >= 24;
  }

  Future<void> recordFetchTime() async {
    final now = DateTime.now().toIso8601String();
    final existing = await db.query('station_fetch_time');
    if (existing.isEmpty) {
      await db.insert('station_fetch_time', {'id': 1, 'fetched_at': now});
    } else {
      await db.update('station_fetch_time', {'fetched_at': now}, where: 'id = 1');
    }
  }
}
