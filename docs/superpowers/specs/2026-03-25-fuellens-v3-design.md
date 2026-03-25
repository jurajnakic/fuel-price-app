# FuelLens V3 — Design Spec

## Overview

Three changes to the fuel price prediction app:
1. **Rebrand** — new icon (`Ikona.png`), rename to "FuelLens"
2. **Bottom navigation** — 3 tabs (Predikcije, Postaje, Postavke)
3. **Station prices feature** — current fuel prices at Croatian gas stations, scraped via GitHub Action

## 1. Icon & App Name

- Copy `Ikona.png` (from repo root) to `fuel_price_app/assets/app_icon.png` (replaces existing)
- Also use it as `assets/app_icon_foreground.png` (adaptive icon foreground layer)
- Run `flutter_launcher_icons` to regenerate all Android densities
- For adaptive icon: image as foreground, blue (`#5B8DD9`) background color
- Rename app to "FuelLens" everywhere:
  - `AndroidManifest.xml` → `android:label="FuelLens"`
  - `app.dart` → `title: 'FuelLens'`

## 2. Bottom Navigation Bar

- New shell `Scaffold` in `app.dart` with `NavigationBar` and `IndexedStack`
- 3 destinations:
  1. **Predikcije** — icon: `Icons.trending_up` — current FuelListScreen
  2. **Postaje** — icon: `Icons.local_gas_station` — new StationListScreen
  3. **Postavke** — icon: `Icons.settings` — existing SettingsScreen
- Remove settings icon from FuelListScreen AppBar
- Each tab is its own `Scaffold` with its own `AppBar` inside the `IndexedStack`
- `IndexedStack` preserves tab state across switches
- Detail screens (FuelDetailPager, station detail) push via root `Navigator` — bottom nav is hidden on detail screens (standard Material 3 behavior)

## 3. Station Prices Feature

### 3.1 Data Source

- **GitHub repo:** `jurajnakic/fuel-price-app` (public)
- **JSON file:** `config/station_prices.json`
- **URL:** `https://raw.githubusercontent.com/jurajnakic/fuel-price-app/main/config/station_prices.json`
- App fetches this JSON, caches locally in SQLite
- Same pattern as existing `fuel_params.json` remote config

### 3.2 JSON Schema — station_prices.json

```json
{
  "updated": "2026-03-25T08:00:00Z",
  "stations": [
    {
      "id": "ina",
      "name": "INA",
      "url": "https://www.ina.hr/...",
      "updated": "2026-03-25",
      "fuels": [
        {"name": "Eurosuper 95", "type": "es95", "price": 1.45},
        {"name": "Eurosuper 100", "type": "es100", "price": 1.52},
        {"name": "Eurodizel", "type": "eurodizel", "price": 1.42},
        {"name": "INA Blue Diesel", "type": "premium_diesel", "price": 1.58},
        {"name": "LPG Autoplin", "type": "lpg", "price": 0.68}
      ]
    }
  ]
}
```

- Stations without data are **excluded** from JSON entirely
- Fuel `type` field uses standardized keys: `es95`, `es100`, `eurodizel`, `lpg`, `premium_diesel`, `premium_95`, `unp10kg`, etc.
- Station fuel types are an independent namespace — they don't map 1:1 to the app's `FuelType` enum. The `name` field is what gets displayed.
- Price is in EUR per unit (litre or kg)

### 3.3 Stations

| ID | Name | Source URL |
|----|------|-----------|
| ina | INA | ina.hr cjenici |
| tifon | Tifon | tifon.hr cjenici |
| crodux | Crodux | crodux.hr |
| petrol | Petrol | petrol.hr/hr |
| shell | Shell | shell.hr |

### 3.4 UI — Station List Screen

- List of stations with name and station icon/logo placeholder
- Only stations present in JSON are shown (no data = not visible)
- Subtitle: date of last price update for that station
- Tap → pushes StationDetailScreen

### 3.5 UI — Station Detail Screen

