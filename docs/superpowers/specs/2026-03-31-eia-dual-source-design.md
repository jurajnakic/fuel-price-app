# Multi-Source Integration Design

## Problem

Yahoo Finance futures (RB=F, HO=F, BZ=F) are US products, not CIF Med. The `cifMedFactor` that converts Yahoo → CIF Med is unstable because the Yahoo↔CIF Med spread varies over time. No single fixed factor gives accurate prices across multiple 14-day cycles.

## Solution

Add two new data sources to complement Yahoo Finance:
1. **EIA API** — US spot prices (daily, unlimited free)
2. **OilPriceAPI** — European Rotterdam prices (every 2-3 days, 50 req/month free)

Calculate fuel prices from all available sources independently, then produce a single weighted-average price. Weights are configurable via remote config for tuning without app rebuild.

## Data Sources

### EIA API (new)
- **Base URL:** `https://api.eia.gov/v2/petroleum/pri/spt/data/`
- **Format:** JSON, daily frequency
- **Free tier:** Unlimited with registered API key
- **Relevant series:**

| Fuel Type   | EIA Series ID                     | Description                        | Unit     |
|-------------|-----------------------------------|------------------------------------|----------|
| es95/es100  | EER_EPMRU_PF4_Y35NY_DPG          | NY Harbor Conventional Gasoline    | USD/gal  |
| eurodizel   | EER_EPD2DXL0_PF4_Y35NY_DPG       | NY Harbor ULSD Diesel              | USD/gal  |
| unp_10kg    | EER_EPLLPA_PF4_Y44MB_DPG         | Mont Belvieu TX Propane            | USD/gal  |

### OilPriceAPI (new — European prices!)
- **Base URL:** `https://api.oilpriceapi.com/v1/`
- **Format:** JSON, updates every 5 min during market hours
- **Free tier:** 50 requests/month (no credit card, no expiry)
- **Auth:** Token header (`Authorization: Token {key}`)
- **Relevant commodities:**

| Fuel Type   | OilPriceAPI Code        | Description                     | Unit    | Geography  |
|-------------|-------------------------|---------------------------------|---------|------------|
| eurodizel   | MGO_05S_NLRTM_USD       | Marine Gasoil 0.5%S Rotterdam   | USD/mt  | Europe/ARA |
| es95/es100  | GASOLINE_RBOB_USD       | RBOB Gasoline (fallback to US)  | USD/gal | US         |
| unp_10kg    | —                       | No LPG available                | —       | —          |

**Key value:** Rotterdam Marine Gasoil is a **European** price that correlates much more closely with CIF Med diesel than US Heating Oil. This is the most valuable single addition for eurodizel accuracy.

**Rate limiting strategy:** Fetch every 2 days (15 req/month for 1 symbol). API returns current + historical data per request, so no data gaps. Remaining requests tracked via `X-RateLimit-Remaining` response header.

### Yahoo Finance (existing, unchanged)
| Fuel Type   | Symbol | Description      | Unit     |
|-------------|--------|------------------|----------|
| es95/es100  | RB=F   | RBOB Gasoline    | USD/gal  |
| eurodizel   | HO=F   | Heating Oil      | USD/gal  |
| unp_10kg    | BZ=F   | Brent Crude      | USD/bbl  |

## Architecture

### New Files

#### 1. `lib/data/services/eia_service.dart`
New service class, same pattern as `YahooFinanceService`.

```dart
class EiaPrice {
  final DateTime date;
  final double value; // spot price in original units
}

class EiaService {
  final Dio dio;
  final String apiKey;

  /// Fetch daily spot prices for an EIA series.
  /// Returns up to [days] of historical data.
  Future<List<EiaPrice>> fetchSpotPrices(String seriesId, {int days = 60});
}
```

**API call pattern:**
```
GET https://api.eia.gov/v2/petroleum/pri/spt/data/
  ?api_key={key}
  &frequency=daily
  &data[]=value
  &facets[series][]={seriesId}
  &start={YYYY-MM-DD}
  &sort[0][column]=period
  &sort[0][direction]=asc
  &length=5000
```

**Resilience:** Single endpoint (government API, stable). Retry once on failure. Timeout 15s.

#### 1b. `lib/data/services/oil_price_api_service.dart`
New service for OilPriceAPI (European prices).

```dart
class OilApiPrice {
  final DateTime date;
  final double value; // price in original units (USD/mt or USD/gal)
}

class OilPriceApiService {
  final Dio dio;
  final String apiKey;

  /// Fetch latest price for a commodity code.
  /// Returns current price + available historical data.
  Future<List<OilApiPrice>> fetchPrices(String commodityCode);

  /// Check remaining monthly requests via response headers.
  int? get remainingRequests;
}
```

