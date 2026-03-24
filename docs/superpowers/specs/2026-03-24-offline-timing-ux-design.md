# Offline UX, Market Timing & Stress Testing — Design Spec

**Date:** 2026-03-24
**Status:** Draft
**Builds on:** 2026-03-23 V2 Design, 2026-03-23 Implementation Plan

---

## Overview

This spec covers corrections and additions to the fuel price prediction app:

1. Market close time correction (16:00 → 18:00 CET)
2. Offline/empty state UX with first-launch auto-fetch
3. Spinner with 10-second timeout and error handling
4. Trend indicator on price display
5. Price change cycle via remote config
6. Stress tests for timeout, offline, and edge-case scenarios

---

## 1. Market Close Time Correction

**Problem:** Previous spec set data fetch at 16:00 CET (Zagreb). Yahoo Finance BZ=F prices come from ICE London. Platts MOC (Market on Close) ends at 16:30 London = 17:30 Zagreb. Fetching at 16:00 Zagreb (15:00 London) misses the last 1.5 hours of trading.

**Change:** Move daily data fetch from 16:00 CET to **18:00 CET** (17:00 London).

**Impact:**
- `WorkManager` periodic task schedule → 18:00 CET
- Retry logic unchanged (hourly on failure)
- Remote config fetch also moves to 18:00 CET (same trigger)

**V2 Spec Amendments Required:**
- V2 spec line 115: "alongside 16:00 CET price data fetch" → change to 18:00 CET
- V2 spec line 168: "Data fetch: Daily at 16:00 CET" → change to 18:00 CET

---

## 2. First Launch & Empty State UX

### Flow

```
App starts
  → Has data in SQLite?
    → YES → Show fuel list normally, background sync at 18:00
    → NO → Auto-attempt data fetch immediately
      → Show full-screen spinner (centered, with "Preuzimanje podataka..." text)
      → Success within 10s → Show fuel list
      → Failure/timeout → Show empty state screen
```

### Empty State Screen

**When shown:** First launch with no internet, or any state where SQLite has zero price data and fetch fails.

**Content:**
- Centered icon (e.g., cloud-off or signal-off icon)
- Text: **"Nema dostupnih podataka. Provjerite internetsku vezu i pritisnite gumb za ažuriranje."**
- Button: **"Ažuriraj"** (triggers manual fetch with spinner + 10s timeout)

**No "Dobrodošli" or formal welcome — keep it functional.**

### Subsequent Launches

- If SQLite has data → show it immediately, even if stale
- Display "Zadnje ažuriranje: DD.MM.YYYY. HH:mm" somewhere visible so user knows data freshness
- Background sync at 18:00 CET updates data silently

---

## 3. Spinner & Timeout Behavior

### Data Fetch Process

All three data sources (Yahoo Finance, HNB API, GitHub config) are fetched in parallel. **Partial success is allowed** — save what succeeds, retry only what fails.

**Timeout:** 10 seconds per source.

### Implementation

```
DataSyncCubit states:
  - SyncIdle              → no sync in progress
  - SyncInProgress        → spinner visible
  - SyncSuccess           → all sources fetched successfully
  - SyncPartial(failures) → some sources succeeded, some failed
  - SyncFailure(msg)      → all sources failed
```

**Behavior:**
1. Emit `SyncInProgress` → UI shows spinner with "Preuzimanje podataka..."
2. Start all 3 HTTP requests concurrently (each with 10s timeout)
3. As each source completes successfully → save its data to SQLite immediately
4. For each source that fails or times out → retry once (only that source)
5. After all complete (including retries):
   - **All succeeded** → emit `SyncSuccess`
   - **Some succeeded, some failed** → emit `SyncPartial` → save partial data, show snackbar: "Ažuriranje nije u potpunosti uspjelo. Prikazani su posljednji dostupni podaci."
   - **All failed** → emit `SyncFailure`
     - If SQLite has existing data → show stale data + snackbar: "Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci."
     - If SQLite is empty → show empty state screen with retry button

**UI always shows generic message** — no per-source details visible to user. Internally, failed sources are logged for debugging.

