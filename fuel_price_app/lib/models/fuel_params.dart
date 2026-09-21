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
  /// Gasoline and diesel → Heating Oil (HO=F), LPG → Brent (BZ=F).
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
      // ES95/ES100 moved off RB=F on 2026-09-21. RBOB decoupled from Croatian
      // petrol during September: P15-P18 errors ran -8/-16/-21/-15c, and in
      // P17->P18 RB=F rose 7.2% while ES95 rose 1.0%. Walk-forward hold-out
      // (holdout_p18.py) scored RB=F at 11.5c against HO=F at 2.5c.
      // Heating oil for petrol reads odd, but Croatian ex-measure prices track
      // distillates (r=0.94) far better than RBOB (r=0.65).
      'es95': 'HO=F',
      'es100': 'HO=F',
      // Diesel's Yahoo entry is a fallback only (oilapi/GASOIL carries weight
      // 1.0). Moved off Brent for the same reason it stopped being primary in
      // July: BZ=F scores 18.8c walk-forward here, HO=F 1.0c.
      'eurodizel': 'HO=F',
      'plavi_dizel': 'HO=F',
      // LPG has no usable Yahoo proxy; Brent stays only so the blender's
      // equal-weight fallback branch has something non-absurd to use.
      'unp_10kg': 'BZ=F',
      'unp_spremnik': 'BZ=F',
    },
    // P18 LS fit (2026-09-21, pick_p18.py): refit on P1-P18 using the
    // prod-matched settlement window (half-open [start, end), per-date HNB
    // rate, available trading days only, 7-day window from P13 onward since
    // the government moved to weekly pricing on 2026-08-18).
    //
    // Yahoo coefficients. For ES95/ES100 these are PRIMARY (weight 1.0) and
    // now sit on HO=F; for diesel they are the fallback, also on HO=F. The LPG
    // pair stays on BZ=F and is fitted rather than guessed — it used to be a
    // bare 16.2/12.5, which was never a fit at all.
    this.cifMedFactors = const {
      'es95': 216.724,
      'es100': 216.724,
      'eurodizel': 317.330,
      'plavi_dizel': 320.348,
      'unp_10kg': 11.521,
      'unp_spremnik': 11.411,
    },
    this.cifMedOffsets = const {
      'es95': 356.216,
      'es100': 356.216,
      'eurodizel': 73.304,
      'plavi_dizel': 1.902,
      'unp_10kg': 23.029,
      'unp_spremnik': -120.325,
    },
    this.eiaApiKey = 'TMDb4mZNHr7DIUP3ti975TA66BlYWf2aQFhkZc5h',
    // Key rotated 2026-07-24. Free tier is 50 requests per DAY
    // (x-ratelimit-window: daily, verified 2026-08-24) — an earlier note here
    // claimed 200/month, which was wrong.
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
    // EIA fallbacks, all refit on P1-P18 (2026-09-21). These are never the
    // weighted source, but PriceBlender falls back to equal weights across
    // whatever has data, so stale values here get used silently.
    this.eiaCifMedFactors = const {
      'es95': 334.867,
      'es100': 334.867,
      'eurodizel': 311.455,
      'plavi_dizel': 314.905,
      // EIA propane remains poor for Croatian LPG (13.7c even refit) — Mont
      // Belvieu is the real source. Kept only so the fallback branch is sane.
      'unp_10kg': 335.162,
      'unp_spremnik': 305.970,
    },
    this.eiaCifMedOffsets = const {
      'es95': 157.006,
      'es100': 157.006,
      'eurodizel': 83.009,
      'plavi_dizel': 9.704,
      'unp_10kg': 854.098,
      'unp_spremnik': 722.211,
    },
    // Primary source for diesel and LPG; refit 2026-09-21 on P1-P18 (pick_p18.py).
    //   GASOIL_USD (ICE Rotterdam) — walk-forward 3.3c / 2.8c, still clearly
    //     the right source. Factor moved 0.87 -> 1.10 because the July fit was
    //     made when GASOIL coverage was 69% of business days; after the
    //     collection fix it is 90%, so the average it feeds on is no longer
    //     biased by missing days.
    //   PROPANE_MONT_BELVIEU_USD — walk-forward 3.5c / 3.8c. Fitted on P11-P18
    //     only: Mont Belvieu starts 2026-04-22 and its earliest points are
    //     sparse noise (they caused the -34c misses on P5/P6).
    this.oilApiCifMedFactors = const {
      'eurodizel': 1.1003,
      'plavi_dizel': 1.1290,
      'unp_10kg': 879.661,
      'unp_spremnik': 875.159,
    },
    this.oilApiCifMedOffsets = const {
      'eurodizel': 0.125,
      'plavi_dizel': -99.888,
      'unp_10kg': 314.655,
      'unp_spremnik': 164.641,
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
    version: '2026-09-21.1',
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
