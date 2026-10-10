---
id: P014
type: regular
lifecycle_strict: true
zadani: .aid-o/plans/P014-zadani.md
zadani_verze: 1
zadani_sha256: SHA_OF_THE_BRIEF
---

# Plan: P014 (test fixture, P109 Step 2)

<!-- The P014 plan as it was: point 2 of the brief is gone from the criteria,
     and the edge case of step 1 says the opposite of it. -->

## Implementation Steps

### Step 1: Delivery behind a named interface

**Objective:** Freelo is the one implementation of the delivery interface.

**Edge Cases:**
- An unknown value of `doruceni` in apps.yaml falls back to Freelo with a warning.

**AID Role:** backend

**Zavírá:** AC1, AC2

### Step 2: E-mail at the person, name in the task

**Objective:** The ticket stores the e-mail; the task description carries it.

**AID Role:** backend

**Zavírá:** AC3, AC4

### Step 3: Measurement, ports page, the whole path, test counts

**Objective:** The measurement, the documentation page and the end-to-end test.

**AID Role:** backend

**Zavírá:** AC5, AC6, AC7, AC8, AC9

## Acceptance Criteria

- [ ] AC1: Mimo implementaci rozhraní a vyjmenované výjimky se klient Freela v kódu nevolá; měří to test, který prochází zdroje.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "pytest tests/test_hranice_freelo.py"
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
