"""
scrape_regulations.py — Checks Narodne Novine for new fuel price regulations.

If a newer regulation is found, only nn_reference and nn_url in
fuel_params.json are updated. Numeric parameters (premiums, excise duties,
density) are intentionally left unchanged — they require manual review before
being updated in the app.
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
PARAMS_FILE = REPO_ROOT / "config" / "fuel_params.json"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Narodne Novine search URL for the fuel price regulation.
# The query targets the full Croatian title of the decree; adjust if the
# search interface changes.
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
    NN URL pattern (for full HTML): /clanci/sluzbeni/full/{YYYY}_{MM}_{issue}_{article_id}.html
    Since the article ID is not known in advance, this function returns None
    and the caller should fall back to the search page URL.
    """
    return None


# ---------------------------------------------------------------------------
# Scraping logic
# ---------------------------------------------------------------------------

def find_latest_regulation() -> dict | None:
    """
    Search Narodne Novine for the latest fuel price regulation decree.

    Returns a dict with keys 'nn_reference' and 'nn_url', or None if nothing
    usable is found.

    --- TUNE BELOW ---
    The selectors depend on NN's current search result HTML structure.
    Inspect the live page and adjust result_selector / title_selector /
    link_selector as needed.
    """
    soup = fetch(NN_SEARCH_URL)

    # Typical NN search results: each result is a <div class="resultItem"> or
    # a <li> element containing a title link and metadata.
    result_selector = ".resultItem, .search-result, li.result"
    title_selector = "a.resultTitle, a.title, h3 > a, .result-title a"
    meta_selector = ".resultMeta, .meta, .nn-reference, .clanak-info"

    results = soup.select(result_selector)

    for result in results:
        title_el = result.select_one(title_selector)
        if not title_el:
            continue

        title_text = title_el.get_text(strip=True).lower()
        # Only consider results that mention the fuel price regulation
        if "naftnih derivata" not in title_text and "cijene goriva" not in title_text:
            continue

        # Try to extract NN reference from the metadata block
        meta_el = result.select_one(meta_selector)
        meta_text = meta_el.get_text(strip=True) if meta_el else result.get_text(strip=True)

        nn_match = re.search(r"NN\s+\d{1,3}/\d{4}", meta_text, re.IGNORECASE)
        if not nn_match:
            continue

        nn_reference = nn_match.group(0).upper().replace("NN", "NN").strip()
        # Normalise spacing: "NN31/2025" → "NN 31/2025"
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

    # Update only the reference fields — numeric params require manual review
    params["price_regulation"]["nn_reference"] = candidate_ref
    params["price_regulation"]["nn_url"] = latest["nn_url"]

    PARAMS_FILE.write_text(
        json.dumps(params, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(
        f"\nUpdated fuel_params.json:\n"
        f"  nn_reference: {current_ref}  →  {candidate_ref}\n"
        f"  nn_url:       {latest['nn_url']}\n"
        f"\nNOTE: Numeric parameters (premiums, excise duties, density) were NOT\n"
        f"changed. Please review the new regulation and update them manually if\n"
        f"the decree changed the values."
    )


if __name__ == "__main__":
    run()
