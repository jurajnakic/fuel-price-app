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
}
