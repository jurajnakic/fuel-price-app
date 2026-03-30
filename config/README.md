# FuelLens - konfiguracija

Ova mapa sadrzi konfiguracijske datoteke koje aplikacija dohvaca s GitHuba.
Promjene ovdje se automatski primjenjuju u aplikaciji bez potrebe za novom verzijom.

---

## Sto je automatski, a sto rucno?

| Podatak | Automatski? | Objasnjenje |
|---------|-------------|-------------|
| Cijene po postajama | DA | Scraper svaki dan dohvaca s cijenegoriva.info |
| Detekcija novih uredbi | DA | Provjera Narodnih novina svaki ponedjeljak |
| Parametri formule (trosarine, premije...) | NE | Rucni update kad izade nova uredba |
| Tržisne cijene sirovina | DA | Aplikacija dohvaca s Yahoo Finance |
| Tecaj EUR/USD | DA | Aplikacija dohvaca s HNB API |

**Jedino sto trebas rucno**: kad dobijes GitHub issue o novoj uredbi, azurirati
brojke u `fuel_params.json` (vidi upute ispod).

---

## fuel_params.json - Parametri formule

Aplikacija koristi ove parametre za izracun cijena goriva prema formuli iz Uredbe.

### Kada azurirati?

Kada Vlada donese novu uredbu. Dobit ces **GitHub issue** s obavijesti.
Uredbe se mijenjaju rijetko (1-2 puta godisnje).

### Koji parametri postoje?

Datoteka ima vise sekcija. Ovdje je objasnjenje svake:

#### 1. Osnovni podaci (azurirati pri svakoj novoj uredbi)

```
"version"           - datum uredbe, format YYYY-MM-DD (npr. "2025-02-26")
"price_regulation"  - naziv, NN broj i link na uredbu o cijenama
"excise_regulation" - naziv i NN broj uredbe o trosarinama
```

#### 2. Parametri iz uredbe (azurirati kad se promijene)

```
"premiums"      - premija (P) za svako gorivo, u EUR/L ili EUR/kg
                  Ovo je fiksni iznos koji se dodaje na baznu cijenu.
                  Nalazi se u tekstu uredbe o cijenama.

"excise_duties" - trosarina za svako gorivo, u EUR/L ili EUR/kg
                  Nalazi se u uredbi o trosarinama.

"vat_rate"      - PDV stopa (0.25 = 25%). Mijenja se krajnje rijetko.

"density"       - gustoca goriva u kg/L. NE MIJENJATI - fizicka konstanta.
```

#### 3. Ciklus cijena

```
"price_cycle.reference_date" - pocetni datum od kojeg se racunaju 14-dnevni ciklusi
"price_cycle.cycle_days"     - trajanje ciklusa (14 dana)
```

Ovo treba azurirati samo ako se promijeni ritam promjene cijena.

#### 4. Konverzijski faktori (NE DIRATI bez razloga)

```
"yahoo_symbols"   - koji Yahoo Finance simbol koristimo za koje gorivo
                    RB=F = benzin (RBOB), HO=F = dizel (Heating Oil), BZ=F = nafta (Brent)
                    Mijenjati samo ako Yahoo ugasi ili promijeni simbol.

"cif_med_factors" - pretvaraju Yahoo cijenu u CIF Med USD/tonne
                    Ovo su kalibrirani omjeri. Trenutne vrijednosti:
                    - es95/es100: 402.4 (USD/galon RBOB -> USD/tonne CIF Med)
                    - eurodizel:  327.0 (USD/galon Heating Oil -> USD/tonne CIF Med)
                    - unp_10kg:    16.0 (USD/barrel Brent -> USD/tonne LPG CIF Med)
```

**Kada dirati faktore?** Samo ako izracunate cijene *sustavno* odskacu od
stvarnih cijena na postajama. Npr. ako aplikacija stalno pokazuje 1.50 EUR
za benzin, a na postajama je 1.62 EUR, faktor treba povecati.

Kako kalibrirati: ako je izracunata cijena preniska, povecaj faktor.
Ako je previsoka, smanji. Promjena od ~5% u faktoru daje promjenu od ~0.05-0.10 EUR u cijeni.

### Primjer: nova uredba s visim trosarinama

Recimo da nova uredba NN 50/2026 povecava trosarinu za benzin na 0.50 EUR/L:

1. Otvori `config/fuel_params.json` na GitHubu (ikona olovke za uredivanje)
2. Promijeni:
   - `"version"` na `"2026-05-15"` (datum nove uredbe)
   - `"nn_reference"` na `"NN 50/2026"`
   - `"effective_date"` na datum stupanja na snagu
   - `"excise_duties" > "es95"` na `0.50`
   - `"excise_duties" > "es100"` na `0.50` (ako se i to mijenja)
3. Klikni "Commit changes" na dnu stranice
4. Aplikacija ce pokupiti promjene pri sljedecem syncu (unutar 24 sata)

### Pregled svih polja

| Polje | Sto je | Koliko cesto se mijenja | Tko mijenja |
|-------|--------|-------------------------|-------------|
| `premiums` | Premija iz uredbe o cijenama | Rijetko (1-2x godisnje) | Ti, rucno |
| `excise_duties` | Trosarina iz uredbe o trosarinama | Rijetko | Ti, rucno |
| `density` | Gustoca goriva (kg/L) | Nikad | Nitko |
| `vat_rate` | PDV stopa | Gotovo nikad | Ti, rucno |
| `reference_date` | Pocetni datum ciklusa | Kad se promijeni ritam | Ti, rucno |
| `yahoo_symbols` | Yahoo Finance simboli | Nikad | Nitko |
| `cif_med_factors` | Konverzijski omjeri | Samo ako cijene odskacu | Ti, rucno |

---

## station_prices.json - Cijene po postajama

**Automatski se azurira** - ne treba dirati!

Scraper svaki dan u 09:00 CET dohvaca cijene s:
- **cijenegoriva.info** (primarni izvor, 9 tvrtki)
- **hak.hr** (backup izvor, 6 tvrtki)

Ako scraper prestane raditi (npr. web stranica promijeni strukturu),
treba popraviti `scripts/scrape_station_prices.py`.

---

## GitHub Actions - automatski zadaci

Na ovom repozitoriju postoje dva automatska zadatka (GitHub Actions).
Oba se mogu pokrenuti i rucno: Actions tab > odaberi workflow > "Run workflow".

### Scrape Station Prices

- **Kada se pokrece:** Svaki dan u 09:00 CET (automatski)
- **Sto radi:** Scrapa cijene goriva sa svih postaja u Hrvatskoj
- **Rezultat:** Azurira `config/station_prices.json` ako ima novih cijena
- **Kad pokrenuti rucno:** Nakon sto uocis da su cijene zastarjele,
  ili nakon popravka scraper skripte

### Check for New Fuel Regulations

- **Kada se pokrece:** Svaki ponedjeljak u 10:00 CET (automatski)
- **Sto radi:** Pretrazuje Narodne novine za nove uredbe o gorivu
- **Rezultat:** Kreira GitHub issue ako pronade novu uredbu
- **Kad pokrenuti rucno:** Kad cujes da je izasla nova uredba pa zelis
  provjeriti odmah, bez cekanja do ponedjeljka
