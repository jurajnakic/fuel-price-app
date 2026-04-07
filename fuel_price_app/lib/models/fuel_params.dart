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

  /// Conversion: cifMed = raw × factor + offset (USD/tonne).
  /// The offset captures fixed CIF Med costs (shipping, insurance, port fees)
  /// that don't scale with the commodity price.
  final Map<String, double> cifMedFactors;
  final Map<String, double> cifMedOffsets;

  /// EIA API key (hardcoded default, overridable via remote config)
  final String eiaApiKey;

  /// OilPriceAPI key (hardcoded default, overridable via remote config)
  final String oilPriceApiKey;

  /// EIA series ID per fuel type
  final Map<String, String> eiaSymbols;

  /// OilPriceAPI commodity code per fuel type
  final Map<String, String> oilApiSymbols;

  /// CIF Med conversion for EIA: cifMed = raw × factor + offset
  final Map<String, double> eiaCifMedFactors;
  final Map<String, double> eiaCifMedOffsets;

  /// CIF Med conversion factors for OilPriceAPI prices
  final Map<String, double> oilApiCifMedFactors;

  /// CIF Med conversion offsets for OilPriceAPI prices
  final Map<String, double> oilApiCifMedOffsets;

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
      'eurodizel': 'BZ=F',
      'unp_10kg': 'BZ=F',
    },
    this.cifMedFactors = const {
      'es95': 300.0,
      'es100': 300.0,
      'eurodizel': 11.23,
      'unp_10kg': 16.2,
    },
    this.cifMedOffsets = const {
      'es95': 261.0,
      'es100': 261.0,
      'eurodizel': 205.0,
      'unp_10kg': 12.5,
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
      'eurodizel': 'GASOIL_USD',
    },
    this.eiaCifMedFactors = const {
      'es95': 366.0,
      'es100': 366.0,
      'eurodizel': 303.0,
      'unp_10kg': 2153.0,
    },
    this.eiaCifMedOffsets = const {
      'es95': 70.0,
      'es100': 70.0,
      'eurodizel': 105.0,
      'unp_10kg': -13.5,
    },
    this.oilApiCifMedFactors = const {
      'eurodizel': 1.0,
    },
    this.oilApiCifMedOffsets = const {
      'eurodizel': 40.0,
    },
    this.sourceWeights = const {
      'es95': {'yahoo': 1.0},
      'es100': {'yahoo': 1.0},
      'eurodizel': {'oilapi': 1.0, 'yahoo': 0.0},
      'unp_10kg': {'eia': 1.0},
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
              'eurodizel': 'BZ=F',
              'unp_10kg': 'BZ=F',
            },
      cifMedFactors: json.containsKey('cif_med_factors')
          ? (json['cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'es95': 300.0,
              'es100': 300.0,
              'eurodizel': 11.23,
              'unp_10kg': 16.2,
            },
      cifMedOffsets: json.containsKey('cif_med_offsets')
          ? (json['cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'es95': 261.0,
              'es100': 261.0,
              'eurodizel': 205.0,
              'unp_10kg': 12.5,
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
              'eurodizel': 'GASOIL_USD',
            },
      eiaCifMedFactors: json.containsKey('eia_cif_med_factors')
          ? (json['eia_cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'es95': 366.0,
              'es100': 366.0,
              'eurodizel': 303.0,
              'unp_10kg': 2153.0,
            },
      eiaCifMedOffsets: json.containsKey('eia_cif_med_offsets')
          ? (json['eia_cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'es95': 70.0,
              'es100': 70.0,
              'eurodizel': 105.0,
              'unp_10kg': -13.5,
            },
      oilApiCifMedFactors: json.containsKey('oil_api_cif_med_factors')
          ? (json['oil_api_cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'eurodizel': 1.0,
            },
      oilApiCifMedOffsets: json.containsKey('oil_api_cif_med_offsets')
          ? (json['oil_api_cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'eurodizel': 40.0,
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
              'es95': {'yahoo': 1.0},
              'es100': {'yahoo': 1.0},
              'eurodizel': {'oilapi': 1.0, 'yahoo': 0.0},
              'unp_10kg': {'eia': 1.0},
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
    oilApiCifMedOffsets: {'eurodizel': 40.0},
  );
}
