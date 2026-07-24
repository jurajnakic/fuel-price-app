import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

void main() {
  group('FuelParams price cycle', () {
    test('defaultParams has referenceDate 2026-03-24', () {
      expect(FuelParams.defaultParams.referenceDate, '2026-03-24');
    });

    test('defaultParams has cycleDays 14', () {
      expect(FuelParams.defaultParams.cycleDays, 14);
    });

    test('fromJson parses price_cycle section', () {
      final json = {
        'version': '2025-02-26',
        'price_cycle': {
          'reference_date': '2026-04-07',
          'cycle_days': 7,
        },
        'price_regulation': {
          'name': 'Test',
          'nn_reference': 'NN 1/2025',
          'effective_date': '2025-01-01',
        },
        'excise_regulation': {
          'name': 'Test Excise',
          'nn_reference': 'NN 2/2025',
          'effective_date': '2025-01-01',
        },
        'premiums': {'es95': 0.1},
        'excise_duties': {'es95': 0.4},
        'density': {'es95': 0.755},
        'vat_rate': 0.25,
      };
      final params = FuelParams.fromJson(json);
      expect(params.referenceDate, '2026-04-07');
      expect(params.cycleDays, 7);
    });

    test('fromJson uses defaults when price_cycle missing', () {
      final json = {
        'version': '2025-02-26',
        'price_regulation': {
          'name': 'Test',
          'nn_reference': 'NN 1/2025',
          'effective_date': '2025-01-01',
        },
        'excise_regulation': {
          'name': 'Test Excise',
          'nn_reference': 'NN 2/2025',
          'effective_date': '2025-01-01',
        },
        'premiums': {'es95': 0.1},
        'excise_duties': {'es95': 0.4},
        'density': {'es95': 0.755},
        'vat_rate': 0.25,
      };
      final params = FuelParams.fromJson(json);
      expect(params.referenceDate, '2026-03-24');
      expect(params.cycleDays, 14);
    });

    test('fromJson falls back to 14 when cycleDays not multiple of 7', () {
      final json = {
        'version': '2025-02-26',
        'price_cycle': {
          'reference_date': '2026-03-24',
          'cycle_days': 10,
        },
        'price_regulation': {
          'name': 'Test',
          'nn_reference': 'NN 1/2025',
          'effective_date': '2025-01-01',
        },
        'excise_regulation': {
          'name': 'Test Excise',
          'nn_reference': 'NN 2/2025',
          'effective_date': '2025-01-01',
        },
        'premiums': {'es95': 0.1},
        'excise_duties': {'es95': 0.4},
        'density': {'es95': 0.755},
        'vat_rate': 0.25,
      };
      final params = FuelParams.fromJson(json);
      expect(params.cycleDays, 14);
      expect(params.referenceDate, '2026-03-24');
    });

    test('fromJson falls back to default when referenceDate is invalid', () {
      final json = {
        'version': '2025-02-26',
        'price_cycle': {
          'reference_date': 'not-a-date',
          'cycle_days': 14,
        },
        'price_regulation': {
          'name': 'Test',
          'nn_reference': 'NN 1/2025',
          'effective_date': '2025-01-01',
        },
        'excise_regulation': {
          'name': 'Test Excise',
          'nn_reference': 'NN 2/2025',
          'effective_date': '2025-01-01',
        },
        'premiums': {'es95': 0.1},
        'excise_duties': {'es95': 0.4},
        'density': {'es95': 0.755},
        'vat_rate': 0.25,
      };
      final params = FuelParams.fromJson(json);
      expect(params.referenceDate, '2026-03-24');
    });
  });

  group('FuelParams multi-source config', () {
    Map<String, dynamic> _baseJson() => {
      'version': '2025-02-26',
      'price_regulation': {
        'name': 'Test', 'nn_reference': 'NN 1/2025', 'effective_date': '2025-01-01',
      },
      'excise_regulation': {
        'name': 'Test Excise', 'nn_reference': 'NN 2/2025', 'effective_date': '2025-01-01',
      },
      'premiums': {'es95': 0.1},
      'excise_duties': {'es95': 0.4},
      'density': {'es95': 0.755},
      'vat_rate': 0.25,
    };

    test('fromJson uses defaults when EIA/OilAPI fields missing', () {
      final params = FuelParams.fromJson(_baseJson());
      expect(params.eiaApiKey, isNotEmpty);
      expect(params.oilPriceApiKey, isNotEmpty);
      expect(params.eiaSymbols, isNotEmpty);
      expect(params.eiaSymbols['es95'], 'EER_EPMRU_PF4_Y35NY_DPG');
      expect(params.oilApiSymbols['eurodizel'], 'GASOIL_USD');
      expect(params.eiaCifMedFactors, isNotEmpty);
      expect(params.oilApiCifMedFactors, isNotEmpty);
      expect(params.sourceWeights, isNotEmpty);
      expect(params.sourceWeights['eurodizel']!['yahoo'], 0.0);
      expect(params.sourceWeights['eurodizel']!['oilapi'], 1.0);
    });

    test('fromJson parses EIA/OilAPI fields from JSON', () {
      final json = _baseJson()
        ..['eia_api_key'] = 'my-eia-key'
        ..['oil_price_api_key'] = 'my-oil-key'
        ..['eia_symbols'] = {'es95': 'CUSTOM_SERIES'}
        ..['eia_cif_med_factors'] = {'es95': 999.0}
        ..['oil_api_symbols'] = {'eurodizel': 'CUSTOM_OIL'}
        ..['oil_api_cif_med_factors'] = {'eurodizel': 1.1}
        ..['source_weights'] = {
          'es95': {'yahoo': 0.7, 'eia': 0.3},
        };
      final params = FuelParams.fromJson(json);
      expect(params.eiaApiKey, 'my-eia-key');
      expect(params.oilPriceApiKey, 'my-oil-key');
      expect(params.eiaSymbols['es95'], 'CUSTOM_SERIES');
      expect(params.eiaCifMedFactors['es95'], 999.0);
      expect(params.oilApiSymbols['eurodizel'], 'CUSTOM_OIL');
      expect(params.oilApiCifMedFactors['eurodizel'], 1.1);
      expect(params.sourceWeights['es95']!['yahoo'], 0.7);
    });

    test('defaultParams has multi-source defaults', () {
      final p = FuelParams.defaultParams;
      expect(p.eiaSymbols['eurodizel'], 'EER_EPD2DXL0_PF4_Y35NY_DPG');
      expect(p.oilApiSymbols['eurodizel'], 'GASOIL_USD');
      expect(p.sourceWeights['eurodizel']!['yahoo'], 0.0);
      expect(p.sourceWeights['eurodizel']!['oilapi'], 1.0);
    });

    test('defaultParams has ES95 P10 LS fit (2026-07-24)', () {
      final p = FuelParams.defaultParams;
      expect(p.cifMedFactors['es95'], 383.647);
      expect(p.cifMedFactors['es100'], 383.647);
      expect(p.cifMedOffsets['es95'], -57.679);
      expect(p.cifMedOffsets['es100'], -57.679);
    });

    test('defaultParams routes diesel and LPG through OilPriceAPI', () {
      final p = FuelParams.defaultParams;
      for (final fuel in ['eurodizel', 'plavi_dizel', 'unp_10kg', 'unp_spremnik']) {
        expect(p.sourceWeights[fuel]!['oilapi'], 1.0, reason: fuel);
        expect(p.oilApiSymbols[fuel], isNotNull, reason: fuel);
        expect(p.oilApiCifMedFactors[fuel], isNotNull, reason: fuel);
      }
      expect(p.oilApiSymbols['eurodizel'], 'GASOIL_USD');
      expect(p.oilApiSymbols['unp_10kg'], 'PROPANE_MONT_BELVIEU_USD');
    });

    test('defaultParams has GASOIL P10 LS fit for diesel', () {
      final p = FuelParams.defaultParams;
      expect(p.oilApiCifMedFactors['eurodizel'], 0.8708);
      expect(p.oilApiCifMedOffsets['eurodizel'], 229.789);
      expect(p.oilApiCifMedFactors['plavi_dizel'], 0.9765);
      expect(p.oilApiCifMedOffsets['plavi_dizel'], 48.104);
    });

    test('defaultParams has Mont Belvieu P10 LS fit for LPG', () {
      final p = FuelParams.defaultParams;
      expect(p.oilApiCifMedFactors['unp_10kg'], 1166.446);
      expect(p.oilApiCifMedOffsets['unp_10kg'], 50.643);
      expect(p.oilApiCifMedFactors['unp_spremnik'], 1076.654);
      expect(p.oilApiCifMedOffsets['unp_spremnik'], -34.083);
    });

    test('LPG fallback coefficients are no longer a constant predictor', () {
      // The old factor=0 constant predictor drifted to +65c by P10.
      final p = FuelParams.defaultParams;
      expect(p.eiaCifMedFactors['unp_10kg'], greaterThan(0));
      expect(p.eiaCifMedFactors['unp_spremnik'], greaterThan(0));
    });

    test('defaultParams includes plavi_dizel and unp_spremnik', () {
      final p = FuelParams.defaultParams;
      expect(p.premiums['plavi_dizel'], 0.0781);
      expect(p.exciseDuties['plavi_dizel'], 0.0);
      expect(p.density['plavi_dizel'], 0.845);
      expect(p.premiums['unp_spremnik'], 0.4116);
    });

    test('defaultParams has oilApiCifMedOffsets for every OilAPI fuel', () {
      final p = FuelParams.defaultParams;
      expect(p.oilApiCifMedOffsets['eurodizel'], 229.789);
      // Regression: defaultParams used to override this map with just
      // {'eurodizel': 40.0}, nulling the LPG offsets.
      for (final fuel in p.oilApiSymbols.keys) {
        expect(p.oilApiCifMedOffsets[fuel], isNotNull, reason: fuel);
      }
    });

    test('fromJson parses oil_api_cif_med_offsets', () {
      final json = _baseJson()
        ..['oil_api_cif_med_offsets'] = {'eurodizel': 55.0};
      final params = FuelParams.fromJson(json);
      expect(params.oilApiCifMedOffsets['eurodizel'], 55.0);
    });

    test('fromJson uses default oilApiCifMedOffsets when missing', () {
      final params = FuelParams.fromJson(_baseJson());
      expect(params.oilApiCifMedOffsets['eurodizel'], 229.789);
    });
  });
}
