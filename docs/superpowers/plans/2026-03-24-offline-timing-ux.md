# Offline UX, Market Timing & Stress Tests — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add offline-first UX with empty state, fix market timing to 18:00 CET, add trend indicator, configurable price cycle, and comprehensive stress tests.

**Architecture:** Extends existing app scaffold. New `PriceCycleService` for date calculations, updated `DataSyncCubit` with partial-success states, new empty/loading UI states, trend indicator on fuel list tiles.

**Tech Stack:** Flutter (Dart), flutter_bloc, dio, sqflite, mocktail for tests

**Spec:** `docs/superpowers/specs/2026-03-24-offline-timing-ux-design.md`
**Base plan:** `docs/superpowers/plans/2026-03-23-fuel-price-app.md`

---

## File Structure

```
fuel_price_app/
├── lib/
│   ├── models/
│   │   └── fuel_params.dart               — MODIFY: add referenceDate, cycleDays fields
│   ├── domain/
│   │   ├── price_cycle_service.dart       — CREATE: nextPriceChangeDate, trendIndicator, cycle validation
│   │   └── formula_engine.dart            — (exists in base plan, no changes here)
│   ├── blocs/
│   │   ├── data_sync_cubit.dart           — CREATE: SyncIdle/InProgress/Success/Partial/Failure states, parallel fetch + retry
│   │   └── data_sync_state.dart           — CREATE: Equatable state classes
│   ├── data/
│   │   └── services/
│   │       └── data_sync_orchestrator.dart — CREATE: parallel fetch, per-source timeout, retry logic
│   ├── scheduling/
│   │   └── schedule_helper.dart           — CREATE: 18:00 CET/CEST calculation with DST handling
│   └── ui/
│       ├── widgets/
│       │   ├── empty_state.dart           — CREATE: "Nema dostupnih podataka" screen
│       │   ├── sync_spinner.dart          — CREATE: full-screen spinner overlay
│       │   └── fuel_list_tile.dart        — MODIFY: add trend indicator arrow with colors
│       └── screens/
│           └── fuel_list_screen.dart      — MODIFY: integrate empty state, spinner, sync states, pull-to-refresh
├── test/
│   ├── models/
│   │   └── fuel_params_test.dart          — CREATE: price cycle field tests
│   ├── domain/
│   │   └── price_cycle_service_test.dart  — CREATE: cycle calculation + trend indicator tests
│   ├── blocs/
│   │   ├── data_sync_state_test.dart      — CREATE: state equality tests
│   │   └── data_sync_cubit_test.dart      — CREATE: timeout, retry, partial success tests
│   ├── ui/
│   │   ├── widgets/
│   │   │   ├── empty_state_test.dart      — CREATE: empty state widget tests
│   │   │   └── fuel_list_tile_test.dart   — CREATE: trend arrow rendering tests
│   │   └── screens/
│   │       └── fuel_list_screen_sync_test.dart — CREATE: sync state integration tests
│   ├── scheduling/
│   │   └── workmanager_schedule_test.dart  — CREATE: 18:00 CET/DST schedule tests
│   └── stress/
│       ├── timeout_stress_test.dart        — CREATE: timeout boundary + repeated failure tests
│       ├── offline_stress_test.dart        — CREATE: empty state, stale data, retry tests
│       ├── data_integrity_test.dart        — CREATE: partial failure, corrupt data, duplicate tests
│       └── concurrent_ops_test.dart        — CREATE: double fetch, rapid retry tests
└── config/
    └── fuel_params.json                    — MODIFY: add price_cycle section
```

---

### Task 1: Update FuelParams Model with Price Cycle Fields

**Files:**
- Modify: `fuel_price_app/lib/models/fuel_params.dart`
- Test: `fuel_price_app/test/models/fuel_params_test.dart` (create)

- [ ] **Step 1: Write failing test for price cycle fields**

Create `test/models/fuel_params_test.dart`:
```dart
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
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/models/fuel_params_test.dart`
Expected: FAIL — `referenceDate` and `cycleDays` don't exist on FuelParams

- [ ] **Step 3: Update FuelParams model**

Modify `lib/models/fuel_params.dart`. Add fields to `FuelParams`:
```dart
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
    int rawCycleDays = (priceCycle?['cycle_days'] as int?) ?? 14;
    // Constraint: must be multiple of 7, otherwise fall back to 14
    if (rawCycleDays <= 0 || rawCycleDays % 7 != 0) {
      rawCycleDays = 14;
    }
    return FuelParams(
      version: json['version'] as String,
      priceRegulation: RegulationInfo.fromJson(json['price_regulation'] as Map<String, dynamic>),
      exciseRegulation: RegulationInfo.fromJson(json['excise_regulation'] as Map<String, dynamic>),
      premiums: (json['premiums'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
      exciseDuties: (json['excise_duties'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
      density: (json['density'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
      vatRate: (json['vat_rate'] as num).toDouble(),
      referenceDate: (priceCycle?['reference_date'] as String?) ?? '2026-03-24',
      cycleDays: rawCycleDays,
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/models/fuel_params_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/fuel_params.dart test/models/fuel_params_test.dart
git commit -m "feat: add price cycle fields to FuelParams model"
```

---

### Task 2: Create PriceCycleService (nextPriceChangeDate + trendIndicator)

