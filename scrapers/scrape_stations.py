"""
scrape_stations.py — Scrapes fuel prices from 5 Croatian gas station websites.

Each station has its own scraper function. CSS selectors are intentional
placeholders — tune them per-station after inspecting the live HTML structure.
Output is written to config/station_prices.json relative to the repo root.
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from bs4 import BeautifulSoup

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_FILE = REPO_ROOT / "config" / "station_prices.json"

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (compatible; FuelPriceBot/1.0; +https://github.com)"
    )
}
REQUEST_TIMEOUT = 15  # seconds


def fetch(url: str) -> BeautifulSoup:
    """Fetch a URL and return a BeautifulSoup document."""
    resp = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "html.parser")


# ---------------------------------------------------------------------------
# Price parsing helpers
# ---------------------------------------------------------------------------

def parse_price(text: str) -> float | None:
    """
    Convert a price string to a float.
    Handles comma decimal separators (e.g. '1,45' → 1.45) and strips
    currency symbols / whitespace.
    """
    if not text:
        return None
    cleaned = text.strip().replace("\xa0", "").replace(" ", "")
    # Remove currency symbols
    cleaned = re.sub(r"[€HRKkn]", "", cleaned, flags=re.IGNORECASE)
    # Replace comma decimal separator
    cleaned = cleaned.replace(",", ".")
    # Remove any thousands separator (dot before 3-digit group already replaced)
    # Re-handle: if multiple dots exist keep only the last as decimal
    parts = cleaned.split(".")
    if len(parts) > 2:
        cleaned = "".join(parts[:-1]) + "." + parts[-1]
    try:
        value = float(cleaned)
        # Sanity check: fuel prices in Croatia are roughly 1.0–3.0 EUR/L
        if 0.5 < value < 10.0:
            return round(value, 4)
        return None
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Fuel type classification
# ---------------------------------------------------------------------------

# Maps fragments of a fuel name (lowercase) to a standardised type key.
# Evaluated in order — first match wins.
FUEL_TYPE_MAP = [
    (["eurosuper 100", "super 100", "es100", "v-power racing", "ultimate 102"], "es100"),
    (["eurosuper 95", "super 95", "es95", "e10", "unleaded 95"], "es95"),
    (["premium dizel", "premium diesel", "ultimate diesel", "v-power diesel", "excellium diesel"], "premium_diesel"),
    (["eurodizel", "euro diesel", "eurodisel", "diesel+", "dizel+"], "eurodizel"),
    (["dizel", "diesel"], "eurodizel"),           # generic fallback
    (["lpg", "autoplin", "ukapljeni"], "lpg"),
    (["unp", "plin"], "lpg"),
    (["lng", "cng", "prirodni plin"], "cng"),
    (["ad blue", "adblue"], "adblue"),
]


def classify_fuel(name: str) -> str:
    """Return a standardised fuel type key for the given fuel name."""
    lower = name.lower()
    for fragments, fuel_type in FUEL_TYPE_MAP:
        if any(f in lower for f in fragments):
            return fuel_type
    return "other"


def make_fuel_entry(name: str, price: float) -> dict:
    return {
        "name": name,
        "type": classify_fuel(name),
        "price": price,
    }


# ---------------------------------------------------------------------------
# Per-station scraper functions
# ---------------------------------------------------------------------------

def scrape_ina() -> dict:
    """
    Scrape INA fuel prices.
    URL: https://www.ina.hr/kupci/cijene-goriva/
    HTML hint: look for a table or structured list of fuel rows.
    Tune: TABLE_SELECTOR, NAME_SELECTOR, PRICE_SELECTOR after inspecting HTML.
    """
    url = "https://www.ina.hr/kupci/cijene-goriva/"
    soup = fetch(url)

    fuels = []

    # --- TUNE BELOW: adjust selectors to match actual HTML ---
    # Common pattern: rows in a pricing table
    rows = soup.select("table.price-table tr, .cijene-goriva tr, .fuel-price-row")

    for row in rows:
        name_el = row.select_one("td:first-child, .fuel-name, th")
        price_el = row.select_one("td:last-child, .fuel-price")
        if not name_el or not price_el:
            continue
        name = name_el.get_text(strip=True)
        price = parse_price(price_el.get_text(strip=True))
        if name and price:
            fuels.append(make_fuel_entry(name, price))

    return {
        "id": "ina",
        "name": "INA",
        "url": url,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "fuels": fuels,
    }


def scrape_tifon() -> dict:
    """
    Scrape Tifon fuel prices.
    URL: https://www.tifon.hr/hr/goriva/cijene-goriva/
    HTML hint: likely a table or div-based price list.
    Tune: TABLE_SELECTOR, NAME_SELECTOR, PRICE_SELECTOR after inspecting HTML.
    """
    url = "https://www.tifon.hr/hr/goriva/cijene-goriva/"
    soup = fetch(url)

    fuels = []

    # --- TUNE BELOW ---
    rows = soup.select(".price-list tr, .fuel-prices tr, table tr")

    for row in rows:
        cells = row.select("td")
        if len(cells) < 2:
            continue
        name = cells[0].get_text(strip=True)
        price = parse_price(cells[-1].get_text(strip=True))
        if name and price:
            fuels.append(make_fuel_entry(name, price))

    return {
        "id": "tifon",
        "name": "Tifon",
        "url": url,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "fuels": fuels,
    }


def scrape_crodux() -> dict:
    """
    Scrape Crodux fuel prices.
    URL: https://www.crodux-derivati.hr/maloprodaja/cijene-goriva
    HTML hint: may use a custom component or table.
    Tune: TABLE_SELECTOR, NAME_SELECTOR, PRICE_SELECTOR after inspecting HTML.
    """
    url = "https://www.crodux-derivati.hr/maloprodaja/cijene-goriva"
    soup = fetch(url)

    fuels = []

    # --- TUNE BELOW ---
    rows = soup.select(".price-table tr, .cijene tr, table.goriva tr")

    for row in rows:
        cells = row.select("td")
        if len(cells) < 2:
            continue
        name = cells[0].get_text(strip=True)
        price = parse_price(cells[-1].get_text(strip=True))
        if name and price:
            fuels.append(make_fuel_entry(name, price))

    return {
        "id": "crodux",
        "name": "Crodux",
        "url": url,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "fuels": fuels,
    }


def scrape_petrol() -> dict:
    """
    Scrape Petrol fuel prices.
    URL: https://www.petrol.hr/gorivo/cjenik
    HTML hint: Petrol Slovenia also operates in Croatia; the page may be JS-heavy.
    Tune: TABLE_SELECTOR, NAME_SELECTOR, PRICE_SELECTOR after inspecting HTML.
    """
    url = "https://www.petrol.hr/gorivo/cjenik"
    soup = fetch(url)

    fuels = []

    # --- TUNE BELOW ---
    rows = soup.select(".price-list tr, .cjenik tr, table tr")

    for row in rows:
        cells = row.select("td")
        if len(cells) < 2:
            continue
        name = cells[0].get_text(strip=True)
        price = parse_price(cells[-1].get_text(strip=True))
        if name and price:
            fuels.append(make_fuel_entry(name, price))

    return {
        "id": "petrol",
        "name": "Petrol",
        "url": url,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "fuels": fuels,
    }


def scrape_shell() -> dict:
    """
    Scrape Shell fuel prices.
    URL: https://www.shell.hr/motoristi/shell-goriva/cijena-goriva.html
    HTML hint: Shell HR typically lists prices in a styled table or definition list.
    Tune: TABLE_SELECTOR, NAME_SELECTOR, PRICE_SELECTOR after inspecting HTML.
    """
    url = "https://www.shell.hr/motoristi/shell-goriva/cijena-goriva.html"
    soup = fetch(url)

    fuels = []

    # --- TUNE BELOW ---
    rows = soup.select(".price-table tr, .fuel-list tr, table tr")

    for row in rows:
        cells = row.select("td")
        if len(cells) < 2:
            continue
        name = cells[0].get_text(strip=True)
        price = parse_price(cells[-1].get_text(strip=True))
        if name and price:
            fuels.append(make_fuel_entry(name, price))

    return {
        "id": "shell",
        "name": "Shell",
        "url": url,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "fuels": fuels,
    }


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

SCRAPERS = [
    scrape_ina,
    scrape_tifon,
    scrape_crodux,
    scrape_petrol,
    scrape_shell,
]


def run() -> None:
    stations = []
    errors = []

    for scraper in SCRAPERS:
        name = scraper.__name__.replace("scrape_", "").upper()
        print(f"Scraping {name}...", end=" ", flush=True)
        try:
            result = scraper()
            stations.append(result)
            fuel_count = len(result["fuels"])
            print(f"OK ({fuel_count} fuel(s) found)")
        except Exception as exc:  # noqa: BLE001
            print(f"FAILED — {exc}")
            errors.append((name, str(exc)))

    output = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "stations": stations,
    }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nWrote {len(stations)} station(s) to {OUTPUT_FILE}")

    if errors:
        print(f"\n{len(errors)} station(s) failed:")
        for station_name, msg in errors:
            print(f"  {station_name}: {msg}")
        # Exit with a non-zero code so the CI step is visible as a warning,
        # but still allow the commit step to run (partially updated data is
        # better than no data). Change to sys.exit(1) to make CI fail hard.
        sys.exit(0)


if __name__ == "__main__":
    run()
