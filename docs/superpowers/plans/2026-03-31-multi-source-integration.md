# Multi-Source Integration + Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add EIA and OilPriceAPI as additional price data sources with weighted averaging, fix dark theme persistence, and bump app version.

**Architecture:** Three data sources (Yahoo, EIA, OilPriceAPI) each fetch commodity prices independently. Prices are stored in the existing `oil_prices` table with different `source` identifiers. At prediction time, each source produces an independent price estimate, then a configurable weighted average produces the final single price. Weights are stored in remote config (`fuel_params.json`) for tuning without app rebuild.

**Tech Stack:** Flutter, Dart, Dio, sqflite, SharedPreferences, BLoC/Cubit, EIA API v2, OilPriceAPI REST

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/data/services/eia_service.dart` | Fetch daily spot prices from EIA API |
| Create | `test/data/services/eia_service_test.dart` | Unit tests for EIA service |
| Create | `lib/data/services/oil_price_api_service.dart` | Fetch European prices from OilPriceAPI |
| Create | `test/data/services/oil_price_api_service_test.dart` | Unit tests for OilPriceAPI service |
| Modify | `lib/models/fuel_params.dart` | Add EIA/OilPriceAPI config fields |
| Modify | `test/models/fuel_params_test.dart` | Test new fields + backward compat |
| Modify | `config/fuel_params.json` | Add EIA/OilPriceAPI sections |
| Modify | `lib/data/services/data_sync_orchestrator.dart` | Add 2 new source callbacks |
| Modify | `test/data/services/data_sync_orchestrator_test.dart` | Test 5-source orchestration |
| Create | `lib/domain/price_blender.dart` | Weighted price blending logic |
| Create | `test/domain/price_blender_test.dart` | Unit tests for blending |
| Modify | `lib/app.dart` | Wire up new services + blended predictions |
| Modify | `lib/scheduling/background_sync.dart` | Add EIA/OilPriceAPI to background sync |
| Modify | `lib/blocs/settings_cubit.dart` | Persist theme mode to SharedPreferences |
| Modify | `lib/ui/screens/settings_screen.dart` | Read version from package_info, update formula text |
| Modify | `pubspec.yaml` | Bump version to 3.0.0+3, add package_info_plus |

---

### Task 1: EIA Service

**Files:**
- Create: `lib/data/services/eia_service.dart`
- Create: `test/data/services/eia_service_test.dart`

- [ ] **Step 1: Write failing test for EIA price parsing**

```dart
// test/data/services/eia_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/eia_service.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

