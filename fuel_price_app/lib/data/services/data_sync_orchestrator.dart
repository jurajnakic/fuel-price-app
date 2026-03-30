/// Result of a sync operation across all three data sources.
class SyncResult {
  final List<double>? oilPrices;
  final List<double>? exchangeRates;
  final Map<String, dynamic>? config;
  final bool oilPricesOk;
  final bool exchangeRatesOk;
  final bool configOk;

  const SyncResult({
    this.oilPrices,
    this.exchangeRates,
    this.config,
    required this.oilPricesOk,
    required this.exchangeRatesOk,
    required this.configOk,
  });

  bool get isFullSuccess => oilPricesOk && exchangeRatesOk && configOk;
  bool get isFullFailure => !oilPricesOk && !exchangeRatesOk && !configOk;

  List<String> get failedSources => [
    if (!oilPricesOk) 'oilPrices',
    if (!exchangeRatesOk) 'exchangeRates',
    if (!configOk) 'config',
  ];
}

/// Orchestrates parallel data fetching with per-source timeout and single retry.
class DataSyncOrchestrator {
  final Future<List<double>> Function() fetchOilPrices;
  final Future<List<double>> Function() fetchExchangeRates;
  final Future<Map<String, dynamic>> Function() fetchConfig;
  final Duration timeout;

  DataSyncOrchestrator({
    required this.fetchOilPrices,
    required this.fetchExchangeRates,
    required this.fetchConfig,
    this.timeout = const Duration(seconds: 30),
  });

  Future<SyncResult> sync() async {
    // First attempt — all in parallel
    final results = await Future.wait([
      _fetchWithTimeout(fetchOilPrices),
      _fetchWithTimeout(fetchExchangeRates),
      _fetchWithTimeout(fetchConfig),
    ]);

    List<double>? oilPrices = results[0] as List<double>?;
    List<double>? exchangeRates = results[1] as List<double>?;
    Map<String, dynamic>? config = results[2] as Map<String, dynamic>?;

    // Retry failed sources once — in parallel
    final retries = await Future.wait([
      oilPrices == null ? _fetchWithTimeout(fetchOilPrices) : Future.value(oilPrices),
      exchangeRates == null ? _fetchWithTimeout(fetchExchangeRates) : Future.value(exchangeRates),
      config == null ? _fetchWithTimeout(fetchConfig) : Future.value(config),
    ]);
    oilPrices ??= retries[0] as List<double>?;
    exchangeRates ??= retries[1] as List<double>?;
    config ??= retries[2] as Map<String, dynamic>?;

    return SyncResult(
      oilPrices: oilPrices,
      exchangeRates: exchangeRates,
      config: config,
      oilPricesOk: oilPrices != null,
      exchangeRatesOk: exchangeRates != null,
      configOk: config != null,
    );
  }

  Future<dynamic> _fetchWithTimeout(Future<dynamic> Function() fetch) async {
    try {
      return await fetch().timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}
