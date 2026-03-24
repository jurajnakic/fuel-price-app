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
