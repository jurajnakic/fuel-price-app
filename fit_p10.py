"""LS fit factor/offset for P1-P10, matching production windowing exactly:
- Half-open window [start, end) per settlementWindow()
- Average of available days only (no fill-forward)
- Per-date exchange rate (closest but not after that date)

Extends fit_p7.py with P8 (eff 2026-06-16), P9 (eff 2026-06-30), P10 (eff 2026-07-14).
New: evaluates ALTERNATIVE commodity sources per fuel (GASOIL for diesel,
Mont Belvieu propane for LPG) side by side with the production source.

Usage: py fit_p10.py [db_path]
"""
import sqlite3
import sys
from datetime import date, timedelta

DB = sys.argv[1] if len(sys.argv) > 1 else 'fuel_prices_p10.db'

EFFECTIVE = {
    'P1':  date(2026, 3, 10),
    'P2':  date(2026, 3, 24),
    'P3':  date(2026, 4,  7),
    'P4':  date(2026, 4, 21),
    'P5':  date(2026, 5,  5),
    'P6':  date(2026, 5, 19),
    'P7':  date(2026, 6,  2),
    'P8':  date(2026, 6, 16),
    'P9':  date(2026, 6, 30),
    'P10': date(2026, 7, 14),
}

REAL = {
    'es95':         {'P1': 1.55, 'P2': 1.71, 'P3': 1.76, 'P4': 1.74, 'P5': 1.79,
                     'P6': 1.82, 'P7': 1.78, 'P8': 1.69, 'P9': 1.62, 'P10': 1.66},
    'eurodizel':    {'P1': 1.72, 'P2': 1.86, 'P3': 2.06, 'P4': 1.99, 'P5': 1.93,
                     'P6': 1.87, 'P7': 1.82, 'P8': 1.78, 'P9': 1.64, 'P10': 1.72},
    'plavi_dizel':  {'P1': 1.06, 'P2': 1.23, 'P3': 1.42, 'P4': 1.36, 'P5': 1.29,
                     'P6': 1.22, 'P7': 1.16, 'P8': 1.11, 'P9': 0.96, 'P10': 1.05},
    'unp_10kg':     {'P1': 2.58, 'P2': 2.77, 'P3': 2.79, 'P4': 2.61, 'P5': 2.44,
                     'P6': 2.30, 'P7': 2.21, 'P8': 2.11, 'P9': 2.00, 'P10': 2.02},
    'unp_spremnik': {'P1': 1.87, 'P2': 2.07, 'P3': 2.09, 'P4': 1.91, 'P5': 1.73,
                     'P6': 1.59, 'P7': 1.50, 'P8': 1.40, 'P9': 1.30, 'P10': 1.32},
}

EIA_PROPANE = 'EER_EPLLPA_PF4_Y44MB_DPG'

PARAMS = {
    'es95':         {'density': 0.755, 'premium': 0.1545, 'excise': 0.45600,
                     'src': 'RB=F', 'alts': []},
    'eurodizel':    {'density': 0.845, 'premium': 0.1545, 'excise': 0.40613,
                     'src': 'BZ=F', 'alts': ['GASOIL_USD']},
    'plavi_dizel':  {'density': 0.845, 'premium': 0.0781, 'excise': 0.00000,
                     'src': 'BZ=F', 'alts': ['GASOIL_USD']},
    'unp_10kg':     {'density': None,  'premium': 0.8429, 'excise': 0.01327,
                     'src': EIA_PROPANE, 'alts': ['PROPANE_MONT_BELVIEU_USD']},
    'unp_spremnik': {'density': None,  'premium': 0.4116, 'excise': 0.01327,
                     'src': EIA_PROPANE, 'alts': ['PROPANE_MONT_BELVIEU_USD']},
}
VAT = 0.25


def window_for(eff):
    """Half-open [start, end): start = pub - 14 (Mon), end = pub (Mon, exclusive)."""
    pub = eff - timedelta(days=1)
    start = pub - timedelta(days=14)
    return start, pub


def find_rate(date_, rates_sorted):
    best = None
    for d, r in rates_sorted:
        if d <= date_:
            best = r
        else:
            break
    return best


