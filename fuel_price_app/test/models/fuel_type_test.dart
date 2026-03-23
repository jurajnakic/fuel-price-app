import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

void main() {
  test('FuelType has 4 values', () {
    expect(FuelType.values.length, 4);
  });

  test('FuelType display names are correct', () {
    expect(FuelType.es95.displayName, 'Eurosuper 95');
    expect(FuelType.eurodizel.displayName, 'Eurodizel');
    expect(FuelType.unp10kg.displayName, 'UNP boca 10kg');
  });

  test('FuelType units distinguish liquid vs kg', () {
    expect(FuelType.es95.unit, 'EUR/L');
    expect(FuelType.unp10kg.unit, 'EUR/kg');
  });
}
