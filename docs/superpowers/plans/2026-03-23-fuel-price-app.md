# Fuel Price Prediction App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Android/tablet Flutter app that predicts Croatian fuel prices for next Tuesday using the official formula from NN 31/2025, with a fuel list home screen, detail screens with charts, remote config for regulatory parameters, and local notifications.

**Architecture:** On-device only, no backend. Data fetched from Yahoo Finance (oil prices), HNB API (exchange rates), and GitHub raw (regulatory config). SQLite for persistence. Bloc/Cubit for state management. WorkManager for background fetch.

**Tech Stack:** Flutter (Dart), flutter_bloc, fl_chart, sqflite, dio, flutter_local_notifications, workmanager, shared_preferences

**Spec:** `docs/superpowers/specs/2026-03-23-fuel-app-v2-design.md`

---

## File Structure

```
fuel_price_app/
├── lib/
│   ├── main.dart                          — Entry point, DI setup, WorkManager init
│   ├── app.dart                           — MaterialApp, theme, routing
│   ├── models/
│   │   ├── fuel_type.dart                 — Enum: es95, es100, eurodizel, unp10kg
│   │   ├── oil_price.dart                 — Daily CIF Med price record
│   │   ├── exchange_rate.dart             — Daily EUR/USD rate record
│   │   ├── fuel_price.dart                — Calculated/actual price record
│   │   └── fuel_params.dart               — Remote config model (premiums, excise, density, regulation info)
│   ├── data/
│   │   ├── database.dart                  — SQLite schema, migrations, DB helper
│   │   ├── repositories/
│   │   │   ├── price_repository.dart      — CRUD for oil_prices, exchange_rates, predicted_prices, actual_prices
│   │   │   ├── settings_repository.dart   — Fuel order, visibility, notification prefs, disclaimer flag
│   │   │   └── config_repository.dart     — Remote config fetch, cache, version tracking
│   │   └── services/
│   │       ├── yahoo_finance_service.dart — Fetch BZ=F, RB=F, HO=F from Yahoo Finance
│   │       ├── hnb_service.dart           — Fetch EUR/USD from api.hnb.hr
│   │       └── remote_config_service.dart — Fetch fuel_params.json from GitHub
│   ├── domain/
│   │   └── formula_engine.dart            — Price calculation per NN 31/2025
│   ├── blocs/
│   │   ├── fuel_list_cubit.dart           — Home screen state (prices, order, visibility)
│   │   ├── fuel_detail_cubit.dart         — Detail screen state (prediction, chart data)
│   │   ├── settings_cubit.dart            — Settings state (all preferences)
│   │   └── data_sync_cubit.dart           — Background sync orchestration
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── fuel_list_screen.dart      — Home: reorderable list of fuels + prices
│   │   │   ├── fuel_detail_screen.dart    — PageView with prediction, chart, swipe
│   │   │   └── settings_screen.dart       — All settings sections
│   │   ├── widgets/
│   │   │   ├── fuel_list_tile.dart        — Single fuel row (name + price)
│   │   │   ├── price_display.dart         — Large predicted price + diff arrow
│   │   │   ├── price_chart.dart           — fl_chart line chart with period selector
│   │   │   └── disclaimer_dialog.dart     — First-launch modal
│   │   └── theme.dart                     — Dark/light themes, edge-to-edge config
│   └── notifications/
│       └── notification_service.dart      — Schedule/cancel local notifications
├── test/
│   ├── domain/
│   │   └── formula_engine_test.dart
│   ├── data/
│   │   ├── database_test.dart
│   │   ├── repositories/
│   │   │   ├── price_repository_test.dart
│   │   │   ├── settings_repository_test.dart
│   │   │   └── config_repository_test.dart
│   │   └── services/
│   │       ├── yahoo_finance_service_test.dart
│   │       ├── hnb_service_test.dart
│   │       └── remote_config_service_test.dart
│   ├── blocs/
│   │   ├── fuel_list_cubit_test.dart
│   │   ├── fuel_detail_cubit_test.dart
│   │   └── settings_cubit_test.dart
│   └── ui/
│       ├── fuel_list_screen_test.dart
│       └── fuel_detail_screen_test.dart
├── config/
│   └── fuel_params.json                   — Remote config file (hosted on GitHub)
└── pubspec.yaml
```

---

## Task 1: Flutter Project Scaffold + Models

**Files:**
- Create: `fuel_price_app/pubspec.yaml`
- Create: `fuel_price_app/lib/main.dart`
- Create: `fuel_price_app/lib/app.dart`
- Create: `fuel_price_app/lib/models/fuel_type.dart`
- Create: `fuel_price_app/lib/models/oil_price.dart`
- Create: `fuel_price_app/lib/models/exchange_rate.dart`
- Create: `fuel_price_app/lib/models/fuel_price.dart`
- Create: `fuel_price_app/lib/models/fuel_params.dart`
- Test: `fuel_price_app/test/models/fuel_type_test.dart`

- [ ] **Step 1: Create Flutter project**

```bash
cd D:/Projekti/test
flutter create fuel_price_app --org hr.lakaindustrija --platforms android
```

- [ ] **Step 2: Add dependencies to pubspec.yaml**

Add to `dependencies`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^9.0.0
  bloc: ^9.0.0
  sqflite: ^2.4.0
  path: ^1.9.0
  dio: ^5.7.0
  fl_chart: ^0.70.0
  flutter_local_notifications: ^18.0.0
  timezone: ^0.10.0
  workmanager: ^0.5.2
  shared_preferences: ^2.3.0
  intl: ^0.19.0
  url_launcher: ^6.3.0
  equatable: ^2.0.7

dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.2.0
  mocktail: ^1.0.4
  flutter_lints: ^5.0.0
```

Run: `cd fuel_price_app && flutter pub get`

- [ ] **Step 3: Create FuelType enum**

Create `lib/models/fuel_type.dart`:
```dart
enum FuelType {
  es95('Eurosuper 95', 'ES95', 'EUR/L'),
  es100('Eurosuper 100', 'ES100', 'EUR/L'),
  eurodizel('Eurodizel', 'ED', 'EUR/L'),
  unp10kg('UNP boca 10kg', 'UNP', 'EUR/kg');

  const FuelType(this.displayName, this.shortName, this.unit);
  final String displayName;
  final String shortName;
  final String unit;
}
```

- [ ] **Step 4: Write FuelType test**

Create `test/models/fuel_type_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

void main() {
  test('FuelType has 4 values', () {
    expect(FuelType.values.length, 4);
  });

  test('FuelType display names are correct', () {
    expect(FuelType.es95.displayName, 'Eurosuper 95');
    expect(FuelType.eurodizel.displayName, 'Eurodizel');
    expect(FuelType.unp10kg.displayName, 'UNP boca 10kg');
  });

  test('FuelType units distinguish liquid vs kg', () {
    expect(FuelType.es95.unit, 'EUR/L');
    expect(FuelType.unp10kg.unit, 'EUR/kg');
  });
}
```

Run: `flutter test test/models/fuel_type_test.dart`
Expected: PASS

- [ ] **Step 5: Create remaining model classes**

Create `lib/models/oil_price.dart`:
```dart
class OilPrice {
  final int? id;
  final DateTime date;
  final double cifMed; // USD/t from Platts
  final String source; // 'BZ=F', 'RB=F', 'HO=F'

  const OilPrice({this.id, required this.date, required this.cifMed, required this.source});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'cif_med': cifMed,
    'source': source,
  };

  factory OilPrice.fromMap(Map<String, dynamic> map) => OilPrice(
    id: map['id'] as int?,
    date: DateTime.parse(map['date'] as String),
    cifMed: (map['cif_med'] as num).toDouble(),
    source: map['source'] as String,
  );
}
```

Create `lib/models/exchange_rate.dart`:
```dart
class ExchangeRate {
  final int? id;
  final DateTime date;
  final double usdEur; // 1 USD = X EUR

