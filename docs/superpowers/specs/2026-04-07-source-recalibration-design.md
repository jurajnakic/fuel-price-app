# Source Recalibration & EIA Fix — Design Spec

**Date:** 2026-04-07
**Context:** Period 3 validation (7.4.-20.4.) showed ES95 ~ok, Eurodizel -8c, UNP +15c errors.
Root causes: Brent is wrong proxy for diesel, EIA API broken (zero data in DB).

## Problem Summary

| Gorivo | Izvor (stari) | Problem |
|--------|--------------|---------|
| ES95 | Yahoo RB=F | ✓ Radi. Offset treba 259→261. |
| Eurodizel | Yahoo BZ=F (Brent) | Diesel crack spread varira, ±7c na 3 perioda, neodrživo |
| UNP 10kg | EIA propan (broken) | Zero EIA podataka u bazi — fallback na Brent × 16.2 potpuno kriv |

## Changes

### 1. ES95: offset tweak

- `cifMedOffsets['es95']`: 259 → 261
- `cifMedOffsets['es100']`: 259 → 261
- Verified: 0c error on all 3 known periods.

### 2. Eurodizel: switch to OilPriceAPI GASOIL_USD

**Source:** OilPriceAPI `GASOIL_USD` = ICE Low Sulphur Gasoil (USD/tonne).
This is the actual European diesel benchmark used to derive CIF Med diesel prices.

**Why better:** BZ=F is crude oil. The diesel crack spread (crude→diesel markup)
varies ±200 USD/t depending on refinery margins, seasonality, disruptions.
GASOIL_USD eliminates this variable entirely.

**Config changes in `fuel_params.dart`:**
- `sourceWeights['eurodizel']`: `{'yahoo': 1.0}` → `{'oilapi': 1.0}`
- `oilApiSymbols['eurodizel']`: `MGO_05S_NLRTM_USD` → `GASOIL_USD`
- `oilApiCifMedFactors['eurodizel']`: recalibrate (current 1.05 was for Rotterdam MGO)
- `oilApiCifMedOffsets` (new map): add offset for GASOIL_USD
- Yahoo BZ=F stays as fallback source for eurodizel (weight 0 in normal config,
  but PriceBlender equal-weight fallback kicks in if OilPriceAPI has no data)

**Calibration:** OilPriceAPI only provides latest price (no history endpoint
on free tier), so we cannot retroactively calibrate against 3 known periods.

Initial estimate: GASOIL_USD is ICE Low Sulphur Gasoil in USD/tonne — same
unit as CIF Med. The difference is freight/insurance to Mediterranean ports,
typically $30-50/t. So: `cifMed = GASOIL_USD × 1.0 + 40` as starting point.

Real calibration happens after the first full 14-day window accumulates
(~2 weeks after deployment). Compare app prediction vs actual Period 4 prices
(21.4.-4.5.) and adjust factor/offset via remote config.

**Accumulation period:** OilPriceAPI `latest` endpoint returns one data point per
call. The app already saves each fetch to `oil_prices` table. Over 14 days of
daily syncs, we accumulate enough data. During ramp-up (first 14 days), if
GASOIL_USD has fewer than `minPoints` (5), the PriceBlender fallback to Yahoo
BZ=F activates via the equal-weight mechanism.

**Explicit fallback:** Rather than relying on the accidental equal-weight
fallback in PriceBlender, add Yahoo BZ=F as a secondary source with explicit
weight. Config: `sourceWeights['eurodizel'] = {'oilapi': 1.0, 'yahoo': 0.0}`.
Background sync already computes Yahoo regardless of weight. If oilapi is
unavailable, PriceBlender sees only yahoo in prices map → equal-weight fallback
→ uses BZ=F × 11.23 + 205 (best-fit Brent params from 3-period LS).

### 3. UNP: fix EIA API encoding

**Bug:** Dio encodes `data[]` and `facets[series][]` query parameters incorrectly
for the EIA v2 API. The brackets get percent-encoded or the array notation is
mangled, causing the API to return empty data or 400 errors. The `catch (e)`
on line 78 silently swallows the error and returns `[]`.

