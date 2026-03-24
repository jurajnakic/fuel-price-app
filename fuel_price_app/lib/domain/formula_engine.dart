import '../models/fuel_type.dart';
import '../models/fuel_params.dart';

class FormulaEngine {
  final FuelParams params;

  FormulaEngine(this.params);

  /// Calculate base price (PC) per NN 31/2025 formula.
  ///
  /// For liquid fuels: PC = [Σ(CIF_Med × ρ / T) / (n × 1000)] + P
  /// For UNP (no density): PC = [Σ(CIF / T) / (n × 1000)] + P
  ///
  /// [cifMedPrices] — daily CIF Med in USD/t
  /// [exchangeRates] — daily USD/EUR rate (1 USD = X EUR)
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

    double sum = 0;
    for (var i = 0; i < n; i++) {
      if (density != null) {
        sum += cifMedPrices[i] * density / exchangeRates[i];
      } else {
        // UNP: no density factor
        sum += cifMedPrices[i] / exchangeRates[i];
      }
    }

    return sum / (n * 1000) + premium;
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
