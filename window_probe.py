"""Grid search over settlement-window shape for the weekly regime (P13, P14).

The shipped coefficients scored 0..-1c on P11/P12 and then -8..-14c on P13/P14,
i.e. exactly when the government moved to weekly changes. Either the window
changed shape, or something else in their formula did. This brute-forces window
length and end-offset against the known P13/P14 prices, using the fuels whose
coefficients are known-good (ES95 on RB=F, diesel on GASOIL).

Usage: py window_probe.py [db_path]
"""
import sqlite3
import sys
from datetime import date, timedelta

DB = sys.argv[1] if len(sys.argv) > 1 else 'fuel_prices_p14.db'
VAT = 0.25

EFFECTIVE = {'P11': date(2026, 7, 28), 'P12': date(2026, 8, 11),
             'P13': date(2026, 8, 18), 'P14': date(2026, 8, 25)}

REAL = {
    'es95':        {'P11': 1.77, 'P12': 1.71, 'P13': 1.78, 'P14': 1.81},
    'eurodizel':   {'P11': 1.94, 'P12': 1.91, 'P13': 2.01, 'P14': 2.07},
    'plavi_dizel': {'P11': 1.28, 'P12': 1.24, 'P13': 1.36, 'P14': 1.41},
}

CFG = {
    'es95':        {'density': 0.755, 'premium': 0.1545, 'excise': 0.45600,
                    'src': 'RB=F', 'factor': 383.647, 'offset': -57.679},
    'eurodizel':   {'density': 0.845, 'premium': 0.1545, 'excise': 0.40613,
                    'src': 'GASOIL_USD', 'factor': 0.8708, 'offset': 229.789},
    'plavi_dizel': {'density': 0.845, 'premium': 0.0781, 'excise': 0.00000,
                    'src': 'GASOIL_USD', 'factor': 0.9765, 'offset': 48.104},
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
    return best


def series(source, start, end_excl):
    return [(date.fromisoformat(d[:10]), v) for d, v in con.execute(
        "SELECT date, cif_med FROM oil_prices WHERE source=? AND date >= ? AND date < ? "
        "ORDER BY date", (source, start.isoformat(), end_excl.isoformat()))]


def predict(cfg, rows):
    if not rows:
        return None
    cifs = [v * cfg['factor'] + cfg['offset'] for _, v in rows]
    rates = [rate_for(d) or RATES[-1][1] for d, _ in rows]
    pc = cfg['density'] * (sum(cifs) / len(cifs)) / (sum(rates) / len(rates)) / 1000 \
        + cfg['premium']
    return round((pc + cfg['excise']) * (1 + VAT) * 100) / 100


print('DB=%s' % DB)
print('Trazim (duljina, pomak kraja) koji minimizira |greska| na P13+P14,')
print('uz provjeru da isti oblik ne razbije P11/P12 (koji su bili tocni na 14d).\n')

results = []
for length in range(3, 22):
    for shift in range(-4, 5):
        rows_ok = True
        errs = {}
        for fuel, cfg in CFG.items():
            for pname in ('P13', 'P14'):
                pub = EFFECTIVE[pname] - timedelta(days=1) + timedelta(days=shift)
                rows = series(cfg['src'], pub - timedelta(days=length), pub)
                pred = predict(cfg, rows)
                if pred is None or len(rows) < 2:
                    rows_ok = False
                    break
                errs['%s/%s' % (fuel, pname)] = pred - REAL[fuel][pname]
            if not rows_ok:
                break
        if not rows_ok:
            continue
        mae = sum(abs(e) for e in errs.values()) / len(errs)
        bias = sum(errs.values()) / len(errs)
        results.append((mae, bias, length, shift, dict(errs)))

results.sort()
print('%-6s %-6s %-6s %-6s  %s' % ('MAE', 'bias', 'duljina', 'pomak', 'greske po gorivu/periodu'))
for mae, bias, length, shift, errs in results[:12]:
    detail = ' '.join('%s:%+.0f' % (k.split('/')[0][:4] + k.split('/')[1][1:], v * 100)
                      for k, v in errs.items())
    print('%5.1fc %+5.1fc %5d %6d   %s' % (mae * 100, bias * 100, length, shift, detail))

print('\n--- referenca: proizvodni oblik (14 dana, pomak 0) i tjedni (7, 0) ---')
for length, shift in ((14, 0), (7, 0)):
    line = []
    for fuel, cfg in CFG.items():
        for pname in ('P11', 'P12', 'P13', 'P14'):
            pub = EFFECTIVE[pname] - timedelta(days=1) + timedelta(days=shift)
            rows = series(cfg['src'], pub - timedelta(days=length), pub)
            pred = predict(cfg, rows)
            if pred is not None:
                line.append('%s%s:%+.0fc' % (fuel[:4], pname[1:], (pred - REAL[fuel][pname]) * 100))
    print('  d=%-2d s=%d  %s' % (length, shift, ' '.join(line)))

print('\n--- sirovi commodity prosjeci po tjednu (kontekst kretanja) ---')
for src in ('RB=F', 'GASOIL_USD'):
    print(' ', src)
    for wk_end in (date(2026, 7, 27), date(2026, 8, 3), date(2026, 8, 10),
                   date(2026, 8, 17), date(2026, 8, 24)):
        rows = series(src, wk_end - timedelta(days=7), wk_end)
        if rows:
            print('    tjedan do %s: n=%d avg=%.3f' % (wk_end, len(rows),
                                                       sum(v for _, v in rows) / len(rows)))
