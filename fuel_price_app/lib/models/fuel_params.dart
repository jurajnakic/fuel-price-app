class RegulationInfo {
  final String name;
  final String nnReference;
  final String effectiveDate;
  final String? nnUrl;
  final String? note;

  const RegulationInfo({
    required this.name,
    required this.nnReference,
    required this.effectiveDate,
    this.nnUrl,
    this.note,
  });

  factory RegulationInfo.fromJson(Map<String, dynamic> json) => RegulationInfo(
    name: json['name'] as String,
    nnReference: json['nn_reference'] as String,
    effectiveDate: json['effective_date'] as String,
    nnUrl: json['nn_url'] as String?,
    note: json['note'] as String?,
  );
}

class FuelParams {
  final String version;
  final RegulationInfo priceRegulation;
  final RegulationInfo exciseRegulation;
  final Map<String, double> premiums;
  final Map<String, double> exciseDuties;
  final Map<String, double> density;
  final double vatRate;
  final String referenceDate;
  final int cycleDays;

  /// Yahoo Finance symbol per fuel type for CIF Med approximation.
  /// Gasoline → RBOB (RB=F), Diesel → Heating Oil (HO=F), LPG → Brent (BZ=F).
  final Map<String, String> yahooSymbols;

  /// Conversion factors: raw Yahoo price → CIF Med USD/tonne.
  /// RB=F (USD/gal): ×349.9 (gal→tonne) × ~1.15 (CIF Med premium) ≈ 402
  /// HO=F (USD/gal): ×312.6 (gal→tonne) × ~1.20 (CIF Med premium) ≈ 375
  /// BZ=F (USD/bbl): ×7.33 (bbl→tonne) × ~2.18 (LPG product/CIF Med factor) ≈ 16.0
  final Map<String, double> cifMedFactors;

  /// EIA API key (hardcoded default, overridable via remote config)
  final String eiaApiKey;

  /// OilPriceAPI key (hardcoded default, overridable via remote config)
  final String oilPriceApiKey;

  /// EIA series ID per fuel type
  final Map<String, String> eiaSymbols;

  /// OilPriceAPI commodity code per fuel type
  final Map<String, String> oilApiSymbols;

  /// CIF Med conversion factors for EIA spot prices
  final Map<String, double> eiaCifMedFactors;

  /// CIF Med conversion factors for OilPriceAPI prices
  final Map<String, double> oilApiCifMedFactors;

  /// Source weights per fuel type: maps source name → weight
  /// Sources: "yahoo", "eia", "oilapi". Normalized at runtime.
  final Map<String, Map<String, double>> sourceWeights;

  const FuelParams({
    required this.version,
    required this.priceRegulation,
    required this.exciseRegulation,
    required this.premiums,
    required this.exciseDuties,
    required this.density,
    required this.vatRate,
    this.referenceDate = '2026-03-24',
    this.cycleDays = 14,
    this.yahooSymbols = const {
      'es95': 'RB=F',
      'es100': 'RB=F',
      'eurodizel': 'HO=F',
      'unp_10kg': 'BZ=F',
    },
    this.cifMedFactors = const {
      'es95': 402.4,
      'es100': 402.4,
      'eurodizel': 327.0,
      'unp_10kg': 16.0,
    },
    this.eiaApiKey = 'TMDb4mZNHr7DIUP3ti975TA66BlYWf2aQFhkZc5h',
    this.oilPriceApiKey = '3275b97a0611f342bff1f4253e9d0158e00a0d33d0f3d512df25db60eb07f3ce',
    this.eiaSymbols = const {
      'es95': 'EER_EPMRU_PF4_Y35NY_DPG',
      'es100': 'EER_EPMRU_PF4_Y35NY_DPG',
      'eurodizel': 'EER_EPD2DXL0_PF4_Y35NY_DPG',
      'unp_10kg': 'EER_EPLLPA_PF4_Y44MB_DPG',
    },
    this.oilApiSymbols = const {
      'eurodizel': 'MGO_05S_NLRTM_USD',
    },
    this.eiaCifMedFactors = const {
      'es95': 293.0,
      'es100': 293.0,
      'eurodizel': 248.0,
      'unp_10kg': 1578.0,
    },
    this.oilApiCifMedFactors = const {
      'eurodizel': 1.05,
    },
    this.sourceWeights = const {
      'es95': {'yahoo': 0.29, 'eia': 0.71},
      'es100': {'yahoo': 0.29, 'eia': 0.71},
      'eurodizel': {'yahoo': 0.1, 'eia': 0.6, 'oilapi': 0.3},
      'unp_10kg': {'yahoo': 0.31, 'eia': 0.69},
    },
  });

