"""Hold-out test for the post-18.8. regime.

Everything so far says P13/P14 sit on a level shift, not a broken slope. If that
is true, correcting the offset on P13 alone should predict P14 well. If P14 is
still off, the shift is not a one-off constant and we need more periods.

Two variants are compared:
  A) shipped factor, offset refit on P13 only        -> predict P14
  B) shipped factor, offset refit on P13+P14         -> in-sample floor

Window: 7 days (confirmed by the August regulation), weekdays only.

Usage: py holdout_p14.py [db_path]
"""
import sqlite3
import sys
from datetime import date, timedelta

DB = sys.argv[1] if len(sys.argv) > 1 else 'fuel_prices_p14.db'
VAT = 0.25

EFFECTIVE = {'P11': date(2026, 7, 28), 'P12': date(2026, 8, 11),
             'P13': date(2026, 8, 18), 'P14': date(2026, 8, 25)}
WEEKLY = {'P13', 'P14'}

REAL = {
    'es95':         {'P11': 1.77, 'P12': 1.71, 'P13': 1.78, 'P14': 1.81},
    'eurodizel':    {'P11': 1.94, 'P12': 1.91, 'P13': 2.01, 'P14': 2.07},
    'plavi_dizel':  {'P11': 1.28, 'P12': 1.24, 'P13': 1.36, 'P14': 1.41},
    'unp_10kg':     {'P11': 2.10, 'P12': 2.02, 'P13': 2.05, 'P14': 2.09},
    'unp_spremnik': {'P11': 1.39, 'P12': 1.31, 'P13': 1.35, 'P14': 1.38},
}

CFG = {
    'es95':         {'density': 0.755, 'premium': 0.1545, 'excise': 0.45600,
                     'src': 'RB=F', 'factor': 383.647, 'offset': -57.679},
    'eurodizel':    {'density': 0.845, 'premium': 0.1545, 'excise': 0.40613,
                     'src': 'GASOIL_USD', 'factor': 0.8708, 'offset': 229.789},
    'plavi_dizel':  {'density': 0.845, 'premium': 0.0781, 'excise': 0.00000,
                     'src': 'GASOIL_USD', 'factor': 0.9765, 'offset': 48.104},
    'unp_10kg':     {'density': 1.0, 'premium': 0.8429, 'excise': 0.01327,
                     'src': 'PROPANE_MONT_BELVIEU_USD', 'factor': 1166.446, 'offset': 50.643},
    'unp_spremnik': {'density': 1.0, 'premium': 0.4116, 'excise': 0.01327,
                     'src': 'PROPANE_MONT_BELVIEU_USD', 'factor': 1076.654, 'offset': -34.083},
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


def retail(cfg, rows, offset):
    cifs = [v * cfg['factor'] + offset for _, v in rows]
    rates = [rate_for(d) for d, _ in rows]
    pc = cfg['density'] * (sum(cifs) / len(cifs)) / (sum(rates) / len(rates)) / 1000 \
        + cfg['premium']
    return (pc + cfg['excise']) * (1 + VAT)


def implied_offset(cfg, rows, real):
    rates = [rate_for(d) for d, _ in rows]
    avg_raw = sum(v for _, v in rows) / len(rows)
    base = real / (1 + VAT) - cfg['excise'] - cfg['premium']
    return base * (sum(rates) / len(rates)) * 1000 / cfg['density'] - cfg['factor'] * avg_raw


print('HOLD-OUT: offset kalibriran na P13, provjera na P14 (7-dnevni prozor, radni dani)\n')
print('%-14s %8s %8s %8s %8s %8s' % ('gorivo', 'off_P13', 'pred_P14', 'real_P14', 'err_P14', 'n_dana'))
errs = []
for fuel, cfg in CFG.items():
    r13, r14 = rows_for(cfg['src'], 'P13'), rows_for(cfg['src'], 'P14')
    if not r13 or not r14:
        print('%-14s nedovoljno podataka (P13 n=%d, P14 n=%d)' % (fuel, len(r13), len(r14)))
        continue
    off13 = implied_offset(cfg, r13, REAL[fuel]['P13'])
    pred14 = round(retail(cfg, r14, off13) * 100) / 100
    e = pred14 - REAL[fuel]['P14']
    errs.append(e)
    print('%-14s %8.1f %8.2f %8.2f %+7.0fc %8d'
          % (fuel, off13, pred14, REAL[fuel]['P14'], e * 100, len(r14)))
if errs:
    print('\nMAE na P14 (out-of-sample) = %.1fc' % (sum(abs(e) for e in errs) / len(errs) * 100))

print('\n\nZa usporedbu: koliko svaki period trazi offseta (faktor fiksan)')
print('%-14s %10s %10s %10s %10s' % ('gorivo', 'P11', 'P12', 'P13', 'P14'))
for fuel, cfg in CFG.items():
    cells = []
    for pname in ('P11', 'P12', 'P13', 'P14'):
        rows = rows_for(cfg['src'], pname)
        cells.append('%10.0f' % implied_offset(cfg, rows, REAL[fuel][pname]) if rows else '%10s' % '-')
    print('%-14s %s' % (fuel, ' '.join(cells)))
