# FuelLens V3 — Design Spec

## Overview

Three changes to the fuel price prediction app:
1. **Rebrand** — new icon (`Ikona.png`), rename to "FuelLens"
2. **Bottom navigation** — 3 tabs (Predikcije, Postaje, Postavke)
3. **Station prices feature** — current fuel prices at Croatian gas stations, scraped via GitHub Action

## 1. Icon & App Name

- Replace current app icon with `Ikona.png` (fuel nozzle + up/down arrows on blue background)
- Use `flutter_launcher_icons` to generate all Android densities
- For adaptive icon: use the image as foreground, keep blue (`#5B8DD9`) as background color
- Rename app to "FuelLens" everywhere:
  - `AndroidManifest.xml` → `android:label="FuelLens"`
  - `app.dart` → `title: 'FuelLens'`

## 2. Bottom Navigation Bar

- Replace current push/pop navigation with `NavigationBar` (Material 3)
- 3 destinations:
  1. **Predikcije** — icon: `Icons.trending_up` — current FuelListScreen
  2. **Postaje** — icon: `Icons.local_gas_station` — new StationListScreen
  3. **Postavke** — icon: `Icons.settings` — existing SettingsScreen
- Remove settings icon from FuelListScreen AppBar
- Each tab preserves state (use `IndexedStack` or similar)
- Detail screens (FuelDetailPager, station detail) still push as full-screen routes on top of the nav bar

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
- Fuel `type` field uses standardized keys: `es95`, `es100`, `eurodizel`, `lpg`, `premium_diesel`, `premium_95`, `unp_10kg`, etc.
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
- Standard fuel types (ES95, Eurodizel, etc.) listed first, then premium/specialty fuels

### 3.6 Data Layer

- **StationPriceService** — fetches `station_prices.json` from GitHub raw URL
- **StationRepository** — caches station data in SQLite, provides CRUD
- **StationsCubit** — manages state for station list and detail screens
- New SQLite tables: `stations`, `station_fuels`

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

## 5. What Does NOT Change

- Formula engine and price prediction logic
- FuelDetailPager with chart and swipe navigation
- Notification system
- WorkManager background sync for predictions
- Existing fuel types enum (ES95, ES100, Eurodizel, UNP 10kg)