  const ExchangeRate({this.id, required this.date, required this.usdEur});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'usd_eur': usdEur,
  };

  factory ExchangeRate.fromMap(Map<String, dynamic> map) => ExchangeRate(
    id: map['id'] as int?,
    date: DateTime.parse(map['date'] as String),
    usdEur: (map['usd_eur'] as num).toDouble(),
  );
}
```

Create `lib/models/fuel_price.dart`:
```dart
import 'fuel_type.dart';

class FuelPrice {
  final int? id;
  final FuelType fuelType;
  final DateTime date; // Tuesday when price takes effect
  final double price; // EUR/L or EUR/kg
  final bool isPrediction;

  const FuelPrice({
    this.id,
    required this.fuelType,
    required this.date,
    required this.price,
    required this.isPrediction,
  });

  /// Rounded to 2 decimal places per regulation
  double get roundedPrice => (price * 100).round() / 100;

  String get formattedPrice => roundedPrice.toStringAsFixed(2);

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'fuel_type': fuelType.name,
    'date': date.toIso8601String().substring(0, 10),
    'price': price,
    'is_prediction': isPrediction ? 1 : 0,
  };

  factory FuelPrice.fromMap(Map<String, dynamic> map) => FuelPrice(
    id: map['id'] as int?,
    fuelType: FuelType.values.byName(map['fuel_type'] as String),
    date: DateTime.parse(map['date'] as String),
    price: (map['price'] as num).toDouble(),
    isPrediction: (map['is_prediction'] as int) == 1,
  );
}
```

Create `lib/models/fuel_params.dart`:
```dart
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

  const FuelParams({
    required this.version,
    required this.priceRegulation,
    required this.exciseRegulation,
    required this.premiums,
    required this.exciseDuties,
    required this.density,
    required this.vatRate,
  });

  factory FuelParams.fromJson(Map<String, dynamic> json) => FuelParams(
    version: json['version'] as String,
    priceRegulation: RegulationInfo.fromJson(json['price_regulation'] as Map<String, dynamic>),
    exciseRegulation: RegulationInfo.fromJson(json['excise_regulation'] as Map<String, dynamic>),
    premiums: (json['premiums'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
    exciseDuties: (json['excise_duties'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
    density: (json['density'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble())),
    vatRate: (json['vat_rate'] as num).toDouble(),
  );

  /// Built-in defaults matching NN 31/2025 + NN 156/2022 consolidated
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
  );
}
```

- [ ] **Step 6: Run all tests**

```bash
flutter test
```
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add fuel_price_app/
git commit -m "feat: scaffold Flutter project with models and dependencies"
```

---

## Task 2: SQLite Database Layer

**Files:**
- Create: `fuel_price_app/lib/data/database.dart`
- Test: `fuel_price_app/test/data/database_test.dart`

- [ ] **Step 1: Write database schema test**

Create `test/data/database_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';

void main() {
  late AppDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
  });

  tearDown(() async {
    await db.close();
  });

  test('creates all tables', () async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    final names = tables.map((t) => t['name'] as String).toSet();
    expect(names, containsAll([
      'oil_prices', 'exchange_rates', 'fuel_prices',
      'fuel_order', 'fuel_visibility', 'notification_settings',
      'config_version',
    ]));
  });

  test('oil_prices insert and query', () async {
    await db.insert('oil_prices', {
      'date': '2026-03-20',
      'cif_med': 650.5,
      'source': 'BZ=F',
    });
    final rows = await db.query('oil_prices');
    expect(rows.length, 1);
    expect(rows.first['cif_med'], 650.5);
  });
}
```

Add `sqflite_common_ffi` to `dev_dependencies` in pubspec.yaml for testing.

Run: `flutter test test/data/database_test.dart`
Expected: FAIL (AppDatabase doesn't exist)

- [ ] **Step 2: Implement AppDatabase**

Create `lib/data/database.dart`:
```dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  Database? _db;
  final bool inMemory;

  AppDatabase({this.inMemory = false});

  Future<Database> get database async {
    _db ??= await init();
    return _db!;
  }

  Future<Database> init() async {
    final path = inMemory ? inMemoryDatabasePath : join(await getDatabasesPath(), 'fuel_prices.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE oil_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        cif_med REAL NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE exchange_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        usd_eur REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fuel_type TEXT NOT NULL,
        date TEXT NOT NULL,
        price REAL NOT NULL,
        is_prediction INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_order (
        fuel_type TEXT PRIMARY KEY,
        position INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_visibility (
        fuel_type TEXT PRIMARY KEY,
        visible INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE notification_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        enabled INTEGER NOT NULL DEFAULT 1,
        day TEXT NOT NULL DEFAULT 'monday',
        hour INTEGER NOT NULL DEFAULT 9
      )
    ''');
    await db.execute('''
      CREATE TABLE notification_fuels (
        fuel_type TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE config_version (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        version TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');

    // Seed default fuel order and visibility
    for (final (i, ft) in FuelTypeHelper.allNames.indexed) {
      await db.insert('fuel_order', {'fuel_type': ft, 'position': i});
      await db.insert('fuel_visibility', {'fuel_type': ft, 'visible': 1});
      await db.insert('notification_fuels', {'fuel_type': ft, 'enabled': 1});
    }
    await db.insert('notification_settings', {'id': 1, 'enabled': 1, 'day': 'monday', 'hour': 9});
  }

  Future<List<Map<String, dynamic>>> query(String table, {String? where, List<dynamic>? whereArgs, String? orderBy}) =>
      _db!.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);

  Future<int> insert(String table, Map<String, dynamic> values) =>
      _db!.insert(table, values);

  Future<int> update(String table, Map<String, dynamic> values, {String? where, List<dynamic>? whereArgs}) =>
      _db!.update(table, values, where: where, whereArgs: whereArgs);

  Future<int> delete(String table, {String? where, List<dynamic>? whereArgs}) =>
      _db!.delete(table, where: where, whereArgs: whereArgs);

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) =>
      _db!.rawQuery(sql, args);

  Future<void> close() async => await _db?.close();
}

class FuelTypeHelper {
  static const allNames = ['es95', 'es100', 'eurodizel', 'unp10kg'];
}
```

- [ ] **Step 3: Run test to verify it passes**

```bash
flutter test test/data/database_test.dart
```
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add SQLite database with schema and migrations"
```

---

## Task 3: Formula Engine

**Files:**
- Create: `fuel_price_app/lib/domain/formula_engine.dart`
- Test: `fuel_price_app/test/domain/formula_engine_test.dart`

This is the core business logic per NN 31/2025:
- `PC = [(Σ CIF_Med_M × ρ ÷ T) ÷ n] + P`
- `retail = (PC + trošarina) × 1.25` (VAT 25%)
- Round final to 2 decimals

- [ ] **Step 1: Write formula engine tests**

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
    test('calculates for ES95 with known CIF Med values', () {
      // Example: 14 days, CIF Med avg = 700 USD/t, avg EUR/USD rate = 0.92
      final dailyPrices = List.generate(14, (_) => 700.0); // USD/t
      final dailyRates = List.generate(14, (_) => 0.92);   // 1 USD = 0.92 EUR
      // PC = [(Σ CIF × ρ / T) / n] + P
      // = [(14 × 700 × 0.755 / 0.92) / 14] + 0.1545
      // = [700 × 0.755 / 0.92] + 0.1545
      // = 574.4565... + 0.1545
      // = 574.611...  -- wait that's in EUR/t, need /1000
      // Actually CIF is USD/t, formula divides by 1000 implicitly via density
      // PC = Σ(CIF_i × ρ / T_i) / (n × 1000) + P
      // Hmm, let me re-derive. The formula from the regulation:
      // PC = [(Σ CIF Med M × ρ ÷ T) ÷ n] + P
      // CIF Med M is in USD/t, ρ is kg/L, T is USD/EUR rate
      // (CIF × ρ / T) gives EUR/1000L... no, let's think:
      // CIF [USD/t] × ρ [kg/L] / T [USD/EUR] = USD/t × kg/L × EUR/USD = EUR×kg/(t×L)
      // Since 1 t = 1000 kg: EUR×kg/(1000kg×L) = EUR/(1000L)
      // So we need to divide by 1000 to get EUR/L
      // PC = [Σ(CIF_i × ρ / T_i) / (n × 1000)] + P
      final pc = engine.calculateBasePrice(
        FuelType.es95,
        dailyPrices,
        dailyRates,
      );
      // = (700 × 0.755 / 0.92) / 1000 + 0.1545
      // = 574.4565 / 1000 + 0.1545
      // = 0.5745 + 0.1545 = 0.7290
      expect(pc, closeTo(0.7290, 0.001));
    });

    test('calculates retail price with excise and VAT', () {
      final pc = 0.7290;
      // retail = (PC + trošarina) × (1 + VAT)
      // = (0.7290 + 0.4560) × 1.25
      // = 1.1850 × 1.25
      // = 1.48125
      final retail = engine.calculateRetailPrice(FuelType.es95, pc);
      expect(retail, closeTo(1.48125, 0.001));
    });

    test('rounds final price to 2 decimals', () {
      expect(FormulaEngine.roundPrice(1.48125), 1.48);
      expect(FormulaEngine.roundPrice(1.485), 1.49);
      expect(FormulaEngine.roundPrice(1.4999), 1.50);
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
  });
}
```

Run: `flutter test test/domain/formula_engine_test.dart`
Expected: FAIL (FormulaEngine doesn't exist)

- [ ] **Step 2: Implement FormulaEngine**

Create `lib/domain/formula_engine.dart`:
```dart
import '../models/fuel_type.dart';
import '../models/fuel_params.dart';

class FormulaEngine {
  final FuelParams params;

  FormulaEngine(this.params);

  /// Calculate base price (PC) per NN 31/2025 formula.
  /// PC = [Σ(CIF_Med × ρ / T) / (n × 1000)] + P
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

    if (density == null) {
      // UNP uses LPG formula per NN 31/2025:
      // PC = {[P_CIF(propane) + P_CIF(butane)] / 2} × T_avg_inv / 1000 + P
      // Since we use a single Brent proxy, approximate:
      // treat cifMedPrices as propane-butane average in USD/t
      double sum = 0;
      for (var i = 0; i < n; i++) {
        sum += cifMedPrices[i] / exchangeRates[i];
      }
      return sum / (n * 1000) + premium;
    }

    double sum = 0;
    for (var i = 0; i < n; i++) {
      sum += cifMedPrices[i] * density / exchangeRates[i];
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

- [ ] **Step 3: Run tests**

```bash
flutter test test/domain/formula_engine_test.dart
```
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add formula engine for fuel price calculation per NN 31/2025"
```

---

## Task 4: API Services (Yahoo Finance + HNB)

**Files:**
- Create: `fuel_price_app/lib/data/services/yahoo_finance_service.dart`
- Create: `fuel_price_app/lib/data/services/hnb_service.dart`
- Test: `fuel_price_app/test/data/services/yahoo_finance_service_test.dart`
- Test: `fuel_price_app/test/data/services/hnb_service_test.dart`

- [ ] **Step 1: Write HNB service test**

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
}
```

Run: `flutter test test/data/services/hnb_service_test.dart`
Expected: FAIL

- [ ] **Step 2: Implement HNB service**

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
    // HNB uses comma as decimal separator
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

- [ ] **Step 3: Run HNB test**

```bash
flutter test test/data/services/hnb_service_test.dart
```
Expected: PASS

- [ ] **Step 4: Write Yahoo Finance service test**

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

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
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
  });
}
```

- [ ] **Step 5: Implement Yahoo Finance service**

Create `lib/data/services/yahoo_finance_service.dart`:
```dart
import 'package:dio/dio.dart';

class YahooFinancePrice {
  final DateTime date;
  final double close; // USD

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

- [ ] **Step 6: Run all service tests**

```bash
flutter test test/data/services/
```
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Yahoo Finance and HNB API services"
```

---

## Task 5: Remote Config Service

**Files:**
- Create: `fuel_price_app/lib/data/services/remote_config_service.dart`
- Create: `fuel_price_app/config/fuel_params.json`
- Test: `fuel_price_app/test/data/services/remote_config_service_test.dart`

- [ ] **Step 1: Create the remote config JSON file**

Create `config/fuel_params.json` with the exact contents from the spec (section 5).

- [ ] **Step 2: Write remote config service test**

Create `test/data/services/remote_config_service_test.dart`:
```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

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
    expect(params.version, '2025-02-26');
    expect(params.vatRate, 0.25);
    expect(params.exciseDuties['es95'], 0.456);
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

- [ ] **Step 3: Implement RemoteConfigService**

Create `lib/data/services/remote_config_service.dart`:
```dart
import 'package:dio/dio.dart';
import '../../models/fuel_params.dart';

class RemoteConfigService {
  final Dio dio;
  /// Set this URL after the GitHub repository is created.
  /// Format: https://raw.githubusercontent.com/{owner}/{repo}/main/config/fuel_params.json
  /// This can also be overridden via remote config or build flavors.
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

- [ ] **Step 4: Run tests**

```bash
flutter test test/data/services/remote_config_service_test.dart
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add remote config service and fuel_params.json"
```

---

## Task 6: Repositories

**Files:**
- Create: `fuel_price_app/lib/data/repositories/price_repository.dart`
- Create: `fuel_price_app/lib/data/repositories/rate_repository.dart`
- Create: `fuel_price_app/lib/data/repositories/settings_repository.dart`
- Create: `fuel_price_app/lib/data/repositories/config_repository.dart`
- Test: `fuel_price_app/test/data/repositories/price_repository_test.dart`
- Test: `fuel_price_app/test/data/repositories/settings_repository_test.dart`

- [ ] **Step 1: Write price repository test**

Create `test/data/repositories/price_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/oil_price.dart';

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

  test('deletes old records', () async {
    final old = OilPrice(date: DateTime(2023, 1, 1), cifMed: 500, source: 'BZ=F');
    await repo.saveOilPrice(old);
    await repo.cleanOldData(Duration(days: 730));
    final prices = await repo.getOilPrices('BZ=F', days: 9999);
    expect(prices, isEmpty);
  });
}
```

Run: `flutter test test/data/repositories/price_repository_test.dart`
Expected: FAIL

- [ ] **Step 2: Implement PriceRepository**

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

- [ ] **Step 3: Run price repository test**

```bash
flutter test test/data/repositories/price_repository_test.dart
```
Expected: PASS

- [ ] **Step 4: Write settings repository test**

Create `test/data/repositories/settings_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

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
}
```

Run: `flutter test test/data/repositories/settings_repository_test.dart`
Expected: FAIL

- [ ] **Step 5: Implement SettingsRepository**

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
    if (enabled != null) values['enabled'] = enabled! ? 1 : 0;
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

  // --- Disclaimer ---

  Future<bool> isDisclaimerAcknowledged() async {
    // Using shared_preferences for simple flags
    return false; // implemented via SharedPreferences in the cubit
  }
}
```

- [ ] **Step 6: Implement ConfigRepository**

Create `lib/data/repositories/config_repository.dart`:
```dart
import '../database.dart';
import '../services/remote_config_service.dart';
import '../../models/fuel_params.dart';

class ConfigRepository {
  final AppDatabase db;
  final RemoteConfigService remoteService;

  ConfigRepository(this.db, this.remoteService);

  /// Fetch remote config. Returns new params if updated, null if unchanged or failed.
  Future<FuelParams?> syncConfig() async {
    final remote = await remoteService.fetchParams();
    if (remote == null) return null;

    final current = await _getStoredVersion();
    if (current == remote.version) return null;

    await _storeVersion(remote.version);
    return remote;
  }

  /// Get active params: stored remote version or built-in defaults.
  FuelParams getActiveParams() {
    // For simplicity, the remote params are stored in memory after sync.
    // The formula engine always uses whatever params are passed to it.
    return FuelParams.defaultParams;
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

- [ ] **Step 7: Run all repository tests**

```bash
flutter test test/data/repositories/
```
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add repositories for prices, settings, and remote config"
```

---

## Task 7: Cubits (State Management)

**Files:**
- Create: `fuel_price_app/lib/blocs/fuel_list_cubit.dart`
- Create: `fuel_price_app/lib/blocs/fuel_detail_cubit.dart`
- Create: `fuel_price_app/lib/blocs/settings_cubit.dart`
- Create: `fuel_price_app/lib/blocs/data_sync_cubit.dart`
- Test: `fuel_price_app/test/blocs/fuel_list_cubit_test.dart`

- [ ] **Step 1: Write FuelListCubit test**

Create `test/blocs/fuel_list_cubit_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';

class MockPriceRepository extends Mock implements PriceRepository {}
class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late MockPriceRepository priceRepo;
  late MockSettingsRepository settingsRepo;

  setUp(() {
    priceRepo = MockPriceRepository();
    settingsRepo = MockSettingsRepository();
  });

  blocTest<FuelListCubit, FuelListState>(
    'loads fuels in user order with current prices',
    build: () {
      when(() => settingsRepo.getFuelOrder())
          .thenAnswer((_) async => ['eurodizel', 'es95', 'es100', 'unp10kg']);
      when(() => settingsRepo.getFuelVisibility())
          .thenAnswer((_) async => {'es95': true, 'es100': true, 'eurodizel': true, 'unp10kg': true});
      when(() => priceRepo.getLatestPrice(any(), prediction: false))
          .thenAnswer((_) async => FuelPrice(
            fuelType: FuelType.es95, date: DateTime(2026, 3, 18), price: 1.48, isPrediction: false,
          ));
      return FuelListCubit(priceRepo: priceRepo, settingsRepo: settingsRepo);
    },
    act: (cubit) => cubit.load(),
    expect: () => [
      isA<FuelListState>().having((s) => s.status, 'status', FuelListStatus.loading),
      isA<FuelListState>()
          .having((s) => s.status, 'status', FuelListStatus.loaded)
          .having((s) => s.fuels.first.fuelType.name, 'first fuel', 'eurodizel'),
    ],
  );
}
```

Run: `flutter test test/blocs/fuel_list_cubit_test.dart`
Expected: FAIL

- [ ] **Step 2: Implement FuelListCubit**

Create `lib/blocs/fuel_list_cubit.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/repositories/price_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../models/fuel_type.dart';
import '../models/fuel_price.dart';

enum FuelListStatus { initial, loading, loaded, error }

class FuelListItem {
  final FuelType fuelType;
  final FuelPrice? currentPrice;

  FuelListItem({required this.fuelType, this.currentPrice});
}

class FuelListState extends Equatable {
  final FuelListStatus status;
  final List<FuelListItem> fuels;
  final String? error;

  const FuelListState({
    this.status = FuelListStatus.initial,
    this.fuels = const [],
    this.error,
  });

  FuelListState copyWith({FuelListStatus? status, List<FuelListItem>? fuels, String? error}) =>
      FuelListState(
        status: status ?? this.status,
        fuels: fuels ?? this.fuels,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [status, fuels, error];
}

class FuelListCubit extends Cubit<FuelListState> {
  final PriceRepository priceRepo;
  final SettingsRepository settingsRepo;

  FuelListCubit({required this.priceRepo, required this.settingsRepo})
      : super(const FuelListState());

  Future<void> load() async {
    emit(state.copyWith(status: FuelListStatus.loading));
    try {
      final order = await settingsRepo.getFuelOrder();
      final visibility = await settingsRepo.getFuelVisibility();

      final fuels = <FuelListItem>[];
      for (final name in order) {
        if (visibility[name] != true) continue;
        final fuelType = FuelType.values.byName(name);
        final price = await priceRepo.getLatestPrice(fuelType, prediction: false);
        fuels.add(FuelListItem(fuelType: fuelType, currentPrice: price));
      }

      emit(state.copyWith(status: FuelListStatus.loaded, fuels: fuels));
    } catch (e) {
      emit(state.copyWith(status: FuelListStatus.error, error: e.toString()));
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final items = List<FuelListItem>.from(state.fuels);
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    emit(state.copyWith(fuels: items));
    await settingsRepo.saveFuelOrder(items.map((i) => i.fuelType.name).toList());
  }
}
```

- [ ] **Step 3: Run cubit test**

```bash
flutter test test/blocs/fuel_list_cubit_test.dart
```
Expected: PASS

- [ ] **Step 4: Implement FuelDetailCubit and SettingsCubit**

Create `lib/blocs/fuel_detail_cubit.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/repositories/price_repository.dart';
import '../models/fuel_type.dart';
import '../models/fuel_price.dart';

class FuelDetailState extends Equatable {
  final FuelType fuelType;
  final FuelPrice? currentPrice;
  final FuelPrice? predictedPrice;
  final List<FuelPrice> history;
  final int chartDays;
  final bool loading;

  const FuelDetailState({
    required this.fuelType,
    this.currentPrice,
    this.predictedPrice,
    this.history = const [],
    this.chartDays = 30,
    this.loading = false,
  });

  double? get priceDifference {
    if (currentPrice == null || predictedPrice == null) return null;
    return predictedPrice!.roundedPrice - currentPrice!.roundedPrice;
  }

  FuelDetailState copyWith({
    FuelPrice? currentPrice,
    FuelPrice? predictedPrice,
    List<FuelPrice>? history,
    int? chartDays,
    bool? loading,
  }) => FuelDetailState(
    fuelType: fuelType,
    currentPrice: currentPrice ?? this.currentPrice,
    predictedPrice: predictedPrice ?? this.predictedPrice,
    history: history ?? this.history,
    chartDays: chartDays ?? this.chartDays,
    loading: loading ?? this.loading,
  );

  @override
  List<Object?> get props => [fuelType, currentPrice, predictedPrice, history, chartDays, loading];
}

class FuelDetailCubit extends Cubit<FuelDetailState> {
  final PriceRepository priceRepo;

  FuelDetailCubit({required this.priceRepo, required FuelType fuelType})
      : super(FuelDetailState(fuelType: fuelType));

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final current = await priceRepo.getLatestPrice(state.fuelType, prediction: false);
    final predicted = await priceRepo.getLatestPrice(state.fuelType, prediction: true);
    final history = await priceRepo.getPriceHistory(state.fuelType, days: state.chartDays);
    emit(state.copyWith(
      currentPrice: current,
      predictedPrice: predicted,
      history: history,
      loading: false,
    ));
  }

  Future<void> setChartPeriod(int days) async {
    emit(state.copyWith(chartDays: days, loading: true));
    final history = await priceRepo.getPriceHistory(state.fuelType, days: days);
    emit(state.copyWith(history: history, loading: false));
  }
}
```

Create `lib/blocs/settings_cubit.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/config_repository.dart';
import '../models/fuel_params.dart';

class SettingsState extends Equatable {
  final Map<String, bool> fuelVisibility;
  final Map<String, bool> notificationFuels;
  final String notificationDay;
  final int notificationHour;
  final bool notificationsEnabled;
  final bool disclaimerAcknowledged;
  final FuelParams params;
  final ThemeMode themeMode;
  final DateTime? lastConfigFetch;

  const SettingsState({
    this.fuelVisibility = const {},
    this.notificationFuels = const {},
    this.notificationDay = 'monday',
    this.notificationHour = 9,
    this.notificationsEnabled = true,
    this.disclaimerAcknowledged = false,
    this.params = FuelParams.defaultParams,
    this.themeMode = ThemeMode.system,
    this.lastConfigFetch,
  });

  SettingsState copyWith({
    Map<String, bool>? fuelVisibility,
    Map<String, bool>? notificationFuels,
    String? notificationDay,
    int? notificationHour,
    bool? notificationsEnabled,
    bool? disclaimerAcknowledged,
    FuelParams? params,
    ThemeMode? themeMode,
    DateTime? lastConfigFetch,
  }) => SettingsState(
    fuelVisibility: fuelVisibility ?? this.fuelVisibility,
    notificationFuels: notificationFuels ?? this.notificationFuels,
    notificationDay: notificationDay ?? this.notificationDay,
    notificationHour: notificationHour ?? this.notificationHour,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    disclaimerAcknowledged: disclaimerAcknowledged ?? this.disclaimerAcknowledged,
    params: params ?? this.params,
    themeMode: themeMode ?? this.themeMode,
    lastConfigFetch: lastConfigFetch ?? this.lastConfigFetch,
  );

  @override
  List<Object?> get props => [fuelVisibility, notificationFuels, notificationDay,
    notificationHour, notificationsEnabled, disclaimerAcknowledged, params, themeMode, lastConfigFetch];
}

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsRepository settingsRepo;
  final ConfigRepository configRepo;

  SettingsCubit({required this.settingsRepo, required this.configRepo})
      : super(const SettingsState());

  Future<void> load() async {
    final vis = await settingsRepo.getFuelVisibility();
    final notifFuels = await settingsRepo.getNotificationFuels();
    final notifSettings = await settingsRepo.getNotificationSettings();
    final prefs = await SharedPreferences.getInstance();
    final disclaimerAck = prefs.getBool('disclaimer_acknowledged') ?? false;
    final themePref = prefs.getString('theme_mode') ?? 'system';
    final themeMode = switch (themePref) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final lastFetch = await configRepo.getLastFetchTime();

    emit(state.copyWith(
      fuelVisibility: vis,
      notificationFuels: notifFuels,
      notificationDay: notifSettings['day'] as String,
      notificationHour: notifSettings['hour'] as int,
      notificationsEnabled: (notifSettings['enabled'] as int) == 1,
      disclaimerAcknowledged: disclaimerAck,
      themeMode: themeMode,
      lastConfigFetch: lastFetch,
    ));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setString('theme_mode', value);
    emit(state.copyWith(themeMode: mode));
  }

  Future<void> setFuelVisibility(String fuel, bool visible) async {
    await settingsRepo.setFuelVisibility(fuel, visible);
    final updated = Map<String, bool>.from(state.fuelVisibility)..[fuel] = visible;
    emit(state.copyWith(fuelVisibility: updated));
  }

  Future<void> setNotificationFuel(String fuel, bool enabled) async {
    await settingsRepo.setNotificationFuel(fuel, enabled);
    final updated = Map<String, bool>.from(state.notificationFuels)..[fuel] = enabled;
    emit(state.copyWith(notificationFuels: updated));
  }

  Future<void> setNotificationDay(String day) async {
    await settingsRepo.saveNotificationSettings(day: day);
    emit(state.copyWith(notificationDay: day));
  }

  Future<void> setNotificationHour(int hour) async {
    await settingsRepo.saveNotificationSettings(hour: hour);
    emit(state.copyWith(notificationHour: hour));
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await settingsRepo.saveNotificationSettings(enabled: enabled);
    emit(state.copyWith(notificationsEnabled: enabled));
  }

  Future<void> acknowledgeDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclaimer_acknowledged', true);
    emit(state.copyWith(disclaimerAcknowledged: true));
  }
}
```

Create `lib/blocs/data_sync_cubit.dart`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/repositories/price_repository.dart';
import '../data/repositories/config_repository.dart';
import '../data/services/yahoo_finance_service.dart';
import '../data/services/hnb_service.dart';
import '../domain/formula_engine.dart';
import '../models/fuel_type.dart';
import '../models/fuel_price.dart';
import '../models/oil_price.dart';
import '../models/exchange_rate.dart';
import '../models/fuel_params.dart';

class DataSyncCubit extends Cubit<bool> {
  final PriceRepository priceRepo;
  final ConfigRepository configRepo;
  final YahooFinanceService yahooService;
  final HnbService hnbService;

  DataSyncCubit({
    required this.priceRepo,
    required this.configRepo,
    required this.yahooService,
    required this.hnbService,
  }) : super(false); // false = not syncing

  Future<void> sync() async {
    if (state) return; // already syncing
    emit(true);

    try {
      // 1. Check for config updates
      final newParams = await configRepo.syncConfig();
      final params = newParams ?? FuelParams.defaultParams;

      // 2. Fetch oil prices (last 30 days to cover 14 working days)
      final brent = await yahooService.fetchHistoricalPrices('BZ=F', 30);
      for (final p in brent) {
        await priceRepo.saveOilPrice(OilPrice(date: p.date, cifMed: p.close, source: 'BZ=F'));
      }

      // 3. Fetch exchange rate
      final rate = await hnbService.fetchUsdEurRate();
      await priceRepo.saveExchangeRate(ExchangeRate(date: DateTime.now(), usdEur: rate));

      // 4. Calculate predictions for each fuel type
      final engine = FormulaEngine(params);
      final rates = await priceRepo.getExchangeRates(days: 30);
      final nextTuesday = _nextTuesday();

      for (final fuelType in FuelType.values) {
        // Use Brent as proxy for now — proper mapping per fuel type can be refined
        final prices = await priceRepo.getOilPrices('BZ=F', days: 30);
        if (prices.length >= 10 && rates.length >= 10) {
          // Take last 14 working days (approximate)
          final recentPrices = prices.reversed.take(14).toList().reversed.toList();
          final recentRates = rates.reversed.take(14).toList().reversed.toList();

          final predicted = engine.predictPrice(
            fuelType,
            recentPrices.map((p) => p.cifMed).toList(),
            recentRates.map((r) => r.usdEur).toList(),
          );

          await priceRepo.saveFuelPrice(FuelPrice(
            fuelType: fuelType,
            date: nextTuesday,
            price: predicted,
            isPrediction: true,
          ));
        }
      }

      // 5. Clean old data (>2 years)
      await priceRepo.cleanOldData(const Duration(days: 730));
    } catch (_) {
      // Silently fail — data will be retried next cycle
    }

    emit(false);
  }

  DateTime _nextTuesday() {
    var d = DateTime.now();
    while (d.weekday != DateTime.tuesday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }
}
```

- [ ] **Step 5: Run all bloc tests**

```bash
flutter test test/blocs/
```
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add cubits for fuel list, detail, settings, and data sync"
```

---

## Task 8: Theme + App Shell

**Files:**
- Create: `fuel_price_app/lib/ui/theme.dart`
- Modify: `fuel_price_app/lib/app.dart`
- Modify: `fuel_price_app/lib/main.dart`

- [ ] **Step 1: Create theme**

Create `lib/ui/theme.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    brightness: Brightness.light,
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
      ),
    ),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    brightness: Brightness.dark,
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
      ),
    ),
  );
}
```

- [ ] **Step 2: Create App widget**

Update `lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/fuel_list_cubit.dart';
import 'blocs/settings_cubit.dart';
import 'blocs/data_sync_cubit.dart';
import 'data/database.dart';
import 'data/repositories/price_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/config_repository.dart';
import 'data/services/yahoo_finance_service.dart';
import 'data/services/hnb_service.dart';
import 'data/services/remote_config_service.dart';
import 'ui/theme.dart';
import 'ui/screens/fuel_list_screen.dart';

