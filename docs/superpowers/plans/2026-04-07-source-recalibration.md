# Source Recalibration & EIA Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch Eurodizel to OilPriceAPI GASOIL_USD (pravi EU diesel benchmark), popraviti EIA API encoding bug za UNP propan, i fino podesiti ES95 offset.

**Architecture:** Mijenjamo samo default parametre i source konfiguraciju u `fuel_params.dart`, popravljamo EIA URL encoding u `eia_service.dart`, i uklanjamo 48h rate limit u `background_sync.dart`. Dodajemo `oilApiCifMedOffsets` mapu za offset podrsku OilPriceAPI izvora.

**Tech Stack:** Flutter, Dart, Dio HTTP, mocktail (testiranje)

**Working directory:** `D:/Projekti/test/fuel_price_app`

**Test command:** `D:/Portable/flutter/bin/flutter.bat test`

---

### Task 1: Dodati `oilApiCifMedOffsets` u FuelParams

Background sync trenutno koristi hardcoded `0.0` za OilPriceAPI offset. Trebamo mapu za offset po gorivu, jednako kao za Yahoo i EIA izvore.

**Files:**
- Modify: `lib/models/fuel_params.dart`
- Modify: `test/models/fuel_params_test.dart`

- [ ] **Step 1: Napisati test za novi `oilApiCifMedOffsets` field**

U `test/models/fuel_params_test.dart`, u grupi `'FuelParams multi-source config'`, dodati assert za defaultne offsete i JSON parsing:

```dart
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
```

- [ ] **Step 2: Pokrenuti test — treba pasti**

Run: `D:/Portable/flutter/bin/flutter.bat test test/models/fuel_params_test.dart`
Expected: FAIL — `oilApiCifMedOffsets` ne postoji

- [ ] **Step 3: Dodati `oilApiCifMedOffsets` field u FuelParams**

U `lib/models/fuel_params.dart`:

1. Dodati field deklaraciju nakon `oilApiCifMedFactors` (linija 63):
```dart
  /// CIF Med conversion offsets for OilPriceAPI prices
  final Map<String, double> oilApiCifMedOffsets;
```

2. Dodati konstruktor parametar nakon `this.oilApiCifMedFactors` (linija 121-122):
```dart
    this.oilApiCifMedOffsets = const {
      'eurodizel': 40.0,
    },
```

3. Dodati fromJson parsing nakon `oilApiCifMedFactors` bloka (nakon linije 233):
```dart
      oilApiCifMedOffsets: json.containsKey('oil_api_cif_med_offsets')
          ? (json['oil_api_cif_med_offsets'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {
              'eurodizel': 40.0,
            },
```

4. Dodati u `defaultParams` (nakon `oilApiCifMedFactors`):
```dart
    oilApiCifMedOffsets: {'eurodizel': 40.0},
```

- [ ] **Step 4: Pokrenuti testove — trebaju proći**

Run: `D:/Portable/flutter/bin/flutter.bat test test/models/fuel_params_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/fuel_params.dart test/models/fuel_params_test.dart
git commit -m "feat: add oilApiCifMedOffsets to FuelParams"
```

---

### Task 2: Ažurirati default parametre (ES95 offset, Eurodizel source, BZ=F fallback)

**Files:**
- Modify: `lib/models/fuel_params.dart`
- Modify: `test/models/fuel_params_test.dart`

- [ ] **Step 1: Ažurirati test za nove default vrijednosti**

U `test/models/fuel_params_test.dart`, ažurirati postojeće testove:

U testu `'defaultParams has multi-source defaults'`:
```dart
    test('defaultParams has multi-source defaults', () {
      final p = FuelParams.defaultParams;
      expect(p.eiaSymbols['eurodizel'], 'EER_EPD2DXL0_PF4_Y35NY_DPG');
      expect(p.oilApiSymbols['eurodizel'], 'GASOIL_USD');
      expect(p.sourceWeights['eurodizel']!['oilapi'], 1.0);
      expect(p.sourceWeights['eurodizel']!['yahoo'], 0.0);
    });
```

U testu `'fromJson uses defaults when EIA/OilAPI fields missing'`, ažurirati:
```dart
      expect(params.oilApiSymbols['eurodizel'], 'GASOIL_USD');
      expect(params.sourceWeights['eurodizel']!['oilapi'], 1.0);
```

Dodati novi test za ES95 offset:
```dart
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
```

- [ ] **Step 2: Pokrenuti testove — trebaju pasti**

Run: `D:/Portable/flutter/bin/flutter.bat test test/models/fuel_params_test.dart`
Expected: FAIL — stare default vrijednosti

- [ ] **Step 3: Ažurirati default parametre u fuel_params.dart**

