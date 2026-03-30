# FuelLens konfiguracija

Ova mapa sadrži konfiguracijske datoteke koje aplikacija dohvaca s GitHuba.
Promjene ovdje se automatski primjenjuju u aplikaciji bez potrebe za novom verzijom.

## fuel_params.json - Parametri formule

Ovo je najvaznija datoteka. Sadrzi parametre za izracun cijena goriva prema Uredbi.

### Kada azurirati?

Kada Vlada donese novu uredbu o cijenama naftnih derivata ili trosarinama.
GitHub Action (`check-regulations.yml`) provjerava Narodne novine svaki ponedjeljak
i kreira GitHub issue ako nade novu uredbu.

### Sto treba rucno mijenjati?

```json
{
  "version": "2025-02-26",        // <-- datum nove uredbe (YYYY-MM-DD)

  "price_cycle": {
    "reference_date": "2026-03-24", // <-- datum od kojeg se racunaju ciklusi
    "cycle_days": 14                // <-- trajanje ciklusa (obicno 14 dana)
  },

  "price_regulation": {
    "name": "...",                  // <-- naziv uredbe
    "nn_reference": "NN 31/2025",  // <-- NN broj nove uredbe
    "effective_date": "2025-02-26", // <-- datum stupanja na snagu
    "nn_url": "https://..."         // <-- link na NN stranicu
  },

  "excise_regulation": {
    "name": "...",                  // <-- naziv uredbe o trosarinama
    "nn_reference": "NN 156/2022", // <-- NN broj
    "effective_date": "2023-01-01"  // <-- datum stupanja na snagu
  },

  "premiums": {                    // <-- premija (P) iz uredbe, EUR/L ili EUR/kg
    "es95": 0.1545,
    "es100": 0.1545,
    "eurodizel": 0.1545,
    "unp_10kg": 0.8429
  },

  "excise_duties": {               // <-- trosarina iz uredbe, EUR/L ili EUR/kg
    "es95": 0.4560,
    "es100": 0.4560,
    "eurodizel": 0.40613,
    "unp_10kg": 0.01327
  },

  "density": {                     // <-- gustoca goriva kg/L (UNP nema gustocu)
    "es95": 0.755,
    "es100": 0.755,
    "eurodizel": 0.845
  },

  "vat_rate": 0.25,               // <-- PDV (0.25 = 25%)

  "yahoo_symbols": {               // <-- NE DIRATI osim ako se promijeni izvor
    "es95": "RB=F",
    "es100": "RB=F",
    "eurodizel": "HO=F",
    "unp_10kg": "BZ=F"
  },

  "cif_med_factors": {             // <-- konverzijski faktori Yahoo -> CIF Med
    "es95": 402.4,                 //     NE DIRATI osim ako cijene drasticno odskacu
    "es100": 402.4,
    "eurodizel": 327.0,
    "unp_10kg": 16.0
  }
}
```

### Primjer: nova uredba s visim trosarinama

Ako nova uredba NN 50/2026 povecava trosarinu za benzin na 0.50 EUR/L:

1. Promijeni `version` na `"2026-05-15"` (datum uredbe)
2. Promijeni `price_regulation.nn_reference` na `"NN 50/2026"`
3. Promijeni `price_regulation.effective_date` na datum stupanja na snagu
4. Promijeni `excise_duties.es95` na `0.50`
5. Commitaj i pushaj - aplikacija ce pokupiti promjene pri sljedecem syncu

### Polja koja se rijetko mijenjaju

| Polje | Kada se mijenja |
|-------|----------------|
| `premiums` | Nova uredba o maloprodajnim cijenama |
| `excise_duties` | Nova uredba o trosarinama |
| `density` | Nikad (fizicka konstanta) |
| `vat_rate` | Promjena PDV-a (jako rijetko) |
| `reference_date` | Kad se promijeni pocetni datum ciklusa |
| `yahoo_symbols` | Nikad (osim ako Yahoo promijeni simbole) |
| `cif_med_factors` | Ako izracunate cijene sustavno odskacu od stvarnih |

---

## station_prices.json - Cijene po postajama

**Automatski se azurira** svaki dan u 09:00 CET putem GitHub Action-a.
Scraper dohvaca podatke s cijenegoriva.info (primarni) i hak.hr (backup).

### Ne treba rucno dirati!

Ova datoteka se generira automatski. Ako scraper prestane raditi
(npr. promjena strukture web stranice), provjeri `scripts/scrape_station_prices.py`.

### Format

```json
{
  "updated": "2026-03-30",
  "validity": "24.03.2026 - 07.04.2026",
  "stations": [
    {
      "id": "ina",
      "name": "INA",
      "url": "https://www.ina.hr",
      "updated": "2026-03-30",
      "fuels": [
        { "name": "Eurosuper 95", "type": "es95", "price": 1.62 },
        { "name": "Eurodizel", "type": "eurodizel", "price": 1.73 }
      ]
    }
  ]
}
```

---

## GitHub Actions

| Workflow | Raspored | Sto radi |
|----------|----------|----------|
| `scrape-station-prices.yml` | Svaki dan 09:00 CET | Scrapa cijene postaja, commitira ako ima promjena |
| `check-regulations.yml` | Svaki ponedjeljak 10:00 CET | Pretrazuje NN za nove uredbe, kreira issue ako nade |

Oba se mogu pokrenuti i rucno: Actions tab > workflow > Run workflow.
