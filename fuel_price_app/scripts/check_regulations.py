#!/usr/bin/env python3
"""
Check Narodne Novine for new fuel-related regulations.

Searches the NN website for recent regulations mentioning fuel/oil derivatives
and compares against the currently known version in fuel_params.json.
If a new regulation is found, outputs details for notification.
"""

import json
import re
import sys
from urllib.request import urlopen, Request
from html.parser import HTMLParser


# Keywords that indicate fuel price regulations
KEYWORDS = [
    'naftni derivat',
    'naftnih derivata',
    'cijena goriva',
    'cijene goriva',
    'maloprodajn',
    'trošarin',
    'energent',
]

SEARCH_URL = 'https://narodne-novine.nn.hr/search.aspx?sortiraj=1&pojam={keyword}&page=1'


def url_encode(text):
    """Simple percent-encoding for URL query parameters."""
    safe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~'
    result = []
    for ch in text:
        if ch in safe:
            result.append(ch)
        elif ch == ' ':
            result.append('+')
        else:
            for b in ch.encode('utf-8'):
                result.append(f'%{b:02X}')
    return ''.join(result)


class NNSearchParser(HTMLParser):
    """Parse search results from narodne-novine.nn.hr."""

    def __init__(self):
        super().__init__()
        self.results = []
        self._in_result = False
        self._in_link = False
        self._current_url = ''
        self._current_title = ''
        self._in_date = False
        self._current_date = ''
        self._current_text = ''

    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        cls = attrs_dict.get('class', '')
        href = attrs_dict.get('href', '')

        if tag == 'div' and 'result-item' in cls:
            self._in_result = True
        elif tag == 'a' and self._in_result and '/clanci/sluzbeni/' in href:
            self._in_link = True
            self._current_url = href
            self._current_title = ''
        elif tag == 'span' and 'date' in cls and self._in_result:
            self._in_date = True
            self._current_date = ''

    def handle_endtag(self, tag):
        if tag == 'a' and self._in_link:
            self._in_link = False
        elif tag == 'span' and self._in_date:
            self._in_date = False
        elif tag == 'div' and self._in_result:
            if self._current_title and self._current_url:
                self.results.append({
                    'title': self._current_title.strip(),
                    'url': self._current_url.strip(),
                    'date': self._current_date.strip(),
                })
            self._in_result = False
            self._current_title = ''
            self._current_url = ''
            self._current_date = ''

    def handle_data(self, data):
        if self._in_link:
            self._current_title += data
        if self._in_date:
            self._current_date += data


def fetch_url(url):
    req = Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (compatible; FuelLens/1.0)',
        'Accept': 'text/html',
    })
    with urlopen(req, timeout=30) as resp:
        return resp.read().decode('utf-8', errors='replace')


def search_nn(keyword):
    """Search Narodne Novine for a keyword."""
    url = SEARCH_URL.format(keyword=url_encode(keyword))
    try:
        html = fetch_url(url)
        parser = NNSearchParser()
        parser.feed(html)
        return parser.results
    except Exception as e:
        print(f'  Search failed for "{keyword}": {e}', file=sys.stderr)
        return []


def is_fuel_regulation(title):
    """Check if a search result title is about fuel price regulation."""
    title_lower = title.lower()
    fuel_terms = ['naftni', 'goriva', 'gorivo', 'derivat', 'maloprodajn',
                  'trošarin', 'energent', 'benzin', 'dizel']
    return any(term in title_lower for term in fuel_terms)


def main():
    # Load current config version
    try:
        with open('config/fuel_params.json', 'r') as f:
            config = json.load(f)
        current_nn = config.get('price_regulation', {}).get('nn_reference', '')
        current_excise_nn = config.get('excise_regulation', {}).get('nn_reference', '')
        print(f'Current price regulation: {current_nn}', file=sys.stderr)
        print(f'Current excise regulation: {current_excise_nn}', file=sys.stderr)
    except Exception:
        current_nn = ''
        current_excise_nn = ''

    # Search NN for fuel-related regulations
    all_results = []
    seen_urls = set()

    for keyword in KEYWORDS:
        print(f'Searching NN for: "{keyword}"...', file=sys.stderr)
        results = search_nn(keyword)
        for r in results:
            if r['url'] not in seen_urls:
                seen_urls.add(r['url'])
                all_results.append(r)

    # Filter for actual fuel regulations
    fuel_results = [r for r in all_results if is_fuel_regulation(r['title'])]
    print(f'Found {len(fuel_results)} fuel-related regulations', file=sys.stderr)

    # Extract NN references from titles (e.g., "NN 31/2025")
    new_regulations = []
    for r in fuel_results:
        nn_match = re.search(r'(\d+/\d{4})', r.get('date', '') + ' ' + r['title'])
        nn_ref = f'NN {nn_match.group(1)}' if nn_match else ''

        # Check if this is newer than what we have
        if nn_ref and nn_ref != current_nn and nn_ref != current_excise_nn:
            new_regulations.append({
                'title': r['title'],
                'nn_reference': nn_ref,
                'url': r['url'] if r['url'].startswith('http') else f'https://narodne-novine.nn.hr{r["url"]}',
                'date': r.get('date', ''),
            })

    if new_regulations:
        print(f'\n!!! Found {len(new_regulations)} potentially new regulation(s):', file=sys.stderr)
        for reg in new_regulations:
            print(f'  - {reg["nn_reference"]}: {reg["title"]}', file=sys.stderr)
            print(f'    URL: {reg["url"]}', file=sys.stderr)

    # Output JSON for GitHub Action
    output = {
        'has_new': len(new_regulations) > 0,
        'current_price_regulation': current_nn,
        'current_excise_regulation': current_excise_nn,
        'new_regulations': new_regulations,
    }
    json.dump(output, sys.stdout, ensure_ascii=False, indent=2)
    print()

    return 0 if not new_regulations else 1


if __name__ == '__main__':
    sys.exit(main())
