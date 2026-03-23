# Fuel Price Prediction App — V2 Design Update

**Date:** 2026-03-23
**Status:** Approved
**Builds on:** Previous design (2026-03-21 brainstorming session)

---

## Overview

This document describes updates to the Croatian fuel price prediction app. The core functionality (formula engine, data sources, tech stack) remains unchanged from the original design. This spec covers UI restructuring, regulatory tracking, notifications, and quality-of-life improvements.

## Changes from V1 Design

### 1. Navigation Restructure

**Previous:** Single dashboard with PageView swipe between 4 fuel types.
**New:** Two-level navigation — fuel list screen → fuel detail screen.

### 2. Home Screen — Fuel Price List

The app opens to a list of all fuel types with their current prices.

- Each row displays: fuel name + current price (e.g., "Eurosuper 95 — 1,42 €")
- Prices displayed with **2 decimal places**, rounded mathematically
- **Drag & drop reordering** — user holds and drags a row to rearrange
  - Order persisted locally (SharedPreferences or SQLite)
  - This order is used everywhere (list, swipe navigation, notifications)
- Tap on a fuel → opens detail screen for that fuel
- Only fuels enabled in settings are shown (default: all enabled)

### 3. Detail Screen — Prediction & Chart

Opened by tapping a fuel on the home screen.

- **Predicted price** for next Tuesday — large, prominent
- **Price difference** vs. current price (green = drop, red = rise, grey = unchanged)
- **Price chart** — default 30 days, selectable periods (7d/30d/90d/6m/1y)
- **Last price change date** — displayed on screen (e.g., "Zadnja izmjena: 18.03.2026.")
- **Swipe left/right** to navigate between fuels — follows user's drag & drop order
- **Dot indicator** at top showing current position
- Back button / swipe back → returns to fuel list
- **Tablet (>600dp):** grid layout instead of swipe

### 4. Settings

Updated settings screen with new sections:

#### Display
- **Fuel visibility** — checkboxes to show/hide each fuel type (default: all on)
- **Theme** — dark / light / system

#### Notifications
- **Notification fuels** — checkboxes to select which fuels appear in notification (default: all active)
- **Notification day** — picker: Saturday / Sunday / Monday (default: Monday)
- **Notification time** — hour picker 0-23 (default: 9:00)
- **Enable/disable** — toggle to turn off notifications entirely

#### Regulatory Info
- **Current regulation** — name, NN reference, effective date
  - e.g., "Uredba o utvrđivanju najviših maloprodajnih cijena naftnih derivata — NN 31/2025"
- **Link to Narodne novine** — opens in browser
- **Last parameter update** — date when remote config was last fetched

#### About
- Disclaimer text (same as first-launch dialog)
- App version
- Formula explanation

### 5. Remote Configuration

A JSON file hosted on GitHub (project repository) for updating regulatory parameters without app updates.

**File:** `config/fuel_params.json`

**Contents:**
```json
{
  "version": "2025-02-26",
  "price_regulation": {
    "name": "Uredba o utvrđivanju najviših maloprodajnih cijena naftnih derivata",
    "nn_reference": "NN 31/2025",
    "effective_date": "2025-02-26",
    "nn_url": "https://narodne-novine.nn.hr/clanci/sluzbeni/full/2025_02_31_326.html"
  },
  "excise_regulation": {
    "name": "Uredba o visini trošarine na energente i električnu energiju",
    "nn_reference": "NN 156/2022 (konsolidirana)",
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

**Note on excise duties:** The excise rates (trošarina) are set by a separate regulation ("Uredba o visini trošarine na energente i električnu energiju") and change periodically by government decree. The values above are the standard rates before any temporary government intervention. Current rates: benzin 456,00 EUR/1000L, dizel 406,13 EUR/1000L, UNP 13,27 EUR/1000kg.

**Behavior:**
- Fetched once daily (alongside 16:00 CET price data fetch)
- On fetch failure → use built-in (bundled) parameters as fallback
- When a change is detected (version field differs) → show in-app notification to user: "Ažurirani parametri prema NN XX/YYYY"
- Built-in parameters are updated with each app release

### 6. Disclaimer

**First launch:** Modal dialog that user must acknowledge (single "Razumijem" button).

**Text:**
> Ovo je neslužbena aplikacija. Prikazane cijene su procjena temeljena na javno dostupnim podacima i važećoj regulativi. Moguća su odstupanja od stvarnih cijena zbog intervencija Vlade, promjena regulatornog okvira ili nedostupnosti podataka. Aplikacija ne preuzima odgovornost za točnost prikazanih cijena.

**Permanently accessible** in Settings → About.

### 7. Price Rounding

- All displayed prices rounded to **2 decimal places**
- Standard mathematical rounding (0.5 rounds up)
- Rounding applied to the **final calculated price only** — intermediate calculation steps use full precision
- Implementation: Dart `double.toStringAsFixed(2)` for display, or `(price * 100).round() / 100` for stored values

### 8. Notifications

Local notifications to remind user before Tuesday price changes.

**Configuration (in Settings):**
- Which fuels to include (checkboxes, default: all active)
- Day: Saturday / Sunday / Monday (default: Monday)
- Time: 0-23 hours (default: 9:00)
- On/off toggle

**Notification content:**
- Title: "Promjena cijene goriva sutra" if notification is on Monday, "Promjena cijene goriva u utorak" if Saturday or Sunday
- Body: one line per selected fuel with predicted price and direction arrow
  - e.g., "Eurodizel: 1,38 € ↓ | ES95: 1,42 € ↑"
  - ↑ = price increase vs. current, ↓ = decrease, no arrow if unchanged

**Behavior:**
- Only sent if prediction data is available (no empty notifications)
- Rescheduled whenever user changes day/time setting
- Implementation: `flutter_local_notifications` + `android_alarm_manager_plus` or `workmanager`
- Fully local — no push server required

---

## Unchanged from V1

The following remain as previously designed:

- **Fuel types:** Eurosuper 95, Eurosuper 100, Eurodizel, UNP boca 10kg
- **Tech stack:** Flutter, Bloc/Cubit, fl_chart, sqflite, dio/http
- **Architecture:** On-device, no backend server
- **Formula (per NN 31/2025):** PC = [(Σ CIF Med M × ρ ÷ T) ÷ n] + P; retail = PC + trošarina + PDV 25%. CIF Med from Platts (proxy: Yahoo Finance BZ=F, RB=F, HO=F), HNB EUR/USD rate, 14-day average. Biofuel fee is NOT part of the regulated price formula.
- **Data fetch:** Daily at 16:00 CET, hourly retry on failure, pull-to-refresh
- **Offline:** Cached data from SQLite
- **SQLite tables:** oil_prices, exchange_rates, predicted_prices, actual_prices
- **Privacy:** Internet permission only, no trackers, no personal data
- **Edge-to-edge UI:** Transparent status bar, hidden navigation keys
- **Data cleanup:** Records older than 2 years

---

## New SQLite Requirements

Additional data to persist:

- **fuel_order** — user's custom ordering of fuel types (fuel_id, position)
- **fuel_visibility** — which fuels are shown (fuel_id, visible boolean)
- **notification_settings** — day, hour, enabled, per-fuel toggles
- **config_version** — last fetched remote config version and timestamp
- **disclaimer_acknowledged** — boolean flag for first-launch dialog
