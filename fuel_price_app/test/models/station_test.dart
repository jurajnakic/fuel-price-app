import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/models/station.dart';

void main() {
  group('StationFuel', () {
    test('fromJson parses correctly', () {
      final json = {'name': 'Eurosuper 95', 'type': 'es95', 'price': 1.45};
      final fuel = StationFuel.fromJson(json);
      expect(fuel.name, 'Eurosuper 95');
      expect(fuel.type, 'es95');
      expect(fuel.price, 1.45);
    });

    test('sortIndex returns correct order for known types', () {
      final es95 = StationFuel(name: 'ES95', type: 'es95', price: 1.0);
      final lpg = StationFuel(name: 'LPG', type: 'lpg', price: 0.5);
      final premium = StationFuel(name: 'Premium', type: 'premium_diesel', price: 1.8);
      expect(es95.sortIndex, 0);
      expect(lpg.sortIndex, 3);
      expect(premium.sortIndex, 999);
    });
  });

  group('Station', () {
    test('fromJson parses full station', () {
      final json = {
        'id': 'ina',
        'name': 'INA',
        'url': 'https://www.ina.hr',
        'updated': '2026-03-25',
        'fuels': [
          {'name': 'Eurosuper 95', 'type': 'es95', 'price': 1.45},
          {'name': 'Eurodizel', 'type': 'eurodizel', 'price': 1.42},
        ],
      };
      final station = Station.fromJson(json);
      expect(station.id, 'ina');
      expect(station.name, 'INA');
      expect(station.url, 'https://www.ina.hr');
      expect(station.updated, '2026-03-25');
      expect(station.fuels.length, 2);
    });

    test('sortedFuels returns fuels in standard order', () {
      final station = Station(
        id: 'test',
        name: 'Test',
        url: '',
        updated: '2026-03-25',
        fuels: [
          StationFuel(name: 'Premium Diesel', type: 'premium_diesel', price: 1.8),
          StationFuel(name: 'LPG', type: 'lpg', price: 0.5),
          StationFuel(name: 'Eurosuper 95', type: 'es95', price: 1.4),
          StationFuel(name: 'Eurodizel', type: 'eurodizel', price: 1.3),
        ],
      );
      final sorted = station.sortedFuels;
      expect(sorted[0].type, 'es95');
      expect(sorted[1].type, 'eurodizel');
      expect(sorted[2].type, 'lpg');
      expect(sorted[3].type, 'premium_diesel');
    });

    test('parseStationsJson parses full JSON response', () {
      final json = {
        'updated': '2026-03-25T08:00:00Z',
        'stations': [
          {
            'id': 'ina',
            'name': 'INA',
            'url': 'https://www.ina.hr',
            'updated': '2026-03-25',
            'fuels': [
              {'name': 'Eurosuper 95', 'type': 'es95', 'price': 1.45},
            ],
          },
        ],
      };
      final result = StationsResponse.fromJson(json);
      expect(result.updated, '2026-03-25T08:00:00Z');
      expect(result.stations.length, 1);
      expect(result.stations.first.id, 'ina');
    });
  });
}
