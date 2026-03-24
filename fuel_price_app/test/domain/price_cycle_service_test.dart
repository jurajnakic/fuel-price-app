import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';

void main() {
  group('nextPriceChangeDate', () {
    final ref = DateTime(2026, 3, 24); // Tuesday

    test('on reference date itself, returns next cycle', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 24), ref, 14);
      expect(result, DateTime(2026, 4, 7));
    });

    test('day after reference, returns next cycle', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 25), ref, 14);
      expect(result, DateTime(2026, 4, 7));
    });

    test('day before next cycle, returns that cycle', () {
      final result = nextPriceChangeDate(DateTime(2026, 4, 6), ref, 14);
      expect(result, DateTime(2026, 4, 7));
    });

    test('on second cycle date, returns third', () {
      final result = nextPriceChangeDate(DateTime(2026, 4, 7), ref, 14);
      expect(result, DateTime(2026, 4, 21));
    });

    test('reference date in future, returns reference date', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 20), ref, 14);
      expect(result, DateTime(2026, 3, 24));
    });

    test('cycle across year boundary', () {
      final refDec = DateTime(2026, 12, 29);
      final result = nextPriceChangeDate(DateTime(2027, 1, 5), refDec, 14);
      expect(result, DateTime(2027, 1, 12));
    });

    test('weekly cycle (7 days)', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 25), ref, 7);
      expect(result, DateTime(2026, 3, 31));
    });
  });

  group('trendIndicator', () {
    test('price increase returns ↑', () {
      expect(trendIndicator(1.42, 1.38), '↑');
    });

    test('price decrease returns ↓', () {
      expect(trendIndicator(1.35, 1.38), '↓');
    });

    test('no change within tolerance returns →', () {
      expect(trendIndicator(1.380, 1.382), '→');
    });

    test('exactly at tolerance boundary returns →', () {
      // 1.384 - 1.380 = 0.004 which is within ±0.005 tolerance
      expect(trendIndicator(1.384, 1.380), '→');
    });

    test('just above tolerance returns ↑', () {
      expect(trendIndicator(1.3861, 1.380), '↑');
    });

    test('large swing returns ↑', () {
      expect(trendIndicator(2.00, 1.00), '↑');
    });

    test('null current returns null', () {
      expect(trendIndicator(1.42, null), isNull);
    });
  });

  group('validateCycleDays', () {
    test('14 is valid', () {
      expect(validateCycleDays(14), 14);
    });

    test('7 is valid', () {
      expect(validateCycleDays(7), 7);
    });

    test('10 is invalid, returns 14', () {
      expect(validateCycleDays(10), 14);
    });

    test('0 is invalid, returns 14', () {
      expect(validateCycleDays(0), 14);
    });

    test('-7 is invalid, returns 14', () {
      expect(validateCycleDays(-7), 14);
    });
  });
}
