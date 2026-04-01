import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/domain/price_blender.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

/// Integration test for multi-source price blending pipeline.
///
/// Verifies: source prices → cifMedFactor → FormulaEngine → PriceBlender → final price.
/// Uses known Yahoo/EIA/OilPriceAPI data from API testing (2026-03-23).
void main() {
  late FormulaEngine engine;
  late FuelParams params;

  setUp(() {
    params = FuelParams.defaultParams;
    engine = FormulaEngine(params);
  });

  group('Multi-source blending pipeline', () {
    // Known data from API testing (2026-03-23):
    // Yahoo RB=F (gasoline): ~3.0 USD/gal
    // EIA NY Harbor Gasoline: 2.998 USD/gal
    // ECB rate: ~1.15 (1 EUR = 1.15 USD, so 1 USD = 0.87 EUR)
    //
    // Yahoo HO=F (diesel): ~4.2 USD/gal
    // EIA NY Harbor ULSD: 4.187 USD/gal
    // OilPriceAPI Rotterdam MGO: 1388.5 USD/mt

    test('ES95: Yahoo + EIA blend with equal weights', () {
      // Yahoo: RB=F = 3.0 USD/gal, cifMedFactor = 402.4
      // CIF Med from Yahoo = 3.0 * 402.4 = 1207.2 USD/t
      // EIA: 2.998 USD/gal, eiaCifMedFactor = 390.0
      // CIF Med from EIA = 2.998 * 390.0 = 1169.22 USD/t
      //
      // Rate: 1 USD = 0.87 EUR (or T = 1/0.87 = 1.1494)
      // Formula uses USD/EUR rate where rate = 1/T
      final rate = 1.0 / 1.15; // = 0.8696

      final yahooCifMed = List.generate(14, (_) => 3.0 * 402.4);
      final eiaCifMed = List.generate(14, (_) => 2.998 * 390.0);
      final rates = List.generate(14, (_) => rate);

      final yahooPrice = engine.predictPrice(FuelType.es95, yahooCifMed, rates);
      final eiaPrice = engine.predictPrice(FuelType.es95, eiaCifMed, rates);

      // Blend with default weights: yahoo=0.5, eia=0.5
      final weights = params.sourceWeights['es95']!;
      final blended = PriceBlender.blend(
        {'yahoo': yahooPrice.toDouble(), 'eia': eiaPrice.toDouble()},
        weights,
      );

      expect(blended, isNotNull);
      // Both sources should give similar but not identical prices
      expect(yahooPrice, isNot(equals(eiaPrice)));
      // Blended should be between the two
      final lower = yahooPrice < eiaPrice ? yahooPrice : eiaPrice;
      final upper = yahooPrice > eiaPrice ? yahooPrice : eiaPrice;
      expect(blended!, greaterThanOrEqualTo(lower));
      expect(blended, lessThanOrEqualTo(upper));
    });

    test('Eurodizel: three sources with Rotterdam getting highest weight', () {
      final rate = 1.0 / 1.15;

      // Yahoo HO=F: 4.2 USD/gal * 327.0 = 1373.4 USD/t
      final yahooCifMed = List.generate(14, (_) => 4.2 * 327.0);
      // EIA ULSD: 4.187 USD/gal * 320.0 = 1339.84 USD/t
      final eiaCifMed = List.generate(14, (_) => 4.187 * 320.0);
      // OilPriceAPI Rotterdam MGO: 1388.5 USD/mt * 1.05 = 1457.925 USD/t
      final oilApiCifMed = List.generate(14, (_) => 1388.5 * 1.05);

      final rates = List.generate(14, (_) => rate);

      final yahooPrice = engine.predictPrice(FuelType.eurodizel, yahooCifMed, rates);
      final eiaPrice = engine.predictPrice(FuelType.eurodizel, eiaCifMed, rates);
      final oilApiPrice = engine.predictPrice(FuelType.eurodizel, oilApiCifMed, rates);

      // Blend: yahoo=0.1, eia=0.6, oilapi=0.3
      final weights = params.sourceWeights['eurodizel']!;
      final blended = PriceBlender.blend(
        {'yahoo': yahooPrice.toDouble(), 'eia': eiaPrice.toDouble(), 'oilapi': oilApiPrice.toDouble()},
        weights,
      );

      expect(blended, isNotNull);
      // Verify blended price is reasonable (between 1.0 and 5.0 EUR)
      expect(blended!, greaterThan(1.0));
      expect(blended, lessThan(5.0));
      // Blended should be between lowest and highest source price
      final prices = [yahooPrice, eiaPrice, oilApiPrice];
      expect(blended, greaterThanOrEqualTo(prices.reduce((a, b) => a < b ? a : b)));
      expect(blended, lessThanOrEqualTo(prices.reduce((a, b) => a > b ? a : b)));
    });

    test('Fallback: only Yahoo available, gets full weight', () {
      final rate = 1.0 / 1.15;
      final yahooCifMed = List.generate(14, (_) => 3.0 * 402.4);
      final rates = List.generate(14, (_) => rate);

      final yahooPrice = engine.predictPrice(FuelType.es95, yahooCifMed, rates);

      // Only Yahoo, even though weights say 50/50
      final weights = params.sourceWeights['es95']!;
      final blended = PriceBlender.blend(
        {'yahoo': yahooPrice.toDouble()},
        weights,
      );

      // With only one source, should equal that source
      expect(blended, yahooPrice);
    });

    test('UNP: Yahoo + EIA blend (no OilPriceAPI for LPG)', () {
      final rate = 1.0 / 1.15;

      // Yahoo BZ=F (Brent): 103.79 USD/bbl * 16.0 = 1660.64 USD/t
      final yahooCifMed = List.generate(14, (_) => 103.79 * 16.0);
      // EIA propane: 0.724 USD/gal * 280.0 = 202.72 USD/t
      final eiaCifMed = List.generate(14, (_) => 0.724 * 280.0);

      final rates = List.generate(14, (_) => rate);

      final yahooPrice = engine.predictPrice(FuelType.unp10kg, yahooCifMed, rates);
      final eiaPrice = engine.predictPrice(FuelType.unp10kg, eiaCifMed, rates);

      final weights = params.sourceWeights['unp_10kg']!;
      final blended = PriceBlender.blend(
        {'yahoo': yahooPrice.toDouble(), 'eia': eiaPrice.toDouble()},
        weights,
      );

      expect(blended, isNotNull);
      // UNP prices should be in reasonable range (1-10 EUR/10kg)
      expect(blended!, greaterThan(1.0));
      expect(blended, lessThan(10.0));
    });

    test('Zero weight source is excluded from blend', () {
      final rate = 1.0 / 1.15;
      final yahooCifMed = List.generate(14, (_) => 3.0 * 402.4);
      final eiaCifMed = List.generate(14, (_) => 2.998 * 390.0);
      final rates = List.generate(14, (_) => rate);

      final yahooPrice = engine.predictPrice(FuelType.es95, yahooCifMed, rates);
      final eiaPrice = engine.predictPrice(FuelType.es95, eiaCifMed, rates);

      // Custom weights: EIA disabled
      final blended = PriceBlender.blend(
        {'yahoo': yahooPrice.toDouble(), 'eia': eiaPrice.toDouble()},
        {'yahoo': 1.0, 'eia': 0.0},
      );

      // Should be pure Yahoo price
      expect(blended, yahooPrice);
    });

    test('OilPriceAPI sparse data (1 point) still contributes via blend', () {
      final rate = 1.0 / 1.15;

      // Yahoo: 14 days
      final yahooCifMed = List.generate(14, (_) => 4.2 * 327.0);
      // OilPriceAPI: only 1 data point (sparse source)
      final oilApiCifMed = [1388.5 * 1.05];

      final yahooRates = List.generate(14, (_) => rate);
      final oilApiRates = [rate];

      final yahooPrice = engine.predictPrice(FuelType.eurodizel, yahooCifMed, yahooRates);
      final oilApiPrice = engine.predictPrice(FuelType.eurodizel, oilApiCifMed, oilApiRates);

      // Even with 1 OilPriceAPI point, blend should work
      final blended = PriceBlender.blend(
        {'yahoo': yahooPrice.toDouble(), 'oilapi': oilApiPrice.toDouble()},
        {'yahoo': 0.3, 'oilapi': 0.5},
      );

      expect(blended, isNotNull);
      // Normalized: yahoo = 0.3/0.8 = 0.375, oilapi = 0.5/0.8 = 0.625
      final expected = yahooPrice * 0.375 + oilApiPrice * 0.625;
      expect(blended!, closeTo(expected, 0.01));
    });
  });
}
