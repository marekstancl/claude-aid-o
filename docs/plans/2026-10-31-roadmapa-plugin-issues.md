# Roadmapa oprav z plugin issues (od 31. 10. 2026)

Živý seznam: co PM z rozborů hlášení vybral, v jakém vydání to jde a jaký to má stav. Každé vydání, které
položku dodá, ji tu ve stejném commitu označí `HOTOVO vX.Y.Z`. Do zdrojového hlášení projektu se dopíše
`> **HOTOVO vX.Y.Z (datum):** …` až při vydání. Rozbor dělá skill `rozbor-plugin-issues`.

Volby PM 31. 10. 2026: „beru tvoje doporučení“ = 1A, 2A, 3A, 4A, 5A, 6A, 7A, 8A, 9A, 10A, 11A, 12B;
nové věci z companionu přihodit; **studio (`/aid-ui`) teď neřešit**.

## 3.12.1 - oprava 3.12.0 (hned)

| # | Co | Zdroj | Stav |
|---|---|---|---|
| 1 | Odložené nálezy (`follow_up`) se ve velkém repu neoznačí: `aid-follow-up.sh` předává seznam souborů repa jako argument (`jq: Argument list too long`). Předat přes soubor, test na repu s tisíci souborů. | WAN P116 28. 10., P118 30. 10. | HOTOVO v3.12.1 |
| 2 | Chybí `defaults/templates/stand-in-decision.md`, kterou čte `aid-stand-in.sh ask`. Doplnit šablonu a test, že každá šablona, kterou skripty čtou, existuje. | WAN P115 25. 10., P116 28. 10. (3×) | HOTOVO v3.12.1 |

## 3.13.0 - běh plánu

| # | Co | Zdroj | Stav |
|---|---|---|---|
| 3 | `aid-step-land.sh` bere bod začínající jménem testu v backticku za příkaz. Za příkaz brát jen spustitelné; jinak náhradní příkaz s důvodem. | WAN P116 28. 10., P118 30. 10. | čeká |
| 4 | `test_named_after_plan` až u bran uzávěru. Pustit už v kontrole kroku (`aid-step-check.sh`). | WAN P115 25. 10., P114 27. 10. | čeká |
| 5 | Strom plánu a kroků bez prostředí: kopírovat neverzované soubory, které projekt vyjmenuje (`.env`), napojit `node_modules`; nápověda, jak měřit ve stromu (ne `docker compose exec` do hlavního checkoutu). | WAN P114 26. 10., P116 28. 10. | čeká |
| 6 | Konec tahu (`turn_step_open`) uznává čekání jen na `aid-job.sh`. Uznat i živé zapsané agenty a revizory na pozadí. | WAN P115 25. 10. (3.10.0), P114 26. 10. (3.12.0) | čeká |
| 7 | `--also-steps`: ve `fix-check` ruší „any“; `finalize` ho nezná. Opravit obojí se stejným záznamem. | WAN P116 28. 10., P118 30. 10. | čeká |
| 8 | `plan-merge-to-main` se při obnově zacyklí (bring-forward na strom sloučení místo tipu, verze z `release-prep.json`). Poznat zapsaný lifecycle commit, pokračovat od tipu, verzi brát z kandidáta. | WAN P116 28. 10. | čeká |
| 9 | Souběžné plány: zmrazení odmítne verzi, která není nad nejvyšším tagem cíle. Hlídání jediné hlavy migrací = brána WANu (projekt, ne plugin) - předat oknu WANu. | WAN P116 + W12 28. 10. | čeká |
| 11 | Spor o nález, jehož řádky změnil pozdější commit: `delegate` (`delegation_fix_pending`) ho uzavře jako „předáno potvrzovacímu kolu“, ne zablokuje. | WAN P115 25. 10. | čeká |
| 12.1 | `close --fixer` odmítne roli s číslicí (`e2e`). | WAN P116 28. 10. | čeká |
| 12.2 | Testovací soubor jmenovaný v AC kroku: `amend-scope` bez zástupce (`amend_scope_no_brief_point`). | WAN P116 28. 10. | čeká |
| 12.3 | Opravář CP7 ve stromu plánu nenajde `merged.json` (cesta do state root). | WAN P118 30. 10. | čeká |
| 12.4 | Zástupce za `final_generalist` vyplní `security_and_operations`, `collect` ho odmítne: sjednotit zadání role a validátor. | WAN P115 25. 10. | čeká |

## 3.14.0 - roadmapa a companion

