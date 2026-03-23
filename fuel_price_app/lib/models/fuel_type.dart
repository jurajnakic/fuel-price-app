enum FuelType {
  es95('Eurosuper 95', 'ES95', 'EUR/L'),
  es100('Eurosuper 100', 'ES100', 'EUR/L'),
  eurodizel('Eurodizel', 'ED', 'EUR/L'),
  unp10kg('UNP boca 10kg', 'UNP', 'EUR/kg');

  const FuelType(this.displayName, this.shortName, this.unit);
  final String displayName;
  final String shortName;
  final String unit;
}