**API call pattern:**
```
GET https://api.oilpriceapi.com/v1/commodities/{code}
  Headers: Authorization: Token {key}
```

**Rate limit awareness:**
- Track `X-RateLimit-Remaining` from responses
- Skip fetch if remaining < 5 (safety buffer)
- Store last fetch timestamp in SharedPreferences
- Only fetch if last fetch > 48 hours ago (every 2 days)

**Resilience:** Single endpoint, retry once. Timeout 10s. Non-critical — app works without it.

### Modified Files

#### 2. `lib/models/fuel_params.dart` — add EIA config fields

New fields in `FuelParams`:
```dart
/// EIA API key (default hardcoded, overridable via remote config)
final String eiaApiKey;

/// OilPriceAPI key (default hardcoded, overridable via remote config)
final String oilPriceApiKey;

/// EIA series ID per fuel type
final Map<String, String> eiaSymbols;

/// OilPriceAPI commodity code per fuel type (only where European data exists)
final Map<String, String> oilApiSymbols;

/// CIF Med conversion factors for EIA spot prices
final Map<String, double> eiaCifMedFactors;

/// CIF Med conversion factors for OilPriceAPI prices
final Map<String, double> oilApiCifMedFactors;

/// Source weights per fuel type: maps source name to weight (0.0-1.0)
/// Sources: "yahoo", "eia", "oilapi"
/// Weights are normalized at runtime (sum to 1.0)
final Map<String, Map<String, double>> sourceWeights;
```

Defaults:
```dart
eiaApiKey: 'HARDCODED_DEFAULT_KEY',
oilPriceApiKey: 'HARDCODED_DEFAULT_KEY',
eiaSymbols: {
  'es95': 'EER_EPMRU_PF4_Y35NY_DPG',
  'es100': 'EER_EPMRU_PF4_Y35NY_DPG',
  'eurodizel': 'EER_EPD2DXL0_PF4_Y35NY_DPG',
  'unp_10kg': 'EER_EPLLPA_PF4_Y44MB_DPG',
},
oilApiSymbols: {
  'eurodizel': 'MGO_05S_NLRTM_USD',  // Rotterdam Marine Gasoil — European!
  // es95, es100, unp_10kg: no European equivalent available
},
eiaCifMedFactors: {
  'es95': 390.0,    // to be calibrated
  'es100': 390.0,
  'eurodizel': 320.0,
  'unp_10kg': 280.0,
},
oilApiCifMedFactors: {
  'eurodizel': 1.05,  // Rotterdam MGO is already USD/mt, close to CIF Med
                       // Small factor for Med premium over ARA
},
sourceWeights: {
  'es95':      {'yahoo': 0.5, 'eia': 0.5},
  'es100':     {'yahoo': 0.5, 'eia': 0.5},
  'eurodizel': {'yahoo': 0.3, 'eia': 0.2, 'oilapi': 0.5},  // Rotterdam gets highest weight for diesel
  'unp_10kg':  {'yahoo': 0.5, 'eia': 0.5},
},
```

#### 3. `config/fuel_params.json` — add EIA section

```json
{
  "eia_api_key": "YOUR_KEY_HERE",
  "eia_symbols": { ... },
  "eia_cif_med_factors": { ... },
  "source_weights": { ... }
}
```

#### 4. `lib/data/services/data_sync_orchestrator.dart` — add EIA + OilPriceAPI

Add `fetchEiaSpotPrices` and `fetchOilApiPrices` callbacks. `SyncResult` gets new `eiaSpotOk` and `oilApiOk` fields. All sources run in parallel with Yahoo and ECB. OilPriceAPI only fires if >48h since last fetch (rate limit protection).

#### 5. `lib/app.dart` — integrate EIA into sync and prediction

**In `initState`:** Create `EiaService` with API key from `_activeParams`.

**In `fetchOilPrices` orchestrator callback:** Add EIA fetch alongside Yahoo. Save EIA prices to `oil_prices` table with source = EIA series ID.

**In `_recalculatePredictions`:** For each fuel type:
1. Get Yahoo prices → calculate Yahoo-based CIF Med → predict Yahoo price
2. Get EIA prices → calculate EIA-based CIF Med → predict EIA price
3. Weighted average: `finalPrice = yahooPrice × (1 - weight) + eiaPrice × weight`
4. If one source has no data, use the other at 100%

#### 6. `lib/scheduling/background_sync.dart` — add EIA to background sync

Same pattern as foreground: fetch EIA series alongside Yahoo, save to DB.

### Database

No schema changes needed. All prices use the existing `oil_prices` table:
- EIA: `source` = EIA series ID (e.g., `'EER_EPMRU_PF4_Y35NY_DPG'`)
- OilPriceAPI: `source` = commodity code (e.g., `'MGO_05S_NLRTM_USD'`)
- `cif_med` = raw price in original units (same as Yahoo raw price storage)
- `date` = price date