| # | Co | Zdroj | Stav |
|---|---|---|---|
| 10 | **Přání PM:** povinná stránka průběhu roadmapy na share. `/aid-plan` ji při založení roadmapy vytvoří, uzávěr plánu a `/aid-do` nad položkou roadmapy ji obnoví, uzávěr neprojde, když se neobnovila. Vzor WAN `cc/wan/provize-stav`. | WAN 30. 10. (pokyn PM 03:32) | čeká |
| C1 | **Přání PM:** companion nesmí předat rozbitý náhled. (a) `shots`/`show` kontrolují v každém snímku vodorovné přetečení a ořez (okno `role=dialog`, `scrollWidth > clientWidth`, obsah za hranou panelu) a stránku odmítnou s výpisem snímku a prvku; (b) skill: agent se podívá na každý snímek a v `navrh.json` potvrdí, že je bez ořezu, vadu dnešní komponenty opraví ve variantě nebo ukáže jako bod „vada dnešní aplikace“; (c) orchestrátor před odkazem PM prohlédne snímky s okny, ne jen `check-1440x900.png`. | WAN P119 31. 10. (pokyn PM 05:32) | čeká |
| C2 | Kopie aplikace bez stylů oken: `.gitignore` projektu (`.aid-o/work/**/ui/`) skryje `proto/src/components/ui/` před Tailwindem. `proto` založí kopii tak, aby ji ignor nezasáhl (nebo doplní `!` výjimky). | WAN P119 31. 10. | čeká |
| C3 | `show` odmítá soubory `ui.copy_extra`, které tam dal `proto`; `proto` je nedoplní do existující kopie. `show` je zná, `proto` je doplní a zapíše do manifestu. | WAN P117 29. 10., P119 31. 10. (potvrzeno) | čeká |
| C4 | Celostránkový snímek (`capture: full` / `scroll: main`): pevné a lepivé lišty se otisknou doprostřed, předek s `overflow:hidden` ořízne výšku. Při celé stránce přepnout `fixed/sticky` na `static` a uvolnit předky. | WAN P117 29. 10., P119 31. 10. (potvrzeno) | čeká |
| C5 | `up` bez běhu brainstormu odmítne: v chybě a ve skillu říct `aid-brainstorm-state.sh init … --no-worktree`. | WAN P113, P900, P119 (potvrzeno) | čeká |
| C6 | `--configLoader runner` neposkytuje `__dirname`: ve skillu to říct, zkoušet až po výchozím načítání. | WAN P113, P117 29. 10. (potvrzeno) | čeká |
| C7 | `shots`: jeden snímek při síťové chybě (`ERR_NETWORK_CHANGED`) zopakovat, ne zahodit celou sadu; `shots --only <jméno>`. | WAN P113 22. a 23. 10. (potvrzeno) | čeká |
| C8 | `proto --refresh` (stará kopie stranou, nová ze současného main, upozornění na zastaralou kopii); `down` pozná vlastní dev server podle skupiny procesů, ne jména. | WAN P113 22. 10. | čeká |

## Čeká na druhý případ (12B, PM 31. 10.)

Nezařazeno do žádného vydání. Přesune se, až se objeví druhý nezávislý případ.

- 12.5 `amend-contract --rename` se nepromítne do kopie plánu ve stromu (WAN P115 25. 10.).
- 12.6 Souběžné slučování ztratí záznam o commitu kroku (`aid_dispatch_contract_commit` → `aid_parallel_merge`, WAN P115 25. 10.).
- 12.7 Slučování větve kroku jde pustit před `increment-step` předchozího kroku (WAN P116 28. 10.).
- 12.8 Chyba, která byla v projektu už předem, jde v kontraktu vykázat jen jako „přeskočeno“ (WAN P116 28. 10.).
- 12.9 Agent z přerušeného sezení dál zapisuje do stromu kroku (WAN P115 25. 10.).

## Mimo plugin (projekty)

- WAN: `inputs:` u bran (návrh `.aid-o/work/evidence/uzaver-konverguje/navrh-inputs-wan-trading.md`), převezme okno WANu.
- WAN: brána jediné hlavy migrací alembic (k položce 9), převezme okno WANu.

## Odloženo PM: studio `/aid-ui`

PM 31. 10. 2026: „Studio věci nechci řešit.“ Zůstává jen evidované, nic se nestaví. Je to deset hlášení
z Trading `aid-plugin-issues.md` č. 2-11 (25.-26. 10.) a čtyři požadavky PM z 26. 10.: viditelnost v samostatném
režimu, rychlost, kvalita a audit skillů. Rozbor a čísla jsou v sezení z 26. 10. a v paměti `project_3120_uzaver`
(a následující).
