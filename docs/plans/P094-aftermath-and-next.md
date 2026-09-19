# Po P094: co je hotové, jak to sledovat, co dál

Zapsáno 2026-09-19 po vydání v2.99.0. Tenhle soubor je paměť pro další
session, která bude pokračovat v opravách AID. Čte se první, před backlogem.

## 1. Co je od v2.99.0 v provozu

Jeden motor kol pro tři kontroly:

| Kontrola | Kdy | Kdo rozhoduje | Evidence |
|---|---|---|---|
| CP1 kontrola plánu (P093) | před generováním EPICů | šest revizorů, 2 kola | `evidence/<plan>/cp1/round-K/` |
| CP2 kontrola kroku (P094) | po každém kroku EPICu | deterministický `aid-step-check.sh` řekne skip / no_change / review / review+security, pak revizoři | `evidence/<epic>/<run>/cp2/step-N/` |
| CP3 kontrola EPICu (P094) | před branami EPICu | totéž nad celým diffem EPICu, uzavření píše `semantic-review-final.json` | `evidence/<epic>/<run>/cp3/` |
| CP6 fast mode (P094) | `/aid-do` | jen advisory, nic neblokuje | `evidence/do/<ts>-<sha>/cp6/` |

Skripty: `aid-review-round.sh` (`--plan` nebo `--checkpoint cp2|cp3|cp6`;
prepare → dispatch → collect → close), `aid-review-adjudicate.sh` (rozhodčí bez
modelu: nález stojí na jedné platné citaci, `absent:path` dokládá chybějící
soubor), `lib/aid-review-summary.sh` (cena v USD z `defaults/prices.yaml`).
FSM: jediná podmínka přechodu je `fsm_check_review_round`. Když Codex není
dostupný, kontrola kroku/EPICu běží nezávislým CC agentem a zapíše proč.

Výchozí revizor kroku je Sonnet (rozhodnutí PM 19. 9. po akceptační sadě:
Sonnet 0,66 USD/krok, 5 z 8 chyb; Opus 1,93 USD/krok, 8 z 8; Sonnet zůstal
a rozhodčí byl zmírněn, protože odmítal reálné nálezy kvůli jedné špatné citaci).

## 2. Jak vyhodnocovat cenu, kvalitu, rychlost

- **Cena:** `/aid-status` dlaždice „Revize plánu" a „Revize kroků"
  (recepty `review_line` / `epic_review_line` v `commands/aid-status.md`);
  ručně `source lib/aid-review-summary.sh; aid_epic_review_summary <run dir>`.
  Sazby v `defaults/prices.yaml`; Sonnet blended je ODHAD, po prvním ostrém
  EPICu ho nahradit naměřenou hodnotou z `close` výstupů.
- **Kvalita:** akceptační sada `scripts/tests/test-step-review-acceptance.sh
  --mode new` nad `fixtures/step-review/acceptance.json` (20 zasabotovaných
  diffů, 8 skutečných chyb); záznam posledního běhu
  `docs/plans/P094-acceptance-run.md`. Měřit cenu NA SKUTEČNOU CHYBU, ne na krok.
- **Rychlost:** čas kola je v `rounds.json` každého kola; součet ve
  `/aid-status` zatím není (nečíslovaný bod backlogu).
- **Že to drží tvar:** `test-review-successors.sh` (tabulka nástupců
  odstraněných kontrol v `reference/review-successors.md`),
  testbed `/opt/eco/projects/aid-testbed/bin/verify.sh`.

## 3. Poučení z P093 + P094 (pro další přestavby kontrol)

1. Rozhodčí má být přísný na FORMU nálezu (čtecí příkaz, soubor:řádek),
   ne na aritmetiku citací; jedna špatná citace mezi několika není důvod nález
   zahodit. Tohle stálo tři reálné nálezy v akceptační sadě.
2. Regex z YAML nepouštět přes `yq @tsv` a bash `=~` (POSIX, `\s` neexistuje);
   `join("\t")` + `grep -E`. Pravidla pro tajemství nikdy nezabrala, než to
   chytila sabotážní fixture.
3. Sabotážní fixture (známé chyby) PŘED prvním ostrým během, ne po něm.
4. Revizor čte celé repo (~90k tokenů na roli) – hlavní páka na cenu je
   balík, ne model.
5. Opravy plánu „na místě" vyrábějí nové vady (Agents pilot: 7 z 16 nálezů
   dalšího kola); nově napsaná tvrzení ověřit deterministicky.
6. Revizor bez pravidla o závažnosti „nedojde" nikdy; revizor má založit
   výstupní soubor hned a připisovat; read-only zadání nic nevynucuje.
7. Testovací sady padají na zestárlé fixtury, ne na kód – před hledáním chyby
   v kódu zkontrolovat datum fixture vůči poslední přestavbě.

## 4. Co se dělá dál: P095 úklid po přestavbě

Jeden plán přes AID (`/aid-plan`), ať si nová kontrola kroků odbyde první
ostrý EPIC. Rozsah (rozhodnutí PM 19. 9. 2026):