class FuelPriceApp extends StatelessWidget {
  final AppDatabase database;

  const FuelPriceApp({super.key, required this.database});

  @override
  Widget build(BuildContext context) {
    final priceRepo = PriceRepository(database);
    final settingsRepo = SettingsRepository(database);
    final configRepo = ConfigRepository(database, RemoteConfigService());

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: priceRepo),
        RepositoryProvider.value(value: settingsRepo),
        RepositoryProvider.value(value: configRepo),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => FuelListCubit(
            priceRepo: priceRepo,
            settingsRepo: settingsRepo,
          )..load()),
          BlocProvider(create: (_) => SettingsCubit(
            settingsRepo: settingsRepo,
            configRepo: configRepo,
          )..load()),
          BlocProvider(create: (_) => DataSyncCubit(
            priceRepo: priceRepo,
            configRepo: configRepo,
            yahooService: YahooFinanceService(),
            hnbService: HnbService(),
          )),
        ],
        child: BlocBuilder<SettingsCubit, SettingsState>(
          buildWhen: (prev, curr) => prev.themeMode != curr.themeMode,
          builder: (context, settings) => MaterialApp(
            title: 'Cijene Goriva',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: const FuelListScreen(),
            debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Create main.dart**

Update `lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/database.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final db = AppDatabase();
  await db.init();

  runApp(FuelPriceApp(database: db));
}
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add theme, app shell with DI, and edge-to-edge config"
```

---

## Task 9: Home Screen — Fuel List with Drag & Drop

**Files:**
- Create: `fuel_price_app/lib/ui/screens/fuel_list_screen.dart`
- Create: `fuel_price_app/lib/ui/widgets/fuel_list_tile.dart`
- Test: `fuel_price_app/test/ui/fuel_list_screen_test.dart`

- [ ] **Step 1: Write widget test**

Create `test/ui/fuel_list_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/ui/screens/fuel_list_screen.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';

class MockFuelListCubit extends Mock implements FuelListCubit {}

void main() {
  late MockFuelListCubit cubit;

  setUp(() {
    cubit = MockFuelListCubit();
    when(() => cubit.state).thenReturn(FuelListState(
      status: FuelListStatus.loaded,
      fuels: [
        FuelListItem(fuelType: FuelType.es95, currentPrice: FuelPrice(
          fuelType: FuelType.es95, date: DateTime(2026, 3, 18), price: 1.48, isPrediction: false,
        )),
        FuelListItem(fuelType: FuelType.eurodizel, currentPrice: FuelPrice(
          fuelType: FuelType.eurodizel, date: DateTime(2026, 3, 18), price: 1.55, isPrediction: false,
        )),
      ],
    ));
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.close()).thenAnswer((_) async {});
  });

  testWidgets('displays fuel names and prices', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<FuelListCubit>.value(
        value: cubit,
        child: const FuelListScreen(),
      ),
    ));

    expect(find.text('Eurosuper 95'), findsOneWidget);
    expect(find.text('1,48 €'), findsOneWidget);
    expect(find.text('Eurodizel'), findsOneWidget);
    expect(find.text('1,55 €'), findsOneWidget);
  });
}
```

Run: `flutter test test/ui/fuel_list_screen_test.dart`
Expected: FAIL

- [ ] **Step 2: Implement FuelListTile**

Create `lib/ui/widgets/fuel_list_tile.dart`:
```dart
import 'package:flutter/material.dart';
import '../../blocs/fuel_list_cubit.dart';

class FuelListTile extends StatelessWidget {
  final FuelListItem item;
  final VoidCallback onTap;

  const FuelListTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final price = item.currentPrice;
    final priceText = price != null
        ? '${price.formattedPrice.replaceAll('.', ',')} €'
        : '—';

    return ListTile(
      title: Text(item.fuelType.displayName, style: const TextStyle(fontSize: 18)),
      trailing: Text(priceText, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 3: Implement FuelListScreen**

Create `lib/ui/screens/fuel_list_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/fuel_list_cubit.dart';
import '../../blocs/data_sync_cubit.dart';
import '../widgets/fuel_list_tile.dart';
import 'fuel_detail_screen.dart';
import 'settings_screen.dart';

class FuelListScreen extends StatelessWidget {
  const FuelListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cijene Goriva'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: BlocBuilder<FuelListCubit, FuelListState>(
        builder: (context, state) {
          if (state.status == FuelListStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == FuelListStatus.error) {
            return Center(child: Text('Greška: ${state.error}'));
          }
          if (state.fuels.isEmpty) {
            return const Center(child: Text('Nema goriva za prikaz'));
          }

          return RefreshIndicator(
            onRefresh: () => context.read<DataSyncCubit>().sync(),
            child: ReorderableListView.builder(
              itemCount: state.fuels.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                context.read<FuelListCubit>().reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final item = state.fuels[index];
                return FuelListTile(
                  key: ValueKey(item.fuelType),
                  item: item,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FuelDetailScreen(
                      initialIndex: index,
                      fuelTypes: state.fuels.map((f) => f.fuelType).toList(),
                    ),
                  )),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run widget test**

```bash
flutter test test/ui/fuel_list_screen_test.dart
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add home screen with reorderable fuel list"
```

---

## Task 10: Detail Screen — Prediction, Chart, Swipe

**Files:**
- Create: `fuel_price_app/lib/ui/screens/fuel_detail_screen.dart`
- Create: `fuel_price_app/lib/ui/widgets/price_display.dart`
- Create: `fuel_price_app/lib/ui/widgets/price_chart.dart`

- [ ] **Step 1: Implement PriceDisplay widget**

Create `lib/ui/widgets/price_display.dart`:
```dart
import 'package:flutter/material.dart';
import '../../models/fuel_price.dart';

class PriceDisplay extends StatelessWidget {
  final FuelPrice? predicted;
  final FuelPrice? current;
  final DateTime? lastChangeDate;

  const PriceDisplay({super.key, this.predicted, this.current, this.lastChangeDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = (predicted != null && current != null)
        ? predicted!.roundedPrice - current!.roundedPrice
        : null;

    Color diffColor = Colors.grey;
    String diffIcon = '';
    if (diff != null) {
      if (diff > 0) {
        diffColor = Colors.red;
        diffIcon = ' ↑';
      } else if (diff < 0) {
        diffColor = Colors.green;
        diffIcon = ' ↓';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Predviđena cijena', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          predicted != null ? '${predicted!.formattedPrice.replaceAll('.', ',')} €' : '—',
          style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (diff != null)
          Text(
            '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2).replaceAll('.', ',')} €$diffIcon',
            style: theme.textTheme.titleLarge?.copyWith(color: diffColor),
          ),
        if (lastChangeDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Zadnja izmjena: ${lastChangeDate!.day}.${lastChangeDate!.month.toString().padLeft(2, '0')}.${lastChangeDate!.year}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Implement PriceChart widget**

Create `lib/ui/widgets/price_chart.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/fuel_price.dart';

class PriceChart extends StatelessWidget {
  final List<FuelPrice> history;
  final int selectedDays;
  final ValueChanged<int> onPeriodChanged;

  const PriceChart({
    super.key,
    required this.history,
    required this.selectedDays,
    required this.onPeriodChanged,
  });

  static const periods = [7, 30, 90, 180, 365];
  static const periodLabels = ['7d', '30d', '90d', '6m', '1g'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(periods.length, (i) {
            final selected = periods[i] == selectedDays;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(periodLabels[i]),
                selected: selected,
                onSelected: (_) => onPeriodChanged(periods[i]),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: history.length < 2
              ? const Center(child: Text('Nedovoljno podataka za graf'))
              : LineChart(_buildChart(context)),
        ),
      ],
    );
  }

  LineChartData _buildChart(BuildContext context) {
    final spots = history.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), e.value.roundedPrice)).toList();

    return LineChartData(
      gridData: const FlGridData(show: true),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: Theme.of(context).colorScheme.primary,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((s) =>
              LineTooltipItem('${s.y.toStringAsFixed(2)} €', const TextStyle())).toList(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement FuelDetailScreen with PageView**

Create `lib/ui/screens/fuel_detail_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/fuel_detail_cubit.dart';
import '../../data/repositories/price_repository.dart';
import '../../models/fuel_type.dart';
import '../widgets/price_display.dart';
import '../widgets/price_chart.dart';

class FuelDetailScreen extends StatefulWidget {
  final int initialIndex;
  final List<FuelType> fuelTypes;

  const FuelDetailScreen({super.key, required this.initialIndex, required this.fuelTypes});

  @override
  State<FuelDetailScreen> createState() => _FuelDetailScreenState();
}

class _FuelDetailScreenState extends State<FuelDetailScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fuelTypes[_currentIndex].displayName),
      ),
      body: Column(
        children: [
          // Dot indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.fuelTypes.length, (i) => Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _currentIndex
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            )),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.fuelTypes.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                return BlocProvider(
                  create: (_) => FuelDetailCubit(
                    priceRepo: context.read<PriceRepository>(),
                    fuelType: widget.fuelTypes[index],
                  )..load(),
                  child: const _FuelDetailPage(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelDetailPage extends StatelessWidget {
  const _FuelDetailPage();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FuelDetailCubit, FuelDetailState>(
      builder: (context, state) {
        if (state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              PriceDisplay(
                predicted: state.predictedPrice,
                current: state.currentPrice,
                lastChangeDate: state.currentPrice?.date,
              ),
              const SizedBox(height: 32),
              PriceChart(
                history: state.history,
                selectedDays: state.chartDays,
                onPeriodChanged: (days) => context.read<FuelDetailCubit>().setChartPeriod(days),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run app to verify navigation works**

```bash
cd fuel_price_app && flutter run
```
Expected: App launches, shows empty fuel list, settings icon visible

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add detail screen with price display, chart, and swipe navigation"
```

---

## Task 11: Settings Screen

**Files:**
- Create: `fuel_price_app/lib/ui/screens/settings_screen.dart`

- [ ] **Step 1: Implement SettingsScreen**

Create `lib/ui/screens/settings_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../blocs/settings_cubit.dart';
import '../../models/fuel_type.dart';
import '../widgets/disclaimer_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Postavke')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          final cubit = context.read<SettingsCubit>();

          return ListView(
            children: [
              // --- Display ---
              const _SectionHeader('Prikaz'),
              for (final ft in FuelType.values)
                CheckboxListTile(
                  title: Text(ft.displayName),
                  value: state.fuelVisibility[ft.name] ?? true,
                  onChanged: (v) => cubit.setFuelVisibility(ft.name, v ?? true),
                ),
              ListTile(
                title: const Text('Tema'),
                trailing: DropdownButton<ThemeMode>(
                  value: state.themeMode,
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('Sustav')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Svijetla')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Tamna')),
                  ],
                  onChanged: (v) => cubit.setThemeMode(v!),
                ),
              ),

              // --- Notifications ---
              const _SectionHeader('Obavijesti'),
              SwitchListTile(
                title: const Text('Omogući obavijesti'),
                value: state.notificationsEnabled,
                onChanged: cubit.setNotificationsEnabled,
              ),
              if (state.notificationsEnabled) ...[
                ListTile(
                  title: const Text('Dan obavijesti'),
                  trailing: DropdownButton<String>(
                    value: state.notificationDay,
                    items: const [
                      DropdownMenuItem(value: 'saturday', child: Text('Subota')),
                      DropdownMenuItem(value: 'sunday', child: Text('Nedjelja')),
                      DropdownMenuItem(value: 'monday', child: Text('Ponedjeljak')),
                    ],
                    onChanged: (v) => cubit.setNotificationDay(v!),
                  ),
                ),
                ListTile(
                  title: const Text('Sat obavijesti'),
                  trailing: DropdownButton<int>(
                    value: state.notificationHour,
                    items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i:00'))),
                    onChanged: (v) => cubit.setNotificationHour(v!),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Goriva u obavijesti:', style: TextStyle(fontWeight: FontWeight.w500)),
                ),
                for (final ft in FuelType.values)
                  CheckboxListTile(
                    title: Text(ft.displayName),
                    value: state.notificationFuels[ft.name] ?? true,
                    onChanged: (v) => cubit.setNotificationFuel(ft.name, v ?? true),
                  ),
              ],

              // --- Regulatory Info ---
              const _SectionHeader('Regulativa'),
              ListTile(
                title: Text(state.params.priceRegulation.name),
                subtitle: Text('${state.params.priceRegulation.nnReference}\n'
                    'Na snazi od: ${state.params.priceRegulation.effectiveDate}'),
                isThreeLine: true,
              ),
              if (state.params.priceRegulation.nnUrl != null)
                ListTile(
                  title: const Text('Otvori u Narodnim novinama'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => launchUrl(Uri.parse(state.params.priceRegulation.nnUrl!)),
                ),
              ListTile(
                title: const Text('Zadnje ažuriranje parametara'),
                subtitle: Text(state.lastConfigFetch != null
                    ? '${state.lastConfigFetch!.day}.${state.lastConfigFetch!.month.toString().padLeft(2, '0')}.${state.lastConfigFetch!.year}.'
                    : 'Još nije dohvaćeno'),
              ),

              // --- About ---
              const _SectionHeader('O aplikaciji'),
              ListTile(
                title: const Text('Uvjeti korištenja'),
                onTap: () => showDisclaimerDialog(context),
              ),
              const ListTile(
                title: Text('Formula'),
                subtitle: Text(
                  'PC = [(Σ CIF Med × ρ ÷ T) ÷ n] + P\n'
                  'Maloprodajna cijena = (PC + trošarina) × 1,25\n\n'
                  'CIF Med: Platts Mediterranean\n'
                  'ρ: gustoća goriva (kg/L)\n'
                  'T: tečaj USD/EUR (HNB)\n'
                  'n: broj dana u obračunskom razdoblju\n'
                  'P: premija energetskog subjekta',
                ),
                isThreeLine: true,
              ),
              const ListTile(
                title: Text('Verzija'),
                subtitle: Text('1.0.0'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary)),
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add settings screen with display, notification, and regulatory sections"
```

---

## Task 12: Disclaimer Dialog

**Files:**
- Create: `fuel_price_app/lib/ui/widgets/disclaimer_dialog.dart`
- Modify: `fuel_price_app/lib/ui/screens/fuel_list_screen.dart` — show on first launch

- [ ] **Step 1: Implement disclaimer dialog**

Create `lib/ui/widgets/disclaimer_dialog.dart`:
```dart
import 'package:flutter/material.dart';

const disclaimerText = 'Ovo je neslužbena aplikacija. Prikazane cijene su procjena '
    'temeljena na javno dostupnim podacima i važećoj regulativi. Moguća su odstupanja '
    'od stvarnih cijena zbog intervencija Vlade, promjena regulatornog okvira ili '
    'nedostupnosti podataka. Aplikacija ne preuzima odgovornost za točnost prikazanih cijena.';

Future<void> showDisclaimerDialog(BuildContext context, {VoidCallback? onAcknowledge}) {
  return showDialog(
    context: context,
    barrierDismissible: onAcknowledge == null,
    builder: (context) => AlertDialog(
      title: const Text('Obavijest'),
      content: const Text(disclaimerText),
      actions: [
        TextButton(
          onPressed: () {
            onAcknowledge?.call();
            Navigator.pop(context);
          },
          child: const Text('Razumijem'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: Add first-launch check to FuelListScreen**

Modify `lib/ui/screens/fuel_list_screen.dart` — wrap the Scaffold in a BlocListener on SettingsCubit. After build, if `!disclaimerAcknowledged`, call `showDisclaimerDialog` with `onAcknowledge: () => settingsCubit.acknowledgeDisclaimer()`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add disclaimer dialog shown on first launch"
```

---

## Task 13: Notification Service

**Files:**
- Create: `fuel_price_app/lib/notifications/notification_service.dart`

- [ ] **Step 1: Implement NotificationService**

Create `lib/notifications/notification_service.dart`:
```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../data/repositories/price_repository.dart';
import '../models/fuel_type.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
  }

  Future<void> scheduleWeeklyNotification({
    required String day,
    required int hour,
    required Map<String, bool> fuelSelection,
    required PriceRepository priceRepo,
  }) async {
    await _plugin.cancelAll();

    final weekday = switch (day) {
      'saturday' => DateTime.saturday,
      'sunday' => DateTime.sunday,
      'monday' => DateTime.monday,
      _ => DateTime.monday,
    };

    final title = day == 'monday'
        ? 'Promjena cijene goriva sutra'
        : 'Promjena cijene goriva u utorak';

    // Build body from predictions
    final parts = <String>[];
    for (final ft in FuelType.values) {
      if (fuelSelection[ft.name] != true) continue;
      final predicted = await priceRepo.getLatestPrice(ft, prediction: true);
      final current = await priceRepo.getLatestPrice(ft, prediction: false);
      if (predicted == null) continue;

      var entry = '${ft.shortName}: ${predicted.formattedPrice.replaceAll('.', ',')} €';
      if (current != null) {
        final diff = predicted.roundedPrice - current.roundedPrice;
        if (diff > 0) entry += ' ↑';
        if (diff < 0) entry += ' ↓';
      }
      parts.add(entry);
    }

    if (parts.isEmpty) return; // No predictions available

    final body = parts.join(' | ');

    // Calculate next occurrence of the chosen weekday + hour in Europe/Zagreb
    final zagreb = tz.getLocation('Europe/Zagreb');
    final now = tz.TZDateTime.now(zagreb);
    var scheduled = tz.TZDateTime(zagreb, now.year, now.month, now.day, hour);
    // Advance to the correct weekday
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      0,
      title,
      body,
      scheduled,
      const NotificationDetails(android: AndroidNotificationDetails(
        'fuel_price_reminder',
        'Podsjetnik za cijenu goriva',
        channelDescription: 'Obavijest o promjeni cijene goriva',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      )),
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
```

- [ ] **Step 2: Wire notification service into SettingsCubit**

When notification settings change in SettingsCubit, call `NotificationService.scheduleWeeklyNotification()` with updated parameters.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add local notification service with weekly scheduling"
```

---

## Task 14: Background Data Fetch (WorkManager)

**Files:**
- Modify: `fuel_price_app/lib/main.dart` — register WorkManager callback

- [ ] **Step 1: Add WorkManager setup to main.dart**

Add to `main.dart`:
```dart
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final db = AppDatabase();
    await db.init();
    final priceRepo = PriceRepository(db);
    final configRepo = ConfigRepository(db, RemoteConfigService());
    final cubit = DataSyncCubit(
      priceRepo: priceRepo,
      configRepo: configRepo,
      yahooService: YahooFinanceService(),
      hnbService: HnbService(),
    );
    await cubit.sync();
    await db.close();
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'fuel-price-sync',
    'syncPrices',
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    initialDelay: const Duration(minutes: 5),
  );

  final db = AppDatabase();
  await db.init();
  runApp(FuelPriceApp(database: db));
}
```

- [ ] **Step 2: Test by running app and checking logs**

```bash
cd fuel_price_app && flutter run
```
Expected: App runs, WorkManager registers task

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add WorkManager for background data sync every hour"
```

---

## Task 15: .gitignore Update

**Files:**
- Modify: `fuel_price_app/.gitignore`

Note: `config/fuel_params.json` was already created in Task 5.

- [ ] **Step 1: Add .superpowers/ to .gitignore**

Append to `.gitignore`:
```
.superpowers/
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add remote config JSON and update gitignore"
```

---

## Task 16: Integration Test — Full Flow

**Files:**
- Create: `fuel_price_app/test/integration/full_flow_test.dart`

- [ ] **Step 1: Write integration test**

Create `test/integration/full_flow_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/oil_price.dart';
import 'package:fuel_price_app/models/exchange_rate.dart';

void main() {
  late AppDatabase db;
  late PriceRepository priceRepo;
  late SettingsRepository settingsRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    priceRepo = PriceRepository(db);
    settingsRepo = SettingsRepository(db);
  });

  tearDown(() async => await db.close());

  test('full flow: seed data → calculate → retrieve prediction', () async {
    // Seed 14 days of oil prices and exchange rates
    for (var i = 0; i < 14; i++) {
      final date = DateTime(2026, 3, 10 + i);
      await priceRepo.saveOilPrice(OilPrice(date: date, cifMed: 700.0, source: 'BZ=F'));
      await priceRepo.saveExchangeRate(ExchangeRate(date: date, usdEur: 0.92));
    }

    // Calculate prediction
    final engine = FormulaEngine(FuelParams.defaultParams);
    final prices = await priceRepo.getOilPrices('BZ=F', days: 30);
    final rates = await priceRepo.getExchangeRates(days: 30);
    final predicted = engine.predictPrice(
      FuelType.es95,
      prices.map((p) => p.cifMed).toList(),
      rates.map((r) => r.usdEur).toList(),
    );

    // Save prediction
    await priceRepo.saveFuelPrice(FuelPrice(
      fuelType: FuelType.es95,
      date: DateTime(2026, 3, 25),
      price: predicted,
      isPrediction: true,
    ));

    // Retrieve
    final result = await priceRepo.getLatestPrice(FuelType.es95, prediction: true);
    expect(result, isNotNull);
    expect(result!.roundedPrice, predicted);

    // Verify fuel order defaults
    final order = await settingsRepo.getFuelOrder();
    expect(order, ['es95', 'es100', 'eurodizel', 'unp10kg']);
  });
}
```

- [ ] **Step 2: Run integration test**

```bash
flutter test test/integration/full_flow_test.dart
```
Expected: PASS

- [ ] **Step 3: Run all tests**

```bash
flutter test
```
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: add integration test for full data flow"
```