OilPriceAPI fetch tracking uses SharedPreferences:
- `oilapi_last_fetch` = ISO timestamp of last successful fetch
- `oilapi_remaining` = remaining monthly requests

### API Key Management (A+B)

1. **Hardcoded default** in `EiaService` — app works out of the box
2. **Remote config override** via `eia_api_key` in `fuel_params.json`
3. App uses remote config key if present, otherwise falls back to hardcoded
4. Free EIA key has no meaningful rate limit for this use case

### Prediction Flow (updated)

```
For each FuelType:
  1. Collect available source prices:
     sources = {}

  2. Yahoo:
     yahooPrices = db.getOilPrices(yahooSymbol, days: 60)
     IF available:
       yahooCifMed = yahooPrices × params.cifMedFactors[fuelType]
       sources['yahoo'] = engine.predictPrice(fuelType, yahooCifMed, rates)

  3. EIA:
     eiaPrices = db.getOilPrices(eiaSymbol, days: 60)
     IF available:
       eiaCifMed = eiaPrices × params.eiaCifMedFactors[fuelType]
       sources['eia'] = engine.predictPrice(fuelType, eiaCifMed, rates)

  4. OilPriceAPI (eurodizel only, or where configured):
     oilApiPrices = db.getOilPrices(oilApiSymbol, days: 60)
     IF available:
       oilApiCifMed = oilApiPrices × params.oilApiCifMedFactors[fuelType]
       sources['oilapi'] = engine.predictPrice(fuelType, oilApiCifMed, rates)

  5. Weighted blend:
     weights = params.sourceWeights[fuelType]  // e.g. {yahoo: 0.3, eia: 0.2, oilapi: 0.5}
     - Filter to sources that have data
     - Normalize remaining weights to sum to 1.0
     - finalPrice = Σ(sourcePrice × normalizedWeight)
     - If no sources available: skip (no prediction)
```

**Example for eurodizel** (all 3 sources available):
- Yahoo HO=F predicts 1.83, weight 0.3
- EIA NY Harbor ULSD predicts 1.80, weight 0.2
- OilPriceAPI Rotterdam MGO predicts 1.85, weight 0.5
- Final: (1.83×0.3 + 1.80×0.2 + 1.85×0.5) = 1.834

**Example for es95** (only Yahoo + EIA):
- Yahoo RB=F predicts 1.55, weight 0.5
- EIA NY Harbor Gasoline predicts 1.53, weight 0.5
- Final: (1.55×0.5 + 1.53×0.5) = 1.54

### UI Changes

- Add small disclaimer text below prices: "Procjena na temelju dostupnih podataka"
- No range display — single price as user requested
- Info (?) button already explains methodology — update text to mention dual-source

### Error Handling

- Any source failure does not block app — remaining sources take over with re-normalized weights
- All new sources fail → falls back to Yahoo-only (existing behavior)
- Yahoo also fails → shows cached data (existing behavior)
- OilPriceAPI rate limit hit → skip silently, rely on cached data + other sources
- Invalid/empty responses → logged, skipped silently

### Testing

- Unit test `EiaService` with mock Dio responses
- Unit test `OilPriceApiService` with mock Dio responses
- Unit test weighted blending logic (normalize weights, fallback when sources missing)
- Unit test `FuelParams.fromJson` with new fields (backward compatible: missing fields use defaults)
- Integration test: orchestrator with 5 sources

### Calibration Strategy

Initial `eiaCifMedFactors` will be estimated, then manually calibrated:
1. Compare EIA spot prices with known CIF Med values from the two known periods (March 10-23 and March 24-April 6, 2026)
2. Calculate optimal factors for EIA
3. Update remote config
4. Adjust `sourceWeights` based on which source gave better accuracy

Future: if Barchart OnDemand API becomes available, same pattern — add as 4th source with its own factors and weights. Barchart has actual CIF Med swap contracts (JZ6, J3G, JZ4, JPS) which would be the most accurate source.

### Backward Compatibility

- All new `fuel_params.json` fields are optional with sensible defaults
- Existing app versions ignore unknown JSON fields
- If EIA fields are missing from remote config, app uses hardcoded defaults
- `sourceWeights` default to equal blend; set any source weight to 0.0 to disable it

## Bug Fixes (bundled)

### 1. Dark theme not persisting across app restarts
Theme selection resets to light on restart because the preference is not saved to persistent storage (SharedPreferences). Fix: save theme mode when changed, load on startup.

### 2. App version stuck at 2.0.0
Version in pubspec.yaml needs to be bumped. Android requires `versionCode` to be strictly higher than installed version for updates. Fix: bump to 3.0.0+3 (or appropriate next version).
