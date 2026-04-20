import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

void main() {
  late FormulaEngine engine;

  setUp(() {
    engine = FormulaEngine(FuelParams.defaultParams);
  });

  group('calculateBasePrice (PC)', () {
    test('calculates for ES95 with known values', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      // PC = [Σ(CIF × ρ / T) / (n × 1000)] + P
      // = [700 × 0.755 / 0.92] / 1000 + 0.1545
      // = 574.4565 / 1000 + 0.1545 = 0.5745 + 0.1545 = 0.7290
      final pc = engine.calculateBasePrice(FuelType.es95, dailyPrices, dailyRates);
      expect(pc, closeTo(0.7290, 0.001));
    });

    test('calculates for Eurodizel with different density', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      // density eurodizel = 0.845
      // = [700 × 0.845 / 0.92] / 1000 + 0.1545 = 0.6429 + 0.1545 = 0.7974
      final pc = engine.calculateBasePrice(FuelType.eurodizel, dailyPrices, dailyRates);
      expect(pc, closeTo(0.7974, 0.001));
    });

    test('calculates for UNP (no density)', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      // UNP: PC = [Σ(CIF / T) / (n × 1000)] + P
      // = [700 / 0.92] / 1000 + 0.8429 = 0.7609 + 0.8429 = 1.6038
      final pc = engine.calculateBasePrice(FuelType.unp10kg, dailyPrices, dailyRates);
      expect(pc, closeTo(1.6038, 0.001));
    });

    test('uses separate avg(cif)/avg(rate) — not per-day division', () {
      // Inputs chosen so per-day and separate-avg formulas diverge visibly.
      // cif = [1000, 100], rate = [1.0, 2.0]
      // Per-day avg: mean(cif[i]/rate[i]) = mean(1000, 50) = 525
      // Separate:   avg(cif)/avg(rate)  = 550 / 1.5 ≈ 366.667
      // Regulation mandates the separate-avg method (NN 31/2025).
      final pc = engine.calculateBasePrice(
        FuelType.es95,
        [1000.0, 100.0],
        [1.0, 2.0],
      );
      // Expected: 0.755 × 366.667 / 1000 + 0.1545 = 0.2768 + 0.1545 = 0.4313
      expect(pc, closeTo(0.4313, 0.001));
    });

    test('varying daily rates — realistic span', () {
      final prices = [700.0, 710.0, 690.0];
      final rates = [0.92, 0.93, 0.91];
      // avg(cif) = 700, avg(rate) = 0.92
      // PC = 0.755 × 700 / 0.92 / 1000 + 0.1545 = 0.5745 + 0.1545 = 0.7290
      final pc = engine.calculateBasePrice(FuelType.es95, prices, rates);
      expect(pc, closeTo(0.7290, 0.001));
    });
  });

  group('calculateRetailPrice', () {
    test('adds excise and VAT for ES95', () {
      // retail = (0.7290 + 0.4560) × 1.25 = 1.48125
      final retail = engine.calculateRetailPrice(FuelType.es95, 0.7290);
      expect(retail, closeTo(1.48125, 0.001));
    });

    test('adds excise and VAT for Eurodizel', () {
      // = (0.7974 + 0.40613) × 1.25 = 1.50441
      final retail = engine.calculateRetailPrice(FuelType.eurodizel, 0.7974);
      expect(retail, closeTo(1.5044, 0.001));
    });
  });

  group('roundPrice', () {
    test('rounds to 2 decimals', () {
      expect(FormulaEngine.roundPrice(1.48125), 1.48);
      expect(FormulaEngine.roundPrice(1.485), 1.49);
      expect(FormulaEngine.roundPrice(1.4999), 1.50);
    });
  });

  group('predictPrice (full pipeline)', () {
    test('ES95 end-to-end', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      final price = engine.predictPrice(FuelType.es95, dailyPrices, dailyRates);
      expect(price, 1.48);
    });
  });

  group('edge cases', () {
    test('empty price list throws', () {
      expect(() => engine.calculateBasePrice(FuelType.es95, [], []), throwsArgumentError);
    });

    test('mismatched list lengths throws', () {
      expect(() => engine.calculateBasePrice(FuelType.es95, [700], [0.92, 0.93]), throwsArgumentError);
    });
  });
}
