# Core Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the formula engine, API services (Yahoo Finance, HNB, remote config), and repositories — the core data layer that all UI depends on.

**Architecture:** Pure domain logic (FormulaEngine) + HTTP services (Dio-based) + SQLite repositories. Services fetch raw data, repositories persist it, formula engine calculates predictions. All testable with mocks.

**Tech Stack:** Flutter (Dart), dio, sqflite, mocktail, sqflite_common_ffi for tests

**Specs:** `docs/superpowers/specs/2026-03-23-fuel-app-v2-design.md`, `docs/superpowers/specs/2026-03-24-offline-timing-ux-design.md`
**Base plan:** `docs/superpowers/plans/2026-03-23-fuel-price-app.md` (Tasks 3-6)

**Run Flutter with:** `D:/Portable/flutter/bin/flutter.bat`

---

## File Structure

```
fuel_price_app/
├── lib/
│   ├── domain/
│   │   ├── price_cycle_service.dart         — EXISTS (from previous plan)
│   │   └── formula_engine.dart              — CREATE: price calculation per NN 31/2025
│   ├── data/
│   │   ├── database.dart                    — EXISTS
│   │   ├── services/
│   │   │   ├── data_sync_orchestrator.dart  — EXISTS (from previous plan)
│   │   │   ├── yahoo_finance_service.dart   — CREATE: fetch BZ=F historical prices
│   │   │   ├── hnb_service.dart             — CREATE: fetch EUR/USD from HNB API
│   │   │   └── remote_config_service.dart   — CREATE: fetch fuel_params.json from GitHub
│   │   └── repositories/
│   │       ├── price_repository.dart        — CREATE: CRUD for oil_prices, exchange_rates, fuel_prices
│   │       ├── settings_repository.dart     — CREATE: fuel order, visibility, notification prefs
│   │       └── config_repository.dart       — CREATE: remote config versioning and storage
├── test/
│   ├── domain/
│   │   ├── price_cycle_service_test.dart    — EXISTS
│   │   └── formula_engine_test.dart         — CREATE
│   ├── data/
│   │   ├── services/
│   │   │   ├── data_sync_orchestrator_test.dart — EXISTS
│   │   │   ├── yahoo_finance_service_test.dart  — CREATE
│   │   │   ├── hnb_service_test.dart            — CREATE
│   │   │   └── remote_config_service_test.dart  — CREATE
│   │   └── repositories/
│   │       ├── price_repository_test.dart       — CREATE
│   │       └── settings_repository_test.dart    — CREATE
```

---

### Task 1: Formula Engine

**Files:**
- Create: `fuel_price_app/lib/domain/formula_engine.dart`
- Create: `fuel_price_app/test/domain/formula_engine_test.dart`

Core business logic per NN 31/2025:
- For liquid fuels: `PC = [Σ(CIF_Med × ρ / T) / (n × 1000)] + P`
- For UNP (LPG): `PC = [Σ(CIF / T) / (n × 1000)] + P` (no density, single proxy)
- Retail: `(PC + trošarina) × 1.25` (25% VAT)
- Round final to 2 decimals

- [ ] **Step 1: Write failing tests**

