import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/models/station.dart';

void main() {
  test('groupedFuels sorts by category then price ascending', () {
    final station = Station(
      id: '1',
      name: 'Test',
      url: '',
      updated: '2026-03-25',
      fuels: const [
        StationFuel(name: 'Eurodizel', type: 'eurodizel', price: 1.40),
        StationFuel(name: 'Eurosuper 100', type: 'es100', price: 1.55),
        StationFuel(name: 'Eurosuper 95', type: 'es95', price: 1.42),
        StationFuel(name: 'UNP 10kg', type: 'unp10kg', price: 5.10),
      ],
    );

    final groups = station.groupedFuels(ascending: true);

    // Eurosuper group first
    expect(groups[0].category, FuelCategory.eurosuper);
    expect(groups[0].fuels[0].type, 'es95'); // cheaper first
    expect(groups[0].fuels[1].type, 'es100');

    // Eurodizel second
    expect(groups[1].category, FuelCategory.eurodizel);

    // LPG/UNP third
    expect(groups[2].category, FuelCategory.lpg);
  });

  test('groupedFuels descending puts expensive first', () {
    final station = Station(
      id: '1',
      name: 'Test',
      url: '',
      updated: '2026-03-25',
      fuels: const [
        StationFuel(name: 'Eurosuper 100', type: 'es100', price: 1.55),
        StationFuel(name: 'Eurosuper 95', type: 'es95', price: 1.42),
      ],
    );

    final groups = station.groupedFuels(ascending: false);
    expect(groups[0].fuels[0].type, 'es100'); // more expensive first
    expect(groups[0].fuels[1].type, 'es95');
  });

  test('groupedFuels with empty fuels returns empty', () {
    final station = Station(
      id: '1', name: 'Test', url: '', updated: '2026-03-25', fuels: const [],
    );

    expect(station.groupedFuels(), isEmpty);
  });

  test('category detection by name for unknown types', () {
    const benzin = StationFuel(name: 'Super benzin 98', type: 'custom1', price: 1.50);
    expect(benzin.category, FuelCategory.eurosuper);

    const diesel = StationFuel(name: 'Premium Diesel', type: 'custom2', price: 1.45);
    expect(diesel.category, FuelCategory.eurodizel);

    const autoplin = StationFuel(name: 'Autoplin', type: 'custom3', price: 0.80);
    expect(autoplin.category, FuelCategory.lpg);

    const unknown = StationFuel(name: 'AdBlue', type: 'custom4', price: 2.00);
    expect(unknown.category, FuelCategory.ostalo);
  });
}