**Fix:** In `eia_service.dart`, switch from Dio query parameters to a pre-built
URL string with the query parameters manually appended. This ensures the exact
format `data[0]=value&facets[series][]=SERIES_ID` that EIA v2 expects.

**Validation:** After fix, verify that the DB accumulates EIA propane data over
subsequent syncs.

**Calibration:** Once EIA data flows, re-verify the UNP factor (2153) and offset
(-13.5) against 3 known periods. The Period 1 and 2 calibration was done with
device-extracted EIA data that no longer exists in the DB, so we need to either:
- Wait for new data to accumulate (14+ days), or
- Fetch historical EIA data in a one-time backfill

**One-time backfill:** Add a `backfillDays` parameter to `fetchSpotPrices` and
call it with `days: 120` on first successful fetch to populate historical data.
This gives us immediate calibration capability. The existing `days: 60` default
in background_sync.dart already requests 60 days of history, so if the API call
succeeds, we get a full window immediately. No separate backfill needed.

### 4. OilPriceAPI rate limiting

**Current:** 48h cooldown between any OilPriceAPI fetches (SharedPreferences
`oilapi_last_fetch`). This was set when OilPriceAPI was a secondary source.

**New:** Daily fetch (no cooldown) for `GASOIL_USD` only. At 1 fetch/day,
that's ~30 requests/month out of 50 free tier limit. This leaves 20 requests
buffer for retries or app reinstalls.

**Change:** Remove the 48h cooldown in `background_sync.dart` lines 103-104.

### 5. Eurodizel Yahoo params update (BZ=F fallback)

Since BZ=F is now fallback-only for eurodizel, update its conversion params to
the best 3-period least-squares fit:
- `cifMedFactors['eurodizel']`: 6.04 → 11.23
- `cifMedOffsets['eurodizel']`: 648 → 205

This gives ±7c max error if BZ=F is used as fallback, vs ±17c with old params.

## Sync Timing Analysis

App syncs at **18:00 CET** (Zagreb local). Source availability at that time:

| Source | Market/Publish | At 18:00 CET | OK? |
|--------|---------------|-------------|-----|
| Yahoo RB=F | NYMEX, closes ~20:30 CET | Previous settlement available | ✓ |
| Yahoo BZ=F | ICE, closes ~19:30 CET | Previous settlement available | ✓ |
| OilPriceAPI GASOIL_USD | ICE, closes ~18:30 CET | Near-close or previous day | ✓ |
| EIA propane | Published ~18:00 ET (~00:00 CET+1) | 1-2 day lag | ✓ (14-day avg smooths lag) |
| ECB USD/EUR | Published ~16:00 CET | Today's rate available | ✓ |

**EIA 1-2 day lag** is fine: the 14-calendar-day window contains ~10 trading
days. Missing the last 1-2 days means ~8-9 points out of 10, well above
`minPoints=5`. The lag is consistent so the calibration factors absorb it.

**No timing changes needed.** 18:00 CET is good for all sources.

## Files to Modify

1. `lib/models/fuel_params.dart` — offsets, factors, source weights, symbols
2. `lib/data/services/eia_service.dart` — fix query parameter encoding
3. `lib/scheduling/background_sync.dart` — remove 48h OilPriceAPI cooldown, read oilapi offset from params instead of hardcoded 0.0
4. `lib/domain/price_blender.dart` — no changes (fallback logic already correct)
5. Tests — update affected tests

## Calibration Plan

**GASOIL_USD (eurodizel):** No historical data available. Deploy with
factor=1.0, offset=40 (estimate). After Period 4 actual prices arrive
(~21.4.), compare and adjust via remote config. No rebuild needed.

**EIA propane (UNP):** Once EIA fix is deployed, historical data (60 days)
flows immediately. Validate existing factor=2153, offset=-13.5 against
3 known periods. Adjust via remote config if needed.

## Out of Scope

- Additional data sources (FRED backup, EC Oil Bulletin)
- UI changes
- Remote config server changes (will update fuel_params.json separately after calibration)
