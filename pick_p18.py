"""Pick the coefficients to ship after the P18 validation.

Walk-forward (holdout_p18.py) settled WHICH source each fuel should use.
This settles WHICH fit window, by scoring candidate windows on the weekly
regime only (P13-P18) — that is the regime the app will actually predict in,
so a fit that looks good on the 14-day era is not what we want.

Prints ready-to-paste Dart values.

Usage: py pick_p18.py [db_path]
"""
import sqlite3
import sys
from datetime import date, timedelta

DB = sys.argv[1] if len(sys.argv) > 1 else 'fuel_prices_p18.db'
VAT = 0.25

EFFECTIVE = {
    'P1':  date(2026, 3, 10), 'P2':  date(2026, 3, 24), 'P3':  date(2026, 4,  7),
    'P4':  date(2026, 4, 21), 'P5':  date(2026, 5,  5), 'P6':  date(2026, 5, 19),
    'P7':  date(2026, 6,  2), 'P8':  date(2026, 6, 16), 'P9':  date(2026, 6, 30),
    'P10': date(2026, 7, 14), 'P11': date(2026, 7, 28), 'P12': date(2026, 8, 11),
    'P13': date(2026, 8, 18), 'P14': date(2026, 8, 25), 'P15': date(2026, 9,  1),
    'P16': date(2026, 9,  8), 'P17': date(2026, 9, 15), 'P18': date(2026, 9, 22),
}
WEEKLY = {'P13', 'P14', 'P15', 'P16', 'P17', 'P18'}
SCORE_ON = ['P13', 'P14', 'P15', 'P16', 'P17', 'P18']

REAL = {
    'es95':         {'P1': 1.55, 'P2': 1.71, 'P3': 1.76, 'P4': 1.74, 'P5': 1.79,
                     'P6': 1.82, 'P7': 1.78, 'P8': 1.69, 'P9': 1.62, 'P10': 1.66,
                     'P11': 1.77, 'P12': 1.71, 'P13': 1.78, 'P14': 1.81,
                     'P15': 1.82, 'P16': 1.88, 'P17': 1.93, 'P18': 1.95},
    'eurodizel':    {'P1': 1.72, 'P2': 1.86, 'P3': 2.06, 'P4': 1.99, 'P5': 1.93,
                     'P6': 1.87, 'P7': 1.82, 'P8': 1.78, 'P9': 1.64, 'P10': 1.72,
                     'P11': 1.94, 'P12': 1.91, 'P13': 2.01, 'P14': 2.07,
                     'P15': 1.97, 'P16': 2.10, 'P17': 2.16, 'P18': 2.26},
    'plavi_dizel':  {'P1': 1.06, 'P2': 1.23, 'P3': 1.42, 'P4': 1.36, 'P5': 1.29,
                     'P6': 1.22, 'P7': 1.16, 'P8': 1.11, 'P9': 0.96, 'P10': 1.05,
                     'P11': 1.28, 'P12': 1.24, 'P13': 1.36, 'P14': 1.41,
                     'P15': 1.30, 'P16': 1.44, 'P17': 1.49, 'P18': 1.60},
    'unp_10kg':     {'P1': 2.58, 'P2': 2.77, 'P3': 2.79, 'P4': 2.61, 'P5': 2.44,
                     'P6': 2.30, 'P7': 2.21, 'P8': 2.11, 'P9': 2.00, 'P10': 2.02,
                     'P11': 2.10, 'P12': 2.02, 'P13': 2.05, 'P14': 2.09,
                     'P15': 2.06, 'P16': 2.14, 'P17': 2.19, 'P18': 2.23},
    'unp_spremnik': {'P1': 1.87, 'P2': 2.07, 'P3': 2.09, 'P4': 1.91, 'P5': 1.73,
                     'P6': 1.59, 'P7': 1.50, 'P8': 1.40, 'P9': 1.30, 'P10': 1.32,
                     'P11': 1.39, 'P12': 1.31, 'P13': 1.35, 'P14': 1.38,
                     'P15': 1.36, 'P16': 1.44, 'P17': 1.49, 'P18': 1.52},
}

