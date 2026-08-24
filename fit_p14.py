"""LS fit P1-P14, matching production windowing, with per-period window length.

New vs fit_p10.py:
- P11 (eff 2026-07-28), P12 (2026-08-11), P13 (2026-08-18), P14 (2026-08-25).
- The government switched to WEEKLY price changes from 2026-08-18 (temporary).
  P13/P14 are therefore 7-day periods. Whether the settlement WINDOW also
  shrank to 7 days is unknown, so it is configurable and both hypotheses are
  reported (--win7 / --win14).
- PRODUCTION reflects the coefficients shipped in fuel_params.dart 2026-07-24.1.

Usage: py fit_p14.py [db_path] [--win7|--win14]
"""
import sqlite3
import sys
from datetime import date, timedelta

argv = [a for a in sys.argv[1:] if not a.startswith('--')]
flags = [a for a in sys.argv[1:] if a.startswith('--')]
DB = argv[0] if argv else 'fuel_prices_p14.db'

EFFECTIVE = {
    'P1':  date(2026, 3, 10), 'P2':  date(2026, 3, 24), 'P3':  date(2026, 4,  7),
    'P4':  date(2026, 4, 21), 'P5':  date(2026, 5,  5), 'P6':  date(2026, 5, 19),
    'P7':  date(2026, 6,  2), 'P8':  date(2026, 6, 16), 'P9':  date(2026, 6, 30),
    'P10': date(2026, 7, 14), 'P11': date(2026, 7, 28), 'P12': date(2026, 8, 11),
    'P13': date(2026, 8, 18), 'P14': date(2026, 8, 25),
}

# Settlement window length per period. Weekly regime from P13.
WEEKLY = {'P13', 'P14'}
FORCE = 7 if '--win7' in flags else (14 if '--win14' in flags else None)


def window_days(pname):
    if FORCE is not None and pname in WEEKLY:
        return FORCE
    return 7 if pname in WEEKLY else 14


REAL = {
    'es95':         {'P1': 1.55, 'P2': 1.71, 'P3': 1.76, 'P4': 1.74, 'P5': 1.79,
                     'P6': 1.82, 'P7': 1.78, 'P8': 1.69, 'P9': 1.62, 'P10': 1.66,
                     'P11': 1.77, 'P12': 1.71, 'P13': 1.78, 'P14': 1.81},
    'eurodizel':    {'P1': 1.72, 'P2': 1.86, 'P3': 2.06, 'P4': 1.99, 'P5': 1.93,
                     'P6': 1.87, 'P7': 1.82, 'P8': 1.78, 'P9': 1.64, 'P10': 1.72,
                     'P11': 1.94, 'P12': 1.91, 'P13': 2.01, 'P14': 2.07},
    'plavi_dizel':  {'P1': 1.06, 'P2': 1.23, 'P3': 1.42, 'P4': 1.36, 'P5': 1.29,
                     'P6': 1.22, 'P7': 1.16, 'P8': 1.11, 'P9': 0.96, 'P10': 1.05,
                     'P11': 1.28, 'P12': 1.24, 'P13': 1.36, 'P14': 1.41},
    'unp_10kg':     {'P1': 2.58, 'P2': 2.77, 'P3': 2.79, 'P4': 2.61, 'P5': 2.44,
                     'P6': 2.30, 'P7': 2.21, 'P8': 2.11, 'P9': 2.00, 'P10': 2.02,
                     'P11': 2.10, 'P12': 2.02, 'P13': 2.05, 'P14': 2.09},
    'unp_spremnik': {'P1': 1.87, 'P2': 2.07, 'P3': 2.09, 'P4': 1.91, 'P5': 1.73,
                     'P6': 1.59, 'P7': 1.50, 'P8': 1.40, 'P9': 1.30, 'P10': 1.32,
                     'P11': 1.39, 'P12': 1.31, 'P13': 1.35, 'P14': 1.38},
}

EIA_PROPANE = 'EER_EPLLPA_PF4_Y44MB_DPG'

