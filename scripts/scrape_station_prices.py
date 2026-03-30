#!/usr/bin/env python3
"""
Scrape fuel prices from Croatian sources and output station_prices.json.

Primary source: cijenegoriva.info (simple HTML tables, 9 companies)
Backup source:  hak.hr/info/cijene-goriva/ (min/max/median, 6 companies)
"""

import json
import re
import sys
from datetime import date
from urllib.request import urlopen, Request
from html.parser import HTMLParser

# --- cijenegoriva.info parser ---

class CijeneGorivaParser(HTMLParser):
    """Parse fuel price tables from cijenegoriva.info."""

    # Map Croatian fuel type headings to our internal types
    FUEL_MAP = {
        'eurosuper 95': 'es95',
        'premium eurosuper 95': 'es95_premium',
        'eurosuper 100': 'es100',
        'eurodizel': 'eurodizel',
        'premium eurodizel': 'eurodizel_premium',
        'autoplin': 'lpg',
    }

    # Normalize company names
    COMPANY_MAP = {
        'ina': ('ina', 'INA', 'https://www.ina.hr'),
        'crodux derivati (petrol)': ('petrol', 'Petrol', 'https://www.petrol.hr'),
        'petrol': ('petrol', 'Petrol', 'https://www.petrol.hr'),
        'shell': ('shell', 'Shell', 'https://www.shell.hr'),
        'tifon': ('tifon', 'Tifon', 'https://tifon.hr'),
        'lukoil': ('lukoil', 'Lukoil', 'https://www.lukoil.hr'),
        'adriaoil': ('adriaoil', 'AdriaOil', 'https://www.adriaoil.hr'),
    }

    def __init__(self):
        super().__init__()
        self.prices = {}  # {company_id: {fuel_type: price}}
        self.company_info = {}  # {company_id: (name, url)}
        self.validity = None
        self._current_fuel = None
        self._in_table = False
        self._in_td = False
        self._td_count = 0
        self._current_company = None
        self._current_text = ''
        self._in_p = False
        self._p_text = ''

    def handle_starttag(self, tag, attrs):
        if tag == 'table':
            self._in_table = True
            self._td_count = 0
        elif tag == 'td' and self._in_table:
            self._in_td = True
            self._current_text = ''
            self._td_count += 1
        elif tag == 'p':
            self._in_p = True
            self._p_text = ''
        elif tag == 'strong' and self._in_p:
            pass  # text will be captured

    def handle_endtag(self, tag):
        if tag == 'table':
            self._in_table = False
            self._current_fuel = None
        elif tag == 'td' and self._in_td:
            self._in_td = False
            text = self._current_text.strip()
            if self._td_count % 2 == 1:
                # Company name column
                self._current_company = text.lower().strip()
            else:
                # Price column
                self._process_price(text)
        elif tag == 'p':
            self._in_p = False
            self._check_heading(self._p_text)

    def handle_data(self, data):
        if self._in_td:
            self._current_text += data
        if self._in_p:
            self._p_text += data

    def handle_entityref(self, name):
        if name == 'euro' and self._in_td:
            self._current_text += '\u20ac'
        if name == 'euro' and self._in_p:
            self._p_text += '\u20ac'

    def _check_heading(self, text):
        text_lower = text.strip().lower()
        # Check for validity dates
        m = re.search(r'vrijede od (\d{2}\.\d{2}\.\d{4})\.\s*do\s*(\d{2}\.\d{2}\.\d{4})\.', text_lower)
        if m:
            self.validity = (m.group(1), m.group(2))
        # Check for fuel type heading
        for key, fuel_type in self.FUEL_MAP.items():
            if key in text_lower and 'premium' not in text_lower and key != 'premium eurosuper 95' and key != 'premium eurodizel':
                self._current_fuel = fuel_type
                return
        # Check premium separately
        if 'premium eurosuper 95' in text_lower or 'premium eurosuper' in text_lower:
            self._current_fuel = 'es95_premium'
        elif 'premium eurodizel' in text_lower or 'premium dizel' in text_lower:
            self._current_fuel = 'eurodizel_premium'

    def _process_price(self, text):
        if not self._current_fuel or not self._current_company:
            return
        # Parse price: "1,62 €" -> 1.62
        text = text.replace('\u20ac', '').replace('€', '').strip()
        text = text.replace(',', '.')
        try:
            price = float(text)
        except ValueError:
            return

        # Find company
        company_key = None
        for key in self.COMPANY_MAP:
            if key in self._current_company:
                company_key = key
                break
        if not company_key:
            return

        cid, cname, curl = self.COMPANY_MAP[company_key]
        self.company_info[cid] = (cname, curl)
        if cid not in self.prices:
            self.prices[cid] = {}
        self.prices[cid][self._current_fuel] = price


def fetch_url(url):
    """Fetch URL with a browser-like User-Agent."""
    req = Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (compatible; FuelLens/1.0)',
        'Accept': 'text/html',
    })
    with urlopen(req, timeout=30) as resp:
        return resp.read().decode('utf-8', errors='replace')


def scrape_cijenegoriva():
    """Scrape prices from cijenegoriva.info."""
    html = fetch_url('https://cijenegoriva.info')
    parser = CijeneGorivaParser()
    parser.feed(html)
    return parser


# --- HAK parser (backup) ---

