"""Is the P13/P14 miss a level shift (changed margin/excise) or a slope problem?

Holds the shipped factor fixed and solves for the offset each period needs.
A margin/excise change shows up as a step in the implied offset that is roughly
constant per fuel; a broken commodity relationship shows up as drift.

Also reports the effect of dropping weekend ticks (Yahoo posts a Sunday-evening
futures open that the government's business-day average would never include).

Usage: py bias_probe.py [db_path]
"""
import sqlite3
import sys
from datetime import date, timedelta

DB = sys.argv[1] if len(sys.argv) > 1 else 'fuel_prices_p14.db'
VAT = 0.25

EFFECTIVE = {
    'P5':  date(2026, 5,  5), 'P6':  date(2026, 5, 19), 'P7':  date(2026, 6,  2),
    'P8':  date(2026, 6, 16), 'P9':  date(2026, 6, 30), 'P10': date(2026, 7, 14),
    'P11': date(2026, 7, 28), 'P12': date(2026, 8, 11), 'P13': date(2026, 8, 18),
    'P14': date(2026, 8, 25),
}
WEEKLY = {'P13', 'P14'}

REAL = {
    'es95':         {'P5': 1.79, 'P6': 1.82, 'P7': 1.78, 'P8': 1.69, 'P9': 1.62,
                     'P10': 1.66, 'P11': 1.77, 'P12': 1.71, 'P13': 1.78, 'P14': 1.81},
    'eurodizel':    {'P5': 1.93, 'P6': 1.87, 'P7': 1.82, 'P8': 1.78, 'P9': 1.64,
                     'P10': 1.72, 'P11': 1.94, 'P12': 1.91, 'P13': 2.01, 'P14': 2.07},
    'plavi_dizel':  {'P5': 1.29, 'P6': 1.22, 'P7': 1.16, 'P8': 1.11, 'P9': 0.96,
                     'P10': 1.05, 'P11': 1.28, 'P12': 1.24, 'P13': 1.36, 'P14': 1.41},
    'unp_10kg':     {'P5': 2.44, 'P6': 2.30, 'P7': 2.21, 'P8': 2.11, 'P9': 2.00,
                     'P10': 2.02, 'P11': 2.10, 'P12': 2.02, 'P13': 2.05, 'P14': 2.09},
    'unp_spremnik': {'P5': 1.73, 'P6': 1.59, 'P7': 1.50, 'P8': 1.40, 'P9': 1.30,
                     'P10': 1.32, 'P11': 1.39, 'P12': 1.31, 'P13': 1.35, 'P14': 1.38},
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


def rows_for(src, pname, drop_weekend):
    pub = EFFECTIVE[pname] - timedelta(days=1)
    start = pub - timedelta(days=7 if pname in WEEKLY else 14)
    rows = [(date.fromisoformat(d[:10]), v) for d, v in con.execute(
        "SELECT date, cif_med FROM oil_prices WHERE source=? AND date >= ? AND date < ? "
        "ORDER BY date", (src, start.isoformat(), pub.isoformat()))]
    if drop_weekend:
        rows = [(d, v) for d, v in rows if d.weekday() < 5]
    return rows


def retail(cfg, rows, offset):
    cifs = [v * cfg['factor'] + offset for _, v in rows]
    rates = [rate_for(d) for d, _ in rows]
    pc = cfg['density'] * (sum(cifs) / len(cifs)) / (sum(rates) / len(rates)) / 1000 \
        + cfg['premium']
    return (pc + cfg['excise']) * (1 + VAT)


def implied_offset(cfg, rows, real):
    """Offset that reproduces `real` exactly, factor held fixed."""
    rates = [rate_for(d) for d, _ in rows]
    avg_rate = sum(rates) / len(rates)
    avg_raw = sum(v for _, v in rows) / len(rows)
    base = real / (1 + VAT) - cfg['excise'] - cfg['premium']
    target_cif = base * avg_rate * 1000 / cfg['density']
    return target_cif - cfg['factor'] * avg_raw


for drop_weekend in (False, True):
    print('\n' + '=' * 78)
    print('VIKEND TICKOVI: %s' % ('IZBACENI (samo pon-pet)' if drop_weekend else 'ukljuceni'))
    print('=' * 78)
    for fuel, cfg in CFG.items():
        line_off, line_err = [], []
        for pname in EFFECTIVE:
            rows = rows_for(cfg['src'], pname, drop_weekend)
            if len(rows) < 1:
                continue
            R = REAL[fuel][pname]
            pred = round(retail(cfg, rows, cfg['offset']) * 100) / 100
            line_err.append('%s:%+.0f' % (pname, (pred - R) * 100))
            line_off.append('%s:%.0f' % (pname, implied_offset(cfg, rows, R)))
        print('\n%s  (shipped offset=%.1f)' % (fuel, cfg['offset']))
        print('  greska:          ' + ' '.join(line_err))
        print('  potreban offset: ' + ' '.join(line_off))

print('\n' + '=' * 78)
print('KOLIKO BI TREBALO POMAKNUTI PREMIJU (EUR/l ili EUR/kg) da P13+P14 sjednu')
print('=' * 78)
for fuel, cfg in CFG.items():
    deltas = []
    for pname in ('P13', 'P14'):
        rows = rows_for(cfg['src'], pname, True)
        if not rows:
            continue
        pred = retail(cfg, rows, cfg['offset'])
        deltas.append((REAL[fuel][pname] - pred) / (1 + VAT))
    if deltas:
        print('  %-14s premija %.4f -> %.4f  (delta %+.4f EUR, po periodu: %s)'
              % (fuel, cfg['premium'], cfg['premium'] + sum(deltas) / len(deltas),
                 sum(deltas) / len(deltas),
                 ', '.join('%+.4f' % d for d in deltas)))
