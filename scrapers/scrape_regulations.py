"""
scrape_regulations.py — Checks Narodne Novine for new fuel price regulations.

If a newer regulation is found, updates nn_reference, nn_url, and attempts
to parse numeric parameters (premiums, excise duties, density, VAT) from
the regulation text. A safety backup is created before any changes, and all
parsed values are validated against reasonable ranges.
"""

import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from bs4 import BeautifulSoup

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
PARAMS_FILE = REPO_ROOT / "config" / "fuel_params.json"
BACKUP_FILE = REPO_ROOT / "config" / "fuel_params_backup.json"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Narodne Novine search URL for the fuel price regulation.
NN_SEARCH_URL = (
    "https://narodne-novine.nn.hr/search.aspx"
    "?upit=uredba+o+utvrđivanju+najvišim+maloprodajnih+cijena+naftnih+derivata"
    "&kategorija=1&rpp=10&qtype=1&pretraga=da"
)

# Fallback: scrape the NN acts index page directly for the decree category.
NN_ACTS_URL = "https://narodne-novine.nn.hr/clanci/sluzbeni/aktuelni.aspx"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (compatible; FuelRegBot/1.0; +https://github.com)"
    )
}
REQUEST_TIMEOUT = 15

# ---------------------------------------------------------------------------
# Validation ranges for parsed numeric values
# ---------------------------------------------------------------------------

