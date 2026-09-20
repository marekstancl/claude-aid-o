# P096 — audit zadrátování po přestavbě konce plánu

20. 9. 2026, před mergem. Otázka: je všechno, co P096 přidal, opravdu zapojené,
a nezůstal po odstraněných mechanismech kód, soubor nebo text, který už nic nečte?

## Jak se měřilo

1. **Funkce bez volajícího** — pro každou funkci definovanou v `aid-plan-fsm.sh`,
   `aid-release-policy.sh`, `aid-review-round.sh`, `aid-fsm.sh`,
   `aid-plan-close-check.sh`, `aid-pm-brief.sh`, `aid-epic-summary.sh` a v knihovnách
   `aid-step-review-packet`, `aid-stage-log`, `aid-review-config`, `aid-codex-transport`,
   `aid-lifecycle`, `aid-plan-close-summary`, `aid-epic-summary-page`: počet zmínek
   mimo vlastní definici napříč `scripts/`, `commands/`, `skills/`, `agents/`, `defaults/`.
2. **Soubory bez čtenáře** — každý soubor v `defaults/schemas`, `defaults/policies`,
   `defaults/templates`, `defaults/prompts` a `scripts/lib`: kdo ho jmenuje mimo testy
   a registr.
3. **Odkazy na smazané** — `grep` jmen všech smazaných souborů, funkcí, klíčů a
   událostí přes celý plugin, `README.md`, `CLAUDE.md` a `docs/extending-aid.md`.
4. **Registr** — `test-enforcement-registry-cites.sh` (každý citovaný soubor existuje),
   `test-review-successors.sh` (každý vyřazený řádek má nástupce nebo zapsaný důvod),
   `test-control-boundary.sh`.

## Co audit našel a co se s tím stalo

| Nález | Kde | Výsledek |
|---|---|---|
| Uzavření plánu pořád vyžadovalo zprávu reportéra (`<plan>-delivery.md`), i když reportér mizí. Plán na to zapomněl. | `aid-plan-close-check.sh` kontroly 1 a 2, `aid-fsm.sh plan-close`, `aid-plan-fsm.sh` | kontroly 1 a 2, přepínač `--skip-delivery-report`, `--auto-annotate` a vykreslování kopií zprávy odstraněny; zůstaly kontroly 3 až 6 |
| Účetní srovnání plánu po merge četlo hlavu revize ze zprávy auditora, která už nevzniká — každý nový plán by vyšel „neověřitelný". | `lib/aid-lifecycle.sh` | čte záznam nové revize (`cp7/rounds.json`, u EPICu `cp3/rounds.json`); stará zpráva zůstává jen pro EPICy uzavřené před 2.101.0 |
| Stránka pro PM o hotovém EPICu a textové shrnutí EPICu se stavěly ze zpráv auditora a kurátora. | `lib/aid-epic-summary-page.sh`, `aid-epic-summary.sh` | čtou výsledek revize EPICu |
| Knihovna přepínačů reportéra a zjednodušovače neměla po úklidu žádného volajícího. | `lib/aid-review-signals.sh` | smazána i se sadou |
| Sonda nezávislosti auditu měla jediného volajícího, smazaný most ke Codexu. | `lib/aid-audit-independence.sh` | smazána |
| Příkaz `pm-override` sloužil jen smyčce auditora. | `aid-fsm.sh` | smazán i se sadou |
| Kontrola výstupu ověřovatele neměla od P094 produkčního volajícího, jen testy. | `fsm_check_verifier_output` | smazána i s testy a šablonou |
| Telemetrie „rozhodnutí předběhnuto" existovala jen kvůli srovnávacímu běhu. | `release_policy_preempted` | tři vysílače a dva testy smazány |
| Volitelná kontrola v CI hlídala soubory, které psal jen reportér. | `defaults/ci/plan-boundary-required-check.yml`, `/aid-init`, `/aid-audit` | smazána |
| Šest schémat vyřazených artefaktů nečetl žádný kód ani test (validátor schémata nenačítá). | `defaults/schemas/` | smazána; typy artefaktů ve validátoru zůstávají, aby šla ověřit stará evidence |
| Tři obezličky kolem vedlejších účinků staré knihovny (přepis `SCRIPT_DIR`, `set -e`). | `aid-hook-verify.sh`, `aid-recovery-adjudicate.sh` | nový `aid-codex-transport.sh` žádné vedlejší účinky nemá, obezličky smazány |
| Funkce bez volajícího, mrtvá už na main. | `_pfsm_verify_plan_final_close_receipt` | smazána (doklad ověřuje `aid-plan-close-check.sh`) |
| Dva zastaralé testy padající už na main. | `test-scoped-preflights` (chyběl `--run-id`), `test-control-boundary` (smazaná politika brány dodávky) | opraveny |
| Odmítnutí před výběrem kroku (`špinavý strom` apod.) nekončilo řádkem `next:`. | `cmd_plan_finalize` | šest odmítnutí jde přes `_pfsm_refusal_next` |

## Co zůstalo vědomě

- **Typy artefaktů vyřazených producentů** (`audit_report`, `audit_input_manifest`, `curator`,
  `delivery_report`, `delivery_gate`, `c3_dispatch`) a jejich kontroly v
  `aid-protocol-validate.sh`, včetně `fingerprint_audit_report`: evidence starších plánů se
  musí dát ověřit i po upgradu.
- **`agents/auditor.md` a `agents/simplifier.md`**: audit zdraví projektu (`/aid-audit`) a agent,
  kterého si PM může zavolat po plánu. Žádná smlouva pro konec plánu.
- **Staré názvy kroků** (`sync`, `inputs`, `review`, `c4`, `summary`, `accept-ancillary`) končí
  kódem 2 a jmenují nástupce — po jedno vydání.
- **`aid-promote-checks.sh`**: plán ho jmenoval k smazání omylem; je to povyšování kontrol
  shody, s koncem plánu nesouvisí.
- **Devět šablon v `defaults/templates/` bez čtenáře** (`run-*.md`, `epic-example.md`, …): nejsou
  z oblasti P096, neřešeno.

## Otevřené (backlog)

IMP-618 až IMP-623 v `.aid-o/work/backlog.md`.

## Nezávislé čtení

_Doplní se po doběhnutí nezávislého ověření._
