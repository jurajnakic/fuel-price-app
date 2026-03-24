import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';

void main() {
  group('Price cycle stress tests', () {
    final ref = DateTime(2026, 3, 24);

    test('100 consecutive cycles are all Tuesdays', () {
      for (int i = 0; i < 100; i++) {
        final today = ref.add(Duration(days: i * 14));
        final next = nextPriceChangeDate(today, ref, 14);
        expect(next.weekday, DateTime.tuesday,
            reason: 'Cycle $i: ${next.toIso8601String()} should be Tuesday');
      }
    });

    test('every day in a 2-year range returns valid next date', () {
      // Start from the reference date to avoid pre-reference edge case
      final start = ref;
      final end = DateTime(2028, 3, 24);
      var current = start;
      while (current.isBefore(end)) {
        final next = nextPriceChangeDate(current, ref, 14);
        expect(next.isAfter(current), isTrue,
            reason: 'For ${current.toIso8601String()}, next=${next.toIso8601String()} should be strictly after today');
        expect(next.difference(current).inDays, lessThanOrEqualTo(14));
        current = current.add(const Duration(days: 1));
      }
    });

    test('cycle across year boundary (Dec 29 → Jan 12)', () {
      final refDec = DateTime(2026, 12, 29);
      final next = nextPriceChangeDate(DateTime(2026, 12, 30), refDec, 14);
      expect(next, DateTime(2027, 1, 12));
    });

    test('cycle across leap year (Feb 28-29)', () {
      final refFeb = DateTime(2028, 2, 15);
      final next = nextPriceChangeDate(DateTime(2028, 2, 28), refFeb, 14);
      expect(next, DateTime(2028, 2, 29));
    });

    test('reference date far in the past still works', () {
      final oldRef = DateTime(2020, 1, 7); // a Tuesday
      final next = nextPriceChangeDate(DateTime(2026, 3, 24), oldRef, 14);
      expect(next.weekday, DateTime.tuesday);
      expect(next.isAfter(DateTime(2026, 3, 24)), isTrue);
    });

    test('validateCycleDays rejects various invalid values', () {
      expect(validateCycleDays(0), 14);
      expect(validateCycleDays(-14), 14);
      expect(validateCycleDays(1), 14);
      expect(validateCycleDays(3), 14);
      expect(validateCycleDays(10), 14);
      expect(validateCycleDays(15), 14);
    });

    test('validateCycleDays accepts multiples of 7', () {
      expect(validateCycleDays(7), 7);
      expect(validateCycleDays(14), 14);
      expect(validateCycleDays(21), 21);
      expect(validateCycleDays(28), 28);
    });
  });
}
