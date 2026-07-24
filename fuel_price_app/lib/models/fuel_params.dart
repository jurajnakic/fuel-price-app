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
      'plavi_dizel': 'BZ=F',
      'unp_10kg': 'BZ=F',
      'unp_spremnik': 'BZ=F',
    },
    // P10 LS fit (2026-07-24, fit_p10.py): refit on P1-P10 using prod-matched
    // settlement window (half-open [start, end), per-date HNB rate, available
    // trading days only).
    //
    // Yahoo (Brent/RBOB) is no longer the primary source for diesel or LPG —
    // see sourceWeights below. These coefficients remain because PriceBlender
    // falls back to equal weights across whatever sources have data when the
    // weighted source is missing, so they must not be stale.
    //   ES95/ES100: fit on P5-P10 (regime shift — the P1-P5 fit drifted to
    //     +4/+9/+6c on P8-P10). Errors on P5-P10: 0/+1/-2/-1/+2/-1c.
    //   Eurodizel/plavi: best Brent fit (P5-P10), ~4c. GASOIL does 2c.
    this.cifMedFactors = const {
      'es95': 383.647,
      'es100': 383.647,
      'eurodizel': 8.276,
      'plavi_dizel': 9.197,
      'unp_10kg': 16.2,
      'unp_spremnik': 16.2,
    },
    this.cifMedOffsets = const {
      'es95': -57.679,
      'es100': -57.679,
      'eurodizel': 429.433,
      'plavi_dizel': 279.678,
      'unp_10kg': 12.5,
      'unp_spremnik': 12.5,
    },
    this.eiaApiKey = 'TMDb4mZNHr7DIUP3ti975TA66BlYWf2aQFhkZc5h',
    // Key rotated 2026-07-24; free tier is now 200 req/month (was 50).
    this.oilPriceApiKey = '79fb860081d26b9db83855f5d12beb9cd0d83392ac6b44ab23416600237c58c7',
    this.eiaSymbols = const {
      'es95': 'EER_EPMRU_PF4_Y35NY_DPG',
      'es100': 'EER_EPMRU_PF4_Y35NY_DPG',
      'eurodizel': 'EER_EPD2DXL0_PF4_Y35NY_DPG',
      'plavi_dizel': 'EER_EPD2DXL0_PF4_Y35NY_DPG',
      'unp_10kg': 'EER_EPLLPA_PF4_Y44MB_DPG',
      'unp_spremnik': 'EER_EPLLPA_PF4_Y44MB_DPG',
    },
    this.oilApiSymbols = const {
      'eurodizel': 'GASOIL_USD',
      'plavi_dizel': 'GASOIL_USD',
      'unp_10kg': 'PROPANE_MONT_BELVIEU_USD',
      'unp_spremnik': 'PROPANE_MONT_BELVIEU_USD',
    },
    this.eiaCifMedFactors = const {
      'es95': 366.0,
      'es100': 366.0,
      'eurodizel': 303.0,
      'plavi_dizel': 303.0,
      // EIA propane is the fallback for LPG, not the primary source. The old
      // constant predictor (factor=0) drifted to +65c by P10 as HR LPG kept
      // falling; this is the P7-P10 fit, which at least has the right sign.
      'unp_10kg': 1374.335,
      'unp_spremnik': 1270.884,
    },
    this.eiaCifMedOffsets = const {
      'es95': 70.0,
      'es100': 70.0,
      'eurodizel': 105.0,
      'plavi_dizel': 105.0,
      'unp_10kg': -101.940,
      'unp_spremnik': -176.761,
    },
    // Primary source for diesel and LPG as of 2026-07-24.
    //   GASOIL_USD (ICE Rotterdam), fit on P5-P10: eurodizel MAE 2.0c,
    //     plavi 2.3c. Factor is stable across fit windows (0.871 vs 0.846),
    //     so this is a real relationship, not an overfit.
    //   PROPANE_MONT_BELVIEU_USD, fit on P7-P10: MAE 4.0c. Fitted on the
    //     recent window only because Mont Belvieu has just 2-3 points per
    //     14-day window and the earliest ones are noise.
    this.oilApiCifMedFactors = const {
      'eurodizel': 0.8708,
      'plavi_dizel': 0.9765,
      'unp_10kg': 1166.446,
      'unp_spremnik': 1076.654,
    },
    this.oilApiCifMedOffsets = const {
      'eurodizel': 229.789,
      'plavi_dizel': 48.104,
      'unp_10kg': 50.643,
      'unp_spremnik': -34.083,
    },
    this.sourceWeights = const {
      'es95': {'yahoo': 1.0},
      'es100': {'yahoo': 1.0},
      'eurodizel': {'yahoo': 0.0, 'oilapi': 1.0},
      'plavi_dizel': {'yahoo': 0.0, 'oilapi': 1.0},
      'unp_10kg': {'eia': 0.0, 'oilapi': 1.0},
      'unp_spremnik': {'eia': 0.0, 'oilapi': 1.0},
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
          : defaultParams.yahooSymbols,
      cifMedFactors: json.containsKey('cif_med_factors')
          ? (json['cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaultParams.cifMedFactors,
      cifMedOffsets: json.containsKey('cif_med_offsets')
          ? (json['cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaultParams.cifMedOffsets,
      eiaApiKey: json.containsKey('eia_api_key')
          ? json['eia_api_key'] as String
          : defaultParams.eiaApiKey,
      oilPriceApiKey: json.containsKey('oil_price_api_key')
          ? json['oil_price_api_key'] as String
          : defaultParams.oilPriceApiKey,
      eiaSymbols: json.containsKey('eia_symbols')
          ? (json['eia_symbols'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : defaultParams.eiaSymbols,
      oilApiSymbols: json.containsKey('oil_api_symbols')
          ? (json['oil_api_symbols'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : defaultParams.oilApiSymbols,
      eiaCifMedFactors: json.containsKey('eia_cif_med_factors')
          ? (json['eia_cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaultParams.eiaCifMedFactors,
      eiaCifMedOffsets: json.containsKey('eia_cif_med_offsets')
          ? (json['eia_cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaultParams.eiaCifMedOffsets,
      oilApiCifMedFactors: json.containsKey('oil_api_cif_med_factors')
          ? (json['oil_api_cif_med_factors'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaultParams.oilApiCifMedFactors,
      oilApiCifMedOffsets: json.containsKey('oil_api_cif_med_offsets')
          ? (json['oil_api_cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaultParams.oilApiCifMedOffsets,
      sourceWeights: json.containsKey('source_weights')
          ? (json['source_weights'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(
                k,
                (v as Map<String, dynamic>).map(
                  (sk, sv) => MapEntry(sk, (sv as num).toDouble()),
                ),
              ),
            )
          : defaultParams.sourceWeights,
    );
  }

  static const defaultParams = FuelParams(
    version: '2026-07-24.1',
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
    premiums: {
      'es95': 0.1545,
      'es100': 0.1545,
      'eurodizel': 0.1545,
      'plavi_dizel': 0.0781,
      'unp_10kg': 0.8429,
      'unp_spremnik': 0.4116,
    },
    exciseDuties: {
      'es95': 0.4560,
      'es100': 0.4560,
      'eurodizel': 0.40613,
      'plavi_dizel': 0.0,
      'unp_10kg': 0.01327,
      'unp_spremnik': 0.01327,
    },
    density: {
      'es95': 0.755,
      'es100': 0.755,
      'eurodizel': 0.845,
      'plavi_dizel': 0.845,
    },
    vatRate: 0.25,
    referenceDate: '2026-03-24',
    cycleDays: 14,
    // NB: do not re-add an oilApiCifMedOffsets override here. It used to carry
    // only {'eurodizel': 40.0}, which silently nulled the LPG offsets (they
    // then resolved to 0.0). The constructor defaults above are the calibration.
  );
}
