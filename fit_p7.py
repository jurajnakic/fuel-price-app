"""LS fit factor/offset for P1-P7, matching production windowing exactly:
- Half-open window [start, end) per settlementWindow()
- Average of available days only (no fill-forward)
- Per-date exchange rate (closest but not after that date)

Extends fit_p5.py with P6 (eff 2026-05-19) and P7 (eff 2026-06-02).
"""
import sqlite3
from datetime import date, timedelta

DB = 'fuel_prices_p6.db'

EFFECTIVE = {
    'P1': date(2026, 3, 10),
    'P2': date(2026, 3, 24),
    'P3': date(2026, 4,  7),
    'P4': date(2026, 4, 21),
    'P5': date(2026, 5,  5),
    'P6': date(2026, 5, 19),
    'P7': date(2026, 6,  2),
}

REAL = {
    'es95':         {'P1': 1.55, 'P2': 1.71, 'P3': 1.76, 'P4': 1.74, 'P5': 1.79, 'P6': 1.82, 'P7': 1.78},
    'eurodizel':    {'P1': 1.72, 'P2': 1.86, 'P3': 2.06, 'P4': 1.99, 'P5': 1.93, 'P6': 1.87, 'P7': 1.82},
    'plavi_dizel':  {'P1': 1.06, 'P2': 1.23, 'P3': 1.42, 'P4': 1.36, 'P5': 1.29, 'P6': 1.22, 'P7': 1.16},
    'unp_10kg':     {'P1': 2.58, 'P2': 2.77, 'P3': 2.79, 'P4': 2.61, 'P5': 2.44, 'P6': 2.30, 'P7': 2.21},
    'unp_spremnik': {'P1': 1.87, 'P2': 2.07, 'P3': 2.09, 'P4': 1.91, 'P5': 1.73, 'P6': 1.59, 'P7': 1.50},
}

PARAMS = {
    'es95':         {'density': 0.755, 'premium': 0.1545,  'excise': 0.45600, 'src': 'RB=F'},
    'eurodizel':    {'density': 0.845, 'premium': 0.1545,  'excise': 0.40613, 'src': 'BZ=F'},
    'plavi_dizel':  {'density': 0.845, 'premium': 0.0781,  'excise': 0.00000, 'src': 'BZ=F'},
    'unp_10kg':     {'density': None,  'premium': 0.8429,  'excise': 0.01327, 'src': 'EER_EPLLPA_PF4_Y44MB_DPG'},
    'unp_spremnik': {'density': None,  'premium': 0.4116,  'excise': 0.01327, 'src': 'EER_EPLLPA_PF4_Y44MB_DPG'},
}
VAT = 0.25

def window_for(eff):
    """Half-open [start, end): start = pub - 14 (Mon), end = pub (Mon, exclusive)."""
    pub = eff - timedelta(days=1)
    start = pub - timedelta(days=14)
    return start, pub  # half-open

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
    return [(date.fromisoformat(d), v) for d, v in rows]

def all_rates(con):
    rows = list(con.execute("SELECT date, usd_eur FROM exchange_rates ORDER BY date"))
    return [(date.fromisoformat(d), r) for d, r in rows]

def ls_fit(xs, ys):
    n = len(xs)
    mx = sum(xs)/n; my = sum(ys)/n
    num = sum((x-mx)*(y-my) for x,y in zip(xs,ys))
    den = sum((x-mx)**2 for x in xs)
    f = num/den if den else 0.0
    o = my - f*mx
    return f, o

def predict_retail(p, factor, offset, raws, rates):
    n = len(raws)
    cifs = [r*factor + offset for r in raws]
    avg_cif = sum(cifs)/n
    avg_rate = sum(rates)/n
    if p['density'] is None:
        pc = avg_cif/avg_rate/1000 + p['premium']
    else:
        pc = p['density']*avg_cif/avg_rate/1000 + p['premium']
    retail = (pc + p['excise'])*(1+VAT)
    return round(retail*100)/100

def main():
    con = sqlite3.connect(DB)
    rates_sorted = all_rates(con)

    new_calib = {}
    for fuel, p in PARAMS.items():
        print(f'\n=== {fuel} (src={p["src"]}) ===')
        period_data = {}
        xs, ys, periods = [], [], []
        for pname, eff in EFFECTIVE.items():
            start, end_excl = window_for(eff)
            oil = collect(con, p['src'], start, end_excl)
            if not oil:
                print(f'  {pname}: no data, skip')
                continue
            raws = [v for _, v in oil]
            rates = [find_rate(d, rates_sorted) for d, _ in oil]
            if any(r is None for r in rates):
                first_avail = rates_sorted[0][1] if rates_sorted else 1.0
                rates = [r if r is not None else first_avail for r in rates]
            avg_oil = sum(raws)/len(raws)
            avg_q = sum(rates)/len(rates)
            R = REAL[fuel][pname]
            B = R/(1+VAT) - p['excise'] - p['premium']
            target_cif = B * avg_q * 1000 / (p['density'] or 1.0)
            xs.append(avg_oil); ys.append(target_cif); periods.append(pname)
            period_data[pname] = (raws, rates)
            print(f'  {pname} window [{start},{end_excl}) n={len(raws)} avgOil={avg_oil:.4f} avgRate={avg_q:.5f} R={R:.2f} target={target_cif:.2f}')
        if len(xs) < 2:
            continue
        f, o = ls_fit(xs, ys)
        new_calib[fuel] = (f, o)
        print(f'  >>> LS fit (all): factor={f:.4f}  offset={o:.4f}')
        errs = []
        for pname in periods:
            raws, rates = period_data[pname]
            pred = predict_retail(p, f, o, raws, rates)
            R = REAL[fuel][pname]
            errs.append(pred-R)
            print(f'    {pname} pred={pred:.3f} real={R:.2f} err={pred-R:+.3f}')
        mae = sum(abs(e) for e in errs)/len(errs)
        print(f'    MAE={mae*100:.1f}c')

        # Also fit on last 4 periods only (P4-P7) to weight recent regime
        recent = [pn for pn in periods if pn in ('P4','P5','P6','P7')]
        if len(recent) >= 2:
            rxs = [xs[periods.index(pn)] for pn in recent]
            rys = [ys[periods.index(pn)] for pn in recent]
            rf, ro = ls_fit(rxs, rys)
            print(f'  >>> LS fit (P4-P7 only): factor={rf:.4f}  offset={ro:.4f}')
            rerrs = []
            for pname in periods:
                raws, rates = period_data[pname]
                pred = predict_retail(p, rf, ro, raws, rates)
                R = REAL[fuel][pname]
                rerrs.append(pred-R)
                tag = '*' if pname in recent else ' '
                print(f'   {tag}{pname} pred={pred:.3f} real={R:.2f} err={pred-R:+.3f}')
            rmae_recent = sum(abs(e) for pn,e in zip(periods,rerrs) if pn in recent)/len(recent)
            print(f'    MAE(P4-P7)={rmae_recent*100:.1f}c')

    print('\n=== SUMMARY (all-7 fit) ===')
    for fuel, (f, o) in new_calib.items():
        print(f"  '{fuel}': factor={f:.3f}  offset={o:.3f}")

if __name__ == '__main__':
    main()
