/// Result of a sync operation across all five data sources.
class SyncResult {
  final List<double>? oilPrices;
  final List<double>? exchangeRates;
  final Map<String, dynamic>? config;
  final List<double>? eiaSpotPrices;
  final List<double>? oilApiPrices;
  final bool oilPricesOk;
  final bool exchangeRatesOk;
  final bool configOk;
  final bool eiaSpotOk;
  final bool oilApiOk;

  const SyncResult({
    this.oilPrices,
    this.exchangeRates,
    this.config,
    this.eiaSpotPrices,
    this.oilApiPrices,
    required this.oilPricesOk,
    required this.exchangeRatesOk,
    required this.configOk,
    required this.eiaSpotOk,
    required this.oilApiOk,
  });

  bool get isFullSuccess =>
      oilPricesOk && exchangeRatesOk && configOk && eiaSpotOk && oilApiOk;
  bool get isFullFailure =>
      !oilPricesOk && !exchangeRatesOk && !configOk && !eiaSpotOk && !oilApiOk;

  List<String> get failedSources => [
    if (!oilPricesOk) 'oilPrices',
    if (!exchangeRatesOk) 'exchangeRates',
    if (!configOk) 'config',
    if (!eiaSpotOk) 'eiaSpot',
    if (!oilApiOk) 'oilApi',
  ];
}

/// Orchestrates parallel data fetching with per-source timeout and single retry.
class DataSyncOrchestrator {
  final Future<List<double>> Function() fetchOilPrices;
  final Future<List<double>> Function() fetchExchangeRates;
  final Future<Map<String, dynamic>> Function() fetchConfig;
  final Future<List<double>> Function()? fetchEiaSpotPrices;
  final Future<List<double>> Function()? fetchOilApiPrices;
  final Duration timeout;

  DataSyncOrchestrator({
    required this.fetchOilPrices,
    required this.fetchExchangeRates,
    required this.fetchConfig,
    this.fetchEiaSpotPrices,
    this.fetchOilApiPrices,
    this.timeout = const Duration(seconds: 30),
  });

  Future<SyncResult> sync() async {
    // Wrap optional callbacks: null => auto-success with empty list
    final eiaFetch = fetchEiaSpotPrices ?? () => Future.value(<double>[]);
    final oilApiFetch = fetchOilApiPrices ?? () => Future.value(<double>[]);

    // First attempt — all in parallel
    final results = await Future.wait([
      _fetchWithTimeout(fetchOilPrices),
      _fetchWithTimeout(fetchExchangeRates),
      _fetchWithTimeout(fetchConfig),
      _fetchWithTimeout(eiaFetch),
      _fetchWithTimeout(oilApiFetch),
    ]);

    List<double>? oilPrices = results[0] as List<double>?;
    List<double>? exchangeRates = results[1] as List<double>?;
    Map<String, dynamic>? config = results[2] as Map<String, dynamic>?;
    List<double>? eiaSpotPrices = results[3] as List<double>?;
    List<double>? oilApiPrices = results[4] as List<double>?;

    // Retry failed sources once — in parallel
    final retries = await Future.wait([
      oilPrices == null ? _fetchWithTimeout(fetchOilPrices) : Future.value(oilPrices),
      exchangeRates == null ? _fetchWithTimeout(fetchExchangeRates) : Future.value(exchangeRates),
      config == null ? _fetchWithTimeout(fetchConfig) : Future.value(config),
      eiaSpotPrices == null ? _fetchWithTimeout(eiaFetch) : Future.value(eiaSpotPrices),
      oilApiPrices == null ? _fetchWithTimeout(oilApiFetch) : Future.value(oilApiPrices),
    ]);
    oilPrices ??= retries[0] as List<double>?;
    exchangeRates ??= retries[1] as List<double>?;
    config ??= retries[2] as Map<String, dynamic>?;
    eiaSpotPrices ??= retries[3] as List<double>?;
    oilApiPrices ??= retries[4] as List<double>?;

    return SyncResult(
      oilPrices: oilPrices,
      exchangeRates: exchangeRates,
      config: config,
      eiaSpotPrices: eiaSpotPrices,
      oilApiPrices: oilApiPrices,
      oilPricesOk: oilPrices != null,
      exchangeRatesOk: exchangeRates != null,
      configOk: config != null,
      eiaSpotOk: eiaSpotPrices != null,
      oilApiOk: oilApiPrices != null,
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