**Files:**
- Create: `fuel_price_app/lib/domain/price_cycle_service.dart`
- Create: `fuel_price_app/test/domain/price_cycle_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/domain/price_cycle_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';

void main() {
  group('nextPriceChangeDate', () {
    final ref = DateTime(2026, 3, 24); // Tuesday

    test('on reference date itself, returns next cycle', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 24), ref, 14);
      expect(result, DateTime(2026, 4, 7));
    });

    test('day after reference, returns next cycle', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 25), ref, 14);
      expect(result, DateTime(2026, 4, 7));
    });

    test('day before next cycle, returns that cycle', () {
      final result = nextPriceChangeDate(DateTime(2026, 4, 6), ref, 14);
      expect(result, DateTime(2026, 4, 7));
    });

    test('on second cycle date, returns third', () {
      final result = nextPriceChangeDate(DateTime(2026, 4, 7), ref, 14);
      expect(result, DateTime(2026, 4, 21));
    });

    test('reference date in future, returns reference date', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 20), ref, 14);
      expect(result, DateTime(2026, 3, 24));
    });

    test('cycle across year boundary', () {
      final refDec = DateTime(2026, 12, 29);
      final result = nextPriceChangeDate(DateTime(2027, 1, 5), refDec, 14);
      expect(result, DateTime(2027, 1, 12));
    });

    test('weekly cycle (7 days)', () {
      final result = nextPriceChangeDate(DateTime(2026, 3, 25), ref, 7);
      expect(result, DateTime(2026, 3, 31));
    });
  });

  group('trendIndicator', () {
    test('price increase returns ↑', () {
      expect(trendIndicator(1.42, 1.38), '↑');
    });

    test('price decrease returns ↓', () {
      expect(trendIndicator(1.35, 1.38), '↓');
    });

    test('no change within tolerance returns →', () {
      expect(trendIndicator(1.380, 1.382), '→');
    });

    test('exactly at tolerance boundary returns →', () {
      expect(trendIndicator(1.385, 1.380), '→');
    });

    test('just above tolerance returns ↑', () {
      expect(trendIndicator(1.3861, 1.380), '↑');
    });

    test('large swing returns ↑', () {
      expect(trendIndicator(2.00, 1.00), '↑');
    });

    test('null current returns null', () {
      expect(trendIndicator(1.42, null), isNull);
    });
  });

  group('validateCycleDays', () {
    test('14 is valid', () {
      expect(validateCycleDays(14), 14);
    });

    test('7 is valid', () {
      expect(validateCycleDays(7), 7);
    });

    test('10 is invalid, returns 14', () {
      expect(validateCycleDays(10), 14);
    });

    test('0 is invalid, returns 14', () {
      expect(validateCycleDays(0), 14);
    });

    test('-7 is invalid, returns 14', () {
      expect(validateCycleDays(-7), 14);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/domain/price_cycle_service_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Implement PriceCycleService**

Create `lib/domain/price_cycle_service.dart`:
```dart
/// Calculates the next price change date based on reference date and cycle length.
///
/// On a cycle date itself, returns the NEXT cycle (today's change already happened).
/// If [today] is before [referenceDate], returns [referenceDate].
DateTime nextPriceChangeDate(DateTime today, DateTime referenceDate, int cycleDays) {
  if (today.isBefore(referenceDate)) return referenceDate;

  final daysDiff = today.difference(referenceDate).inDays;
  final cyclesPassed = daysDiff ~/ cycleDays;

  return referenceDate.add(Duration(days: (cyclesPassed + 1) * cycleDays));
}

/// Returns a trend arrow comparing predicted vs current price.
///
/// Returns `null` if [current] is null (no official price yet).
/// Uses ±0.005 € tolerance to account for rounding.
String? trendIndicator(double predicted, double? current) {
  if (current == null) return null;
  final diff = predicted - current;
  if (diff > 0.005) return '↑';
  if (diff < -0.005) return '↓';
  return '→';
}

