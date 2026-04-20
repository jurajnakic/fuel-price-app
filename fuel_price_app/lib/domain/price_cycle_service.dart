/// Calculates the next price change date based on reference date and cycle length.
///
/// On a cycle date itself, returns the NEXT cycle (today's change already happened).
/// If [today] is before [referenceDate], returns [referenceDate].
DateTime nextPriceChangeDate(DateTime today, DateTime referenceDate, int cycleDays) {
  if (today.isBefore(referenceDate)) return referenceDate;

  // Use UTC for date arithmetic to avoid DST issues
  final todayUtc = DateTime.utc(today.year, today.month, today.day);
  final refUtc = DateTime.utc(referenceDate.year, referenceDate.month, referenceDate.day);
  final daysDiff = todayUtc.difference(refUtc).inDays;
  final cyclesPassed = daysDiff ~/ cycleDays;
  final nextDays = (cyclesPassed + 1) * cycleDays;
  final nextUtc = refUtc.add(Duration(days: nextDays));

  // Return as local DateTime (date only)
  return DateTime(nextUtc.year, nextUtc.month, nextUtc.day);
}

/// Returns a trend arrow comparing predicted vs current price.
///
/// Returns `null` if [current] is null (no official price yet).
/// Uses ±0.005 € tolerance to account for rounding.
String? trendIndicator(double predicted, double? current) {
  if (current == null) return null;
  final diff = predicted - current;
  if (diff > 0.005) return '↑';
  if (diff < -0.005) return '↓';
  return '→';
}

/// Validates cycle_days: must be positive and multiple of 7. Returns 14 if invalid.
int validateCycleDays(int cycleDays) {
  if (cycleDays <= 0 || cycleDays % 7 != 0) return 14;
  return cycleDays;
}

/// Settlement window per NN 31/2025: last two Mon-Sun weeks ending the Sunday
/// before the publication Monday (which is [nextChange] - 1 day).
///
/// Returns (start, end) in half-open form: days [start, end).
/// Assumes [nextChange] is a Tuesday (publication Monday = nextChange − 1);
/// boundaries only land on Mon/Sun when that assumption holds. If the
/// government ever shifts its publication cadence, this helper must be updated.
({DateTime start, DateTime end}) settlementWindow(DateTime nextChange, int cycleDays) {
  // Use UTC midnight for date arithmetic to avoid DST 23h/25h days shifting
  // the window by an hour across the March/October switches.
  final anchor = DateTime.utc(nextChange.year, nextChange.month, nextChange.day);
  final pubUtc = anchor.subtract(const Duration(days: 1));
  final startUtc = pubUtc.subtract(Duration(days: cycleDays));
  return (
    start: DateTime(startUtc.year, startUtc.month, startUtc.day),
    end: DateTime(pubUtc.year, pubUtc.month, pubUtc.day),
  );
}