PARAMS = {
    'es95':         {'density': 0.755, 'premium': 0.1545, 'excise': 0.45600,
                     'src': 'RB=F', 'alts': []},
    'eurodizel':    {'density': 0.845, 'premium': 0.1545, 'excise': 0.40613,
                     'src': 'GASOIL_USD', 'alts': ['BZ=F']},
    'plavi_dizel':  {'density': 0.845, 'premium': 0.0781, 'excise': 0.00000,
                     'src': 'GASOIL_USD', 'alts': ['BZ=F']},
    'unp_10kg':     {'density': None,  'premium': 0.8429, 'excise': 0.01327,
                     'src': 'PROPANE_MONT_BELVIEU_USD', 'alts': [EIA_PROPANE]},
    'unp_spremnik': {'density': None,  'premium': 0.4116, 'excise': 0.01327,
                     'src': 'PROPANE_MONT_BELVIEU_USD', 'alts': [EIA_PROPANE]},
}
VAT = 0.25

# Shipped in fuel_params.dart 2026-07-24.1 (source with weight 1.0).
PRODUCTION = {
    'es95':         {'src': 'RB=F',                     'factor': 383.647,  'offset': -57.679},
    'eurodizel':    {'src': 'GASOIL_USD',               'factor': 0.8708,   'offset': 229.789},
    'plavi_dizel':  {'src': 'GASOIL_USD',               'factor': 0.9765,   'offset': 48.104},
    'unp_10kg':     {'src': 'PROPANE_MONT_BELVIEU_USD', 'factor': 1166.446, 'offset': 50.643},
    'unp_spremnik': {'src': 'PROPANE_MONT_BELVIEU_USD', 'factor': 1076.654, 'offset': -34.083},
}


def window_for(pname):
    """Half-open [start, end): start = pub - N (Mon), end = pub (Mon, exclusive)."""
    pub = EFFECTIVE[pname] - timedelta(days=1)
    return pub - timedelta(days=window_days(pname)), pub


def find_rate(d, rates_sorted):
    best = None
    for dt, r in rates_sorted:
        if dt <= d:
            best = r
        else:
            break
    return best


def collect(con, source, start, end_excl):
    rows = con.execute(
        "SELECT date, cif_med FROM oil_prices WHERE source=? AND date >= ? AND date < ? "
        "ORDER BY date", (source, start.isoformat(), end_excl.isoformat()))
    return [(date.fromisoformat(d[:10]), v) for d, v in rows]


def all_rates(con):
    return [(date.fromisoformat(d[:10]), r) for d, r
            in con.execute("SELECT date, usd_eur FROM exchange_rates ORDER BY date")]


