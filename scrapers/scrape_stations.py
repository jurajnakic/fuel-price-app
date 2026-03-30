"""
scrape_stations.py — Scrapes fuel prices from cijenegoriva.info aggregator.

This site lists current fuel prices for all Croatian fuel companies in a
simple static HTML page, replacing the need for per-station scrapers.
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

SOURCE_URL = "https://www.cijenegoriva.info/"


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
    (["eurosuper 100", "super 100", "es100"], "es100"),
    (["premium eurosuper 95", "premium eurosuper95"], "premium_95"),
    (["eurosuper 95", "super 95", "es95"], "es95"),
    (["premium eurodizel", "premium eurodisel", "premium dizel",
      "premium diesel"], "premium_diesel"),
    (["eurodizel", "euro diesel", "eurodisel"], "eurodizel"),
    (["autoplin", "lpg", "ukapljeni"], "lpg"),
    (["loz ulje", "loživo ulje", "lož ulje"], "heating_oil"),
    (["plavi dizel", "plavi diesel"], "blue_diesel"),
    (["dizel", "diesel"], "eurodizel"),  # generic fallback
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


def make_company_id(name: str) -> str:
    """Generate a lowercase ID from company name.

    Examples: "INA" → "ina", "Lukoil Croatia" → "lukoil_croatia"
    """
    cid = name.strip().lower()
    cid = re.sub(r"[^a-z0-9]+", "_", cid)
    cid = cid.strip("_")
    return cid


# ---------------------------------------------------------------------------
# Main scraper
# ---------------------------------------------------------------------------

def scrape_cijenegoriva() -> list[dict]:
    """
    Scrape cijenegoriva.info for all Croatian fuel company prices.

    Returns a list of station dicts in the standard format.
    """
    soup = fetch(SOURCE_URL)

    # --- Extract validity date ---
    validity_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    validity_match = re.search(
        r"CIJENE\s+vrijede\s+od\s+(\d{1,2})\.(\d{1,2})\.(\d{4})\.\s+do\s+(\d{1,2})\.(\d{1,2})\.(\d{4})\.",
        soup.get_text(),
        re.IGNORECASE,
    )
    if validity_match:
        # Use the "from" date as the updated date
        day, month, year = validity_match.group(1), validity_match.group(2), validity_match.group(3)
        validity_date = f"{year}-{month.zfill(2)}-{day.zfill(2)}"
        print(f"  Validity period: {validity_match.group(0)}")
    else:
        print("  WARNING: Could not find validity date, using today's date")

    # --- Parse fuel sections ---
    # Each fuel type is in a <strong> tag followed by a <table>
    # All content is inside div.tr-details.content
    content_div = soup.select_one("div.tr-details.content")
    if content_div is None:
        # Fallback: search the whole page
        content_div = soup

    # Build: company_name → list of fuel entries
    companies: dict[str, list[dict]] = {}

    # Find all <strong> elements that contain fuel type names
    strong_tags = content_div.find_all("strong")

    for strong in strong_tags:
        fuel_name = strong.get_text(strip=True)
        if not fuel_name:
            continue

        # Only process known fuel types
        fuel_type = classify_fuel(fuel_name)
        if fuel_type == "other":
            continue

        # Find the next <table> after this <strong>
        # Walk through siblings of the parent element
        table = None
        parent = strong.parent
        if parent is None:
            continue

        # The table might be a sibling of the parent <p> element
        for sibling in parent.find_next_siblings():
            if sibling.name == "table":
                table = sibling
                break
            # If we hit another <p> with a <strong>, stop looking
            if sibling.name == "p" and sibling.find("strong"):
                break

        # Also try: table might be directly after the strong within same parent
        if table is None:
            table = strong.find_next("table")

        if table is None:
            print(f"  WARNING: No table found for fuel type '{fuel_name}'")
            continue

        rows = table.find_all("tr")
        row_count = 0
        for row in rows:
            cells = row.find_all("td")
            if len(cells) < 2:
                continue

            company_name = cells[0].get_text(strip=True)
            price_text = cells[1].get_text(strip=True)

            if not company_name:
                continue

            price = parse_price(price_text)
            if price is None:
                continue

            if company_name not in companies:
                companies[company_name] = []

            companies[company_name].append(make_fuel_entry(fuel_name, price))
            row_count += 1

        print(f"  {fuel_name} ({fuel_type}): {row_count} companies")

    # --- Filter to known stations only ---
    ALLOWED_STATIONS = {"ina", "petrol", "shell", "tifon", "lukoil"}

    # --- Transform to station list ---
    stations = []
    for company_name, fuels in sorted(companies.items()):
        company_id = make_company_id(company_name)
        if company_id not in ALLOWED_STATIONS:
            print(f"  Skipping: {company_name} ({company_id})")
            continue
        station = {
            "id": company_id,
            "name": company_name,
            "url": SOURCE_URL,
            "updated": validity_date,
            "fuels": fuels,
        }
        stations.append(station)

    return stations


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def run() -> None:
    print(f"Scraping {SOURCE_URL}...")

    try:
        stations = scrape_cijenegoriva()
    except Exception as exc:  # noqa: BLE001
        print(f"FAILED — {exc}", file=sys.stderr)
        sys.exit(1)

    output = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "stations": stations,
    }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")

    total_fuels = sum(len(s["fuels"]) for s in stations)
    print(f"\nWrote {len(stations)} company/station(s) ({total_fuels} fuel entries) to {OUTPUT_FILE}")

    if not stations:
        print("\nWARNING: No stations found. The page structure may have changed.")


if __name__ == "__main__":
    run()
