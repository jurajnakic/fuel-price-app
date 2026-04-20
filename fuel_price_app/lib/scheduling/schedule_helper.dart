/// Zagreb timezone offset: CET = UTC+1 (Nov-Mar), CEST = UTC+2 (Mar-Oct).
/// DST switch: last Sunday of March at 01:00 UTC (to CEST),
/// last Sunday of October at 01:00 UTC (to CET).
int zagrebUtcOffset(DateTime utcDate) {
  final year = utcDate.year;
  // Last Sunday of March
  final marchLast = DateTime.utc(year, 3, 31);
  final dstStart = marchLast.subtract(Duration(days: marchLast.weekday % 7));
  // Last Sunday of October
  final octLast = DateTime.utc(year, 10, 31);
  final dstEnd = octLast.subtract(Duration(days: octLast.weekday % 7));

  // CEST: from last Sunday of March 01:00 UTC to last Sunday of October 01:00 UTC
  final cestStart = DateTime.utc(dstStart.year, dstStart.month, dstStart.day, 1);
  final cestEnd = DateTime.utc(dstEnd.year, dstEnd.month, dstEnd.day, 1);

  if (utcDate.isAfter(cestStart) && utcDate.isBefore(cestEnd)) {
    return 2; // CEST
  }
  return 1; // CET
}

/// Returns the next occurrence of [targetLocalHour] Zagreb local time as UTC.
DateTime nextFetchTime(DateTime nowUtc, {int targetLocalHour = 9}) {
  final offset = zagrebUtcOffset(nowUtc);
  final localHour = nowUtc.hour + offset;

  if (localHour < targetLocalHour) {
    return DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, targetLocalHour - offset);
  } else {
    final tomorrow = nowUtc.add(const Duration(days: 1));
    final tomorrowOffset = zagrebUtcOffset(tomorrow);
    return DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, targetLocalHour - tomorrowOffset);
  }
}

/// Duration until next [targetLocalHour] Zagreb time.
Duration initialFetchDelay(DateTime nowUtc, {int targetLocalHour = 9}) {
  return nextFetchTime(nowUtc, targetLocalHour: targetLocalHour).difference(nowUtc);
}