VALID_RANGES = {
    "premium": (0.01, 1.0),       # EUR
    "excise": (0.001, 1.0),       # EUR
    "density": (0.6, 1.0),        # kg/L
    "vat_rate": (0.1, 0.5),       # 10-50%
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fetch(url: str) -> BeautifulSoup:
    resp = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return BeautifulSoup(resp.text, "html.parser")


def parse_nn_reference(text: str) -> tuple[int, int] | None:
    """
    Extract (year, issue_number) from an NN reference string.
    Accepts formats like 'NN 31/2025' or 'Narodne novine 31/2025'.
    Returns None if the text cannot be parsed.
    """
    match = re.search(r"(\d{1,3})[/\\](\d{4})", text)
    if match:
        issue = int(match.group(1))
        year = int(match.group(2))
        return (year, issue)
    return None


def is_newer(candidate: str, current: str) -> bool:
    """
    Return True if candidate NN reference is newer than current.
    Comparison is based on (year, issue_number).
    """
    c_parsed = parse_nn_reference(candidate)
    cur_parsed = parse_nn_reference(current)
    if c_parsed is None or cur_parsed is None:
        return False
    return c_parsed > cur_parsed


def build_nn_url(nn_reference: str) -> str | None:
    """
    Attempt to construct the direct article URL from an NN reference.
    Since the article ID is not known in advance, returns None.
    """
    return None


def parse_croatian_float(text: str) -> float | None:
    """Parse a Croatian-format number (comma as decimal separator)."""
    if not text:
        return None
    cleaned = text.strip().replace("\xa0", "").replace(" ", "")
    cleaned = cleaned.replace(",", ".")
    try:
        return float(cleaned)
    except ValueError:
        return None


def validate_value(value: float, category: str) -> bool:
    """Check if a value falls within the expected range for its category."""
    if category not in VALID_RANGES:
        return False
    low, high = VALID_RANGES[category]
    return low <= value <= high


# ---------------------------------------------------------------------------
# Scraping logic
# ---------------------------------------------------------------------------

def find_latest_regulation() -> dict | None:
    """
    Search Narodne Novine for the latest fuel price regulation decree.

    Returns a dict with keys 'nn_reference' and 'nn_url', or None if nothing
    usable is found.
    """
    soup = fetch(NN_SEARCH_URL)

    result_selector = ".resultItem, .search-result, li.result"
    title_selector = "a.resultTitle, a.title, h3 > a, .result-title a"
    meta_selector = ".resultMeta, .meta, .nn-reference, .clanak-info"

    results = soup.select(result_selector)

    for result in results:
        title_el = result.select_one(title_selector)
        if not title_el:
            continue

        title_text = title_el.get_text(strip=True).lower()
        if "naftnih derivata" not in title_text and "cijene goriva" not in title_text:
            continue

        meta_el = result.select_one(meta_selector)
        meta_text = meta_el.get_text(strip=True) if meta_el else result.get_text(strip=True)

        nn_match = re.search(r"NN\s+\d{1,3}/\d{4}", meta_text, re.IGNORECASE)
        if not nn_match:
            continue

        nn_reference = nn_match.group(0).upper().replace("NN", "NN").strip()
        nn_reference = re.sub(r"NN\s*(\d)", r"NN \1", nn_reference)

        href = title_el.get("href", "")
        if href and not href.startswith("http"):
            href = "https://narodne-novine.nn.hr" + href

        nn_url = href if href else NN_SEARCH_URL

        return {
            "nn_reference": nn_reference,
            "nn_url": nn_url,
        }

    return None


# ---------------------------------------------------------------------------
# Regulation text parser
# ---------------------------------------------------------------------------

def parse_regulation_params(url: str) -> dict:
    """
    Fetch the full regulation text and attempt to extract numeric parameters.

    Returns a dict with parsed values. Missing values are omitted (not None).
    Structure:
    {
        "premiums": {"es95": 0.1545, ...},
        "excise_duties": {"es95": 0.456, ...},
        "density": {"es95": 0.755, ...},
        "vat_rate": 0.25,
        "effective_date": "2025-02-26",
    }
    """
    result: dict = {}

    try:
        soup = fetch(url)
    except Exception as exc:
        print(f"  WARNING: Could not fetch regulation text: {exc}")
        return result

    text = soup.get_text()

    # --- Extract effective date ---
    # Look for patterns like "stupa na snagu DD. MM. YYYY." or
    # "primjenjuje se od DD. MMMM YYYY."
    date_match = re.search(
        r"(?:stupa\s+na\s+snagu|primjenjuje\s+se\s+od)\s+(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})",
        text, re.IGNORECASE,
    )
    if date_match:
        day = date_match.group(1).zfill(2)
        month = date_match.group(2).zfill(2)
        year = date_match.group(3)
        result["effective_date"] = f"{year}-{month}-{day}"
        print(f"  Parsed effective_date: {result['effective_date']}")

    # --- Extract premiums (premija) ---
    # Look for patterns like "premija ... 0,1545 EUR/L" or "premija ... 0,1545 €/l"
    premiums = {}
    fuel_premium_patterns = [
        (r"eurosuper\s*95.*?premij[au]\s*[:\s]*(\d+[,\.]\d+)", "es95"),
        (r"eurosuper\s*100.*?premij[au]\s*[:\s]*(\d+[,\.]\d+)", "es100"),
        (r"premij[au].*?eurosuper\s*95[^0-9]*(\d+[,\.]\d+)", "es95"),
        (r"premij[au].*?eurosuper\s*100[^0-9]*(\d+[,\.]\d+)", "es100"),
        (r"premij[au].*?eurodizel[^0-9]*(\d+[,\.]\d+)", "eurodizel"),
        (r"eurodizel.*?premij[au]\s*[:\s]*(\d+[,\.]\d+)", "eurodizel"),
        (r"premij[au].*?UNP.*?(\d+[,\.]\d+)", "unp_10kg"),
    ]
    for pattern, fuel_key in fuel_premium_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match and fuel_key not in premiums:
            val = parse_croatian_float(match.group(1))
            if val is not None:
                premiums[fuel_key] = val

    # Also try a general table-like pattern for premiums
    # "premija ... 0,1545 EUR" appearing near fuel names
    general_premium = re.findall(
        r"premij[au]\s*[^0-9]{0,50}?(\d+[,\.]\d+)\s*(?:EUR|€|kn)",
        text, re.IGNORECASE,
    )
    if general_premium and not premiums:
        # If only one premium value found, it likely applies to es95 and eurodizel
        val = parse_croatian_float(general_premium[0])
        if val is not None:
            premiums.setdefault("es95", val)
            premiums.setdefault("es100", val)
            premiums.setdefault("eurodizel", val)

    if premiums:
        result["premiums"] = premiums
        print(f"  Parsed premiums: {premiums}")

    # --- Extract excise duties (trošarina) ---
    excise = {}
    fuel_excise_patterns = [
        (r"eurosuper\s*95.*?trošarin[aeu]\s*[:\s]*(\d+[,\.]\d+)", "es95"),
        (r"eurosuper\s*100.*?trošarin[aeu]\s*[:\s]*(\d+[,\.]\d+)", "es100"),
        (r"trošarin[aeu].*?eurosuper\s*95[^0-9]*(\d+[,\.]\d+)", "es95"),
        (r"trošarin[aeu].*?eurosuper\s*100[^0-9]*(\d+[,\.]\d+)", "es100"),
        (r"trošarin[aeu].*?eurodizel[^0-9]*(\d+[,\.]\d+)", "eurodizel"),
        (r"eurodizel.*?trošarin[aeu]\s*[:\s]*(\d+[,\.]\d+)", "eurodizel"),
        (r"trošarin[aeu].*?UNP.*?(\d+[,\.]\d+)", "unp_10kg"),
    ]
    for pattern, fuel_key in fuel_excise_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match and fuel_key not in excise:
            val = parse_croatian_float(match.group(1))
            if val is not None:
                excise[fuel_key] = val

    if excise:
        result["excise_duties"] = excise
        print(f"  Parsed excise_duties: {excise}")

    # --- Extract density (gustoća) ---
    density = {}
    fuel_density_patterns = [
        (r"eurosuper\s*95.*?gustoć[aeu]\s*[:\s]*(\d+[,\.]\d+)", "es95"),
        (r"eurosuper\s*100.*?gustoć[aeu]\s*[:\s]*(\d+[,\.]\d+)", "es100"),
        (r"gustoć[aeu].*?eurosuper\s*95[^0-9]*(\d+[,\.]\d+)", "es95"),
        (r"gustoć[aeu].*?eurosuper\s*100[^0-9]*(\d+[,\.]\d+)", "es100"),
        (r"gustoć[aeu].*?eurodizel[^0-9]*(\d+[,\.]\d+)", "eurodizel"),
        (r"eurodizel.*?gustoć[aeu]\s*[:\s]*(\d+[,\.]\d+)", "eurodizel"),
    ]
    for pattern, fuel_key in fuel_density_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match and fuel_key not in density:
            val = parse_croatian_float(match.group(1))
            if val is not None:
                density[fuel_key] = val

    if density:
        result["density"] = density
        print(f"  Parsed density: {density}")

    # --- Extract VAT rate ---
    vat_match = re.search(r"PDV[^0-9]{0,30}?(\d{1,2})\s*%", text, re.IGNORECASE)
    if not vat_match:
        vat_match = re.search(r"porez\s+na\s+dodanu\s+vrijednost[^0-9]{0,30}?(\d{1,2})\s*%", text, re.IGNORECASE)
    if vat_match:
        vat_pct = int(vat_match.group(1))
        result["vat_rate"] = vat_pct / 100.0
        print(f"  Parsed vat_rate: {result['vat_rate']}")

    return result


def validate_parsed_params(parsed: dict) -> tuple[bool, list[str]]:
    """
    Validate all parsed numeric values against reasonable ranges.

    Returns (all_valid, list_of_warnings).
    If any value is out of range, all_valid is False.
    """
    warnings = []
    all_valid = True

    for fuel_key, val in parsed.get("premiums", {}).items():
        if not validate_value(val, "premium"):
            warnings.append(f"Premium {fuel_key}={val} outside range {VALID_RANGES['premium']}")
            all_valid = False

    for fuel_key, val in parsed.get("excise_duties", {}).items():
        if not validate_value(val, "excise"):
            warnings.append(f"Excise {fuel_key}={val} outside range {VALID_RANGES['excise']}")
            all_valid = False

    for fuel_key, val in parsed.get("density", {}).items():
        if not validate_value(val, "density"):
            warnings.append(f"Density {fuel_key}={val} outside range {VALID_RANGES['density']}")
            all_valid = False

    if "vat_rate" in parsed:
        if not validate_value(parsed["vat_rate"], "vat_rate"):
            warnings.append(f"VAT rate={parsed['vat_rate']} outside range {VALID_RANGES['vat_rate']}")
            all_valid = False

    return all_valid, warnings


def apply_parsed_params(params: dict, parsed: dict) -> None:
    """
    Merge validated parsed numeric parameters into the params dict.
    Only updates keys that were actually found in the regulation text.
    """
    if "premiums" in parsed:
        for fuel_key, val in parsed["premiums"].items():
            old = params["premiums"].get(fuel_key)
            params["premiums"][fuel_key] = val
            print(f"  premiums.{fuel_key}: {old} -> {val}")

    if "excise_duties" in parsed:
        for fuel_key, val in parsed["excise_duties"].items():
            old = params["excise_duties"].get(fuel_key)
            params["excise_duties"][fuel_key] = val
            print(f"  excise_duties.{fuel_key}: {old} -> {val}")

    if "density" in parsed:
        for fuel_key, val in parsed["density"].items():
            old = params["density"].get(fuel_key)
            params["density"][fuel_key] = val
            print(f"  density.{fuel_key}: {old} -> {val}")

    if "vat_rate" in parsed:
        old = params.get("vat_rate")
        params["vat_rate"] = parsed["vat_rate"]
        print(f"  vat_rate: {old} -> {parsed['vat_rate']}")

    if "effective_date" in parsed:
        old = params.get("price_regulation", {}).get("effective_date")
        params["price_regulation"]["effective_date"] = parsed["effective_date"]
        print(f"  effective_date: {old} -> {parsed['effective_date']}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run() -> None:
    if not PARAMS_FILE.exists():
        print(f"ERROR: {PARAMS_FILE} not found.", file=sys.stderr)
        sys.exit(1)

    params = json.loads(PARAMS_FILE.read_text(encoding="utf-8"))
    current_ref = params.get("price_regulation", {}).get("nn_reference", "")

    print(f"Current regulation: {current_ref}")
    print("Checking Narodne Novine for newer regulation...")

    try:
        latest = find_latest_regulation()
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: Failed to fetch Narodne Novine — {exc}", file=sys.stderr)
        sys.exit(1)

    if latest is None:
        print("No regulation found in search results. No changes made.")
        return

    candidate_ref = latest["nn_reference"]
    print(f"Latest found:       {candidate_ref}")

    if not is_newer(candidate_ref, current_ref):
        print("No newer regulation found. No changes made.")
        return

    # --- Create safety backup before any changes ---
    print(f"\nCreating backup: {BACKUP_FILE}")
    shutil.copy2(PARAMS_FILE, BACKUP_FILE)

    # --- Always update the reference fields ---
    params["price_regulation"]["nn_reference"] = candidate_ref
    params["price_regulation"]["nn_url"] = latest["nn_url"]

    # --- Attempt to parse numeric parameters from regulation text ---
    print(f"\nFetching regulation text from: {latest['nn_url']}")
    parsed = parse_regulation_params(latest["nn_url"])

    numeric_updated = False

    if parsed:
        # Check for non-reference fields (effective_date, premiums, etc.)
        has_numeric = any(
            k in parsed for k in ("premiums", "excise_duties", "density", "vat_rate")
        )

        if has_numeric:
            all_valid, warnings = validate_parsed_params(parsed)

            if all_valid:
                print("\nAll parsed values within valid ranges. Applying updates:")
                apply_parsed_params(params, parsed)
                numeric_updated = True
            else:
                print("\nWARNING: Some parsed values are outside valid ranges:")
                for w in warnings:
                    print(f"  - {w}")
                print("Keeping ALL old numeric parameters. Only updating reference.")
                # Still apply effective_date if it was parsed (it's not numeric)
                if "effective_date" in parsed:
                    params["price_regulation"]["effective_date"] = parsed["effective_date"]
                    print(f"  (effective_date updated to {parsed['effective_date']})")
        else:
            # Only effective_date found, no numeric values
            if "effective_date" in parsed:
                params["price_regulation"]["effective_date"] = parsed["effective_date"]
                print(f"\nUpdated effective_date: {parsed['effective_date']}")
            else:
                print("\nNo numeric parameters could be parsed from regulation text.")
    else:
        print("\nWARNING: Could not parse any parameters from regulation text.")
        print("Only nn_reference and nn_url were updated.")

    # --- Update version to match the new regulation date ---
    if "effective_date" in parsed:
        params["version"] = parsed["effective_date"]
    else:
        # Use today's date if no effective date was parsed
        params["version"] = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # --- Write updated params ---
    PARAMS_FILE.write_text(
        json.dumps(params, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"\nUpdated fuel_params.json:")
    print(f"  nn_reference: {current_ref}  ->  {candidate_ref}")
    print(f"  nn_url:       {latest['nn_url']}")
    print(f"  version:      {params['version']}")

    if numeric_updated:
        print(f"\n  Numeric parameters were updated from the regulation text.")
    else:
        print(
            f"\n  NOTE: Numeric parameters (premiums, excise duties, density) were NOT\n"
            f"  changed. Please review the new regulation and update them manually if\n"
            f"  the decree changed the values."
        )

    print(f"\n  Backup saved to: {BACKUP_FILE}")


if __name__ == "__main__":
    run()
