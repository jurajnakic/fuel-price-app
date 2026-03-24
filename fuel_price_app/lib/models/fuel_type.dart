enum FuelType {
  es95('Eurosuper 95', 'ES95', 'EUR/L', 'es95'),
  es100('Eurosuper 100', 'ES100', 'EUR/L', 'es100'),
  eurodizel('Eurodizel', 'ED', 'EUR/L', 'eurodizel'),
  unp10kg('UNP boca 10kg', 'UNP', 'EUR/kg', 'unp_10kg');

  const FuelType(this.displayName, this.shortName, this.unit, this.paramKey);
  final String displayName;
  final String shortName;
  final String unit;
  /// Key used in FuelParams maps (premiums, excise_duties, density)
  final String paramKey;
}