def ls_fit(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    den = sum((x - mx) ** 2 for x in xs)
    f = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0
    return f, my - f * mx


def predict_retail(p, factor, offset, raws, rates):
    avg_cif = sum(r * factor + offset for r in raws) / len(raws)
    avg_rate = sum(rates) / len(rates)
    pc = (p['density'] or 1.0) * avg_cif / avg_rate / 1000 + p['premium']
    return round((pc + p['excise']) * (1 + VAT) * 100) / 100


def gather(con, fuel, p, source, rates_sorted, verbose=True):
    xs, ys, periods, period_data = [], [], [], {}
    for pname in EFFECTIVE:
        start, end_excl = window_for(pname)
        oil = collect(con, source, start, end_excl)
        if not oil:
            if verbose:
                print('  %s: nema podataka za %s, preskacem' % (pname, source))
            continue
        raws = [v for _, v in oil]
        rates = [find_rate(d, rates_sorted) for d, _ in oil]
        if any(r is None for r in rates):
            fb = rates_sorted[0][1] if rates_sorted else 1.0
            rates = [r if r is not None else fb for r in rates]
        avg_oil, avg_q = sum(raws) / len(raws), sum(rates) / len(rates)
        R = REAL[fuel][pname]
        B = R / (1 + VAT) - p['excise'] - p['premium']
        target_cif = B * avg_q * 1000 / (p['density'] or 1.0)
        xs.append(avg_oil)
        ys.append(target_cif)
        periods.append(pname)
        period_data[pname] = (raws, rates)
        if verbose:
            print('  %s [%s,%s) d=%d n=%2d avgOil=%9.4f avgRate=%.5f R=%.2f target=%.2f'
                  % (pname, start, end_excl, window_days(pname), len(raws),
                     avg_oil, avg_q, R, target_cif))
    return xs, ys, periods, period_data


def evaluate(fuel, p, source, xs, ys, periods, period_data, subset=None, label=''):
    subset = periods if subset is None else subset
    sub = [pn for pn in subset if pn in periods]
    if len(sub) < 2:
        print('  %s: premalo perioda (%d), preskacem' % (label, len(sub)))
        return None
    f, o = ls_fit([xs[periods.index(pn)] for pn in sub],
                  [ys[periods.index(pn)] for pn in sub])
    print('  >>> %s factor=%.4f offset=%.4f   (fit na %d: %s)'
          % (label, f, o, len(sub), ','.join(sub)))
    errs = {}
    for pname in periods:
        pred = predict_retail(p, f, o, *period_data[pname])
        errs[pname] = pred - REAL[fuel][pname]
        print('   %s%4s pred=%.3f real=%.2f err=%+.3f'
              % ('*' if pname in sub else ' ', pname, pred, REAL[fuel][pname], errs[pname]))
    mae_fit = sum(abs(errs[pn]) for pn in sub) / len(sub)
    mae_all = sum(abs(e) for e in errs.values()) / len(errs)
    print('      MAE(fit)=%.1fc  MAE(sve)=%.1fc' % (mae_fit * 100, mae_all * 100))
    return {'factor': f, 'offset': o, 'mae_fit': mae_fit, 'mae_all': mae_all,
            'source': source, 'label': label, 'n_fit': len(sub)}


def baseline(con, rates_sorted):
    print('\n\n=== BASELINE: koeficijenti koji su SADA u APK-u (2026-07-24.1) ===')
    for fuel, prod in PRODUCTION.items():
        p = PARAMS[fuel]
        xs, ys, periods, pd_ = gather(con, fuel, p, prod['src'], rates_sorted, verbose=False)
        if not periods:
            continue
        errs, line = [], []
        for pname in periods:
            pred = predict_retail(p, prod['factor'], prod['offset'], *pd_[pname])
            e = pred - REAL[fuel][pname]
            errs.append(e)
            line.append('%s:%+.0fc' % (pname, e * 100))
        new = [e for pn, e in zip(periods, errs) if pn in ('P11', 'P12', 'P13', 'P14')]
        mae = sum(abs(e) for e in errs) / len(errs)
        mae_n = sum(abs(e) for e in new) / len(new) if new else float('nan')
        print('\n%s (%s f=%s o=%s)' % (fuel, prod['src'], prod['factor'], prod['offset']))
        print('  ' + ' '.join(line))
        print('  MAE(sve)=%.1fc   MAE(P11-P14, out-of-sample)=%.1fc' % (mae * 100, mae_n * 100))


def main():
    con = sqlite3.connect(DB)
    rates_sorted = all_rates(con)
    print('DB=%s  tecajeva=%d (%s .. %s)  P13/P14 prozor=%d dana'
          % (DB, len(rates_sorted), rates_sorted[0][0], rates_sorted[-1][0],
             FORCE if FORCE else 7))
    baseline(con, rates_sorted)

    best = {}
    for fuel, p in PARAMS.items():
        for source in [p['src']] + p['alts']:
            tag = 'PRODUKCIJA' if source == p['src'] else 'ALTERNATIVA'
            print('\n=== %s | %s (%s) ===' % (fuel, source, tag))
            xs, ys, periods, pd_ = gather(con, fuel, p, source, rates_sorted)
            if len(xs) < 2:
                print('  premalo perioda za fit')
                continue
            subsets = [(None, 'LS fit (svi periodi)')]
            for k in (8, 6, 4):
                sub = periods[-k:]
                if 2 <= len(sub) < len(periods):
                    subsets.append((sub, 'LS fit (zadnjih %d: %s)' % (k, ','.join(sub))))
            for subset, label in subsets:
                r = evaluate(fuel, p, source, xs, ys, periods, pd_, subset, label)
                if r:
                    best[(fuel, r['source'], r['label'])] = r

    print('\n\n=== SAZETAK: fitovi po gorivu (sortirano po MAE na fitanim tockama) ===')
    for fuel in PARAMS:
        cands = sorted([v for k, v in best.items() if k[0] == fuel],
                       key=lambda v: v['mae_fit'])
        if not cands:
            continue
        print('\n%s:' % fuel)
        for c in cands:
            print('  %-28s %-40s factor=%10.4f offset=%10.4f MAEfit=%5.1fc MAEsve=%5.1fc'
                  % (c['source'], c['label'], c['factor'], c['offset'],
                     c['mae_fit'] * 100, c['mae_all'] * 100))


if __name__ == '__main__':
    main()
