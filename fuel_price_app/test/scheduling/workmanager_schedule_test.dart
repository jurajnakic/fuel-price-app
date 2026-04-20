import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/scheduling/schedule_helper.dart';

void main() {
  group('WorkManager schedule helper', () {
    test('next 18:00 from morning returns today 18:00 CET', () {
      // March 24 2026 10:00 UTC → 11:00 CET (before DST switch), before 18:00
      // 18:00 CET = 17:00 UTC
      final now = DateTime.utc(2026, 3, 24, 10, 0);
      final next = nextFetchTime(now, targetLocalHour: 18);
      expect(next, DateTime.utc(2026, 3, 24, 17, 0));
    });

    test('next 18:00 from evening returns tomorrow 18:00', () {
      final now = DateTime.utc(2026, 3, 24, 18, 0);
      final next = nextFetchTime(now, targetLocalHour: 18);
      expect(next, DateTime.utc(2026, 3, 25, 17, 0));
    });

    test('after DST switch uses CEST offset', () {
      // April 1 2026 10:00 UTC = 12:00 CEST, 18:00 CEST = 16:00 UTC
      final now = DateTime.utc(2026, 4, 1, 10, 0);
      final next = nextFetchTime(now, targetLocalHour: 18);
      expect(next, DateTime.utc(2026, 4, 1, 16, 0));
    });

    test('initialDelay calculates correct duration (18:00 target)', () {
      final now = DateTime.utc(2026, 3, 24, 10, 0);
      final delay = initialFetchDelay(now, targetLocalHour: 18);
      expect(delay.inHours, 7);
    });

    test('default target is 09:00 local', () {
      // April 1 2026 04:00 UTC = 06:00 CEST, before 09:00
      // 09:00 CEST = 07:00 UTC
      final now = DateTime.utc(2026, 4, 1, 4, 0);
      final next = nextFetchTime(now);
      expect(next, DateTime.utc(2026, 4, 1, 7, 0));
    });

    test('CET offset is 1 before DST', () {
      expect(zagrebUtcOffset(DateTime.utc(2026, 3, 1)), 1);
    });

    test('CEST offset is 2 after DST', () {
      expect(zagrebUtcOffset(DateTime.utc(2026, 4, 1)), 2);
    });

    test('CET offset is 1 after October DST ends', () {
      expect(zagrebUtcOffset(DateTime.utc(2026, 11, 1)), 1);
    });
  });
}