**Price calculation:** If oil prices succeed but exchange rate fails (or vice versa), the app uses the latest available data from SQLite for the missing source. Prediction is recalculated with whatever combination of fresh + cached data is available.

### Manual Refresh (Pull-to-Refresh)

Same logic: parallel fetch, 10s per source, retry failures once. On partial/full failure:
- Snackbar: "Ažuriranje nije uspjelo. Pokušajte ponovno kasnije."
- Existing data remains visible

---

## 4. Trend Indicator

### Display

Each fuel row on the home screen shows:

```
Eurosuper 95    1,42 €/L  ↑
Eurodizel       1,38 €/L  ↓
UNP boca 10kg   5,20 €/kg →
```

- **↑** (red) — predicted price is higher than current official price
- **↓** (green) — predicted price is lower than current official price
- **→** (grey) — no change (within ±0.005 € tolerance for rounding)
- No arrow — when there is no current official price yet (first prediction)

### Logic

```dart
/// Returns trend arrow, or null if current price is not available.
String? trendIndicator(double predicted, double? current) {
  if (current == null) return null; // no trend on first prediction
  final diff = predicted - current;
  if (diff > 0.005) return '↑';  // rise
  if (diff < -0.005) return '↓'; // drop
  return '→';                     // unchanged
}
```

When `trendIndicator` returns `null`, the UI shows only the predicted price without any arrow.

**Note:** The predicted price updates daily as new market data arrives. The trend compares the evolving prediction against the last official Tuesday price. This is the **B approach** — single predicted price with trend indicator, no daily price breakdown.

### Detail Screen

The detail screen already shows predicted price and price difference (green/red/grey). The trend indicator on the home screen is consistent with this — same comparison, just condensed.

---

## 5. Price Change Cycle — Remote Config

### New Fields in `fuel_params.json`

```json
{
  "version": "2025-02-26",
  "price_cycle": {
    "reference_date": "2026-03-24",
    "cycle_days": 14
  },
  ...existing fields...
}
```

### FuelParams Model Update

Add to `FuelParams`:
```dart
final String referenceDate;  // ISO date string "2026-03-24"
final int cycleDays;          // 14
```

With defaults:
```dart
referenceDate: '2026-03-24',
cycleDays: 14,
```

### Next Price Change Date Calculation

```dart
DateTime nextPriceChangeDate(DateTime today, DateTime referenceDate, int cycleDays) {
  // If reference date is in the future, that's the next change date
  if (today.isBefore(referenceDate)) return referenceDate;

  int daysDiff = today.difference(referenceDate).inDays;
  int cyclesPassed = (daysDiff / cycleDays).floor();

  // If today is exactly a cycle date, the change already happened today —
  // prediction targets the NEXT cycle
  return referenceDate.add(Duration(days: (cyclesPassed + 1) * cycleDays));
}
```

**Note:** On a price change date, the app shows the prediction for the *next* cycle (today + `cycleDays`), since today's change has already taken effect.

### Notification Scheduling

Notifications are scheduled relative to the next price change date:
- If user chose Monday → 1 day before
- If user chose Sunday → 2 days before
- If user chose Saturday → 3 days before

**Constraint:** `cycle_days` must be a multiple of 7 so that price changes always fall on the same weekday (Tuesday, given the reference date 2026-03-24 is a Tuesday). This keeps the notification text ("u utorak" / "sutra") correct. The remote config should enforce this constraint; if a non-multiple-of-7 value is received, fall back to 14.

After each cycle date passes, app recalculates and schedules the next notification.

---

## 6. Stress Tests

### 6.1 Timeout Tests

| Test | Description | Expected |
|------|-------------|----------|
| All sources timeout | Mock all 3 HTTP calls to delay >10s | `SyncFailure` emitted within ~10s, spinner stops |
| One source timeout | Mock Yahoo to delay >10s, others instant | `SyncFailure` emitted, all results discarded |
| Exact boundary | Mock responses at 9.9s and 10.1s | 9.9s succeeds, 10.1s fails |
| Repeated timeouts | 3 consecutive timeout attempts | Each shows error, no infinite spinner, no memory leak |

### 6.2 Offline / Empty State Tests

