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

All three data sources (Yahoo Finance, HNB API, GitHub config) are fetched together. This is an **all-or-nothing** operation.

**Timeout:** 10 seconds total for all sources combined.

### Implementation

```
DataSyncCubit states:
  - SyncIdle          → no sync in progress
  - SyncInProgress    → spinner visible
  - SyncSuccess       → data loaded, transition to normal view
  - SyncFailure(msg)  → error message shown
```

**Behavior:**
1. Emit `SyncInProgress` → UI shows spinner overlay with "Preuzimanje podataka..."
2. Start all 3 HTTP requests concurrently
3. Wait for all to complete OR 10-second timeout (whichever comes first)
4. If all succeed → save to SQLite → emit `SyncSuccess`
5. If any fails or timeout → emit `SyncFailure`
   - If SQLite has existing data → show stale data + snackbar: "Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci."
   - If SQLite is empty → show empty state screen with retry button

**No partial saves.** If Yahoo succeeds but HNB fails, we discard all and retry next cycle.

### Manual Refresh (Pull-to-Refresh)

Same 10-second timeout and all-or-nothing logic. On failure:
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

### Logic

```dart
String trendIndicator(double predicted, double current) {
  final diff = predicted - current;
  if (diff > 0.005) return '↑';  // rise
  if (diff < -0.005) return '↓'; // drop
  return '→';                     // unchanged
}
```

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
  // Find the next cycle date on or after today
  int daysDiff = today.difference(referenceDate).inDays;
  int cyclesPassed = (daysDiff / cycleDays).floor();
  DateTime next = referenceDate.add(Duration(days: (cyclesPassed + 1) * cycleDays));
  // If today IS a change date, still show next one (current already happened)
  if (daysDiff % cycleDays == 0 && today.isAfter(referenceDate)) {
    // Today is a change date — prediction is for the NEXT cycle
    next = referenceDate.add(Duration(days: (cyclesPassed + 1) * cycleDays));
  }
  return next;
}
```

### Notification Scheduling

Notifications are scheduled relative to the next price change Tuesday:
- If user chose Monday → 1 day before
- If user chose Sunday → 2 days before
- If user chose Saturday → 3 days before

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
| Partial source failure | Yahoo OK, HNB fails | Nothing saved, SyncFailure |
| Corrupt API response | Invalid JSON from Yahoo | SyncFailure, existing data preserved |
| Empty API response | Valid JSON but 0 records | SyncFailure (no data to calculate) |
| Duplicate dates | Same date data fetched twice | No duplicate DB records (UPSERT or skip) |

### 6.4 Price Cycle Tests

| Test | Description | Expected |
|------|-------------|----------|
| Next cycle calculation | Various "today" dates relative to reference | Correct next Tuesday returned |
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

---

## Impact on Existing Plan

| Area | Change |
|------|--------|
| `WorkManager` schedule | 16:00 → 18:00 CET |
| `DataSyncCubit` | Add `SyncFailure` state, 10s timeout |
| `FuelParams` model | Add `referenceDate`, `cycleDays` |
| `fuel_params.json` | Add `price_cycle` section |
| Home screen | Add trend indicator (↑↓→) |
| Home screen | Add empty state / first-launch view |
| Notification scheduling | Use `price_cycle` from remote config instead of hardcoded "next Tuesday" |
| Test suite | Add stress tests from section 6 |

---

## Out of Scope

- Daily price chart (option C — rejected)
- Push notifications via server
- Multiple language support