void main() {
  late EiaService service;
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
  });

  setUp(() {
    mockDio = MockDio();
    service = EiaService(dio: mockDio, apiKey: 'test-key');
  });

  test('parses daily spot prices from EIA API response', () async {
    final jsonData = {
      'response': {
        'data': [
          {
            'period': '2026-03-20',
            'series-description': 'NY Harbor Conventional Gasoline',
            'value': '2.45',
            'units': '\$/GAL',
          },
          {
            'period': '2026-03-19',
            'series-description': 'NY Harbor Conventional Gasoline',
            'value': '2.42',
            'units': '\$/GAL',
          },
        ],
      },
    };

    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchSpotPrices('EER_EPMRU_PF4_Y35NY_DPG', days: 30);
    expect(prices.length, 2);
    expect(prices.first.date, DateTime.utc(2026, 3, 20));
    expect(prices.first.value, 2.45);
    expect(prices.last.value, 2.42);
  });

  test('returns empty list on API error', () async {
    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionTimeout,
    ));

    final prices = await service.fetchSpotPrices('EER_EPMRU_PF4_Y35NY_DPG', days: 30);
    expect(prices, isEmpty);
  });

  test('skips entries with null or "." value', () async {
    final jsonData = {
      'response': {
        'data': [
          {'period': '2026-03-20', 'value': '2.45'},
          {'period': '2026-03-19', 'value': '.'},
          {'period': '2026-03-18', 'value': null},
          {'period': '2026-03-17', 'value': '2.40'},
        ],
      },
    };

    when(() => mockDio.get(
      any(),
      queryParameters: any(named: 'queryParameters'),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchSpotPrices('EER_EPMRU_PF4_Y35NY_DPG', days: 30);
    expect(prices.length, 2);
    expect(prices.first.value, 2.45);
    expect(prices.last.value, 2.40);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/data/services/eia_service_test.dart`
Expected: FAIL — `eia_service.dart` does not exist

- [ ] **Step 3: Implement EIA service**

```dart
// lib/data/services/eia_service.dart
import 'package:dio/dio.dart';

class EiaPrice {
  final DateTime date;
  final double value;

  EiaPrice({required this.date, required this.value});
}

class EiaService {
  final Dio dio;
  final String apiKey;

  static const _baseUrl = 'https://api.eia.gov/v2/petroleum/pri/spt/data/';

  EiaService({Dio? dio, required this.apiKey}) : dio = dio ?? Dio();

  // ignore: avoid_print
  static void _log(String msg) => print('[EIA] $msg');

  /// Fetch daily spot prices for an EIA series.
  Future<List<EiaPrice>> fetchSpotPrices(String seriesId, {int days = 60}) async {
    try {
      final start = DateTime.now().subtract(Duration(days: days + 7));
      final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

      _log('fetching $seriesId from $startStr');
      final response = await dio.get(
        _baseUrl,
        queryParameters: {
          'api_key': apiKey,
          'frequency': 'daily',
          'data[]': 'value',
          'facets[series][]': seriesId,
          'start': startStr,
          'sort[0][column]': 'period',
          'sort[0][direction]': 'asc',
          'length': '5000',
        },
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = response.data;
      final rows = (data['response']?['data'] as List?) ?? [];

      final prices = <EiaPrice>[];
      for (final row in rows) {
        final period = row['period'] as String?;
        final rawValue = row['value'];
        if (period == null) continue;

        final valueStr = rawValue?.toString();
        if (valueStr == null || valueStr == '.' || valueStr.isEmpty) continue;
        final value = double.tryParse(valueStr);
        if (value == null) continue;

        prices.add(EiaPrice(
          date: DateTime.parse(period),
          value: value,
        ));
      }

      _log('got ${prices.length} prices for $seriesId');
      return prices;
    } catch (e) {
      _log('FAILED for $seriesId: $e');
      return [];
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/data/services/eia_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/data/services/eia_service.dart fuel_price_app/test/data/services/eia_service_test.dart
git commit -m "feat: add EIA API service for US spot prices"
```

---

### Task 2: OilPriceAPI Service

**Files:**
- Create: `lib/data/services/oil_price_api_service.dart`
- Create: `test/data/services/oil_price_api_service_test.dart`

- [ ] **Step 1: Write failing test for OilPriceAPI**

```dart
// test/data/services/oil_price_api_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/oil_price_api_service.dart';

class MockDio extends Mock implements Dio {}

class FakeOptions extends Fake implements Options {}

void main() {
  late OilPriceApiService service;
  late MockDio mockDio;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
  });

  setUp(() {
    mockDio = MockDio();
    service = OilPriceApiService(dio: mockDio, apiKey: 'test-token');
  });

  test('parses latest price from OilPriceAPI response', () async {
    final jsonData = {
      'status': 'success',
      'data': {
        'price': 720.50,
        'formatted': '\$720.50',
        'currency': 'USD',
        'code': 'MGO_05S_NLRTM_USD',
        'created_at': '2026-03-28T14:30:00Z',
      },
    };

    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      headers: Headers.fromMap({
        'x-ratelimit-remaining': ['45'],
      }),
      requestOptions: RequestOptions(path: ''),
    ));

    final result = await service.fetchLatestPrice('MGO_05S_NLRTM_USD');
    expect(result, isNotNull);
    expect(result!.value, 720.50);
    expect(result.date.year, 2026);
    expect(service.remainingRequests, 45);
  });

  test('returns null on API error', () async {
    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
    )).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionTimeout,
    ));

    final result = await service.fetchLatestPrice('MGO_05S_NLRTM_USD');
    expect(result, isNull);
  });

  test('returns null when status is not success', () async {
    final jsonData = {
      'status': 'error',
      'message': 'Invalid API key',
    };

    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 401,
      requestOptions: RequestOptions(path: ''),
    ));

    final result = await service.fetchLatestPrice('MGO_05S_NLRTM_USD');
    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/data/services/oil_price_api_service_test.dart`
Expected: FAIL — file does not exist

- [ ] **Step 3: Implement OilPriceAPI service**

```dart
// lib/data/services/oil_price_api_service.dart
import 'package:dio/dio.dart';

class OilApiPrice {
  final DateTime date;
  final double value;

  OilApiPrice({required this.date, required this.value});
}

class OilPriceApiService {
  final Dio dio;
  final String apiKey;
  int? _remainingRequests;

  static const _baseUrl = 'https://api.oilpriceapi.com/v1/prices/latest';

  OilPriceApiService({Dio? dio, required this.apiKey}) : dio = dio ?? Dio();

  int? get remainingRequests => _remainingRequests;

  // ignore: avoid_print
  static void _log(String msg) => print('[OilPriceAPI] $msg');

  /// Fetch latest price for a commodity code.
  Future<OilApiPrice?> fetchLatestPrice(String commodityCode) async {
    try {
      _log('fetching $commodityCode');
      final response = await dio.get(
        _baseUrl,
        options: Options(
          headers: {
            'Authorization': 'Token $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 10),
        ),
        queryParameters: {
          'by_code': commodityCode,
        },
      );

      // Track rate limit from headers
      final remaining = response.headers.value('x-ratelimit-remaining');
      if (remaining != null) {
        _remainingRequests = int.tryParse(remaining);
        _log('remaining requests: $_remainingRequests');
      }

      final data = response.data;
      if (data['status'] != 'success') {
        _log('non-success status: ${data['status']}');
        return null;
      }

      final priceData = data['data'];
      final price = (priceData['price'] as num?)?.toDouble();
      final createdAt = priceData['created_at'] as String?;
      if (price == null || createdAt == null) return null;

      final date = DateTime.parse(createdAt);
      _log('got $commodityCode = $price at $date');

      return OilApiPrice(date: date, value: price);
    } catch (e) {
      _log('FAILED for $commodityCode: $e');
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/data/services/oil_price_api_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/data/services/oil_price_api_service.dart fuel_price_app/test/data/services/oil_price_api_service_test.dart
git commit -m "feat: add OilPriceAPI service for European Rotterdam prices"
```

---

### Task 3: FuelParams — add multi-source config fields

**Files:**
- Modify: `lib/models/fuel_params.dart`
- Modify: `test/models/fuel_params_test.dart`

- [ ] **Step 1: Write failing tests for new FuelParams fields**

Add to the end of `test/models/fuel_params_test.dart`, inside `main()`:

```dart
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
      expect(params.oilApiSymbols['eurodizel'], 'MGO_05S_NLRTM_USD');
      expect(params.eiaCifMedFactors, isNotEmpty);
      expect(params.oilApiCifMedFactors, isNotEmpty);
      expect(params.sourceWeights, isNotEmpty);
      expect(params.sourceWeights['eurodizel']!['oilapi'], 0.5);
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
      expect(p.oilApiSymbols['eurodizel'], 'MGO_05S_NLRTM_USD');
      expect(p.sourceWeights['eurodizel']!['oilapi'], 0.5);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/models/fuel_params_test.dart`
Expected: FAIL — `eiaApiKey` not found on FuelParams

- [ ] **Step 3: Add new fields to FuelParams**

In `lib/models/fuel_params.dart`, add these fields to the `FuelParams` class, update `fromJson`, and update `defaultParams`:

```dart
class FuelParams {
  // ... existing fields ...

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
```

Add these to the constructor with defaults:

```dart
  this.eiaApiKey = 'REPLACE_WITH_REAL_KEY',
  this.oilPriceApiKey = 'REPLACE_WITH_REAL_KEY',
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
    'es95': 390.0,
    'es100': 390.0,
    'eurodizel': 320.0,
    'unp_10kg': 280.0,
  },
  this.oilApiCifMedFactors = const {
    'eurodizel': 1.05,
  },
  this.sourceWeights = const {
    'es95': {'yahoo': 0.5, 'eia': 0.5},
    'es100': {'yahoo': 0.5, 'eia': 0.5},
    'eurodizel': {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5},
    'unp_10kg': {'yahoo': 0.5, 'eia': 0.5},
  },
```

Add parsing in `fromJson`:

```dart
  eiaApiKey: (json['eia_api_key'] as String?) ?? 'REPLACE_WITH_REAL_KEY',
  oilPriceApiKey: (json['oil_price_api_key'] as String?) ?? 'REPLACE_WITH_REAL_KEY',
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
      : const {'eurodizel': 'MGO_05S_NLRTM_USD'},
  eiaCifMedFactors: json.containsKey('eia_cif_med_factors')
      ? (json['eia_cif_med_factors'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()))
      : const {'es95': 390.0, 'es100': 390.0, 'eurodizel': 320.0, 'unp_10kg': 280.0},
  oilApiCifMedFactors: json.containsKey('oil_api_cif_med_factors')
      ? (json['oil_api_cif_med_factors'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()))
      : const {'eurodizel': 1.05},
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
          'es95': {'yahoo': 0.5, 'eia': 0.5},
          'es100': {'yahoo': 0.5, 'eia': 0.5},
          'eurodizel': {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5},
          'unp_10kg': {'yahoo': 0.5, 'eia': 0.5},
        },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/models/fuel_params_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/models/fuel_params.dart fuel_price_app/test/models/fuel_params_test.dart
git commit -m "feat: add EIA/OilPriceAPI config fields to FuelParams"
```

---

### Task 4: Price Blender — weighted averaging logic

**Files:**
- Create: `lib/domain/price_blender.dart`
- Create: `test/domain/price_blender_test.dart`

- [ ] **Step 1: Write failing tests for price blending**

```dart
// test/domain/price_blender_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/price_blender.dart';

void main() {
  group('PriceBlender', () {
    test('blends three sources with configured weights', () {
      final weights = {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5};
      final prices = {'yahoo': 1.83, 'eia': 1.80, 'oilapi': 1.85};
      final result = PriceBlender.blend(prices, weights);
      // (1.83*0.3 + 1.80*0.2 + 1.85*0.5) = 0.549 + 0.36 + 0.925 = 1.834
      expect(result, closeTo(1.834, 0.001));
    });

    test('normalizes weights when one source is missing', () {
      final weights = {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5};
      final prices = {'yahoo': 1.83, 'eia': 1.80}; // oilapi missing
      final result = PriceBlender.blend(prices, weights);
      // Remaining: yahoo=0.3, eia=0.2, sum=0.5
      // Normalized: yahoo=0.6, eia=0.4
      // 1.83*0.6 + 1.80*0.4 = 1.098 + 0.72 = 1.818
      expect(result, closeTo(1.818, 0.001));
    });

    test('returns single source price when only one available', () {
      final weights = {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5};
      final prices = {'oilapi': 1.85};
      final result = PriceBlender.blend(prices, weights);
      expect(result, 1.85);
    });

    test('returns null when no sources available', () {
      final weights = {'yahoo': 0.5, 'eia': 0.5};
      final prices = <String, double>{};
      final result = PriceBlender.blend(prices, weights);
      expect(result, isNull);
    });

    test('handles missing weight config gracefully (equal weights)', () {
      final weights = <String, double>{}; // no weights configured
      final prices = {'yahoo': 1.80, 'eia': 1.82};
      final result = PriceBlender.blend(prices, weights);
      // Equal weights: (1.80 + 1.82) / 2 = 1.81
      expect(result, closeTo(1.81, 0.001));
    });

    test('ignores sources with zero weight', () {
      final weights = {'yahoo': 0.0, 'eia': 1.0};
      final prices = {'yahoo': 999.0, 'eia': 1.80};
      final result = PriceBlender.blend(prices, weights);
      expect(result, 1.80);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/domain/price_blender_test.dart`
Expected: FAIL — `price_blender.dart` does not exist

- [ ] **Step 3: Implement PriceBlender**

```dart
// lib/domain/price_blender.dart

/// Blends prices from multiple sources using configurable weights.
class PriceBlender {
  /// Calculate weighted average of [prices] using [weights].
  ///
  /// Only sources present in both maps are used.
  /// Weights are normalized to sum to 1.0 among available sources.
  /// Returns null if no sources have data.
  static double? blend(
    Map<String, double> prices,
    Map<String, double> weights,
  ) {
    if (prices.isEmpty) return null;

    // Filter to sources that have both a price and a non-zero weight
    final available = <String, double>{};
    for (final source in prices.keys) {
      final w = weights[source];
      if (w != null && w > 0) {
        available[source] = w;
      }
    }

    // If no weights configured for available sources, use equal weights
    if (available.isEmpty) {
      final equalWeight = 1.0 / prices.length;
      double sum = 0;
      for (final price in prices.values) {
        sum += price * equalWeight;
      }
      return sum;
    }

    // Normalize weights to sum to 1.0
    final totalWeight = available.values.fold(0.0, (a, b) => a + b);
    if (totalWeight == 0) return null;

    double result = 0;
    for (final entry in available.entries) {
      final price = prices[entry.key];
      if (price != null) {
        result += price * (entry.value / totalWeight);
      }
    }

    return result;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/domain/price_blender_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/domain/price_blender.dart fuel_price_app/test/domain/price_blender_test.dart
git commit -m "feat: add PriceBlender for weighted multi-source averaging"
```

---

### Task 5: Update DataSyncOrchestrator for 5 sources

**Files:**
- Modify: `lib/data/services/data_sync_orchestrator.dart`
- Modify: `test/data/services/data_sync_orchestrator_test.dart`

- [ ] **Step 1: Write failing test for new sources**

Add to the end of `test/data/services/data_sync_orchestrator_test.dart`, inside `main()`:

```dart
    test('EIA and OilAPI sources run in parallel with existing sources', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0],
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        fetchEiaSpotPrices: () async => [2.45],
        fetchOilApiPrices: () async => [720.0],
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.isFullSuccess, isTrue);
      expect(result.eiaSpotOk, isTrue);
      expect(result.oilApiOk, isTrue);
    });

    test('EIA failure does not affect other sources', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0],
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        fetchEiaSpotPrices: () async => throw Exception('EIA down'),
        fetchOilApiPrices: () async => [720.0],
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.eiaSpotOk, isFalse);
      expect(result.oilApiOk, isTrue);
      expect(result.failedSources, contains('eiaSpot'));
    });

    test('orchestrator works without optional source callbacks', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0],
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.eiaSpotOk, isTrue); // null callback = auto-success
      expect(result.oilApiOk, isTrue);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/data/services/data_sync_orchestrator_test.dart`
Expected: FAIL — `fetchEiaSpotPrices` not a named parameter

- [ ] **Step 3: Update DataSyncOrchestrator**

Replace `lib/data/services/data_sync_orchestrator.dart` with:

```dart
/// Result of a sync operation across all data sources.
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

  bool get isFullSuccess => oilPricesOk && exchangeRatesOk && configOk && eiaSpotOk && oilApiOk;
  bool get isFullFailure => !oilPricesOk && !exchangeRatesOk && !configOk && !eiaSpotOk && !oilApiOk;

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
    // First attempt — all in parallel
    final results = await Future.wait([
      _fetchWithTimeout(fetchOilPrices),
      _fetchWithTimeout(fetchExchangeRates),
      _fetchWithTimeout(fetchConfig),
      fetchEiaSpotPrices != null ? _fetchWithTimeout(fetchEiaSpotPrices!) : Future.value(<double>[]),
      fetchOilApiPrices != null ? _fetchWithTimeout(fetchOilApiPrices!) : Future.value(<double>[]),
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
      eiaSpotPrices == null && fetchEiaSpotPrices != null
          ? _fetchWithTimeout(fetchEiaSpotPrices!)
          : Future.value(eiaSpotPrices),
      oilApiPrices == null && fetchOilApiPrices != null
          ? _fetchWithTimeout(fetchOilApiPrices!)
          : Future.value(oilApiPrices),
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test test/data/services/data_sync_orchestrator_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/data/services/data_sync_orchestrator.dart fuel_price_app/test/data/services/data_sync_orchestrator_test.dart
git commit -m "feat: extend DataSyncOrchestrator with EIA and OilPriceAPI sources"
```

---

### Task 6: Update remote config JSON

**Files:**
- Modify: `config/fuel_params.json`

- [ ] **Step 1: Add new fields to fuel_params.json**

Add these fields to the existing JSON (after `"cif_med_factors"`):

```json
  "eia_api_key": "REPLACE_WITH_REAL_KEY",
  "oil_price_api_key": "REPLACE_WITH_REAL_KEY",
  "eia_symbols": {
    "es95": "EER_EPMRU_PF4_Y35NY_DPG",
    "es100": "EER_EPMRU_PF4_Y35NY_DPG",
    "eurodizel": "EER_EPD2DXL0_PF4_Y35NY_DPG",
    "unp_10kg": "EER_EPLLPA_PF4_Y44MB_DPG"
  },
  "oil_api_symbols": {
    "eurodizel": "MGO_05S_NLRTM_USD"
  },
  "eia_cif_med_factors": {
    "es95": 390.0,
    "es100": 390.0,
    "eurodizel": 320.0,
    "unp_10kg": 280.0
  },
  "oil_api_cif_med_factors": {
    "eurodizel": 1.05
  },
  "source_weights": {
    "es95": {"yahoo": 0.5, "eia": 0.5},
    "es100": {"yahoo": 0.5, "eia": 0.5},
    "eurodizel": {"yahoo": 0.3, "eia": 0.2, "oilapi": 0.5},
    "unp_10kg": {"yahoo": 0.5, "eia": 0.5}
  }
```

- [ ] **Step 2: Commit**

```bash
cd /d/Projekti/test
git add config/fuel_params.json
git commit -m "feat: add EIA/OilPriceAPI config to fuel_params.json"
```

---

### Task 7: Wire up new services in app.dart

**Files:**
- Modify: `lib/app.dart`

- [ ] **Step 1: Add imports and service fields**

Add imports at the top of `app.dart`:
```dart
import 'package:fuel_price_app/data/services/eia_service.dart';
import 'package:fuel_price_app/data/services/oil_price_api_service.dart';
import 'package:fuel_price_app/domain/price_blender.dart';
import 'package:shared_preferences/shared_preferences.dart';
```

Add fields in `_FuelPriceAppState`:
```dart
late final EiaService _eiaService;
late final OilPriceApiService _oilPriceApiService;
```

- [ ] **Step 2: Initialize services in initState**

After `_hnbService = HnbService(dio: _dio);` add:
```dart
_eiaService = EiaService(dio: _dio, apiKey: _activeParams.eiaApiKey);
_oilPriceApiService = OilPriceApiService(dio: _dio, apiKey: _activeParams.oilPriceApiKey);
```

- [ ] **Step 3: Add EIA fetch to orchestrator callback**

In the `DataSyncOrchestrator` constructor, add `fetchEiaSpotPrices`:

```dart
fetchEiaSpotPrices: () async {
  final seriesIds = _activeParams.eiaSymbols.values.toSet();
  for (final seriesId in seriesIds) {
    final prices = await _eiaService.fetchSpotPrices(seriesId, days: 60);
    for (final p in prices) {
      await _priceRepo.saveOilPrice(
        OilPrice(date: p.date, cifMed: p.value, source: seriesId),
      );
    }
    _log('EIA: fetched ${prices.length} prices for $seriesId');
  }
  return [1.0]; // success indicator
},
```

- [ ] **Step 4: Add OilPriceAPI fetch to orchestrator callback**

Add `fetchOilApiPrices` with rate-limit awareness:

```dart
fetchOilApiPrices: () async {
  final prefs = await SharedPreferences.getInstance();
  final lastFetch = prefs.getString('oilapi_last_fetch');
  final now = DateTime.now();

  // Only fetch every 2 days to conserve 50 req/month limit
  if (lastFetch != null) {
    final last = DateTime.tryParse(lastFetch);
    if (last != null && now.difference(last).inHours < 48) {
      _log('OilPriceAPI: skipping, last fetch ${now.difference(last).inHours}h ago');
      return [1.0]; // success — using cached data
    }
  }

  final symbols = _activeParams.oilApiSymbols.values.toSet();
  for (final code in symbols) {
    final price = await _oilPriceApiService.fetchLatestPrice(code);
    if (price != null) {
      await _priceRepo.saveOilPrice(
        OilPrice(date: price.date, cifMed: price.value, source: code),
      );
      _log('OilPriceAPI: $code = ${price.value}');
    }
  }

  await prefs.setString('oilapi_last_fetch', now.toIso8601String());
  return [1.0];
},
```

- [ ] **Step 5: Update _recalculatePredictions for multi-source blending**

Replace the existing prediction loop body in `_recalculatePredictions` (the `for (final ft in FuelType.values)` loop) with multi-source logic:

```dart
for (final ft in FuelType.values) {
  try {
    final weights = _activeParams.sourceWeights[ft.paramKey] ?? {'yahoo': 1.0};

    // Collect predictions from each source
    final sourcePrices = <String, double>{};

    // Yahoo
    final yahooSymbol = _activeParams.yahooSymbols[ft.paramKey] ?? 'BZ=F';
    final yahooFactor = _activeParams.cifMedFactors[ft.paramKey] ?? 402.4;
    final yahooPrices = await _priceRepo.getOilPrices(yahooSymbol, days: 60);

    // EIA
    final eiaSymbol = _activeParams.eiaSymbols[ft.paramKey];
    final eiaFactor = _activeParams.eiaCifMedFactors[ft.paramKey];
    final eiaPrices = eiaSymbol != null
        ? await _priceRepo.getOilPrices(eiaSymbol, days: 60)
        : <OilPrice>[];

    // OilPriceAPI
    final oilApiSymbol = _activeParams.oilApiSymbols[ft.paramKey];
    final oilApiFactor = _activeParams.oilApiCifMedFactors[ft.paramKey];
    final oilApiPrices = oilApiSymbol != null
        ? await _priceRepo.getOilPrices(oilApiSymbol, days: 60)
        : <OilPrice>[];

    // --- Helper to compute price from a source ---
    double? computePrice(List<OilPrice> prices, double factor, bool isCurrent) {
      if (prices.isEmpty) return null;
      final window = isCurrent
          ? prices.where((p) => p.date.isBefore(currentPeriodStart)).toList()
          : prices;
      if (window.length < (isCurrent ? 10 : 1)) return null;
      final count = window.length < 14 ? window.length : 14;
      final slice = window.reversed.take(count).toList().reversed.toList();
      final cifMed = slice.map((p) => p.cifMed * factor).toList();
      final ratesList = slice.map((p) => _findRate(rates, p.date)).toList();
      return engine.predictPrice(ft, cifMed, ratesList);
    }

    // --- Current period price ---
    final currentSourcePrices = <String, double>{};
    final yc = computePrice(yahooPrices, yahooFactor, true);
    if (yc != null) currentSourcePrices['yahoo'] = yc;
    final ec = eiaFactor != null ? computePrice(eiaPrices, eiaFactor, true) : null;
    if (ec != null) currentSourcePrices['eia'] = ec;
    final oc = oilApiFactor != null ? computePrice(oilApiPrices, oilApiFactor, true) : null;
    if (oc != null) currentSourcePrices['oilapi'] = oc;

    final currentPrice = PriceBlender.blend(currentSourcePrices, weights);
    if (currentPrice != null) {
      final rounded = FormulaEngine.roundPrice(currentPrice);
      _log('${ft.name}: current=$rounded (sources: $currentSourcePrices)');
      await _priceRepo.saveFuelPrice(
        FuelPrice(fuelType: ft, date: currentPeriodStart, price: rounded, isPrediction: false),
      );
    }

    // --- Next period prediction ---
    final nextSourcePrices = <String, double>{};
    final yn = computePrice(yahooPrices, yahooFactor, false);
    if (yn != null) nextSourcePrices['yahoo'] = yn;
    final en = eiaFactor != null ? computePrice(eiaPrices, eiaFactor, false) : null;
    if (en != null) nextSourcePrices['eia'] = en;
    final on_ = oilApiFactor != null ? computePrice(oilApiPrices, oilApiFactor, false) : null;
    if (on_ != null) nextSourcePrices['oilapi'] = on_;

    final predictedPrice = PriceBlender.blend(nextSourcePrices, weights);
    if (predictedPrice != null) {
      final rounded = FormulaEngine.roundPrice(predictedPrice);
      _log('${ft.name}: predicted=$rounded (sources: $nextSourcePrices)');
      await _priceRepo.saveFuelPrice(
        FuelPrice(fuelType: ft, date: nextChange, price: rounded, isPrediction: true),
      );
    }
  } catch (e) {
    _log('prediction FAILED for ${ft.name}: $e');
  }
}
```

- [ ] **Step 6: Update service API keys after remote config sync**

In `_initApp`, after `_activeParams = newParams;` add:

```dart
_eiaService = EiaService(dio: _dio, apiKey: _activeParams.eiaApiKey);
_oilPriceApiService = OilPriceApiService(dio: _dio, apiKey: _activeParams.oilPriceApiKey);
```

- [ ] **Step 7: Run all tests to check nothing is broken**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test`
Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/app.dart
git commit -m "feat: wire up EIA + OilPriceAPI with weighted price blending"
```

---

### Task 8: Update background sync

**Files:**
- Modify: `lib/scheduling/background_sync.dart`

- [ ] **Step 1: Add EIA and OilPriceAPI imports and fetching**

Add imports:
```dart
import 'package:fuel_price_app/data/services/eia_service.dart';
import 'package:fuel_price_app/data/services/oil_price_api_service.dart';
import 'package:fuel_price_app/domain/price_blender.dart';
```

After the Yahoo Finance fetch block (step 3), add EIA fetch:

```dart
      // 3b. Fetch EIA spot prices
      final eia = EiaService(apiKey: params.eiaApiKey);
      final eiaSeriesIds = params.eiaSymbols.values.toSet();
      for (final seriesId in eiaSeriesIds) {
        try {
          final eiaPrices = await eia.fetchSpotPrices(seriesId, days: 60);
          for (final p in eiaPrices) {
            await priceRepo.saveOilPrice(OilPrice(
              date: p.date, cifMed: p.value, source: seriesId,
            ));
          }
        } catch (_) {
          // Non-critical — continue with other sources
        }
      }

      // 3c. Fetch OilPriceAPI prices (rate-limited: every 2 days)
      final prefs = await SharedPreferences.getInstance();
      final lastOilApiFetch = prefs.getString('oilapi_last_fetch');
      final shouldFetchOilApi = lastOilApiFetch == null ||
          today.difference(DateTime.tryParse(lastOilApiFetch) ?? today).inHours >= 48;

      if (shouldFetchOilApi) {
        final oilApi = OilPriceApiService(apiKey: params.oilPriceApiKey);
        for (final code in params.oilApiSymbols.values.toSet()) {
          try {
            final price = await oilApi.fetchLatestPrice(code);
            if (price != null) {
              await priceRepo.saveOilPrice(OilPrice(
                date: price.date, cifMed: price.value, source: code,
              ));
            }
          } catch (_) {}
        }
        await prefs.setString('oilapi_last_fetch', today.toIso8601String());
      }
```

- [ ] **Step 2: Update prediction calculation to use PriceBlender**

Replace the existing prediction loop (step 5) with multi-source blending logic matching the pattern from Task 7 Step 5. Use `PriceBlender.blend()` with `params.sourceWeights`.

The core pattern: for each `fuelType`, compute predictions from yahoo, eia, and oilapi sources independently, then blend using `PriceBlender.blend(sourcePrices, params.sourceWeights[fuelType.paramKey])`.

- [ ] **Step 3: Run all tests**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/scheduling/background_sync.dart
git commit -m "feat: add EIA + OilPriceAPI to background sync with blending"
```

---

### Task 9: Fix dark theme persistence

**Files:**
- Modify: `lib/blocs/settings_cubit.dart`

- [ ] **Step 1: Add SharedPreferences import and persist theme mode**

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

Update the `load()` method — after existing loads, add:

```dart
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode');
    final themeMode = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    emit(state.copyWith(
      themeMode: themeMode,
      fuelVisibility: visibility,
      // ... rest stays the same
    ));
```

Update `setThemeMode` to persist:

```dart
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('theme_mode', value);
    emit(state.copyWith(themeMode: mode));
  }
```

- [ ] **Step 2: Run all tests**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/lib/blocs/settings_cubit.dart
git commit -m "fix: persist dark theme selection across app restarts"
```

---

### Task 10: Bump version and update settings screen

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/ui/screens/settings_screen.dart`

- [ ] **Step 1: Bump version in pubspec.yaml**

Change line 19 from:
```yaml
version: 2.0.0+2
```
to:
```yaml
version: 3.0.0+3
```

- [ ] **Step 2: Add package_info_plus dependency**

Add to `dependencies:` section of `pubspec.yaml`:
```yaml
  package_info_plus: ^8.0.0
```

Run: `cd /d/Projekti/test/fuel_price_app && flutter pub get`

- [ ] **Step 3: Update version display in settings screen**

In `lib/ui/screens/settings_screen.dart`, replace the hardcoded version ListTile:

```dart
              const ListTile(
                leading: Icon(Icons.tag),
                title: Text('Verzija'),
                subtitle: Text('2.0.0'),
              ),
```

with:

```dart
              FutureBuilder(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? '...';
                  return ListTile(
                    leading: const Icon(Icons.tag),
                    title: const Text('Verzija'),
                    subtitle: Text(version),
                  );
                },
              ),
```

Add import at top of file:
```dart
import 'package:package_info_plus/package_info_plus.dart';
```

- [ ] **Step 4: Update formula dialog text**

In `_showFormulaDialog`, replace the last two lines of the formula text:
```dart
            'Izvor cijena: Yahoo Finance (BZ=F)\n'
            'Izvor tečaja: HNB API',
```
with:
```dart
            'Izvori cijena:\n'
            '• Yahoo Finance (RB=F, HO=F, BZ=F)\n'
            '• EIA (američki spot cijene)\n'
            '• OilPriceAPI (Rotterdam/europske cijene)\n\n'
            'Izvor tečaja: ECB / HNB API',
```

- [ ] **Step 5: Run all tests**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
cd /d/Projekti/test
git add fuel_price_app/pubspec.yaml fuel_price_app/lib/ui/screens/settings_screen.dart
git commit -m "fix: bump version to 3.0.0, show dynamic version in settings"
```

---

### Task 11: Final integration test and run all tests

**Files:** None new

- [ ] **Step 1: Run full test suite**

Run: `cd /d/Projekti/test/fuel_price_app && flutter test`
Expected: ALL PASS (161+ tests)

- [ ] **Step 2: Fix any failures**

If tests fail, diagnose and fix. Common issues:
- Existing orchestrator tests may need updating for new `SyncResult` fields
- `DataSyncState` tests may need updating if they check `SyncResult` shape

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
cd /d/Projekti/test
git add -A
git commit -m "test: fix test suite for multi-source integration"
```
