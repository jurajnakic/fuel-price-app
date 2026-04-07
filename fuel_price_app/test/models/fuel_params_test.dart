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
      expect(p.sourceWeights['eurodizel']!['oilapi'], 1.0);
      expect(p.sourceWeights['eurodizel']!['yahoo'], 0.0);
    });

    test('defaultParams has ES95 offset 261', () {
      final p = FuelParams.defaultParams;
      expect(p.cifMedOffsets['es95'], 261.0);
      expect(p.cifMedOffsets['es100'], 261.0);
    });

    test('defaultParams has eurodizel BZ=F fallback factor 11.23', () {
      final p = FuelParams.defaultParams;
      expect(p.cifMedFactors['eurodizel'], 11.23);
      expect(p.cifMedOffsets['eurodizel'], 205.0);
    });

    test('defaultParams has oilApiCifMedOffsets', () {
      final p = FuelParams.defaultParams;
      expect(p.oilApiCifMedOffsets['eurodizel'], 40.0);
    });

    test('fromJson parses oil_api_cif_med_offsets', () {
      final json = _baseJson()
        ..['oil_api_cif_med_offsets'] = {'eurodizel': 55.0};
      final params = FuelParams.fromJson(json);
      expect(params.oilApiCifMedOffsets['eurodizel'], 55.0);
    });

    test('fromJson uses default oilApiCifMedOffsets when missing', () {
      final params = FuelParams.fromJson(_baseJson());
      expect(params.oilApiCifMedOffsets['eurodizel'], 40.0);
    });
  });
}
