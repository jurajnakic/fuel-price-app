import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/scheduling/schedule_helper.dart';

void main() {
  group('WorkManager schedule helper', () {
    test('next18CET from morning returns today 18:00 CEST', () {
      // March 24 2026 10:00 UTC → 12:00 CEST (after DST switch March 29)
      // Wait - March 24 is BEFORE March 29 DST switch, so still CET (UTC+1)
      // 10:00 UTC = 11:00 CET → before 18:00
      // 18:00 CET = 17:00 UTC
      final now = DateTime.utc(2026, 3, 24, 10, 0);
      final next = nextFetchTime(now);
      expect(next, DateTime.utc(2026, 3, 24, 17, 0)); // 18:00 CET = 17:00 UTC
    });

    test('next18CET from evening returns tomorrow 18:00', () {
      // March 24 2026 18:00 UTC = 19:00 CET → after 18:00
      final now = DateTime.utc(2026, 3, 24, 18, 0);
      final next = nextFetchTime(now);
      // Tomorrow 18:00 CET = 17:00 UTC
      expect(next, DateTime.utc(2026, 3, 25, 17, 0));
    });

    test('after DST switch uses CEST offset', () {
      // April 1 2026 10:00 UTC = 12:00 CEST
      final now = DateTime.utc(2026, 4, 1, 10, 0);
      final next = nextFetchTime(now);
      // 18:00 CEST = 16:00 UTC
      expect(next, DateTime.utc(2026, 4, 1, 16, 0));
    });

    test('initialDelay calculates correct duration', () {
      // March 24 2026 10:00 UTC, CET offset = 1
      // 18:00 CET = 17:00 UTC, delay = 7 hours
      final now = DateTime.utc(2026, 3, 24, 10, 0);
      final delay = initialFetchDelay(now);
      expect(delay.inHours, 7);
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