| Test | Description | Expected |
|------|-------------|----------|
| First launch, no internet | Empty DB + mocked network error | Auto-fetch fails → empty state with retry button |
| First launch, success | Empty DB + mocked success | Spinner → data shown |
| Stale data, no internet | DB has data + mocked network error | Stale data shown + snackbar warning |
| Retry after failure | Empty state → tap "Ažuriraj" → success | Spinner → data shown |
| Retry after failure again | Empty state → tap "Ažuriraj" → fail again | Spinner → error message again (no crash) |

### 6.3 Data Integrity Tests

| Test | Description | Expected |
|------|-------------|----------|
| Partial source failure | Yahoo OK, HNB fails after retry | Yahoo data saved, SyncPartial, prediction uses cached exchange rate |
| All sources fail | All 3 timeout after retry | Nothing saved, SyncFailure |
| Corrupt API response | Invalid JSON from Yahoo | Yahoo fails, retry, others saved if OK |
| Empty API response | Valid JSON but 0 records | Treated as failure for that source, retry |
| Duplicate dates | Same date data fetched twice | No duplicate DB records (UPSERT or skip) |
| Retry succeeds | Yahoo fails first try, succeeds on retry | All data saved, SyncSuccess |
| Cached + fresh mix | Fresh oil prices + cached exchange rate | Prediction calculated with mixed data |

### 6.4 Price Cycle Tests

| Test | Description | Expected |
|------|-------------|----------|
| Next cycle calculation | Various "today" dates relative to reference | Correct next change date returned |
| Cycle across year boundary | Reference 2026-12-29, today 2027-01-05 | Correct date in January |
| Remote config cycle change | cycle_days changes from 14 to 7 | Next date recalculated immediately |
| Notification rescheduling | User changes day from Monday to Saturday | Next notification date updated |

### 6.5 Trend Indicator Tests

| Test | Description | Expected |
|------|-------------|----------|
| Price increase | predicted=1.42, current=1.38 | ↑ (red) |
| Price decrease | predicted=1.35, current=1.38 | ↓ (green) |
| No change | predicted=1.380, current=1.382 | → (grey, within ±0.005) |
| Large swing | predicted=2.00, current=1.00 | ↑ (red) |
| First prediction | No current price exists | No trend shown (just price) |

### 6.6 Concurrent Operation Tests

| Test | Description | Expected |
|------|-------------|----------|
| Double fetch | User pull-to-refresh during auto-sync | Second request ignored or queued, no parallel fetches |
| Fetch during app close | App backgrounded during sync | WorkManager handles gracefully |
| Rapid retry | User taps "Ažuriraj" 5x quickly | Only one fetch runs at a time |

### 6.7 Scheduling Tests

| Test | Description | Expected |
|------|-------------|----------|
| WorkManager fires at 18:00 CET | Verify scheduled time is 18:00 CET | Task registered with correct time |
| DST transition (CET→CEST) | March 29, 2026 clock change | Task still fires at 18:00 local Zagreb time |
| Reference date in future | referenceDate = tomorrow | nextPriceChangeDate returns referenceDate |
| Invalid cycle_days | cycle_days = 10 (not multiple of 7) | Falls back to 14 |

---

## Impact on Existing Plan

| Area | Change |
|------|--------|
| `WorkManager` schedule | 16:00 → 18:00 CET |
| `DataSyncCubit` | Add `SyncPartial`/`SyncFailure` states, 10s per-source timeout, retry logic |
| `FuelParams` model | Add `referenceDate`, `cycleDays` |
| `fuel_params.json` | Add `price_cycle` section |
| Home screen | Add trend indicator (↑↓→) |
| Home screen | Add empty state / first-launch view |
| Notification scheduling | Use `price_cycle` from remote config instead of hardcoded "next Tuesday" |
| Test suite | Add stress tests from section 6 |

---

## V2 Spec Notification Alignment

V2 spec says "no arrow if unchanged" for notifications. This spec uses → (grey) for the home screen. To align:
- **Home screen:** Show → (grey) for unchanged prices
- **Notifications:** Omit fuels with unchanged prices entirely (no arrow, no line) — keeps notification text compact

---

## Out of Scope

- Daily price chart (option C — rejected)
- Push notifications via server
- Multiple language support