class HAKParser(HTMLParser):
    """Parse fuel price tables from hak.hr."""

    FUEL_MAP = {
        'div_eurosuper95': 'es95',
        'div_eurosuper100': 'es100',
        'div_eurodizel': 'eurodizel',
        'div_autoplin': 'lpg',
    }

    COMPANY_MAP = {
        'ina': ('ina', 'INA', 'https://www.ina.hr'),
        'petrol': ('petrol', 'Petrol', 'https://www.petrol.hr'),
        'coral': ('shell', 'Shell', 'https://www.shell.hr'),
        'lukoil': ('lukoil', 'Lukoil', 'https://www.lukoil.hr'),
        'tifon': ('tifon', 'Tifon', 'https://tifon.hr'),
        'adria': ('adriaoil', 'AdriaOil', 'https://www.adriaoil.hr'),
    }

    def __init__(self):
        super().__init__()
        self.prices = {}
        self.company_info = {}
        self._current_fuel = None
        self._in_table = False
        self._in_tr = False
        self._in_td = False
        self._td_index = 0
        self._row_data = []
        self._current_text = ''

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        if tag == 'div':
            div_id = attrs_dict.get('id', '')
            if div_id in self.FUEL_MAP:
                self._current_fuel = self.FUEL_MAP[div_id]
        elif tag == 'table' and self._current_fuel:
            self._in_table = True
        elif tag == 'tr' and self._in_table:
            self._in_tr = True
            self._td_index = 0
            self._row_data = []
        elif tag == 'td' and self._in_tr:
            self._in_td = True
            self._current_text = ''
            self._td_index += 1

    def handle_endtag(self, tag):
        if tag == 'td' and self._in_td:
            self._in_td = False
            self._row_data.append(self._current_text.strip())
        elif tag == 'tr' and self._in_tr:
            self._in_tr = False
            self._process_row()
        elif tag == 'table' and self._in_table:
            self._in_table = False
        elif tag == 'div' and self._current_fuel:
            # Don't reset fuel on every div close, only on table end
            pass

    def handle_data(self, data):
        if self._in_td:
            self._current_text += data

    def _process_row(self):
        # HAK table: Obveznik | Gorivo | Minimalna | Maksimalna | Medijan
        if len(self._row_data) < 5 or not self._current_fuel:
            return

        company_raw = self._row_data[0].lower()
        # Use median price (column 4, index 4)
        price_text = self._row_data[4].replace('\u20ac', '').replace('€', '').replace(',', '.').strip()

        try:
            price = float(price_text)
        except ValueError:
            return

        for key, (cid, cname, curl) in self.COMPANY_MAP.items():
            if key in company_raw:
                self.company_info[cid] = (cname, curl)
                if cid not in self.prices:
                    self.prices[cid] = {}
                # Only set if not already set (first match wins for base fuel)
                fuel = self._current_fuel
                if fuel not in self.prices[cid]:
                    self.prices[cid][fuel] = price
                break


def scrape_hak():
    """Scrape prices from hak.hr (backup source)."""
    html = fetch_url('https://www.hak.hr/info/cijene-goriva/')
    parser = HAKParser()
    parser.feed(html)
    return parser


# --- Build station_prices.json ---

def build_json(primary, backup=None):
    """Merge primary and backup data into station_prices.json format."""
    # Use primary, fill gaps from backup
    all_companies = set(primary.prices.keys())
    if backup:
        all_companies |= set(backup.prices.keys())

    stations = []
    today = date.today().isoformat()

    for cid in sorted(all_companies):
        p_prices = primary.prices.get(cid, {})
        b_prices = backup.prices.get(cid, {}) if backup else {}
        p_info = primary.company_info.get(cid)
        b_info = backup.company_info.get(cid) if backup else None
        info = p_info or b_info
        if not info:
            continue

        name, url = info
        fuels = []

        # Map internal types to display names and app fuel types
        fuel_defs = [
            ('es95', 'Eurosuper 95', 'es95'),
            ('es95_premium', 'Eurosuper 95 Premium', 'es95'),
            ('es100', 'Eurosuper 100', 'es100'),
            ('eurodizel', 'Eurodizel', 'eurodizel'),
            ('eurodizel_premium', 'Eurodizel Premium', 'eurodizel'),
            ('lpg', 'Autoplin (LPG)', 'lpg'),
        ]

        for src_key, display_name, app_type in fuel_defs:
            price = p_prices.get(src_key) or b_prices.get(src_key)
            if price:
                fuels.append({
                    'name': display_name,
                    'type': app_type if src_key == app_type else src_key,
                    'price': round(price, 2),
                })

        if fuels:
            stations.append({
                'id': cid,
                'name': name,
                'url': url,
                'updated': today,
                'fuels': fuels,
            })

    validity_text = ''
    if primary.validity:
        validity_text = f'{primary.validity[0]} - {primary.validity[1]}'

    return {
        'updated': today,
        'validity': validity_text,
        'source': 'cijenegoriva.info + hak.hr',
        'stations': stations,
    }


def main():
    print('Scraping cijenegoriva.info...', file=sys.stderr)
    try:
        primary = scrape_cijenegoriva()
        print(f'  Found {len(primary.prices)} companies', file=sys.stderr)
    except Exception as e:
        print(f'  FAILED: {e}', file=sys.stderr)
        primary = CijeneGorivaParser()  # empty

    print('Scraping hak.hr (backup)...', file=sys.stderr)
    try:
        backup = scrape_hak()
        print(f'  Found {len(backup.prices)} companies', file=sys.stderr)
    except Exception as e:
        print(f'  FAILED: {e}', file=sys.stderr)
        backup = None

    if not primary.prices and (not backup or not backup.prices):
        print('ERROR: Both sources failed!', file=sys.stderr)
        sys.exit(1)

    result = build_json(primary, backup)
    print(f'Output: {len(result["stations"])} stations', file=sys.stderr)

    # Write to stdout
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    print()  # trailing newline


if __name__ == '__main__':
    main()