Create `test/domain/formula_engine_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

void main() {
  late FormulaEngine engine;

  setUp(() {
    engine = FormulaEngine(FuelParams.defaultParams);
  });

  group('calculateBasePrice (PC)', () {
    test('calculates for ES95 with known values', () {
      // 14 days, CIF Med avg = 700 USD/t, avg EUR/USD rate = 0.92
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      // PC = [Σ(CIF × ρ / T) / (n × 1000)] + P
      // = [(14 × 700 × 0.755 / 0.92) / (14 × 1000)] + 0.1545
      // = [700 × 0.755 / 0.92] / 1000 + 0.1545
      // = 574.4565 / 1000 + 0.1545
      // = 0.5745 + 0.1545 = 0.7290
      final pc = engine.calculateBasePrice(FuelType.es95, dailyPrices, dailyRates);
      expect(pc, closeTo(0.7290, 0.001));
    });

    test('calculates for Eurodizel with different density', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      // density eurodizel = 0.845
      // = [700 × 0.845 / 0.92] / 1000 + 0.1545
      // = 642.935 / 1000 + 0.1545
      // = 0.6429 + 0.1545 = 0.7974
      final pc = engine.calculateBasePrice(FuelType.eurodizel, dailyPrices, dailyRates);
      expect(pc, closeTo(0.7974, 0.001));
    });

    test('calculates for UNP (no density)', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      // UNP: PC = [Σ(CIF / T) / (n × 1000)] + P
      // = [700 / 0.92] / 1000 + 0.8429
      // = 760.87 / 1000 + 0.8429
      // = 0.7609 + 0.8429 = 1.6038
      final pc = engine.calculateBasePrice(FuelType.unp10kg, dailyPrices, dailyRates);
      expect(pc, closeTo(1.6038, 0.001));
    });
  });

  group('calculateRetailPrice', () {
    test('adds excise and VAT for ES95', () {
      final pc = 0.7290;
      // retail = (PC + trošarina) × (1 + PDV)
      // = (0.7290 + 0.4560) × 1.25 = 1.1850 × 1.25 = 1.48125
      final retail = engine.calculateRetailPrice(FuelType.es95, pc);
      expect(retail, closeTo(1.48125, 0.001));
    });

    test('adds excise and VAT for Eurodizel', () {
      final pc = 0.7974;
      // = (0.7974 + 0.40613) × 1.25 = 1.50441
      final retail = engine.calculateRetailPrice(FuelType.eurodizel, pc);
      expect(retail, closeTo(1.5044, 0.001));
    });
  });

  group('roundPrice', () {
    test('rounds to 2 decimals', () {
      expect(FormulaEngine.roundPrice(1.48125), 1.48);
      expect(FormulaEngine.roundPrice(1.485), 1.49);
      expect(FormulaEngine.roundPrice(1.4999), 1.50);
    });
  });

  group('predictPrice (full pipeline)', () {
    test('ES95 end-to-end', () {
      final dailyPrices = List.generate(14, (_) => 700.0);
      final dailyRates = List.generate(14, (_) => 0.92);
      final price = engine.predictPrice(FuelType.es95, dailyPrices, dailyRates);
      // PC = 0.7290, retail = 1.48125, rounded = 1.48
      expect(price, 1.48);
    });
  });

  group('edge cases', () {
    test('empty price list throws', () {
      expect(
        () => engine.calculateBasePrice(FuelType.es95, [], []),
        throwsArgumentError,
      );
    });

    test('mismatched list lengths throws', () {
      expect(
        () => engine.calculateBasePrice(FuelType.es95, [700], [0.92, 0.93]),
        throwsArgumentError,
      );
    });

    test('varying daily rates', () {
      final prices = [700.0, 710.0, 690.0];
      final rates = [0.92, 0.93, 0.91];
      // Each day: CIF × ρ / T
      // Day 1: 700 × 0.755 / 0.92 = 574.457
      // Day 2: 710 × 0.755 / 0.93 = 576.559
      // Day 3: 690 × 0.755 / 0.91 = 572.198
      // Sum = 1723.214, PC = 1723.214 / (3 × 1000) + 0.1545 = 0.5744 + 0.1545 = 0.7289
      final pc = engine.calculateBasePrice(FuelType.es95, prices, rates);
      expect(pc, closeTo(0.7289, 0.001));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/domain/formula_engine_test.dart`
Expected: FAIL — FormulaEngine doesn't exist

- [ ] **Step 3: Implement FormulaEngine**

