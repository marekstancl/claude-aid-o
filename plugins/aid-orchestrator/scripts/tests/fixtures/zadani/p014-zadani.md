---
zadani: P014
verze: 1
datum: 2026-10-07
autor: PM + AI
---

# P014 - hlášení z e-mailu, oznámení a měření

<!-- Test fixture (P109 Step 2): the P014 brief of the comparative experiment
     (docs/reference/2026-10-08-experiment-p014-zkousky/zadani-zuzene.md) with its
     nine done-when points written as AC<n> criteria. The permanent record of the
     defect the brief pass refuses: the P014 plan dropped point 2. -->

## 1. Co PM chce

> „potřebuju aby asistent byl pořád vyvýjen tak aby byl použitelnej i jinde“

**Co je v sázce:** druhý zákazník, který nepoužívá Freelo, by musel rozplétat závislost, kterou nikdo neměřil.

## 2. Změřený výchozí stav

- Freelo volá jen brána (`bin/freelo_rest.py`, `bin/telegram-gateway.py`).

## 3. Co udělat

**(1) Doručení hlášení za pojmenovaným rozhraním.** Freelo je jeho jediná implementace, vybírá se podle konfigurace.

## 4. Kde co je

| Co | Kde |
|---|---|
| klient Freela | `bin/freelo_rest.py` |

## 5. Pravidla práce

- Měř, nehádej.

## 6. Hotovo, když

- [ ] AC1: Mimo implementaci rozhraní a vyjmenované výjimky se klient Freela v kódu nevolá; měří to test, který prochází zdroje.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_hranice_freelo.py"
    expected_exit: 0
  ```
- [ ] AC2: Zakládání úkolu, čtečka i testovací scénář jdou přes rozhraní; neznámá hodnota v konfiguraci skončí chybou při startu, ne tichým přechodem na Freelo.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_doruceni_konfigurace.py"
    expected_exit: 0
  ```
- [ ] AC3: Po přihlášení existuje dvojice e-mail → člověk a e-mail je i u relace.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_vstupenka_email.py"
    expected_exit: 0
  ```
- [ ] AC4: Popis nového úkolu nese jméno, e-mail i roli; e-mail poslaný v těle požadavku se ignoruje.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_popis_ukolu.py"
    expected_exit: 0
  ```
- [ ] AC5: Měření vypíše celkem, se štítkem a neposouzeno s pojmenovaným jmenovatelem; při nečitelných štítcích u víc než poloviny skončí nenulovým kódem.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_mereni.py"
    expected_exit: 0
  ```
- [ ] AC6: Stránka „čtyři porty asistenta“ je v Docusaurusu a odkazuje na ni index i runbook pro vložení do projektu.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "test -f /opt/eco/docs/docs/agents/asistent/porty.md"
    expected_exit: 0
  ```
- [ ] AC7: Celá cesta projde testem proti atrapě rozhraní, bez nasazení a bez skutečného Freela.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_cesta_hlaseni.py"
    expected_exit: 0
  ```
- [ ] AC8: Testy mají domovskou sadu a patro podle ceny; počty v `CLAUDE.md` (tabulka i souhrnná sedmička) a v Docusaurusu sedí se skutečným sběrem.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bin/pocty-testu --check"
    expected_exit: 0
  ```
- [ ] AC9: Nic se nenasazovalo ani nemergovalo - výsledek zůstává v pracovní kopii.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "git diff --quiet main -- deploy-manifest.txt"
    expected_exit: 0
  ```