Promjene u `defaultParams` i konstruktor defaultima:

**ES95/ES100 offset** — u konstruktoru i defaultParams:
```
'es95': 259.0 → 'es95': 261.0
'es100': 259.0 → 'es100': 261.0
```

**Eurodizel Yahoo (fallback) faktori** — u konstruktoru i defaultParams:
```
'eurodizel': 6.04 (cifMedFactors) → 'eurodizel': 11.23
'eurodizel': 648.0 (cifMedOffsets) → 'eurodizel': 205.0
```

**OilPriceAPI simbol** — u konstruktoru i defaultParams:
```
'eurodizel': 'MGO_05S_NLRTM_USD' → 'eurodizel': 'GASOIL_USD'
```

**OilPriceAPI faktor** — u konstruktoru i defaultParams:
```
'eurodizel': 1.05 (oilApiCifMedFactors) → 'eurodizel': 1.0
```

**Source weights** — u konstruktoru i defaultParams:
```
'eurodizel': {'yahoo': 1.0} → 'eurodizel': {'oilapi': 1.0, 'yahoo': 0.0}
```

- [ ] **Step 4: Pokrenuti testove — trebaju proći**

Run: `D:/Portable/flutter/bin/flutter.bat test test/models/fuel_params_test.dart`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/fuel_params.dart test/models/fuel_params_test.dart
git commit -m "feat: switch eurodizel to GASOIL_USD, update ES95 offset to 261"
```

---

### Task 3: Popraviti EIA API encoding bug

Dio krivo enkodira `data[]` i `facets[series][]` URL parametre. Umjesto Dio query parametara, koristiti ručno izgrađen URL.

**Files:**
- Modify: `lib/data/services/eia_service.dart`
- Modify: `test/data/services/eia_service_test.dart`

- [ ] **Step 1: Napisati test koji provjerava URL format**

U `test/data/services/eia_service_test.dart`, dodati test:

```dart
  test('builds correct v2 URL with bracket parameters', () async {
    final jsonData = {
      'response': {
        'data': [
          {'period': '2026-03-20', 'value': '2.45'},
        ],
      },
    };

    String? capturedUrl;
    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
    )).thenAnswer((invocation) async {
      capturedUrl = invocation.positionalArguments[0] as String;
      return Response(
        data: jsonData,
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      );
    });

    await service.fetchSpotPrices('EER_EPLLPA_PF4_Y44MB_DPG', days: 30);

    expect(capturedUrl, isNotNull);
    expect(capturedUrl, contains('data[0]=value'));
    expect(capturedUrl, contains('facets[series][]=EER_EPLLPA_PF4_Y44MB_DPG'));
    expect(capturedUrl, contains('api_key=test-key'));
    expect(capturedUrl, contains('frequency=daily'));
  });
```

- [ ] **Step 2: Pokrenuti test — treba pasti**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/eia_service_test.dart`
Expected: FAIL — trenutni kod koristi `queryParameters` pa Dio dodaje parametre, a mock prima `any()` za queryParameters (ne samo URL)

- [ ] **Step 3: Popraviti EIA service — koristiti ručno izgrađen URL**

Zamijeniti `fetchSpotPrices` metodu u `lib/data/services/eia_service.dart`:

```dart
  /// Fetch daily spot prices for an EIA series.
  Future<List<EiaPrice>> fetchSpotPrices(String seriesId, {int days = 60}) async {
    try {
      final start = DateTime.now().subtract(Duration(days: days + 7));
      final startStr = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

      // Build URL manually — Dio mangles bracket parameters like data[] and facets[series][]
      final url = '$_baseUrl'
          '?api_key=$apiKey'
          '&frequency=daily'
          '&data[0]=value'
          '&facets[series][]=$seriesId'
          '&start=$startStr'
          '&sort[0][column]=period'
          '&sort[0][direction]=asc'
          '&length=5000';

      _log('fetching $seriesId from $startStr');
      final response = await dio.get(
        url,
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
          date: _parseUtcDate(period),
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
```

Ključna razlika: `dio.get(url)` umjesto `dio.get(_baseUrl, queryParameters: {...})`. Uklonjen je `queryParameters` parametar.

- [ ] **Step 4: Ažurirati stare testove za novi potpis (bez queryParameters)**

Postojeći testovi koriste `queryParameters: any(named: 'queryParameters')` u mock setupu. Promijeniti sve `when` blokove da matchaju novi potpis bez queryParameters:

```dart
    when(() => mockDio.get(
      any(),
      options: any(named: 'options'),
    )).thenAnswer((_) async => Response(
      data: jsonData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ));
```

Ovo se odnosi na testove:
- `'parses daily spot prices from EIA API response'`
- `'returns empty list on API error'`
- `'skips entries with null or "." value'`

