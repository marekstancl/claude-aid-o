# P097 — co sledovat na prvních třech živých bězích 2.103.0

Vytvořeno v kroku 10 (release), 2026-09-23. Vydání samo dělá tento krok jen
uvnitř stromu (tag, GitHub release, `claude plugin update`, testbed dělá
controller po mergi na `main` s PM souhlasem) — čísla níže se doplní AŽ po
prvním ostrém běhu brány na 2.103.0 v ACTA, WAN a tomto repozitáři.

## Co zapsat u každého ze tří běhů

Pro každý projekt (ACTA, WAN, aid-orchestrator) jeden blok:

- **Datum a commit**, na kterém běžela brána.
- **Řádky podle důvodu** (`gates_report.json.gates.<id>.reason`) — kolik
  `exit_0`, kolik `exit_<n>`, kolik `not_in_profile`, `missing_script`,
  `vacuous_pass`, `reused_from`; hlavně kolik `legacy_row` (řádek bez
  `result`, čtený verzí 1 schématu beze změny stavu).
- **Timeouty**: kolik `job_timeout` a u kterých gate; jestli je
  `timeout_seconds` u té brány výchozích 60 s nebo dřívější baseline hodnota.
- **Upgrade konfigurace**: proběhl `aid-init-execution-yaml.sh upgrade`
  před tímto během, nebo běh nejdřív odmítl starý klíč (`required_when`,
  `needs_services`, `services:`, `gate_profile_defaults`) a upgrade se
  spustil až pak? Co upgrade skutečně změnil (diff, ne tvrzení).

## Otázka pro PM po třech bězích

Má `aid-gate-runtime-baseline.sh propose` číslo (2× p95 posledních 20 běhů)
nahradit ručně nastavené `timeout_seconds` v `execution.yaml` projekt po
projektu, nebo zůstat jen návrhem, který si někdo ručně přenese? Rozhodnutí
čeká na data z výše — bez nich je to dohad.

## Dva otevřené nálezy z vlastní merge cesty plánu

Zjištěné při stavbě P097 samotného, ne u konzumujících projektů:

- **T0+T1 běží 44 minut proti rozpočtu 12 minut.** Rozpočet ze standardu
  testovacích pater (`/ecosystem/specs/test-standard`) merge cestu tohoto
  rozsahu nepočítal; buď rozpočet neplatí pro EPIC této velikosti, nebo
  některá sada patří do vyššího patra. Neověřeno proč, jen naměřeno.
- **Nálezy z revizních kol v `.aid-o/work/aid-plugin-issues.md` datované
  2026-09-23** — vznikly během review kol tohoto plánu, ještě nesebrané
  přes `aid-plugin-issues-collect.sh` do `plugin-issues-inbox.md`. Sběr a
  rozhodnutí (viz `CONTRIBUTING.md` § Problémy pluginu hlášené projekty)
  je samostatný krok, ne součást tohoto vydání.
