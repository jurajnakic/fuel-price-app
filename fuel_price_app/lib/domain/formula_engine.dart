import '../models/fuel_type.dart';
import '../models/fuel_params.dart';

class FormulaEngine {
  final FuelParams params;

  FormulaEngine(this.params);

  /// Calculate base price (PC) per NN 31/2025 formula.
  ///
  /// Regulation specifies separate averages: avg(CIF) and avg(rate),
  /// then divide — *not* per-day division averaged.
  ///   PC = ρ × avg(CIF_Med) / avg(rate) / 1000 + P   (liquid fuels)
  ///   PC =     avg(CIF_Med) / avg(rate) / 1000 + P   (UNP, no density)
  ///
  /// [cifMedPrices] — daily CIF Med in USD/t (Platt's European Marketscan)
  /// [exchangeRates] — daily USD/EUR middle rate (HNB) for same days
  double calculateBasePrice(
    FuelType fuelType,
    List<double> cifMedPrices,
    List<double> exchangeRates,
  ) {
    if (cifMedPrices.isEmpty || exchangeRates.isEmpty) {
      throw ArgumentError('Price and rate lists must not be empty');
    }
    if (cifMedPrices.length != exchangeRates.length) {
      throw ArgumentError('Price and rate lists must have same length');
    }

    final density = params.density[fuelType.paramKey];
    final premium = params.premiums[fuelType.paramKey]!;
    final n = cifMedPrices.length;

    final avgCif = cifMedPrices.reduce((a, b) => a + b) / n;
    final avgRate = exchangeRates.reduce((a, b) => a + b) / n;

    if (density != null) {
      return density * avgCif / avgRate / 1000 + premium;
    }
    return avgCif / avgRate / 1000 + premium;
  }

  /// Calculate retail price: (PC + trošarina) × (1 + PDV)
  double calculateRetailPrice(FuelType fuelType, double basePrice) {
    final excise = params.exciseDuties[fuelType.paramKey]!;
    final vatMultiplier = 1 + params.vatRate;
    return (basePrice + excise) * vatMultiplier;
  }

  /// Full calculation: base → retail → rounded
  double predictPrice(
    FuelType fuelType,
    List<double> cifMedPrices,
    List<double> exchangeRates,
  ) {
    final pc = calculateBasePrice(fuelType, cifMedPrices, exchangeRates);
    final retail = calculateRetailPrice(fuelType, pc);
    return roundPrice(retail);
  }

  static double roundPrice(double price) => (price * 100).round() / 100;
}