Create `lib/domain/formula_engine.dart`:
```dart
import '../models/fuel_type.dart';
import '../models/fuel_params.dart';

class FormulaEngine {
  final FuelParams params;

  FormulaEngine(this.params);

  /// Calculate base price (PC) per NN 31/2025 formula.
  ///
  /// For liquid fuels: PC = [Σ(CIF_Med × ρ / T) / (n × 1000)] + P
  /// For UNP (no density): PC = [Σ(CIF / T) / (n × 1000)] + P
  ///
  /// [cifMedPrices] — daily CIF Med in USD/t
  /// [exchangeRates] — daily USD/EUR rate (1 USD = X EUR)
  double calculateBasePrice(
    FuelType fuelType,
    List<double> cifMedPrices,
    List<double> exchangeRates,
  ) {
    if (cifMedPrices.isEmpty || exchangeRates.isEmpty) {
      throw ArgumentError('Price and rate lists must not be empty');
    }
    if (cifMedPrices.length != exchangeRates.length) {
      throw ArgumentError('Price and rate lists must have same length');
    }

    final density = params.density[fuelType.name];
    final premium = params.premiums[fuelType.name]!;
    final n = cifMedPrices.length;

    double sum = 0;
    for (var i = 0; i < n; i++) {
      if (density != null) {
        sum += cifMedPrices[i] * density / exchangeRates[i];
      } else {
        // UNP: no density factor
        sum += cifMedPrices[i] / exchangeRates[i];
      }
    }

    return sum / (n * 1000) + premium;
  }

  /// Calculate retail price: (PC + trošarina) × (1 + PDV)
  double calculateRetailPrice(FuelType fuelType, double basePrice) {
    final excise = params.exciseDuties[fuelType.name]!;
    final vatMultiplier = 1 + params.vatRate;
    return (basePrice + excise) * vatMultiplier;
  }

  /// Full calculation: base → retail → rounded
  double predictPrice(
    FuelType fuelType,
    List<double> cifMedPrices,
    List<double> exchangeRates,
  ) {
    final pc = calculateBasePrice(fuelType, cifMedPrices, exchangeRates);
    final retail = calculateRetailPrice(fuelType, pc);
    return roundPrice(retail);
  }

  static double roundPrice(double price) => (price * 100).round() / 100;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/domain/formula_engine_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/domain/formula_engine.dart fuel_price_app/test/domain/formula_engine_test.dart
git commit -m "feat: add formula engine for fuel price calculation per NN 31/2025"
```

---

### Task 2: HNB Exchange Rate Service

**Files:**
- Create: `fuel_price_app/lib/data/services/hnb_service.dart`
- Create: `fuel_price_app/test/data/services/hnb_service_test.dart`

HNB API: `https://api.hnb.hr/tecajn-eur/v3?valuta=USD` — returns JSON array with `srednji_tecaj` (middle rate, comma decimal).

- [ ] **Step 1: Write failing test**

Create `test/data/services/hnb_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/hnb_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late HnbService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = HnbService(dio: mockDio);
  });

  test('fetches USD/EUR rate', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: [
        {'srednji_tecaj': '0,920000', 'valuta': 'USD'}
      ],
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final rate = await service.fetchUsdEurRate();
    expect(rate, closeTo(0.92, 0.001));
  });

  test('throws on empty response', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: [],
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    expect(() => service.fetchUsdEurRate(), throwsException);
  });

  test('fetches rate for specific date', () async {
    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: [
        {'srednji_tecaj': '0,930000', 'valuta': 'USD'}
      ],
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final rate = await service.fetchUsdEurRateForDate(DateTime(2026, 3, 20));
    expect(rate, closeTo(0.93, 0.001));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/hnb_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement HnbService**

Create `lib/data/services/hnb_service.dart`:
```dart
import 'package:dio/dio.dart';

class HnbService {
  final Dio dio;
  static const _baseUrl = 'https://api.hnb.hr/tecajn-eur/v3';

  HnbService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch current USD/EUR middle rate (1 USD = X EUR)
  Future<double> fetchUsdEurRate() async {
    final response = await dio.get('$_baseUrl?valuta=USD');
    final data = response.data as List;
    if (data.isEmpty) throw Exception('No USD rate from HNB');
    final rateStr = data[0]['srednji_tecaj'] as String;
    return double.parse(rateStr.replaceAll(',', '.'));
  }