EIA_PROPANE = 'EER_EPLLPA_PF4_Y44MB_DPG'

# Source per fuel decided by walk-forward hold-out; ES95 moved off RB=F.
CHOSEN = {
    'es95':         {'density': 0.755, 'premium': 0.1545, 'excise': 0.45600, 'src': 'HO=F'},
    'eurodizel':    {'density': 0.845, 'premium': 0.1545, 'excise': 0.40613, 'src': 'GASOIL_USD'},
    'plavi_dizel':  {'density': 0.845, 'premium': 0.0781, 'excise': 0.00000, 'src': 'GASOIL_USD'},
    'unp_10kg':     {'density': None,  'premium': 0.8429, 'excise': 0.01327, 'src': 'PROPANE_MONT_BELVIEU_USD'},
    'unp_spremnik': {'density': None,  'premium': 0.4116, 'excise': 0.01327, 'src': 'PROPANE_MONT_BELVIEU_USD'},
}

# Fallback sources must be refit too: PriceBlender falls back to equal weights
# across whatever has data when the weighted source is missing, so stale
# fallback coefficients get used silently.
FALLBACKS = {
    'es95':         [('yahoo_alt', 'RB=F'), ('eia', 'EER_EPMRU_PF4_Y35NY_DPG')],
    'eurodizel':    [('yahoo', 'HO=F'), ('eia', 'EER_EPD2DXL0_PF4_Y35NY_DPG')],
    'plavi_dizel':  [('yahoo', 'HO=F'), ('eia', 'EER_EPD2DXL0_PF4_Y35NY_DPG')],
    'unp_10kg':     [('eia', EIA_PROPANE)],
    'unp_spremnik': [('eia', EIA_PROPANE)],
}

con = sqlite3.connect(DB)
RATES = [(date.fromisoformat(d[:10]), r) for d, r
         in con.execute("SELECT date, usd_eur FROM exchange_rates ORDER BY date")]


def rate_for(d):
    best = None
    for dt, r in RATES:
        if dt <= d:
            best = r
        else:
            break
    return best or RATES[-1][1]


def rows_for(src, pname):
    pub = EFFECTIVE[pname] - timedelta(days=1)
    start = pub - timedelta(days=7 if pname in WEEKLY else 14)
    rows = [(date.fromisoformat(d[:10]), v) for d, v in con.execute(
        "SELECT date, cif_med FROM oil_prices WHERE source=? AND date >= ? AND date < ? "
        "ORDER BY date", (src, start.isoformat(), pub.isoformat()))]
    return [(d, v) for d, v in rows if d.weekday() < 5]