  factory FuelParams.fromJson(Map<String, dynamic> json) {
    final priceCycle = json['price_cycle'] as Map<String, dynamic>?;
    final rawReferenceDate =
        (priceCycle?['reference_date'] as String?) ?? '2026-03-24';
    // Validate date format; fall back to default on parse failure
    String referenceDate;
    try {
      DateTime.parse(rawReferenceDate);
      referenceDate = rawReferenceDate;
    } on FormatException {
      referenceDate = '2026-03-24';
    }
    final int rawCycleDays = (priceCycle?['cycle_days'] as num?)?.toInt() ?? 14;
    final int cycleDays =
        (rawCycleDays > 0 && rawCycleDays % 7 == 0) ? rawCycleDays : 14;

    return FuelParams(
      version: json['version'] as String,
      priceRegulation: RegulationInfo.fromJson(
          json['price_regulation'] as Map<String, dynamic>),
      exciseRegulation: RegulationInfo.fromJson(
          json['excise_regulation'] as Map<String, dynamic>),
      premiums: (json['premiums'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      exciseDuties: (json['excise_duties'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      density: (json['density'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      vatRate: (json['vat_rate'] as num).toDouble(),
      referenceDate: referenceDate,
      cycleDays: cycleDays,
      yahooSymbols: json.containsKey('yahoo_symbols')
          ? (json['yahoo_symbols'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : const {
              'es95': 'RB=F',
              'es100': 'RB=F',
              'eurodizel': 'HO=F',
              'unp_10kg': 'BZ=F',
            },
      cifMedFactors: json.containsKey('cif_med_factors')
          ? (json['cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'es95': 402.4,
              'es100': 402.4,
              'eurodizel': 327.0,
              'unp_10kg': 16.0,
            },
      eiaApiKey: json.containsKey('eia_api_key')
          ? json['eia_api_key'] as String
          : 'TMDb4mZNHr7DIUP3ti975TA66BlYWf2aQFhkZc5h',
      oilPriceApiKey: json.containsKey('oil_price_api_key')
          ? json['oil_price_api_key'] as String
          : '3275b97a0611f342bff1f4253e9d0158e00a0d33d0f3d512df25db60eb07f3ce',
      eiaSymbols: json.containsKey('eia_symbols')
          ? (json['eia_symbols'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : const {
              'es95': 'EER_EPMRU_PF4_Y35NY_DPG',
              'es100': 'EER_EPMRU_PF4_Y35NY_DPG',
              'eurodizel': 'EER_EPD2DXL0_PF4_Y35NY_DPG',
              'unp_10kg': 'EER_EPLLPA_PF4_Y44MB_DPG',
            },
      oilApiSymbols: json.containsKey('oil_api_symbols')
          ? (json['oil_api_symbols'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : const {
              'eurodizel': 'MGO_05S_NLRTM_USD',
            },
      eiaCifMedFactors: json.containsKey('eia_cif_med_factors')
          ? (json['eia_cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'es95': 293.0,
              'es100': 293.0,
              'eurodizel': 248.0,
              'unp_10kg': 1578.0,
            },
      oilApiCifMedFactors: json.containsKey('oil_api_cif_med_factors')
          ? (json['oil_api_cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'eurodizel': 1.05,
            },
      sourceWeights: json.containsKey('source_weights')
          ? (json['source_weights'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(
                k,
                (v as Map<String, dynamic>).map(
                  (sk, sv) => MapEntry(sk, (sv as num).toDouble()),
                ),
              ),
            )
          : const {
              'es95': {'yahoo': 0.29, 'eia': 0.71},
              'es100': {'yahoo': 0.29, 'eia': 0.71},
              'eurodizel': {'yahoo': 0.1, 'eia': 0.6, 'oilapi': 0.3},
              'unp_10kg': {'yahoo': 0.31, 'eia': 0.69},
            },
    );
  }

  static const defaultParams = FuelParams(
    version: '2025-02-26',
    priceRegulation: RegulationInfo(
      name: 'Uredba o utvrđivanju najviših maloprodajnih cijena naftnih derivata',
      nnReference: 'NN 31/2025',
      effectiveDate: '2025-02-26',
      nnUrl: 'https://narodne-novine.nn.hr/clanci/sluzbeni/full/2025_02_31_326.html',
    ),
    exciseRegulation: RegulationInfo(
      name: 'Uredba o visini trošarine na energente i električnu energiju',
      nnReference: 'NN 156/2022 (konsolidirana)',
      effectiveDate: '2023-01-01',
      note: 'Vlada periodički mijenja visinu trošarine zasebnim uredbama',
    ),
    premiums: {'es95': 0.1545, 'es100': 0.1545, 'eurodizel': 0.1545, 'unp_10kg': 0.8429},
    exciseDuties: {'es95': 0.4560, 'es100': 0.4560, 'eurodizel': 0.40613, 'unp_10kg': 0.01327},
    density: {'es95': 0.755, 'es100': 0.755, 'eurodizel': 0.845},
    vatRate: 0.25,
    referenceDate: '2026-03-24',
    cycleDays: 14,
  );
}
