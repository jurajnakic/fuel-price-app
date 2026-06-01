"""
Validate Period 3 predictions (7.4.-20.4.2026)
Window: Mar 24 - Apr 6 (14 calendar days)
Uses same formula as the Flutter app (NN 31/2025)
"""
import json
import urllib.request
import csv
from datetime import datetime, timedelta
from io import StringIO

# === Parameters (from fuel_params.dart defaults) ===
PARAMS = {
    'es95': {
        'source': 'yahoo', 'symbol': 'RB=F',
        'factor': 300.0, 'offset': 259.0,
        'premium': 0.1545, 'excise': 0.4560, 'density': 0.755,
    },
    'eurodizel': {
        'source': 'yahoo', 'symbol': 'BZ=F',
        'factor': 6.04, 'offset': 648.0,
        'premium': 0.1545, 'excise': 0.40613, 'density': 0.845,
    },
    'unp_10kg': {
        'source': 'eia', 'eia_series': 'EER_EPLLPA_PF4_Y44MB_DPG',
        'factor': 2153.0, 'offset': -13.5,
        'premium': 0.8429, 'excise': 0.01327, 'density': None,
    },
}
VAT_RATE = 0.25
EIA_API_KEY = 'TMDb4mZNHr7DIUP3ti975TA66BlYWf2aQFhkZc5h'

# Window: 14 calendar days before period start
WINDOW_END = datetime(2026, 4, 7)  # period start = window end
WINDOW_START = WINDOW_END - timedelta(days=14)  # Mar 24

print(f"Window: {WINDOW_START.date()} to {WINDOW_END.date()} (exclusive)")
print()

# === Fetch Yahoo Finance data ===
def fetch_yahoo(symbol, start_date, end_date):
    """Fetch historical prices from Yahoo Finance"""
    p1 = int(start_date.timestamp())
    p2 = int(end_date.timestamp())
    url = f"https://query1.finance.yahoo.com/v7/finance/download/{symbol}?period1={p1}&period2={p2}&interval=1d&events=history"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp:
        text = resp.read().decode('utf-8')
    reader = csv.DictReader(StringIO(text))
    prices = []
    for row in reader:
        try:
            date = datetime.strptime(row['Date'], '%Y-%m-%d')
            close = float(row['Close'])
            if WINDOW_START <= date < WINDOW_END:
                prices.append((date, close))
        except (ValueError, KeyError):
            continue
    prices.sort(key=lambda x: x[0])
    return prices

# === Fetch EIA data ===
def fetch_eia(series_id):
    """Fetch EIA spot prices"""
    url = f"https://api.eia.gov/v2/seriesid/{series_id}?api_key={EIA_API_KEY}&length=60"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    prices = []
    for item in data.get('response', {}).get('data', []):
        try:
            date = datetime.strptime(item['period'], '%Y-%m-%d')
            value = float(item['value'])
            if WINDOW_START <= date < WINDOW_END:
                prices.append((date, value))
        except (ValueError, KeyError, TypeError):
            continue
    prices.sort(key=lambda x: x[0])
    return prices

# === Fetch ECB USD/EUR rate ===
def fetch_ecb_rate():
    """Get average USD/EUR rate for the window period"""
    # Use ECB Statistical Data Warehouse
    start_str = WINDOW_START.strftime('%Y-%m-%d')
    end_str = (WINDOW_END - timedelta(days=1)).strftime('%Y-%m-%d')
    url = f"https://data-api.ecb.europa.eu/service/data/EXR/D.USD.EUR.SP00.A?startPeriod={start_str}&endPeriod={end_str}&format=csvdata"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp:
        text = resp.read().decode('utf-8')
    reader = csv.DictReader(StringIO(text))
    rates = {}
    for row in reader:
        try:
            date = datetime.strptime(row['TIME_PERIOD'], '%Y-%m-%d')
            rate = float(row['OBS_VALUE'])
            if WINDOW_START <= date < WINDOW_END:
                rates[date.strftime('%Y-%m-%d')] = rate
        except (ValueError, KeyError):
            continue
    return rates

# === Formula (same as FormulaEngine) ===
def calculate_price(fuel_type, cif_med_list, exchange_rates):
    """
    PC = [Σ(CIF_Med × ρ / T) / (n × 1000)] + P   (liquid fuels)
    PC = [Σ(CIF / T) / (n × 1000)] + P             (UNP, no density)
    Retail = (PC + excise) × (1 + VAT)
    """
    p = PARAMS[fuel_type]
    n = len(cif_med_list)
    total = 0
    for i in range(n):
        if p['density'] is not None:
            total += cif_med_list[i] * p['density'] / exchange_rates[i]
        else:
            total += cif_med_list[i] / exchange_rates[i]

    pc = total / (n * 1000) + p['premium']
    retail = (pc + p['excise']) * (1 + VAT_RATE)
    rounded = round(retail * 100) / 100
    return pc, retail, rounded

