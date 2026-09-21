"""Walk-forward hold-out over P15-P18: fit on everything before period X,
then predict X blind. This is the only honest way to compare candidate
sources, because in-sample MAE always flatters the source with more freedom.

Motivation: RB=F decoupled from Croatian petrol during September (P15-P18
errors -8/-16/-21/-15c) while GASOIL_USD kept tracking it. Before moving
ES95 off the source that served it for a year, the replacement has to win
out-of-sample, not just in-sample.

Usage: py holdout_p18.py [db_path]
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
TEST = ['P15', 'P16', 'P17', 'P18']

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

PARAMS = {
    'es95':         {'density': 0.755, 'premium': 0.1545, 'excise': 0.45600,
                     'srcs': ['RB=F', 'GASOIL_USD', 'HO=F']},
    'eurodizel':    {'density': 0.845, 'premium': 0.1545, 'excise': 0.40613,
                     'srcs': ['GASOIL_USD', 'HO=F', 'BZ=F', 'EER_EPD2DXL0_PF4_Y35NY_DPG']},
    'plavi_dizel':  {'density': 0.845, 'premium': 0.0781, 'excise': 0.00000,
                     'srcs': ['GASOIL_USD', 'HO=F', 'BZ=F', 'EER_EPD2DXL0_PF4_Y35NY_DPG']},
    'unp_10kg':     {'density': None,  'premium': 0.8429, 'excise': 0.01327,
                     'srcs': ['PROPANE_MONT_BELVIEU_USD', EIA_PROPANE]},
    'unp_spremnik': {'density': None,  'premium': 0.4116, 'excise': 0.01327,
                     'srcs': ['PROPANE_MONT_BELVIEU_USD', EIA_PROPANE]},
}

# Currently shipped (fuel_params.dart 2026-07-24.1).
PRODUCTION = {
    'es95':         ('RB=F', 383.647, -57.679),
    'eurodizel':    ('GASOIL_USD', 0.8708, 229.789),
    'plavi_dizel':  ('GASOIL_USD', 0.9765, 48.104),
    'unp_10kg':     ('PROPANE_MONT_BELVIEU_USD', 1166.446, 50.643),
    'unp_spremnik': ('PROPANE_MONT_BELVIEU_USD', 1076.654, -34.083),
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


def target_cif(p, rows, real):
    rates = [rate_for(d) for d, _ in rows]
    base = real / (1 + VAT) - p['excise'] - p['premium']
    return base * (sum(rates) / len(rates)) * 1000 / (p['density'] or 1.0)


def predict(p, rows, f, o):
    avg_cif = sum(v * f + o for _, v in rows) / len(rows)
    avg_rate = sum(rate_for(d) for d, _ in rows) / len(rows)
    pc = (p['density'] or 1.0) * avg_cif / avg_rate / 1000 + p['premium']
    return round((pc + p['excise']) * (1 + VAT) * 100) / 100


def walk_forward(fuel, p, src):
    """For each test period, fit on every earlier period and predict it blind."""
    names = list(EFFECTIVE)
    errs = []
    for target in TEST:
        cutoff = names.index(target)
        xs, ys = [], []
        for pname in names[:cutoff]:
            rows = rows_for(src, pname)
            if not rows:
                continue
            xs.append(sum(v for _, v in rows) / len(rows))
            ys.append(target_cif(p, rows, REAL[fuel][pname]))
        test_rows = rows_for(src, target)
        if len(xs) < 3 or not test_rows:
            errs.append(None)
            continue
        f, o = ls_fit(xs, ys)
        errs.append(predict(p, test_rows, f, o) - REAL[fuel][target])
    return errs


print('WALK-FORWARD HOLD-OUT — svaki period predviden iz SAMO ranijih podataka')
print('(7-dnevni prozor od P13, radni dani)\n')
print('%-14s %-26s %7s %7s %7s %7s   %s'
      % ('gorivo', 'izvor', *TEST, 'MAE'))
print('-' * 86)

best_by_fuel = {}
for fuel, p in PARAMS.items():
    rows_out = []
    for src in p['srcs']:
        errs = walk_forward(fuel, p, src)
        ok = [e for e in errs if e is not None]
        if not ok:
            continue
        mae = sum(abs(e) for e in ok) / len(ok)
        cells = ' '.join('%+6.0fc' % (e * 100) if e is not None else '     -'
                         for e in errs)
        marker = ' <- sada' if src == PRODUCTION[fuel][0] else ''
        rows_out.append((mae, src, cells, marker))
    rows_out.sort()
    for mae, src, cells, marker in rows_out:
        print('%-14s %-26s %s  %5.1fc%s' % (fuel, src, cells, mae * 100, marker))
    if rows_out:
        best_by_fuel[fuel] = rows_out[0]
    print()

print('\nZAKLJUCAK (najbolji izvor po out-of-sample MAE):')
for fuel, (mae, src, _, _) in best_by_fuel.items():
    cur = PRODUCTION[fuel][0]
    verdict = 'ostaje' if src == cur else 'PREBACITI s %s' % cur
    print('  %-14s %-26s %5.1fc   %s' % (fuel, src, mae * 100, verdict))