**Z backlogu P094:** IMP-612 (producent `acceptance-evidence.json`; dnes
prázdný a hlásí průchod – spolu s hlášením WAN 2. 9.), IMP-607 + IMP-608
(zestárlé základny a fixtury padající na main), IMP-610 (chybějící yq má
padnout nahlas), IMP-611 (šablona CP4 popisuje pre-filter).
IMP-609 opraven 19. 9. přímo v testbedu.

**Z hlášení projektů (acta, agents, wan):**
1. Záloha za Codex všude – `aid-brainstorm-opponent.sh` a kontrola plánu
   dostanou stejný fallback na CC agenta jako CP2/CP3; binárka Codexu podle
   verze, ne první v PATH (požadavek PM 19. 9.).
2. C3 bridge `aid-c3-dispatch.sh verify`: při neshodě raw verdiktu a reportu
   nesmí skončit 0 ani nechat zavádějící `audit-report.json` (acta 16).
3. `aid-evidence-verify.sh --at-head` v režimu plan_branch: balík hledat
   v kořeni stavu, hlavu brát z manifestu, při nenalezení nic nezapisovat,
   `git_clean` jen sledované změny (acta 19 + wan 2. 9.).
4. Pre-push hook: push složený jen z `(delete)` má guard přeskočit
   (příznak „viděl jsem ref" zůstane false) (acta 2. 9.).
5. `aid-fsm.sh alloc plan-id`: po alokaci ověřit kolizi se souborem
   v `plans/` a `tasks/` (wan 19. 9.).
6. `aid-fsm.sh set-field`: zápis do timeline + `--reason` u polí, která
   ovlivňují přechody (acta 3. 9.).
7. `/aid-run --auto`: buď skutečně zapsat `auto-mode-state.yaml`, nebo
   opravit dokumentaci, která to tvrdí (acta 15).
8. plan-finalize: `overall_verdict: skipped` číst ve fázi `gates` a `inputs`
   stejně; `--force` na tu podmínku dosáhne, nebo hláška řekne, že ne
   (acta 14 + 3. 9.); řešit spolu s IMP-612.

**Z pěti čerstvých diffů 19. 9. (`docs/plans/P094-fresh-diffs.md`), priorita
NEJVYŠŠÍ, protože bez toho kontrola kroku propouští reálné chyby:**
9. Rozhodčí přijme rozsah řádků `path:N-M` v důkazu (schéma + text rolí).
10. Rozhodčí přijme inline reprodukci `bash -c '…'`, když je jen ke čtení,
    nebo zadání revizora řekne tučně, že inline reprodukce se zahazuje.
    Sonnet ji píše inline ve 3 ze 4 kol.
11. `aid-review-adjudicate.sh:168` — `local` mimo funkci, hláška při každém
    `collect`.
12. Po opravě znovu pustit pět diffů ze scratch větve: čekáme 1 pass,
    3 fail, 1 skip (dnes 3 pass, 1 fail, 1 skip).

**Pozorování z běhu CP1 plánu P095 (19. 9., dvě kola, 21,03 USD, 42 + 21
nálezů, 0 zahozeno):** 13. Codex nad limitem účtu zapíše `dispatch`
jako `no_file` (ne `rate_limited`), takže roli `collect` počítá jako
`missing` a kolo je neplatné; zástupce CC byl nutný ručně — přesně
krok 3 P095. 14. Brána CP1 chce v kritériu citovat prvních osm slov
nálezu i s cestou k neexistujícímu souboru, `aid-plan-check.sh` A5/B1
takové kritérium blokuje; obě kontroly se vylučují, když nález jmenuje
soubor, který nemá vzniknout (vyřešeno založením sady, ale pravidlo
citace potřebuje výjimku pro cesty, nebo A5 výjimku pro citované nálezy).
Do P095 nezařazeno (plán je po finalize); patří do backlogu jako IMP.

**Nízká priorita, mimo P095:** acta 18 (kdo vyrábí `<plan>-delivery.md`,
Head proti merge commitu), acta plan_branch vs. kroky vyžadující main
(odstavec v plan-writing.md + advisory), wan pre-push `chore(release):`
vzor, wan brainstorm bez plánu bez záznamu (volba PM, ne oprava).

**Bezpředmětné přestavbou (zapsat do souborů projektů jako ZAMÍTNUTO):**
agents 1, 3, 6, 7; acta 17, 20; agents 2b (independence detect); agents 5
kromě odkazu na `skills/role-cards.md` (ověřit).

Po P095: spustit `bin/aid-plugin-issues-collect.sh`, dopsat pod každý bod
v projektech HOTOVO/ZAMÍTNUTO s verzí.

## 5. Nečíslované body backlogu

- součet času revizí ve `/aid-status` (po prvním ostrém EPICu),
- naměřená blended sazba Sonnetu do `prices.yaml`,
- Codex jako `epic_security` naostro (limit vyprší 21. 9. 2026 8:29).