# === Main ===
print("Fetching ECB exchange rates...")
ecb_rates = fetch_ecb_rate()
print(f"  Got {len(ecb_rates)} daily rates")
for d, r in sorted(ecb_rates.items()):
    print(f"    {d}: {r}")
print()

# ES95 (Yahoo RB=F)
print("=" * 60)
print("ES95 (RBOB Gasoline RB=F, Yahoo)")
print("=" * 60)
rb_prices = fetch_yahoo('RB=F', WINDOW_START - timedelta(days=2), WINDOW_END + timedelta(days=1))
print(f"  Prices in window ({len(rb_prices)} days):")
cif_list_es95 = []
rate_list_es95 = []
for date, price in rb_prices:
    date_str = date.strftime('%Y-%m-%d')
    rate = ecb_rates.get(date_str)
    if rate is None:
        # Use nearest available rate
        for delta in range(1, 5):
            for d in [date - timedelta(days=delta), date + timedelta(days=delta)]:
                r = ecb_rates.get(d.strftime('%Y-%m-%d'))
                if r:
                    rate = r
                    break
            if rate:
                break
    if rate:
        cif = price * 300.0 + 259.0
        cif_list_es95.append(cif)
        rate_list_es95.append(rate)
        print(f"    {date_str}: raw={price:.4f}, cifMed={cif:.1f}, rate={rate}")

if cif_list_es95:
    pc, retail, rounded = calculate_price('es95', cif_list_es95, rate_list_es95)
    print(f"\n  PC (base price) = {pc:.4f} EUR/L")
    print(f"  Retail = ({pc:.4f} + {PARAMS['es95']['excise']}) × 1.25 = {retail:.4f}")
    print(f"  >>> PREDICTION: {rounded:.2f} EUR/L <<<")
print()

# EURODIZEL (Yahoo BZ=F Brent)
print("=" * 60)
print("EURODIZEL (Brent BZ=F, Yahoo)")
print("=" * 60)
bz_prices = fetch_yahoo('BZ=F', WINDOW_START - timedelta(days=2), WINDOW_END + timedelta(days=1))
print(f"  Prices in window ({len(bz_prices)} days):")
cif_list_ed = []
rate_list_ed = []
for date, price in bz_prices:
    date_str = date.strftime('%Y-%m-%d')
    rate = ecb_rates.get(date_str)
    if rate is None:
        for delta in range(1, 5):
            for d in [date - timedelta(days=delta), date + timedelta(days=delta)]:
                r = ecb_rates.get(d.strftime('%Y-%m-%d'))
                if r:
                    rate = r
                    break
            if rate:
                break
    if rate:
        cif = price * 6.04 + 648.0
        cif_list_ed.append(cif)
        rate_list_ed.append(rate)
        print(f"    {date_str}: raw={price:.2f}, cifMed={cif:.1f}, rate={rate}")

if cif_list_ed:
    pc, retail, rounded = calculate_price('eurodizel', cif_list_ed, rate_list_ed)
    print(f"\n  PC (base price) = {pc:.4f} EUR/L")
    print(f"  Retail = ({pc:.4f} + {PARAMS['eurodizel']['excise']}) × 1.25 = {retail:.4f}")
    print(f"  >>> PREDICTION: {rounded:.2f} EUR/L <<<")
print()

# UNP (EIA Propane)
print("=" * 60)
print("UNP 10kg (EIA Propane)")
print("=" * 60)
eia_prices = fetch_eia('EER_EPLLPA_PF4_Y44MB_DPG')
print(f"  Prices in window ({len(eia_prices)} days):")
cif_list_unp = []
rate_list_unp = []
for date, price in eia_prices:
    date_str = date.strftime('%Y-%m-%d')
    rate = ecb_rates.get(date_str)
    if rate is None:
        for delta in range(1, 5):
            for d in [date - timedelta(days=delta), date + timedelta(days=delta)]:
                r = ecb_rates.get(d.strftime('%Y-%m-%d'))
                if r:
                    rate = r
                    break
            if rate:
                break
    if rate:
        cif = price * 2153.0 + (-13.5)
        cif_list_unp.append(cif)
        rate_list_unp.append(rate)
        print(f"    {date_str}: raw={price:.4f}, cifMed={cif:.1f}, rate={rate}")

if cif_list_unp:
    pc, retail, rounded = calculate_price('unp_10kg', cif_list_unp, rate_list_unp)
    print(f"\n  PC (base price) = {pc:.4f} EUR/L")
    print(f"  Retail = ({pc:.4f} + {PARAMS['unp_10kg']['excise']}) × 1.25 = {retail:.4f}")
    print(f"  >>> PREDICTION: {rounded:.2f} EUR <<<")
print()

print("=" * 60)
print("SUMMARY - Period 3 (7.4. - 20.4.2026) predictions")
print("=" * 60)