- [ ] **Step 5: Pokrenuti testove — trebaju proći**

Run: `D:/Portable/flutter/bin/flutter.bat test test/data/services/eia_service_test.dart`
Expected: ALL PASS (4 testa)

- [ ] **Step 6: Commit**

```bash
git add lib/data/services/eia_service.dart test/data/services/eia_service_test.dart
git commit -m "fix: EIA API encoding — build URL manually to preserve bracket params"
```

---

### Task 4: Background sync — ukloniti 48h rate limit i dodati oilapi offset

**Files:**
- Modify: `lib/scheduling/background_sync.dart`

- [ ] **Step 1: Ukloniti 48h rate limit za OilPriceAPI**

U `lib/scheduling/background_sync.dart`, zamijeniti blok na linijama 100-119:

Staro (s 48h provjerom):
```dart
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

Novo (dnevni sync, bez SharedPreferences provjere):
```dart
      // 3c. Fetch OilPriceAPI prices (daily — free tier allows ~50 req/month)
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
```

- [ ] **Step 2: Koristiti `oilApiCifMedOffsets` umjesto hardcoded 0.0**

Na linijama 204 i 206 (nakon uklanjanja rate limit koda, linije se pomiču), zamijeniti:

Staro:
```dart
            final oc = computeSource(oilApiPrices, oilApiFactor, 0.0, currentPeriodStart, currentRate, minPoints: 1);
            ...
            final on_ = computeSource(oilApiPrices, oilApiFactor, 0.0, nextChange, usdEurRate, minPoints: 1);
```

Novo:
```dart
        final oilApiOffset = params.oilApiCifMedOffsets[fuelType.paramKey] ?? 0.0;
        ...
            final oc = computeSource(oilApiPrices, oilApiFactor, oilApiOffset, currentPeriodStart, currentRate, minPoints: 1);
            ...
            final on_ = computeSource(oilApiPrices, oilApiFactor, oilApiOffset, nextChange, usdEurRate, minPoints: 1);
```

- [ ] **Step 3: Ukloniti nepotrebni SharedPreferences import ako se nigdje drugdje ne koristi**

Provjeriti koristi li se `SharedPreferences` još negdje u background_sync.dart. Ako ne, ukloniti import.

- [ ] **Step 4: Pokrenuti sve testove**

Run: `D:/Portable/flutter/bin/flutter.bat test`
Expected: ALL PASS (186+ testova)

- [ ] **Step 5: Commit**

```bash
git add lib/scheduling/background_sync.dart
git commit -m "feat: daily OilPriceAPI sync, use oilApiCifMedOffsets for offset"
```

---

### Task 5: Ažurirati integration test i multi-source blending test

**Files:**
- Modify: `test/domain/multi_source_blending_test.dart`
- Modify: `test/integration/full_flow_test.dart` (ako referencira stare default vrijednosti)

- [ ] **Step 1: Pregledati i ažurirati multi-source blending test**

Pročitati `test/domain/multi_source_blending_test.dart`. Ako test hardcodira stare source weights (`'eurodizel': {'yahoo': 1.0}`), ažurirati na nove (`{'oilapi': 1.0, 'yahoo': 0.0}`).

Ako test koristi stare faktore (6.04, 648), ažurirati na nove (11.23, 205 za yahoo fallback; 1.0, 40 za oilapi).

- [ ] **Step 2: Pregledati i ažurirati integration test**

Pročitati `test/integration/full_flow_test.dart`. Ažurirati hardcodirane parametre ako ih koristi.

- [ ] **Step 3: Pokrenuti sve testove**

Run: `D:/Portable/flutter/bin/flutter.bat test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add test/
git commit -m "test: update tests for new source config and offsets"
```

---

### Task 6: Završni pregled i full test run

- [ ] **Step 1: Pokrenuti sve testove**

Run: `D:/Portable/flutter/bin/flutter.bat test`
Expected: ALL PASS

- [ ] **Step 2: Pregledati promjene**

```bash
git diff HEAD~5 --stat
git log --oneline -5
```

Provjeriti da su sve promjene iz specifikacije pokrivene:
- ✅ ES95 offset 259→261
- ✅ Eurodizel: GASOIL_USD kao primarni izvor (oilapi weight 1.0)
- ✅ Eurodizel: BZ=F fallback s boljim faktorima (11.23 + 205)
- ✅ EIA encoding bug popravljen
- ✅ OilPriceAPI 48h cooldown uklonjen
- ✅ `oilApiCifMedOffsets` mapa dodana
- ✅ background_sync koristi offset iz params

- [ ] **Step 3: Commit sažetak (ako ima nezacommitanih promjena)**

Ako je sve već commitano, ovaj korak se preskače.