- AppBar with station name
- List of fuels with name and price (EUR, 2 decimals)
- "Ažurirano: DD.MM.YYYY." at the top
- Fuel sort order: `es95`, `es100`, `eurodizel`, `lpg`, `unp10kg` first (in that order), then any remaining fuels alphabetically by `name`
- Station `url` field shown as "Izvor cijena" link at bottom of detail screen

### 3.6 Data Layer

- **StationPriceService** — fetches `station_prices.json` from GitHub raw URL
- **StationRepository** — caches station data in SQLite, provides CRUD
- **StationsCubit** — manages state for station list and detail screens
- New SQLite tables: `stations`, `station_fuels`

### 3.7 Database Migration

- Bump database version from 1 to 2
- Add `onUpgrade` handler that creates `stations` and `station_fuels` tables
- New tables:
  - `stations`: id (TEXT PK), name (TEXT), url (TEXT), updated (TEXT)
  - `station_fuels`: id (INTEGER PK AUTOINCREMENT), station_id (TEXT FK), name (TEXT), type (TEXT), price (REAL)

### 3.8 Data Freshness & Caching

- App fetches `station_prices.json` once per day (same logic as fuel_params — check last fetch timestamp)
- Pull-to-refresh on StationListScreen forces immediate re-fetch
- Station data cached in SQLite indefinitely (overwritten on each successful fetch)
- **Empty state:** If no cached data and fetch fails, show "Nema podataka. Provjerite internetsku vezu." message
- **Loading state:** Show spinner on first load

### 3.9 StationsCubit Lifecycle

- Created in `app.dart` alongside other cubits, provided via `MultiBlocProvider`
- Uses same `Dio` instance as other services
- Does NOT participate in `DataSyncOrchestrator` — fetches independently
- Station data fetched lazily: only when user first navigates to Postaje tab (not on app startup)

## 4. GitHub Repository Setup — `jurajnakic/fuel-price-app`

### 4.1 Repository Contents

```
fuel-price-app/
├── config/
│   ├── fuel_params.json          — regulatory parameters (existing)
│   └── station_prices.json       — scraped station prices (generated)
├── scrapers/
│   ├── scrape_stations.py        — scrapes 5 gas station websites
│   └── scrape_regulations.py     — scrapes NN for regulation changes
├── .github/
│   └── workflows/
│       ├── scrape-stations.yml   — daily at 08:00 CET
│       └── scrape-regulations.yml — weekly check for new regulations
└── README.md
```

### 4.2 GitHub Action — Station Price Scraper

- **Schedule:** Daily at 08:00 CET (`cron: '0 7 * * *'` UTC)
- **Script:** `scrapers/scrape_stations.py`
- **Process:**
  1. Scrape each station's website for current fuel prices
  2. Build `station_prices.json` with only successfully scraped stations
  3. Commit and push to `main` if data changed
- **Dependencies:** Python 3, `requests`, `beautifulsoup4`
- **Error handling:** If a station fails, skip it (station excluded from JSON). Log errors. Workflow succeeds even if some stations fail.

### 4.3 GitHub Action — Regulation Scraper

- **Schedule:** Weekly (Monday 09:00 CET)
- **Script:** `scrapers/scrape_regulations.py`
- **Process:**
  1. Check Narodne Novine for new fuel price regulations
  2. If new regulation detected: update `fuel_params.json` with new parameters
  3. Commit and push to `main` if changed
- **Note:** This is a best-effort scraper. Manual review recommended when regulations change — significant parameter changes should be verified before the app picks them up.

### 4.4 Remote Config URL Update

- Update `remote_config_service.dart` URL from `iersegovic/fuel-price-app` to `jurajnakic/fuel-price-app`

## 5. Version

- Bump app version from `1.0.0` to `2.0.0` (significant feature addition + rebrand)

## 6. What Does NOT Change

- Formula engine and price prediction logic
- FuelDetailPager with chart and swipe navigation
- Notification system
- WorkManager background sync for predictions
- Existing fuel types enum (ES95, ES100, Eurodizel, UNP 10kg)
