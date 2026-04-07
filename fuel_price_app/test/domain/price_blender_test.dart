// test/domain/price_blender_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/price_blender.dart';

void main() {
  group('PriceBlender', () {
    test('blends three sources with configured weights', () {
      final weights = {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5};
      final prices = {'yahoo': 1.83, 'eia': 1.80, 'oilapi': 1.85};
      final result = PriceBlender.blend(prices, weights);
      // (1.83*0.3 + 1.80*0.2 + 1.85*0.5) = 0.549 + 0.36 + 0.925 = 1.834
      expect(result, closeTo(1.834, 0.001));
    });

    test('normalizes weights when one source is missing', () {
      final weights = {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5};
      final prices = {'yahoo': 1.83, 'eia': 1.80}; // oilapi missing
      final result = PriceBlender.blend(prices, weights);
      // Remaining: yahoo=0.3, eia=0.2, sum=0.5
      // Normalized: yahoo=0.6, eia=0.4
      // 1.83*0.6 + 1.80*0.4 = 1.098 + 0.72 = 1.818
      expect(result, closeTo(1.818, 0.001));
    });

    test('returns single source price when only one available', () {
      final weights = {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5};
      final prices = {'oilapi': 1.85};
      final result = PriceBlender.blend(prices, weights);
      expect(result, 1.85);
    });

    test('returns null when no sources available', () {
      final weights = {'yahoo': 0.5, 'eia': 0.5};
      final prices = <String, double>{};
      final result = PriceBlender.blend(prices, weights);
      expect(result, isNull);
    });

    test('handles missing weight config gracefully (equal weights)', () {
      final weights = <String, double>{}; // no weights configured
      final prices = {'yahoo': 1.80, 'eia': 1.82};
      final result = PriceBlender.blend(prices, weights);
      // Equal weights: (1.80 + 1.82) / 2 = 1.81
      expect(result, closeTo(1.81, 0.001));
    });

    test('ignores sources with zero weight', () {
      final weights = {'yahoo': 0.0, 'eia': 1.0};
      final prices = {'yahoo': 999.0, 'eia': 1.80};
      final result = PriceBlender.blend(prices, weights);
      expect(result, 1.80);
    });

    test('falls back to equal weights when primary source missing (ramp-up)', () {
      // Eurodizel scenario: oilapi=1.0, yahoo=0.0 but oilapi has no data
      final weights = {'oilapi': 1.0, 'yahoo': 0.0};
      final prices = {'yahoo': 1.89}; // only yahoo available
      final result = PriceBlender.blend(prices, weights);
      // yahoo has weight 0 → excluded from available → equal-weight fallback
      expect(result, 1.89);
    });
  });
}