  /// Fetch USD/EUR rate for a specific date
  Future<double> fetchUsdEurRateForDate(DateTime date) async {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final response = await dio.get('$_baseUrl?valuta=USD&datum-primjene=$dateStr');
    final data = response.data as List;
    if (data.isEmpty) throw Exception('No USD rate from HNB for $dateStr');
    final rateStr = data[0]['srednji_tecaj'] as String;
    return double.parse(rateStr.replaceAll(',', '.'));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/hnb_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/data/services/hnb_service.dart fuel_price_app/test/data/services/hnb_service_test.dart
git commit -m "feat: add HNB exchange rate service"
```

---

### Task 3: Yahoo Finance Service

**Files:**
- Create: `fuel_price_app/lib/data/services/yahoo_finance_service.dart`
- Create: `fuel_price_app/test/data/services/yahoo_finance_service_test.dart`

Yahoo Finance CSV endpoint for historical prices. Symbol `BZ=F` = Brent Crude.

- [ ] **Step 1: Write failing test**

Create `test/data/services/yahoo_finance_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/yahoo_finance_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late YahooFinanceService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = YahooFinanceService(dio: mockDio);
  });

  test('parses historical prices from CSV response', () async {
    const csvData = 'Date,Open,High,Low,Close,Adj Close,Volume\n'
        '2026-03-10,71.5,72.0,70.8,71.2,71.2,100000\n'
        '2026-03-11,71.3,71.8,70.5,71.0,71.0,120000\n';

    when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => Response(
      data: csvData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 2);
    expect(prices.first.close, 71.2);
    expect(prices.first.date, DateTime(2026, 3, 10));
  });

  test('handles null/zero close prices', () async {
    const csvData = 'Date,Open,High,Low,Close,Adj Close,Volume\n'
        '2026-03-10,71.5,72.0,70.8,null,71.2,100000\n'
        '2026-03-11,71.3,71.8,70.5,71.0,71.0,120000\n';

    when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => Response(
      data: csvData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices.length, 1); // null row filtered out
  });

  test('empty CSV returns empty list', () async {
    const csvData = 'Date,Open,High,Low,Close,Adj Close,Volume\n';

    when(() => mockDio.get(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => Response(
      data: csvData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final prices = await service.fetchHistoricalPrices('BZ=F', 14);
    expect(prices, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/yahoo_finance_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement YahooFinanceService**

Create `lib/data/services/yahoo_finance_service.dart`:
```dart
import 'package:dio/dio.dart';

class YahooFinancePrice {
  final DateTime date;
  final double close;

  YahooFinancePrice({required this.date, required this.close});
}

class YahooFinanceService {
  final Dio dio;

  YahooFinanceService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch historical closing prices for a symbol.
  /// [symbol]: 'BZ=F' (Brent), 'RB=F' (RBOB), 'HO=F' (Heating Oil)
  /// [days]: number of calendar days to look back
  Future<List<YahooFinancePrice>> fetchHistoricalPrices(String symbol, int days) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days + 7)); // buffer for weekends
    final period1 = from.millisecondsSinceEpoch ~/ 1000;
    final period2 = now.millisecondsSinceEpoch ~/ 1000;

    final response = await dio.get(
      'https://query1.finance.yahoo.com/v7/finance/download/$symbol',
      queryParameters: {
        'period1': period1,
        'period2': period2,
        'interval': '1d',
        'events': 'history',
      },
    );

    return _parseCsv(response.data as String);
  }

  List<YahooFinancePrice> _parseCsv(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.length < 2) return [];

    return lines.skip(1).where((line) => line.trim().isNotEmpty).map((line) {
      final cols = line.split(',');
      final date = DateTime.parse(cols[0]);
      final close = double.tryParse(cols[4]) ?? 0;
      return YahooFinancePrice(date: date, close: close);
    }).where((p) => p.close > 0).toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/yahoo_finance_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/data/services/yahoo_finance_service.dart fuel_price_app/test/data/services/yahoo_finance_service_test.dart
git commit -m "feat: add Yahoo Finance historical price service"
```

---

### Task 4: Remote Config Service

**Files:**
- Create: `fuel_price_app/lib/data/services/remote_config_service.dart`
- Create: `fuel_price_app/test/data/services/remote_config_service_test.dart`

Note: `config/fuel_params.json` already exists from previous plan.

- [ ] **Step 1: Write failing test**

Create `test/data/services/remote_config_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late RemoteConfigService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = RemoteConfigService(dio: mockDio);
  });

  test('fetches and parses remote config', () async {
    final json = {
      'version': '2025-02-26',
      'price_cycle': {
        'reference_date': '2026-03-24',
        'cycle_days': 14,
      },
      'price_regulation': {
        'name': 'Test',
        'nn_reference': 'NN 31/2025',
        'effective_date': '2025-02-26',
      },
      'excise_regulation': {
        'name': 'Test',
        'nn_reference': 'NN 156/2022',
        'effective_date': '2023-01-01',
      },
      'premiums': {'es95': 0.1545},
      'excise_duties': {'es95': 0.456},
      'density': {'es95': 0.755},
      'vat_rate': 0.25,
    };

    when(() => mockDio.get(any())).thenAnswer((_) async => Response(
      data: json,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));

    final params = await service.fetchParams();
    expect(params, isNotNull);
    expect(params!.version, '2025-02-26');
    expect(params.vatRate, 0.25);
    expect(params.cycleDays, 14);
  });

  test('returns null on fetch failure', () async {
    when(() => mockDio.get(any())).thenThrow(DioException(
      requestOptions: RequestOptions(path: ''),
      type: DioExceptionType.connectionTimeout,
    ));

    final params = await service.fetchParams();
    expect(params, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/remote_config_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement RemoteConfigService**

Create `lib/data/services/remote_config_service.dart`:
```dart
import 'package:dio/dio.dart';
import '../../models/fuel_params.dart';

class RemoteConfigService {
  final Dio dio;
  static const _configUrl =
      'https://raw.githubusercontent.com/iersegovic/fuel-price-app/main/config/fuel_params.json';

  RemoteConfigService({Dio? dio}) : dio = dio ?? Dio();

  /// Fetch remote config. Returns null on any failure.
  Future<FuelParams?> fetchParams() async {
    try {
      final response = await dio.get(_configUrl);
      final data = response.data as Map<String, dynamic>;
      return FuelParams.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/remote_config_service_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/data/services/remote_config_service.dart fuel_price_app/test/data/services/remote_config_service_test.dart
git commit -m "feat: add remote config service for GitHub-hosted parameters"
```

---

### Task 5: Price Repository

**Files:**
- Create: `fuel_price_app/lib/data/repositories/price_repository.dart`
- Create: `fuel_price_app/test/data/repositories/price_repository_test.dart`

CRUD for oil_prices, exchange_rates, fuel_prices tables.

- [ ] **Step 1: Write failing test**

Create `test/data/repositories/price_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/oil_price.dart';
import 'package:fuel_price_app/models/exchange_rate.dart';

void main() {
  late AppDatabase db;
  late PriceRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    repo = PriceRepository(db);
  });

  tearDown(() async => await db.close());

  test('saves and retrieves oil prices', () async {
    final price = OilPrice(date: DateTime(2026, 3, 20), cifMed: 700.5, source: 'BZ=F');
    await repo.saveOilPrice(price);
    final prices = await repo.getOilPrices('BZ=F', days: 30);
    expect(prices.length, 1);
    expect(prices.first.cifMed, 700.5);
  });

  test('saves and retrieves exchange rates', () async {
    final rate = ExchangeRate(date: DateTime(2026, 3, 20), usdEur: 0.92);
    await repo.saveExchangeRate(rate);
    final rates = await repo.getExchangeRates(days: 30);
    expect(rates.length, 1);
    expect(rates.first.usdEur, 0.92);
  });

  test('saves and retrieves fuel prices', () async {
    final fp = FuelPrice(
      fuelType: FuelType.es95,
      date: DateTime(2026, 3, 25),
      price: 1.48,
      isPrediction: true,
    );
    await repo.saveFuelPrice(fp);
    final latest = await repo.getLatestPrice(FuelType.es95, prediction: true);
    expect(latest?.price, 1.48);
  });

  test('getLatestPrice returns null when empty', () async {
    final result = await repo.getLatestPrice(FuelType.es95, prediction: false);
    expect(result, isNull);
  });

  test('getPriceHistory returns sorted prices', () async {
    await repo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95, date: DateTime(2026, 3, 10), price: 1.45, isPrediction: false));
    await repo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95, date: DateTime(2026, 3, 24), price: 1.48, isPrediction: false));
    final history = await repo.getPriceHistory(FuelType.es95, days: 30);
    expect(history.length, 2);
    expect(history.first.date.isBefore(history.last.date), isTrue);
  });

  test('deletes old records', () async {
    final old = OilPrice(date: DateTime(2023, 1, 1), cifMed: 500, source: 'BZ=F');
    await repo.saveOilPrice(old);
    await repo.cleanOldData(const Duration(days: 730));
    final prices = await repo.getOilPrices('BZ=F', days: 9999);
    expect(prices, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/repositories/price_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement PriceRepository**

Create `lib/data/repositories/price_repository.dart`:
```dart
import '../database.dart';
import '../../models/oil_price.dart';
import '../../models/exchange_rate.dart';
import '../../models/fuel_price.dart';
import '../../models/fuel_type.dart';

class PriceRepository {
  final AppDatabase db;

  PriceRepository(this.db);

  Future<void> saveOilPrice(OilPrice price) async =>
      await db.insert('oil_prices', price.toMap());

  Future<List<OilPrice>> getOilPrices(String source, {required int days}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.query(
      'oil_prices',
      where: 'source = ? AND date >= ?',
      whereArgs: [source, cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'date ASC',
    );
    return rows.map(OilPrice.fromMap).toList();
  }

  Future<void> saveExchangeRate(ExchangeRate rate) async =>
      await db.insert('exchange_rates', rate.toMap());

  Future<List<ExchangeRate>> getExchangeRates({required int days}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.query(
      'exchange_rates',
      where: 'date >= ?',
      whereArgs: [cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'date ASC',
    );
    return rows.map(ExchangeRate.fromMap).toList();
  }

  Future<void> saveFuelPrice(FuelPrice price) async =>
      await db.insert('fuel_prices', price.toMap());

  Future<FuelPrice?> getLatestPrice(FuelType fuelType, {required bool prediction}) async {
    final rows = await db.query(
      'fuel_prices',
      where: 'fuel_type = ? AND is_prediction = ?',
      whereArgs: [fuelType.name, prediction ? 1 : 0],
      orderBy: 'date DESC',
    );
    if (rows.isEmpty) return null;
    return FuelPrice.fromMap(rows.first);
  }

  Future<List<FuelPrice>> getPriceHistory(FuelType fuelType, {required int days}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await db.query(
      'fuel_prices',
      where: 'fuel_type = ? AND is_prediction = 0 AND date >= ?',
      whereArgs: [fuelType.name, cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'date ASC',
    );
    return rows.map(FuelPrice.fromMap).toList();
  }

  Future<void> cleanOldData(Duration maxAge) async {
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String().substring(0, 10);
    await db.delete('oil_prices', where: 'date < ?', whereArgs: [cutoff]);
    await db.delete('exchange_rates', where: 'date < ?', whereArgs: [cutoff]);
    await db.delete('fuel_prices', where: 'date < ?', whereArgs: [cutoff]);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/repositories/price_repository_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/data/repositories/price_repository.dart fuel_price_app/test/data/repositories/price_repository_test.dart
git commit -m "feat: add PriceRepository for oil prices, exchange rates, and fuel prices"
```

---

### Task 6: Settings Repository

**Files:**
- Create: `fuel_price_app/lib/data/repositories/settings_repository.dart`
- Create: `fuel_price_app/test/data/repositories/settings_repository_test.dart`

CRUD for fuel_order, fuel_visibility, notification_settings, notification_fuels tables.

- [ ] **Step 1: Write failing test**

Create `test/data/repositories/settings_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    repo = SettingsRepository(db);
  });

  tearDown(() async => await db.close());

  test('returns default fuel order', () async {
    final order = await repo.getFuelOrder();
    expect(order, ['es95', 'es100', 'eurodizel', 'unp10kg']);
  });

  test('updates fuel order', () async {
    await repo.saveFuelOrder(['eurodizel', 'es95', 'es100', 'unp10kg']);
    final order = await repo.getFuelOrder();
    expect(order.first, 'eurodizel');
  });

  test('returns default visibility (all visible)', () async {
    final vis = await repo.getFuelVisibility();
    expect(vis.values.every((v) => v), isTrue);
  });

  test('toggles fuel visibility', () async {
    await repo.setFuelVisibility('es100', false);
    final vis = await repo.getFuelVisibility();
    expect(vis['es100'], isFalse);
    expect(vis['es95'], isTrue);
  });

  test('returns default notification settings', () async {
    final settings = await repo.getNotificationSettings();
    expect(settings['day'], 'monday');
    expect(settings['hour'], 9);
    expect(settings['enabled'], 1);
  });

  test('updates notification settings', () async {
    await repo.saveNotificationSettings(day: 'saturday', hour: 10);
    final settings = await repo.getNotificationSettings();
    expect(settings['day'], 'saturday');
    expect(settings['hour'], 10);
  });

  test('returns default notification fuels (all enabled)', () async {
    final fuels = await repo.getNotificationFuels();
    expect(fuels.values.every((v) => v), isTrue);
  });

  test('toggles notification fuel', () async {
    await repo.setNotificationFuel('unp10kg', false);
    final fuels = await repo.getNotificationFuels();
    expect(fuels['unp10kg'], isFalse);
    expect(fuels['es95'], isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/repositories/settings_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement SettingsRepository**

Create `lib/data/repositories/settings_repository.dart`:
```dart
import '../database.dart';

class SettingsRepository {
  final AppDatabase db;

  SettingsRepository(this.db);

  // --- Fuel Order ---

  Future<List<String>> getFuelOrder() async {
    final rows = await db.query('fuel_order', orderBy: 'position ASC');
    return rows.map((r) => r['fuel_type'] as String).toList();
  }

  Future<void> saveFuelOrder(List<String> order) async {
    for (var i = 0; i < order.length; i++) {
      await db.update('fuel_order', {'position': i},
          where: 'fuel_type = ?', whereArgs: [order[i]]);
    }
  }

  // --- Fuel Visibility ---

  Future<Map<String, bool>> getFuelVisibility() async {
    final rows = await db.query('fuel_visibility');
    return {for (final r in rows) r['fuel_type'] as String: (r['visible'] as int) == 1};
  }

  Future<void> setFuelVisibility(String fuelType, bool visible) async {
    await db.update('fuel_visibility', {'visible': visible ? 1 : 0},
        where: 'fuel_type = ?', whereArgs: [fuelType]);
  }

  // --- Notification Settings ---

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final rows = await db.query('notification_settings');
    return rows.first;
  }

  Future<void> saveNotificationSettings({String? day, int? hour, bool? enabled}) async {
    final values = <String, dynamic>{};
    if (day != null) values['day'] = day;
    if (hour != null) values['hour'] = hour;
    if (enabled != null) values['enabled'] = enabled ? 1 : 0;
    if (values.isNotEmpty) {
      await db.update('notification_settings', values, where: 'id = 1');
    }
  }

  // --- Notification Fuels ---

  Future<Map<String, bool>> getNotificationFuels() async {
    final rows = await db.query('notification_fuels');
    return {for (final r in rows) r['fuel_type'] as String: (r['enabled'] as int) == 1};
  }

  Future<void> setNotificationFuel(String fuelType, bool enabled) async {
    await db.update('notification_fuels', {'enabled': enabled ? 1 : 0},
        where: 'fuel_type = ?', whereArgs: [fuelType]);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/repositories/settings_repository_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/data/repositories/settings_repository.dart fuel_price_app/test/data/repositories/settings_repository_test.dart
git commit -m "feat: add SettingsRepository for fuel order, visibility, and notifications"
```

---

### Task 7: Config Repository

**Files:**
- Create: `fuel_price_app/lib/data/repositories/config_repository.dart`
- Create: `fuel_price_app/test/data/repositories/config_repository_test.dart`

Manages remote config versioning — detects version changes, stores last fetch time.

- [ ] **Step 1: Write failing test**

Create `test/data/repositories/config_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/config_repository.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

void main() {
  late AppDatabase db;
  late MockRemoteConfigService mockService;
  late ConfigRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    mockService = MockRemoteConfigService();
    repo = ConfigRepository(db, mockService);
  });

  tearDown(() async => await db.close());

  test('syncConfig returns params on first fetch', () async {
    when(() => mockService.fetchParams())
        .thenAnswer((_) async => FuelParams.defaultParams);
    final result = await repo.syncConfig();
    expect(result, isNotNull);
    expect(result!.version, '2025-02-26');
  });

  test('syncConfig returns null when version unchanged', () async {
    when(() => mockService.fetchParams())
        .thenAnswer((_) async => FuelParams.defaultParams);
    await repo.syncConfig(); // first fetch — stores version
    final result = await repo.syncConfig(); // second fetch — same version
    expect(result, isNull);
  });

  test('syncConfig returns null on fetch failure', () async {
    when(() => mockService.fetchParams()).thenAnswer((_) async => null);
    final result = await repo.syncConfig();
    expect(result, isNull);
  });

  test('getLastFetchTime returns null initially', () async {
    final time = await repo.getLastFetchTime();
    expect(time, isNull);
  });

  test('getLastFetchTime returns time after sync', () async {
    when(() => mockService.fetchParams())
        .thenAnswer((_) async => FuelParams.defaultParams);
    await repo.syncConfig();
    final time = await repo.getLastFetchTime();
    expect(time, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/repositories/config_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement ConfigRepository**

Create `lib/data/repositories/config_repository.dart`:
```dart
import '../database.dart';
import '../services/remote_config_service.dart';
import '../../models/fuel_params.dart';

class ConfigRepository {
  final AppDatabase db;
  final RemoteConfigService remoteService;

  ConfigRepository(this.db, this.remoteService);

  /// Fetch remote config. Returns new params if version changed, null otherwise.
  Future<FuelParams?> syncConfig() async {
    final remote = await remoteService.fetchParams();
    if (remote == null) return null;

    final current = await _getStoredVersion();
    if (current == remote.version) return null;

    await _storeVersion(remote.version);
    return remote;
  }

  Future<String?> _getStoredVersion() async {
    final rows = await db.query('config_version');
    if (rows.isEmpty) return null;
    return rows.first['version'] as String;
  }

  Future<void> _storeVersion(String version) async {
    final existing = await db.query('config_version');
    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('config_version', {'id': 1, 'version': version, 'fetched_at': now});
    } else {
      await db.update('config_version', {'version': version, 'fetched_at': now}, where: 'id = 1');
    }
  }

  Future<DateTime?> getLastFetchTime() async {
    final rows = await db.query('config_version');
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['fetched_at'] as String);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/repositories/config_repository_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add fuel_price_app/lib/data/repositories/config_repository.dart fuel_price_app/test/data/repositories/config_repository_test.dart
git commit -m "feat: add ConfigRepository for remote config versioning"
```

---

### Task 8: Run Full Test Suite

**Files:** None (verification only)

- [ ] **Step 1: Run entire test suite**

Run: `D:/Portable/flutter/bin/flutter.bat test`
Expected: ALL PASS, 0 failures

- [ ] **Step 2: Verify all new files exist**

Check that these files were created:
- `lib/domain/formula_engine.dart`
- `lib/data/services/hnb_service.dart`
- `lib/data/services/yahoo_finance_service.dart`
- `lib/data/services/remote_config_service.dart`
- `lib/data/repositories/price_repository.dart`
- `lib/data/repositories/settings_repository.dart`
- `lib/data/repositories/config_repository.dart`