def collect(con, source, start, end_excl):
    rows = list(con.execute(
        "SELECT date, cif_med FROM oil_prices WHERE source=? AND date >= ? AND date < ? ORDER BY date",
        (source, start.isoformat(), end_excl.isoformat())))
    return [(date.fromisoformat(d[:10]), v) for d, v in rows]


def all_rates(con):
    rows = list(con.execute("SELECT date, usd_eur FROM exchange_rates ORDER BY date"))
    return [(date.fromisoformat(d[:10]), r) for d, r in rows]


def ls_fit(xs, ys):
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = sum((x - mx) ** 2 for x in xs)
    f = num / den if den else 0.0
    o = my - f * mx
    return f, o


def predict_retail(p, factor, offset, raws, rates):
    n = len(raws)
    cifs = [r * factor + offset for r in raws]
    avg_cif = sum(cifs) / n
    avg_rate = sum(rates) / n
    if p['density'] is None:
        pc = avg_cif / avg_rate / 1000 + p['premium']
    else:
        pc = p['density'] * avg_cif / avg_rate / 1000 + p['premium']
    retail = (pc + p['excise']) * (1 + VAT)
    return round(retail * 100) / 100


def gather(con, fuel, p, source, rates_sorted, verbose=True):
    """Build (xs, ys, periods, period_data) for one fuel/source combo."""
    xs, ys, periods, period_data = [], [], [], {}
    for pname, eff in EFFECTIVE.items():
        start, end_excl = window_for(eff)
        oil = collect(con, source, start, end_excl)
        if not oil:
            if verbose:
                print(f'  {pname}: nema podataka za {source}, preskacem')
            continue
        raws = [v for _, v in oil]
        rates = [find_rate(d, rates_sorted) for d, _ in oil]
        if any(r is None for r in rates):
            first_avail = rates_sorted[0][1] if rates_sorted else 1.0
            rates = [r if r is not None else first_avail for r in rates]
        avg_oil = sum(raws) / len(raws)
        avg_q = sum(rates) / len(rates)
        R = REAL[fuel][pname]
        B = R / (1 + VAT) - p['excise'] - p['premium']
        target_cif = B * avg_q * 1000 / (p['density'] or 1.0)
        xs.append(avg_oil)
        ys.append(target_cif)
        periods.append(pname)
        period_data[pname] = (raws, rates)
        if verbose:
            print(f'  {pname} [{start},{end_excl}) n={len(raws):>2} avgOil={avg_oil:>9.4f} '
                  f'avgRate={avg_q:.5f} R={R:.2f} target={target_cif:.2f}')
    return xs, ys, periods, period_data


def evaluate(fuel, p, source, xs, ys, periods, period_data, subset=None, label=''):
    """Fit on `subset` (or all), report errors over all periods present."""
    if subset is None:
        subset = periods
    sub = [pn for pn in subset if pn in periods]
    if len(sub) < 2:
        print(f'  {label}: premalo perioda ({len(sub)}), preskacem')
        return None
    sxs = [xs[periods.index(pn)] for pn in sub]
    sys_ = [ys[periods.index(pn)] for pn in sub]
    f, o = ls_fit(sxs, sys_)
    print(f'  >>> {label} factor={f:.4f} offset={o:.4f}   (fit na {len(sub)} tocaka: {",".join(sub)})')
    errs = {}
    for pname in periods:
        raws, rates = period_data[pname]
        pred = predict_retail(p, f, o, raws, rates)
        R = REAL[fuel][pname]
        errs[pname] = pred - R
        tag = '*' if pname in sub else ' '
        print(f'   {tag}{pname:>3} pred={pred:.3f} real={R:.2f} err={pred - R:+.3f}')
    mae_fit = sum(abs(errs[pn]) for pn in sub) / len(sub)
    mae_all = sum(abs(e) for e in errs.values()) / len(errs)
    print(f'      MAE(fit)={mae_fit * 100:.1f}c  MAE(sve)={mae_all * 100:.1f}c')
    return {'factor': f, 'offset': o, 'mae_fit': mae_fit, 'mae_all': mae_all,
            'source': source, 'label': label, 'n_fit': len(sub)}