def ls_fit(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    den = sum((x - mx) ** 2 for x in xs)
    f = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0
    return f, my - f * mx


def fit_over(fuel, cfg, src, names):
    xs, ys, used = [], [], []
    for pname in names:
        rows = rows_for(src, pname)
        if not rows:
            continue
        rates = [rate_for(d) for d, _ in rows]
        base = REAL[fuel][pname] / (1 + VAT) - cfg['excise'] - cfg['premium']
        xs.append(sum(v for _, v in rows) / len(rows))
        ys.append(base * (sum(rates) / len(rates)) * 1000 / (cfg['density'] or 1.0))
        used.append(pname)
    if len(xs) < 2:
        return None
    f, o = ls_fit(xs, ys)
    return f, o, used


def predict(cfg, rows, f, o):
    avg_cif = sum(v * f + o for _, v in rows) / len(rows)
    avg_rate = sum(rate_for(d) for d, _ in rows) / len(rows)
    pc = (cfg['density'] or 1.0) * avg_cif / avg_rate / 1000 + cfg['premium']
    return round((pc + cfg['excise']) * (1 + VAT) * 100) / 100


def score(fuel, cfg, src, f, o):
    errs = []
    for pname in SCORE_ON:
        rows = rows_for(src, pname)
        if rows:
            errs.append(predict(cfg, rows, f, o) - REAL[fuel][pname])
    return errs


names_all = list(EFFECTIVE)
CANDIDATES = [
    ('svi', names_all),
    ('zadnjih 10', names_all[-10:]),
    ('zadnjih 8', names_all[-8:]),
    ('tjedni rezim (P13-P18)', SCORE_ON),
]

# The window is NOT chosen by the MAE printed below: those periods are the same
# ones the narrower windows fit on, so that score is in-sample and always
# flatters the narrowest window (UNP's 0.5c is fitting its own training data).
# holdout_p18.py already answered this honestly — it fits only on earlier
# periods — and what it validates is "fit on everything available". So that is
# the default here, with one documented exception.
WINDOW_FOR = {
    'es95': 'svi',
    'eurodizel': 'svi',
    'plavi_dizel': 'svi',
    # Mont Belvieu only starts 2026-04-22 and its earliest points are sparse
    # noise (they drove the -34c misses on P5/P6). Same call as the P10 session.
    'unp_10kg': 'zadnjih 8',
    'unp_spremnik': 'zadnjih 8',
}
WHY = {
    'es95': 'walk-forward validirao fit na svim ranijim podacima',
    'eurodizel': 'walk-forward validirao fit na svim ranijim podacima',
    'plavi_dizel': 'walk-forward validirao fit na svim ranijim podacima',
    'unp_10kg': 'rane Mont Belvieu tocke su sum, izbacene',
    'unp_spremnik': 'rane Mont Belvieu tocke su sum, izbacene',
}

print('Greske na P13-P18 po kandidatu za prozor fita.')
print('PAZNJA: za uze prozore je to IN-SAMPLE broj — ne birati po njemu.')
print('Izbor dolazi iz holdout_p18.py (walk-forward).\n')
chosen_out = {}
for fuel, cfg in CHOSEN.items():
    print('=== %s  <- %s' % (fuel, cfg['src']))
    best = None
    for label, names in CANDIDATES:
        r = fit_over(fuel, cfg, cfg['src'], names)
        if not r:
            continue
        f, o, used = r
        errs = score(fuel, cfg, cfg['src'], f, o)
        mae = sum(abs(e) for e in errs) / len(errs)
        cells = ' '.join('%+3.0f' % (e * 100) for e in errs)
        print('   %-24s f=%10.4f o=%10.4f  n=%2d  [%s]  MAE=%4.1fc'
              % (label, f, o, len(used), cells, mae * 100))
        if label == WINDOW_FOR[fuel]:
            best = (mae, f, o, label)
    chosen_out[fuel] = best
    print('   -> biram: %s (MAE %.1fc in-sample) — %s\n'
          % (best[3], best[0] * 100, WHY[fuel]))

print('\n' + '=' * 78)
print('ZA UPIS U fuel_params.dart')
print('=' * 78)
for fuel, (mae, f, o, label) in chosen_out.items():
    print("  %-14s src=%-26s factor=%9.4f  offset=%10.4f   (%s, MAE %.1fc)"
          % (fuel, CHOSEN[fuel]['src'], f, o, label, mae * 100))

print('\nREZERVNI izvori (PriceBlender ih tiho koristi kad primarni nema podatke):')
for fuel, fbs in FALLBACKS.items():
    cfg = CHOSEN[fuel]
    for kind, src in fbs:
        r = fit_over(fuel, cfg, src, names_all)
        if not r:
            print('  %-14s %-8s %-26s nema podataka' % (fuel, kind, src))
            continue
        f, o, used = r
        errs = score(fuel, cfg, src, f, o)
        mae = sum(abs(e) for e in errs) / len(errs) if errs else float('nan')
        print('  %-14s %-8s %-26s factor=%9.4f offset=%10.4f  MAE=%4.1fc'
              % (fuel, kind, src, f, o, mae * 100))
