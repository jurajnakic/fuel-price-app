// lib/domain/price_blender.dart

/// Blends prices from multiple sources using configurable weights.
class PriceBlender {
  /// Calculate weighted average of [prices] using [weights].
  ///
  /// Only sources present in both maps are used.
  /// Weights are normalized to sum to 1.0 among available sources.
  /// Returns null if no sources have data.
  static double? blend(
    Map<String, double> prices,
    Map<String, double> weights,
  ) {
    if (prices.isEmpty) return null;

    // Filter to sources that have both a price and a non-zero weight
    final available = <String, double>{};
    for (final source in prices.keys) {
      final w = weights[source];
      if (w != null && w > 0) {
        available[source] = w;
      }
    }

    // If no weights configured for available sources, use equal weights
    if (available.isEmpty) {
      final equalWeight = 1.0 / prices.length;
      double sum = 0;
      for (final price in prices.values) {
        sum += price * equalWeight;
      }
      return sum;
    }

    // Normalize weights to sum to 1.0
    final totalWeight = available.values.fold(0.0, (a, b) => a + b);
    if (totalWeight == 0) return null;

    double result = 0;
    for (final entry in available.entries) {
      final price = prices[entry.key];
      if (price != null) {
        result += price * (entry.value / totalWeight);
      }
    }

    return result;
  }
}