# Coefficients currently shipped in fuel_params.dart (version 2026-05-04.1),
# for the source that actually has weight 1.0 for that fuel.
PRODUCTION = {
    'es95':         {'src': 'RB=F',      'factor': 256.280, 'offset': 397.277},
    'eurodizel':    {'src': 'BZ=F',      'factor': 9.505,   'offset': 400.134},
    'plavi_dizel':  {'src': 'BZ=F',      'factor': 10.343,  'offset': 277.130},
    'unp_10kg':     {'src': EIA_PROPANE, 'factor': 0.0,     'offset': 1459.84},
    'unp_spremnik': {'src': EIA_PROPANE, 'factor': 0.0,     'offset': 1306.21},
}


def baseline(con, rates_sorted):
    """How do the coefficients currently in the APK score on every period?"""
    print('\n\n=== BASELINE: koeficijenti koji su SADA u aplikaciji (2026-05-04.1) ===')
    for fuel, prod in PRODUCTION.items():
        p = PARAMS[fuel]
        xs, ys, periods, period_data = gather(
            con, fuel, p, prod['src'], rates_sorted, verbose=False)
        if not periods:
            continue
        errs, line = [], []
        for pname in periods:
            raws, rates = period_data[pname]
            pred = predict_retail(p, prod['factor'], prod['offset'], raws, rates)
            e = pred - REAL[fuel][pname]
            errs.append(e)
            line.append(f'{pname}:{e * 100:+.0f}c')
        recent = [e for pn, e in zip(periods, errs) if pn in ('P8', 'P9', 'P10')]
        mae = sum(abs(e) for e in errs) / len(errs)
        mae_r = sum(abs(e) for e in recent) / len(recent) if recent else float('nan')
        print(f'\n{fuel} ({prod["src"]} f={prod["factor"]} o={prod["offset"]})')
        print('  ' + ' '.join(line))
        print(f'  MAE(sve)={mae * 100:.1f}c   MAE(P8-P10)={mae_r * 100:.1f}c')


def main():
    con = sqlite3.connect(DB)
    rates_sorted = all_rates(con)
    print(f'DB={DB}  tecajeva={len(rates_sorted)} '
          f'({rates_sorted[0][0]} .. {rates_sorted[-1][0]})')
    baseline(con, rates_sorted)

    best = {}
    for fuel, p in PARAMS.items():
        for source in [p['src']] + p['alts']:
            tag = 'PRODUKCIJA' if source == p['src'] else 'ALTERNATIVA'
            print(f'\n=== {fuel} | {source} ({tag}) ===')
            xs, ys, periods, period_data = gather(con, fuel, p, source, rates_sorted)
            if len(xs) < 2:
                print('  premalo perioda za fit')
                continue
            results = []
            r = evaluate(fuel, p, source, xs, ys, periods, period_data,
                         None, 'LS fit (svi periodi)')
            if r:
                results.append(r)
            for k in (6, 4):
                recent = periods[-k:]
                if 2 <= len(recent) < len(periods):
                    r = evaluate(fuel, p, source, xs, ys, periods, period_data,
                                 recent, f'LS fit (zadnjih {k}: {",".join(recent)})')
                    if r:
                        results.append(r)
            for r in results:
                key = (fuel, r['source'], r['label'])
                best[key] = r

    print('\n\n=== SAZETAK: najbolji fit po gorivu (po MAE na fitanim tockama) ===')
    for fuel in PARAMS:
        cands = [v for k, v in best.items() if k[0] == fuel]
        if not cands:
            continue
        cands.sort(key=lambda v: v['mae_fit'])
        print(f'\n{fuel}:')
        for c in cands:
            print(f'  {c["source"]:<28} {c["label"]:<32} '
                  f'factor={c["factor"]:>10.4f} offset={c["offset"]:>10.4f} '
                  f'MAEfit={c["mae_fit"] * 100:>5.1f}c MAEsve={c["mae_all"] * 100:>5.1f}c')


if __name__ == '__main__':
    main()