/// Validates cycle_days: must be positive and multiple of 7. Returns 14 if invalid.
int validateCycleDays(int cycleDays) {
  if (cycleDays <= 0 || cycleDays % 7 != 0) return 14;
  return cycleDays;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/domain/price_cycle_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/domain/price_cycle_service.dart test/domain/price_cycle_service_test.dart
git commit -m "feat: add PriceCycleService with date calculation and trend indicator"
```

---

### Task 3: Create DataSyncState Classes

**Files:**
- Create: `fuel_price_app/lib/blocs/data_sync_state.dart`
- Create: `fuel_price_app/test/blocs/data_sync_state_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/blocs/data_sync_state_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';

void main() {
  test('SyncIdle is initial state', () {
    const state = SyncIdle();
    expect(state, isA<DataSyncState>());
  });

  test('SyncInProgress is distinct from SyncIdle', () {
    expect(const SyncIdle() == const SyncInProgress(), isFalse);
  });

  test('SyncSuccess is distinct', () {
    expect(const SyncSuccess(), isA<DataSyncState>());
  });

  test('SyncPartial contains list of failed source names', () {
    const state = SyncPartial(failedSources: ['yahoo', 'hnb']);
    expect(state.failedSources, ['yahoo', 'hnb']);
  });

  test('SyncFailure contains message', () {
    const state = SyncFailure(message: 'No internet');
    expect(state.message, 'No internet');
  });

  test('two SyncPartial with same failures are equal', () {
    const a = SyncPartial(failedSources: ['yahoo']);
    const b = SyncPartial(failedSources: ['yahoo']);
    expect(a, equals(b));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/blocs/data_sync_state_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Implement state classes**

Create `lib/blocs/data_sync_state.dart`:
```dart
import 'package:equatable/equatable.dart';

sealed class DataSyncState extends Equatable {
  const DataSyncState();
}

class SyncIdle extends DataSyncState {
  const SyncIdle();
  @override
  List<Object?> get props => [];
}

class SyncInProgress extends DataSyncState {
  const SyncInProgress();
  @override
  List<Object?> get props => [];
}

class SyncSuccess extends DataSyncState {
  const SyncSuccess();
  @override
  List<Object?> get props => [];
}

class SyncPartial extends DataSyncState {
  final List<String> failedSources;
  const SyncPartial({required this.failedSources});
  @override
  List<Object?> get props => [failedSources];
}

class SyncFailure extends DataSyncState {
  final String message;
  const SyncFailure({required this.message});
  @override
  List<Object?> get props => [message];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/blocs/data_sync_state_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/blocs/data_sync_state.dart test/blocs/data_sync_state_test.dart
git commit -m "feat: add DataSyncState sealed classes with Equatable"
```

---

### Task 4: Create DataSyncOrchestrator (Parallel Fetch + Retry)

**Files:**
- Create: `fuel_price_app/lib/data/services/data_sync_orchestrator.dart`
- Create: `fuel_price_app/test/data/services/data_sync_orchestrator_test.dart`

This is the core fetch logic — parallel requests, per-source timeout, retry on failure.

- [ ] **Step 1: Write failing tests**

Create `test/data/services/data_sync_orchestrator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('DataSyncOrchestrator', () {
    test('all sources succeed returns SyncResult with all success', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0, 2.0],
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.exchangeRatesOk, isTrue);
      expect(result.configOk, isTrue);
      expect(result.isFullSuccess, isTrue);
      expect(result.isFullFailure, isFalse);
    });

    test('one source fails, retries once, then partial', () async {
      int yahooAttempts = 0;
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async {
          yahooAttempts++;
          throw Exception('Network error');
        },
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(yahooAttempts, 2); // initial + 1 retry
      expect(result.oilPricesOk, isFalse);
      expect(result.exchangeRatesOk, isTrue);
      expect(result.configOk, isTrue);
      expect(result.isFullSuccess, isFalse);
      expect(result.isFullFailure, isFalse);
      expect(result.failedSources, ['oilPrices']);
    });

    test('all sources fail returns full failure', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('fail'),
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => throw Exception('fail'),
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.isFullFailure, isTrue);
    });

    test('source timeout triggers retry', () async {
      int attempts = 0;
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async {
          attempts++;
          if (attempts == 1) {
            await Future.delayed(const Duration(seconds: 5)); // exceeds timeout
          }
          return [1.0];
        },
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(attempts, 2);
      expect(result.oilPricesOk, isTrue);
      expect(result.isFullSuccess, isTrue);
    });

    test('retry also fails keeps source as failed', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('always fails'),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isFalse);
      expect(result.failedSources, ['oilPrices']);
    });

    test('successful data is available via result even on partial failure', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [1.0, 2.0],
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPrices, [1.0, 2.0]);
      expect(result.exchangeRates, isNull);
      expect(result.config, {'version': '1'});
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/data/services/data_sync_orchestrator_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Implement DataSyncOrchestrator**

Create `lib/data/services/data_sync_orchestrator.dart`:
```dart
/// Result of a sync operation across all three data sources.
class SyncResult {
  final List<double>? oilPrices;
  final List<double>? exchangeRates;
  final Map<String, dynamic>? config;
  final bool oilPricesOk;
  final bool exchangeRatesOk;
  final bool configOk;

  const SyncResult({
    this.oilPrices,
    this.exchangeRates,
    this.config,
    required this.oilPricesOk,
    required this.exchangeRatesOk,
    required this.configOk,
  });

  bool get isFullSuccess => oilPricesOk && exchangeRatesOk && configOk;
  bool get isFullFailure => !oilPricesOk && !exchangeRatesOk && !configOk;

  List<String> get failedSources => [
    if (!oilPricesOk) 'oilPrices',
    if (!exchangeRatesOk) 'exchangeRates',
    if (!configOk) 'config',
  ];
}

/// Orchestrates parallel data fetching with per-source timeout and single retry.
class DataSyncOrchestrator {
  final Future<List<double>> Function() fetchOilPrices;
  final Future<List<double>> Function() fetchExchangeRates;
  final Future<Map<String, dynamic>> Function() fetchConfig;
  final Duration timeout;

  DataSyncOrchestrator({
    required this.fetchOilPrices,
    required this.fetchExchangeRates,
    required this.fetchConfig,
    this.timeout = const Duration(seconds: 10),
  });

  Future<SyncResult> sync() async {
    // First attempt — all in parallel
    final results = await Future.wait([
      _fetchWithTimeout(fetchOilPrices),
      _fetchWithTimeout(fetchExchangeRates),
      _fetchWithTimeout(fetchConfig),
    ]);

    List<double>? oilPrices = results[0] as List<double>?;
    List<double>? exchangeRates = results[1] as List<double>?;
    Map<String, dynamic>? config = results[2] as Map<String, dynamic>?;

    // Retry failed sources once — in parallel
    final retries = await Future.wait([
      if (oilPrices == null) _fetchWithTimeout(fetchOilPrices) else Future.value(oilPrices),
      if (exchangeRates == null) _fetchWithTimeout(fetchExchangeRates) else Future.value(exchangeRates),
      if (config == null) _fetchWithTimeout(fetchConfig) else Future.value(config),
    ]);
    oilPrices ??= retries[0] as List<double>?;
    exchangeRates ??= retries[1] as List<double>?;
    config ??= retries[2] as Map<String, dynamic>?;

    return SyncResult(
      oilPrices: oilPrices,
      exchangeRates: exchangeRates,
      config: config,
      oilPricesOk: oilPrices != null,
      exchangeRatesOk: exchangeRates != null,
      configOk: config != null,
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

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/data/services/data_sync_orchestrator_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/services/data_sync_orchestrator.dart test/data/services/data_sync_orchestrator_test.dart
git commit -m "feat: add DataSyncOrchestrator with parallel fetch, timeout, and retry"
```

---

### Task 5: Create DataSyncCubit

**Files:**
- Create: `fuel_price_app/lib/blocs/data_sync_cubit.dart`
- Create: `fuel_price_app/test/blocs/data_sync_cubit_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/blocs/data_sync_cubit_test.dart`:
```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('DataSyncCubit', () {
    blocTest<DataSyncCubit, DataSyncState>(
      'emits [SyncInProgress, SyncSuccess] on full success',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [1.0],
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'emits [SyncInProgress, SyncPartial] on partial failure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        const SyncPartial(failedSources: ['oilPrices']),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'emits [SyncInProgress, SyncFailure] on full failure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => throw Exception('fail'),
          fetchConfig: () async => throw Exception('fail'),
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        isA<SyncFailure>(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'ignores concurrent sync calls (no double fetch)',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async {
            await Future.delayed(const Duration(milliseconds: 500));
            return [1.0];
          },
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) {
        cubit.sync(); // first
        cubit.sync(); // should be ignored
        cubit.sync(); // should be ignored
      },
      wait: const Duration(seconds: 2),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/blocs/data_sync_cubit_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Implement DataSyncCubit**

Create `lib/blocs/data_sync_cubit.dart`:
```dart
import 'package:bloc/bloc.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

class DataSyncCubit extends Cubit<DataSyncState> {
  final DataSyncOrchestrator orchestrator;
  final Future<void> Function(SyncResult result) onSyncResult;
  bool _syncing = false;

  DataSyncCubit({
    required this.orchestrator,
    required this.onSyncResult,
  }) : super(const SyncIdle());

  Future<void> sync() async {
    if (_syncing) return; // prevent concurrent syncs
    _syncing = true;
    emit(const SyncInProgress());

    try {
      final result = await orchestrator.sync();
      await onSyncResult(result);

      if (result.isFullSuccess) {
        emit(const SyncSuccess());
      } else if (result.isFullFailure) {
        emit(const SyncFailure(message: 'Svi izvori podataka su nedostupni.'));
      } else {
        emit(SyncPartial(failedSources: result.failedSources));
      }
    } catch (e) {
      emit(SyncFailure(message: e.toString()));
    } finally {
      _syncing = false;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/blocs/data_sync_cubit_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/blocs/data_sync_cubit.dart test/blocs/data_sync_cubit_test.dart
git commit -m "feat: add DataSyncCubit with partial success and concurrent guard"
```

---

### Task 6: Create Empty State and Sync Spinner Widgets

**Files:**
- Create: `fuel_price_app/lib/ui/widgets/empty_state.dart`
- Create: `fuel_price_app/lib/ui/widgets/sync_spinner.dart`
- Create: `fuel_price_app/test/ui/widgets/empty_state_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/ui/widgets/empty_state_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/ui/widgets/empty_state.dart';

void main() {
  group('EmptyStateWidget', () {
    testWidgets('shows error message text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () {}),
          ),
        ),
      );
      expect(
        find.text('Nema dostupnih podataka. Provjerite internetsku vezu i pritisnite gumb za ažuriranje.'),
        findsOneWidget,
      );
    });

    testWidgets('shows retry button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () {}),
          ),
        ),
      );
      expect(find.text('Ažuriraj'), findsOneWidget);
    });

    testWidgets('tap retry button calls onRetry', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () => called = true),
          ),
        ),
      );
      await tester.tap(find.text('Ažuriraj'));
      expect(called, isTrue);
    });

    testWidgets('shows cloud-off icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () {}),
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/ui/widgets/empty_state_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Implement EmptyStateWidget**

Create `lib/ui/widgets/empty_state.dart`:
```dart
import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  final VoidCallback onRetry;

  const EmptyStateWidget({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nema dostupnih podataka. Provjerite internetsku vezu i pritisnite gumb za ažuriranje.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Ažuriraj'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement SyncSpinner**

Create `lib/ui/widgets/sync_spinner.dart`:
```dart
import 'package:flutter/material.dart';

class SyncSpinner extends StatelessWidget {
  const SyncSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Preuzimanje podataka...'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/ui/widgets/empty_state_test.dart`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/empty_state.dart lib/ui/widgets/sync_spinner.dart test/ui/widgets/empty_state_test.dart
git commit -m "feat: add EmptyStateWidget and SyncSpinner for offline UX"
```

---

### Task 7: Update fuel_params.json with price_cycle

**Files:**
- Modify: `fuel_price_app/config/fuel_params.json` (create if not exists)

- [ ] **Step 1: Create/update config file**

Create `config/fuel_params.json`:
```json
{
  "version": "2025-02-26",
  "price_cycle": {
    "reference_date": "2026-03-24",
    "cycle_days": 14
  },
  "price_regulation": {
    "name": "Uredba o utvrđivanju najviših maloprodajnih cijena naftnih derivata",
    "nn_reference": "NN 31/2025",
    "effective_date": "2025-02-26",
    "nn_url": "https://narodne-novine.nn.hr/clanci/sluzbeni/full/2025_02_31_326.html"
  },
  "excise_regulation": {
    "name": "Uredba o visini trošarine na energente i električnu energiju",
    "nn_reference": "NN 156/2022 (konsolidirana)",
    "effective_date": "2023-01-01",
    "note": "Vlada periodički mijenja visinu trošarine zasebnim uredbama"
  },
  "premiums": {
    "es95": 0.1545,
    "es100": 0.1545,
    "eurodizel": 0.1545,
    "unp_10kg": 0.8429
  },
  "excise_duties": {
    "es95": 0.4560,
    "es100": 0.4560,
    "eurodizel": 0.40613,
    "unp_10kg": 0.01327
  },
  "density": {
    "es95": 0.755,
    "es100": 0.755,
    "eurodizel": 0.845
  },
  "vat_rate": 0.25
}
```

- [ ] **Step 2: Commit**

```bash
git add config/fuel_params.json
git commit -m "feat: add price_cycle to remote config file"
```

---

### Task 8: Stress Tests — Timeout & Boundary

**Files:**
- Create: `fuel_price_app/test/stress/timeout_stress_test.dart`

- [ ] **Step 1: Write timeout stress tests**

Create `test/stress/timeout_stress_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Timeout stress tests', () {
    test('all sources timeout — result is full failure within ~10s', () async {
      final sw = Stopwatch()..start();
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () => Future.delayed(const Duration(seconds: 15), () => [1.0]),
        fetchExchangeRates: () => Future.delayed(const Duration(seconds: 15), () => [0.92]),
        fetchConfig: () => Future.delayed(const Duration(seconds: 15), () => <String, dynamic>{}),
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      sw.stop();
      expect(result.isFullFailure, isTrue);
      // First attempt 2s + retry 2s per source (parallel), so ~4-5s max, not 30s+
      expect(sw.elapsedMilliseconds, lessThan(10000));
    });

    test('one source timeout, others instant — partial result', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () => Future.delayed(const Duration(seconds: 15), () => [1.0]),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isFalse);
      expect(result.exchangeRatesOk, isTrue);
      expect(result.configOk, isTrue);
    });

    test('repeated timeouts do not accumulate state', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('fail'),
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => throw Exception('fail'),
        timeout: const Duration(seconds: 1),
      );
      // Run 3 consecutive syncs
      for (int i = 0; i < 3; i++) {
        final result = await orchestrator.sync();
        expect(result.isFullFailure, isTrue);
      }
    });

    test('source responds just before timeout succeeds', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () => Future.delayed(const Duration(milliseconds: 900), () => [1.0]),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.isFullSuccess, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/stress/timeout_stress_test.dart`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add test/stress/timeout_stress_test.dart
git commit -m "test: add timeout stress tests for DataSyncOrchestrator"
```

---

### Task 9: Stress Tests — Offline & Empty State

**Files:**
- Create: `fuel_price_app/test/stress/offline_stress_test.dart`

- [ ] **Step 1: Write offline stress tests**

Create `test/stress/offline_stress_test.dart`:
```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Offline / empty state stress tests', () {
    blocTest<DataSyncCubit, DataSyncState>(
      'first launch, no internet — emits SyncFailure',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('No internet'),
          fetchExchangeRates: () async => throw Exception('No internet'),
          fetchConfig: () async => throw Exception('No internet'),
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        isA<SyncFailure>(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'first launch, success — emits SyncSuccess',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [80.0],
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) => cubit.sync(),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'retry after failure then success',
      build: () {
        int attempt = 0;
        return DataSyncCubit(
          orchestrator: DataSyncOrchestrator(
            fetchOilPrices: () async {
              attempt++;
              if (attempt <= 2) throw Exception('fail'); // fail first sync (attempt + retry)
              return [80.0];
            },
            fetchExchangeRates: () async => [0.92],
            fetchConfig: () async => {'version': '1'},
            timeout: const Duration(seconds: 2),
          ),
          onSyncResult: (_) async {},
        );
      },
      act: (cubit) async {
        await cubit.sync(); // first try — fails
        await cubit.sync(); // second try — succeeds
      },
      expect: () => [
        const SyncInProgress(),
        isA<SyncPartial>(), // oil failed, others ok
        const SyncInProgress(),
        const SyncSuccess(), // third attempt of oil succeeds
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'multiple retries all fail — no crash or infinite loop',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => throw Exception('fail'),
          fetchExchangeRates: () async => throw Exception('fail'),
          fetchConfig: () async => throw Exception('fail'),
          timeout: const Duration(seconds: 1),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) async {
        await cubit.sync();
        await cubit.sync();
        await cubit.sync();
      },
      expect: () => [
        const SyncInProgress(),
        isA<SyncFailure>(),
        const SyncInProgress(),
        isA<SyncFailure>(),
        const SyncInProgress(),
        isA<SyncFailure>(),
      ],
    );
  });
}
```

- [ ] **Step 2: Run tests**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/stress/offline_stress_test.dart`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add test/stress/offline_stress_test.dart
git commit -m "test: add offline and empty state stress tests"
```

---

### Task 10: Stress Tests — Data Integrity & Concurrent Operations

**Files:**
- Create: `fuel_price_app/test/stress/data_integrity_test.dart`
- Create: `fuel_price_app/test/stress/concurrent_ops_test.dart`

- [ ] **Step 1: Write data integrity tests**

Create `test/stress/data_integrity_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Data integrity stress tests', () {
    test('partial source failure — successful sources have data', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => [80.0, 81.0],
        fetchExchangeRates: () async => throw Exception('HNB down'),
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPrices, [80.0, 81.0]);
      expect(result.exchangeRates, isNull);
      expect(result.config, isNotNull);
      expect(result.failedSources, ['exchangeRates']);
    });

    test('corrupt API response (exception) treated as failure', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw FormatException('Invalid JSON'),
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isFalse);
      expect(result.exchangeRatesOk, isTrue);
    });

    test('retry succeeds after initial failure', () async {
      int attempt = 0;
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async {
          attempt++;
          if (attempt == 1) throw Exception('transient');
          return [80.0];
        },
        fetchExchangeRates: () async => [0.92],
        fetchConfig: () async => {'version': '1'},
        timeout: const Duration(seconds: 2),
      );
      final result = await orchestrator.sync();
      expect(result.oilPricesOk, isTrue);
      expect(result.isFullSuccess, isTrue);
      expect(attempt, 2);
    });

    test('all sources fail after retry', () async {
      final orchestrator = DataSyncOrchestrator(
        fetchOilPrices: () async => throw Exception('fail'),
        fetchExchangeRates: () async => throw Exception('fail'),
        fetchConfig: () async => throw Exception('fail'),
        timeout: const Duration(seconds: 1),
      );
      final result = await orchestrator.sync();
      expect(result.isFullFailure, isTrue);
      expect(result.oilPrices, isNull);
      expect(result.exchangeRates, isNull);
      expect(result.config, isNull);
    });
  });
}
```

- [ ] **Step 2: Write concurrent operations tests**

Create `test/stress/concurrent_ops_test.dart`:
```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';

void main() {
  group('Concurrent operation stress tests', () {
    blocTest<DataSyncCubit, DataSyncState>(
      'rapid retry (5x) — only one sync runs at a time',
      build: () {
        int syncCount = 0;
        return DataSyncCubit(
          orchestrator: DataSyncOrchestrator(
            fetchOilPrices: () async {
              syncCount++;
              await Future.delayed(const Duration(milliseconds: 200));
              return [80.0];
            },
            fetchExchangeRates: () async => [0.92],
            fetchConfig: () async => {'version': '1'},
            timeout: const Duration(seconds: 2),
          ),
          onSyncResult: (result) async {
            // syncCount should only have incremented for one sync cycle
          },
        );
      },
      act: (cubit) {
        // Fire 5 syncs rapidly — only first should run
        for (int i = 0; i < 5; i++) {
          cubit.sync();
        }
      },
      wait: const Duration(seconds: 2),
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
        // Only 1 cycle of InProgress+Success, not 5
      ],
    );

    blocTest<DataSyncCubit, DataSyncState>(
      'sequential syncs after completion work correctly',
      build: () => DataSyncCubit(
        orchestrator: DataSyncOrchestrator(
          fetchOilPrices: () async => [80.0],
          fetchExchangeRates: () async => [0.92],
          fetchConfig: () async => {'version': '1'},
          timeout: const Duration(seconds: 2),
        ),
        onSyncResult: (_) async {},
      ),
      act: (cubit) async {
        await cubit.sync(); // completes
        await cubit.sync(); // should work again
      },
      expect: () => [
        const SyncInProgress(),
        const SyncSuccess(),
        const SyncInProgress(),
        const SyncSuccess(),
      ],
    );
  });
}
```

- [ ] **Step 3: Run all stress tests**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/stress/`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add test/stress/data_integrity_test.dart test/stress/concurrent_ops_test.dart
git commit -m "test: add data integrity and concurrent operation stress tests"
```

---

### Task 11: Stress Tests — Price Cycle & Scheduling Edge Cases

**Files:**
- Create: `fuel_price_app/test/stress/price_cycle_stress_test.dart`

- [ ] **Step 1: Write price cycle edge case tests**

Create `test/stress/price_cycle_stress_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';

void main() {
  group('Price cycle stress tests', () {
    final ref = DateTime(2026, 3, 24);

    test('100 consecutive cycles are all Tuesdays', () {
      for (int i = 0; i < 100; i++) {
        final today = ref.add(Duration(days: i * 14));
        final next = nextPriceChangeDate(today, ref, 14);
        expect(next.weekday, DateTime.tuesday,
            reason: 'Cycle $i: ${next.toIso8601String()} should be Tuesday');
      }
    });

    test('every day in a 2-year range returns valid next date', () {
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2028, 1, 1);
      var current = start;
      while (current.isBefore(end)) {
        final next = nextPriceChangeDate(current, ref, 14);
        expect(next.isAfter(current), isTrue,
            reason: 'For ${current.toIso8601String()}, next=${next.toIso8601String()} should be strictly after today');
        // Next should be within 14 days
        expect(next.difference(current).inDays, lessThanOrEqualTo(14));
        current = current.add(const Duration(days: 1));
      }
    });

    test('cycle across year boundary (Dec 29 → Jan 12)', () {
      final refDec = DateTime(2026, 12, 29);
      final next = nextPriceChangeDate(DateTime(2026, 12, 30), refDec, 14);
      expect(next, DateTime(2027, 1, 12));
    });

    test('cycle across leap year (Feb 28-29)', () {
      // 2028 is a leap year
      final refFeb = DateTime(2028, 2, 15);
      final next = nextPriceChangeDate(DateTime(2028, 2, 28), refFeb, 14);
      expect(next, DateTime(2028, 2, 29));
    });

    test('reference date far in the past still works', () {
      final oldRef = DateTime(2020, 1, 7); // a Tuesday
      final next = nextPriceChangeDate(DateTime(2026, 3, 24), oldRef, 14);
      expect(next.weekday, DateTime.tuesday);
      expect(next.isAfter(DateTime(2026, 3, 24)), isTrue);
    });

    test('validateCycleDays rejects various invalid values', () {
      expect(validateCycleDays(0), 14);
      expect(validateCycleDays(-14), 14);
      expect(validateCycleDays(1), 14);
      expect(validateCycleDays(3), 14);
      expect(validateCycleDays(10), 14);
      expect(validateCycleDays(15), 14);
    });

    test('validateCycleDays accepts multiples of 7', () {
      expect(validateCycleDays(7), 7);
      expect(validateCycleDays(14), 14);
      expect(validateCycleDays(21), 21);
      expect(validateCycleDays(28), 28);
    });
  });
}
```

- [ ] **Step 2: Run tests**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/stress/price_cycle_stress_test.dart`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add test/stress/price_cycle_stress_test.dart
git commit -m "test: add price cycle edge case and scheduling stress tests"
```

---

### Task 12: Integrate Trend Indicator into FuelListTile

**Files:**
- Modify: `fuel_price_app/lib/ui/widgets/fuel_list_tile.dart`
- Create: `fuel_price_app/test/ui/widgets/fuel_list_tile_test.dart`

Note: `fuel_list_tile.dart` is created in the base plan (Task 8 of the base plan). This task modifies it to include the trend arrow.

- [ ] **Step 1: Write failing widget test for trend arrow**

Create `test/ui/widgets/fuel_list_tile_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/ui/widgets/fuel_list_tile.dart';

void main() {
  group('FuelListTile trend indicator', () {
    testWidgets('shows ↑ in red when price rises', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurosuper 95',
              price: '1,42',
              unit: 'EUR/L',
              trend: '↑',
              onTap: () {},
            ),
          ),
        ),
      );
      final arrow = find.text('↑');
      expect(arrow, findsOneWidget);
      final text = tester.widget<Text>(arrow);
      expect(text.style?.color, Colors.red);
    });

    testWidgets('shows ↓ in green when price drops', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurodizel',
              price: '1,35',
              unit: 'EUR/L',
              trend: '↓',
              onTap: () {},
            ),
          ),
        ),
      );
      final arrow = find.text('↓');
      expect(arrow, findsOneWidget);
      final text = tester.widget<Text>(arrow);
      expect(text.style?.color, Colors.green);
    });

    testWidgets('shows → in grey when unchanged', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurosuper 95',
              price: '1,38',
              unit: 'EUR/L',
              trend: '→',
              onTap: () {},
            ),
          ),
        ),
      );
      final arrow = find.text('→');
      expect(arrow, findsOneWidget);
      final text = tester.widget<Text>(arrow);
      expect(text.style?.color, Colors.grey);
    });

    testWidgets('shows no arrow when trend is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurosuper 95',
              price: '1,42',
              unit: 'EUR/L',
              trend: null,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('↑'), findsNothing);
      expect(find.text('↓'), findsNothing);
      expect(find.text('→'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/ui/widgets/fuel_list_tile_test.dart`
Expected: FAIL — `FuelListTile` doesn't accept `trend` parameter yet

- [ ] **Step 3: Update FuelListTile to include trend arrow**

Modify `lib/ui/widgets/fuel_list_tile.dart` to add `trend` parameter and render colored arrow:
```dart
import 'package:flutter/material.dart';

class FuelListTile extends StatelessWidget {
  final String fuelName;
  final String price;
  final String unit;
  final String? trend;
  final VoidCallback onTap;

  const FuelListTile({
    super.key,
    required this.fuelName,
    required this.price,
    required this.unit,
    this.trend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(fuelName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$price $unit', style: Theme.of(context).textTheme.titleMedium),
          if (trend != null) ...[
            const SizedBox(width: 8),
            Text(
              trend!,
              style: TextStyle(
                fontSize: 18,
                color: _trendColor(trend!),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  static Color _trendColor(String trend) {
    return switch (trend) {
      '↑' => Colors.red,
      '↓' => Colors.green,
      _ => Colors.grey,
    };
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/ui/widgets/fuel_list_tile_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/fuel_list_tile.dart test/ui/widgets/fuel_list_tile_test.dart
git commit -m "feat: add trend indicator arrow with colors to FuelListTile"
```

---

### Task 13: Integrate Empty State, Spinner, and Sync into FuelListScreen

**Files:**
- Modify: `fuel_price_app/lib/ui/screens/fuel_list_screen.dart`
- Create: `fuel_price_app/test/ui/screens/fuel_list_screen_sync_test.dart`

Note: `fuel_list_screen.dart` is created in the base plan. This task modifies it to handle sync states, empty state, spinner, pull-to-refresh, snackbars, and "Zadnje ažuriranje" timestamp.

- [ ] **Step 1: Write failing widget tests for sync state integration**

Create `test/ui/screens/fuel_list_screen_sync_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/ui/screens/fuel_list_screen.dart';

class MockDataSyncCubit extends MockCubit<DataSyncState> implements DataSyncCubit {}

void main() {
  late MockDataSyncCubit mockSyncCubit;

  setUp(() {
    mockSyncCubit = MockDataSyncCubit();
  });

  Widget buildSubject() {
    return MaterialApp(
      home: BlocProvider<DataSyncCubit>.value(
        value: mockSyncCubit,
        child: const FuelListScreen(),
      ),
    );
  }

  group('FuelListScreen sync integration', () {
    testWidgets('shows spinner when SyncInProgress and no data', (tester) async {
      when(() => mockSyncCubit.state).thenReturn(const SyncInProgress());
      when(() => mockSyncCubit.hasData).thenReturn(false);
      await tester.pumpWidget(buildSubject());
      expect(find.text('Preuzimanje podataka...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state on SyncFailure with no data', (tester) async {
      when(() => mockSyncCubit.state).thenReturn(const SyncFailure(message: 'fail'));
      when(() => mockSyncCubit.hasData).thenReturn(false);
      await tester.pumpWidget(buildSubject());
      expect(
        find.text('Nema dostupnih podataka. Provjerite internetsku vezu i pritisnite gumb za ažuriranje.'),
        findsOneWidget,
      );
      expect(find.text('Ažuriraj'), findsOneWidget);
    });

    testWidgets('shows snackbar on SyncPartial with existing data', (tester) async {
      whenListen(
        mockSyncCubit,
        Stream<DataSyncState>.fromIterable([
          const SyncPartial(failedSources: ['oilPrices']),
        ]),
        initialState: const SyncIdle(),
      );
      when(() => mockSyncCubit.hasData).thenReturn(true);
      await tester.pumpWidget(buildSubject());
      await tester.pump(); // process stream
      expect(
        find.text('Ažuriranje nije u potpunosti uspjelo. Prikazani su posljednji dostupni podaci.'),
        findsOneWidget,
      );
    });

    testWidgets('shows snackbar on SyncFailure with existing data', (tester) async {
      whenListen(
        mockSyncCubit,
        Stream<DataSyncState>.fromIterable([
          const SyncFailure(message: 'fail'),
        ]),
        initialState: const SyncIdle(),
      );
      when(() => mockSyncCubit.hasData).thenReturn(true);
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(
        find.text('Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci.'),
        findsOneWidget,
      );
    });

    testWidgets('shows last update timestamp', (tester) async {
      when(() => mockSyncCubit.state).thenReturn(const SyncSuccess());
      when(() => mockSyncCubit.hasData).thenReturn(true);
      when(() => mockSyncCubit.lastSyncTime).thenReturn(DateTime(2026, 3, 24, 18, 0));
      await tester.pumpWidget(buildSubject());
      expect(find.textContaining('Zadnje ažuriranje:'), findsOneWidget);
      expect(find.textContaining('24.03.2026.'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/ui/screens/fuel_list_screen_sync_test.dart`
Expected: FAIL — FuelListScreen doesn't handle sync states yet

- [ ] **Step 3: Update FuelListScreen with sync state handling**

Modify `lib/ui/screens/fuel_list_screen.dart`. The key structure:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/ui/widgets/empty_state.dart';
import 'package:fuel_price_app/ui/widgets/sync_spinner.dart';

class FuelListScreen extends StatelessWidget {
  const FuelListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DataSyncCubit, DataSyncState>(
      listener: (context, state) {
        final cubit = context.read<DataSyncCubit>();
        if (state is SyncPartial && cubit.hasData) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ažuriranje nije u potpunosti uspjelo. Prikazani su posljednji dostupni podaci.')),
          );
        } else if (state is SyncFailure && cubit.hasData) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci.')),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<DataSyncCubit>();

        // No data states
        if (!cubit.hasData) {
          if (state is SyncInProgress) {
            return const SyncSpinner();
          }
          if (state is SyncFailure) {
            return EmptyStateWidget(onRetry: () => cubit.sync());
          }
        }

        // Has data — show fuel list with pull-to-refresh
        return RefreshIndicator(
          onRefresh: () => cubit.sync(),
          child: Column(
            children: [
              if (cubit.lastSyncTime != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Zadnje ažuriranje: ${DateFormat('dd.MM.yyyy. HH:mm').format(cubit.lastSyncTime!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: _buildFuelList(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFuelList(BuildContext context) {
    // Fuel list implementation from base plan
    // Uses FuelListTile with trend parameter
    return const Placeholder(); // Replaced by base plan Task 8
  }
}
```

Add `hasData` and `lastSyncTime` getters to `DataSyncCubit`:
```dart
// Add to lib/blocs/data_sync_cubit.dart:
bool _hasData = false;
DateTime? _lastSyncTime;

bool get hasData => _hasData;
DateTime? get lastSyncTime => _lastSyncTime;

// In sync() method, after onSyncResult:
if (!result.isFullFailure) {
  _hasData = true;
  _lastSyncTime = DateTime.now();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/ui/screens/fuel_list_screen_sync_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/fuel_list_screen.dart lib/blocs/data_sync_cubit.dart test/ui/screens/fuel_list_screen_sync_test.dart
git commit -m "feat: integrate sync states, empty state, spinner, and pull-to-refresh into FuelListScreen"
```

---

### Task 14: Add WorkManager 18:00 CET Scheduling

**Files:**
- Modify: `fuel_price_app/lib/main.dart`
- Create: `fuel_price_app/test/scheduling/workmanager_schedule_test.dart`

Note: WorkManager is initialized in `main.dart` per the base plan. This task ensures the schedule uses 18:00 CET and handles DST.

- [ ] **Step 1: Write failing test for schedule calculation**

Create `test/scheduling/workmanager_schedule_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/scheduling/schedule_helper.dart';

void main() {
  group('WorkManager schedule helper', () {
    test('next18CET from 10:00 CET returns today 18:00', () {
      // March 24 2026 10:00 CET = 09:00 UTC
      final now = DateTime.utc(2026, 3, 24, 9, 0);
      final next = nextFetchTime(now);
      expect(next.hour, 17); // 18:00 CET = 17:00 UTC in winter... but March 24 is after DST
      // March 24 2026 is CEST (UTC+2), so 18:00 CEST = 16:00 UTC
      expect(next, DateTime.utc(2026, 3, 24, 16, 0));
    });

    test('next18CET from 19:00 CET returns tomorrow 18:00', () {
      // March 24 2026 19:00 CEST = 17:00 UTC
      final now = DateTime.utc(2026, 3, 24, 17, 0);
      final next = nextFetchTime(now);
      // Tomorrow 18:00 CEST = 16:00 UTC
      expect(next, DateTime.utc(2026, 3, 25, 16, 0));
    });

    test('initialDelay calculates correct duration', () {
      final now = DateTime.utc(2026, 3, 24, 10, 0); // 12:00 CEST
      final delay = initialFetchDelay(now);
      // 18:00 CEST (16:00 UTC) - 12:00 CEST (10:00 UTC) = 6 hours
      expect(delay.inHours, 6);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/scheduling/workmanager_schedule_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Create schedule helper**

Create `lib/scheduling/schedule_helper.dart`:
```dart
/// Zagreb timezone offset: CET = UTC+1 (Nov-Mar), CEST = UTC+2 (Mar-Oct).
/// DST switch: last Sunday of March (to CEST), last Sunday of October (to CET).
int _zagrebUtcOffset(DateTime utcDate) {
  final year = utcDate.year;
  // Last Sunday of March
  final marchLast = DateTime.utc(year, 3, 31);
  final dstStart = marchLast.subtract(Duration(days: marchLast.weekday % 7));
  // Last Sunday of October
  final octLast = DateTime.utc(year, 10, 31);
  final dstEnd = octLast.subtract(Duration(days: octLast.weekday % 7));

  // CEST: from last Sunday of March 01:00 UTC to last Sunday of October 01:00 UTC
  final cestStart = DateTime.utc(dstStart.year, dstStart.month, dstStart.day, 1);
  final cestEnd = DateTime.utc(dstEnd.year, dstEnd.month, dstEnd.day, 1);

  if (utcDate.isAfter(cestStart) && utcDate.isBefore(cestEnd)) {
    return 2; // CEST
  }
  return 1; // CET
}

/// Returns the next 18:00 Zagreb local time as a UTC DateTime.
DateTime nextFetchTime(DateTime nowUtc) {
  final offset = _zagrebUtcOffset(nowUtc);
  final localHour = nowUtc.hour + offset;

  if (localHour < 18) {
    // Today at 18:00 local = 18 - offset in UTC
    return DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 18 - offset);
  } else {
    // Tomorrow at 18:00 local
    final tomorrow = nowUtc.add(const Duration(days: 1));
    final tomorrowOffset = _zagrebUtcOffset(tomorrow);
    return DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day, 18 - tomorrowOffset);
  }
}

/// Duration until next 18:00 Zagreb time.
Duration initialFetchDelay(DateTime nowUtc) {
  return nextFetchTime(nowUtc).difference(nowUtc);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/scheduling/workmanager_schedule_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Update main.dart to use 18:00 CET schedule**

In `lib/main.dart`, when initializing WorkManager, use `initialFetchDelay`:
```dart
import 'package:fuel_price_app/scheduling/schedule_helper.dart';

// In main() or WorkManager initialization:
final delay = initialFetchDelay(DateTime.now().toUtc());
Workmanager().registerPeriodicTask(
  'dailySync',
  'fetchPriceData',
  initialDelay: delay,
  frequency: const Duration(hours: 24),
  constraints: Constraints(networkType: NetworkType.connected),
);
```

- [ ] **Step 6: Commit**

```bash
git add lib/scheduling/schedule_helper.dart test/scheduling/workmanager_schedule_test.dart lib/main.dart
git commit -m "feat: add 18:00 CET WorkManager scheduling with DST handling"
```

---

### Task 15: Run All Tests and Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run entire test suite**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test`
Expected: ALL PASS, 0 failures

- [ ] **Step 2: Verify file structure is correct**

Run: `find fuel_price_app/lib fuel_price_app/test -name '*.dart' | sort`
Verify all expected files exist per the file structure header.

- [ ] **Step 3: Run existing tests haven't broken**

Run: `cd D:/Projekti/test/fuel_price_app && flutter test test/models/fuel_type_test.dart test/data/database_test.dart`
Expected: ALL PASS (pre-existing tests still work)

- [ ] **Step 4: Verify all spec requirements covered**

Checklist:
- [ ] 18:00 CET scheduling with DST (Task 14)
- [ ] Empty state with "Nema dostupnih podataka..." message (Task 6)
- [ ] Spinner with "Preuzimanje podataka..." (Task 6)
- [ ] Partial fetch + retry per source (Task 4)
- [ ] Trend indicator ↑↓→ with colors (Task 12)
- [ ] Price cycle in remote config (Tasks 1, 7)
- [ ] nextPriceChangeDate calculation (Task 2)
- [ ] Pull-to-refresh with snackbar (Task 13)
- [ ] "Zadnje ažuriranje" timestamp (Task 13)
- [ ] Concurrent sync guard (Task 5)
- [ ] Stress tests (Tasks 8-11)

- [ ] **Step 5: Commit any remaining changes**

If any fixes were needed, commit them.
