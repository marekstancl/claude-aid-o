# AID Control System v2 - Unified Refactor Plan

**Status:** schválený master design; E0 přijato, formální roadmapa vytvořena; další krok je executable plán pouze pro E1
**Datum:** 2026-06-22
**Autor:** PM + AI
**Nezávislá revalidace:** 2026-06-22 proti Doc-1, Doc-2, P048 a aktuálnímu Reporter/FSM flow; zapracovány opravy handoff proof, type-specific schemas, profile drift, Auditor isolation, P048 kalibrace a PM communication contract
**Rozsah:** celý kontrolní systém AID - plánovací řetězec, přenos kontraktu (brainstorm → Writer → Visual Companion → implementátor), CP1-CP6, Delivery Gate, Auditor, Curator, integrační review, release decision, PM komunikace, plus začlenění P048 jako frontendové větve
**Vstupy:**
1. `docs/AID-CP1-CP6-review-instruction-audit-and-refactor.md` (dále **Doc-1**)
2. `docs/AID-CP1-CP6-review-instruction-audit-second-opinion.md` (dále **Doc-2**)
3. `.aid-o/plans/P048-ui-design-to-code-fidelity-mvp.md` (dále **P048**)

---

## 0. Shrnutí (lidská řeč)

**Jednou větou:** AID dnes umí prohlásit EPIC za hotový, aniž by prokázal, že výsledek jde sestavit, je vnitřně kompatibilní a skutečně dělá to, co bylo schváleno - a tenhle plán to opravuje jako jeden provázaný kontrolní systém v2, ne jako hromadu izolovaných záplat.

**Co se dnes láme.** Současný systém je dobrý v lokální kontrole (každý krok splní své AC, kód je čistý, nejsou hrubé bezpečnostní díry). Selhává na třech místech najednou:

1. **Plánování není ověřitelné.** CP1 ověří, že pojmenované soubory existují, ale neověří, že graf kroků je acyklický, že producent vyrobí kontrakt dřív než ho spotřebitel čte, že znovupoužitá komponenta nemá vedlejší efekty, ani že plánovaná funkce má opravdu tu signaturu.
2. **Kontrakt se cestou ztrácí.** Rozhodnutí z brainstormu, z Visual Companion a z Writeru se k implementátorovi dostanou jen jako volný text. Nikdo neověří, že je implementátor opravdu spotřeboval. P048 ukázal stejný problém u UI: vizuální kontrakt vůbec nedoputuje do `plan.json`.
3. **Kontrola hotového výsledku je děravá.** Delivery Gate (build/typecheck/test/závislosti, runtime reachability) neexistuje jako deterministická blokující vrstva. CP3 věří lokálním AC. Auditor a Curator běží paralelně a skóre umí přebít blocker. CP5 čte jediný boolean. Release decision je roztříštěná mezi `aid-fsm.sh`, `aid-release.sh` a pre-commit hook.

**Co navrhuji.** Jeden cílový systém s těmito principy:

- **Deterministické kontroly oddělené od LLM úsudku.** Build/typecheck/test/závislosti/reachability/vizuální fidelita běží jako skript a zapisují exit kódy. LLM nesmí převést `fail` na `pass` prózou ani skóre.
- **Každá kontrola vlastní jednu třídu selhání** (žádný jeden obří prompt všem agentům).
- **Široký katalog lenses, minimum kontrolních mechanismů.** Build, wire, security, UI fidelity nebo oracle jsou specializované checks jednoho enginu, ne důvod vytvořit další checkpoint/autoritu. CP názvy se zachovají jen jako dočasné kompatibilní aliasy.
- **Adaptivní review profil** odvozený z dotčených povrchů určuje, které lenses a probes se spustí.
- **Jedna release autorita** (deterministická Release Policy; dočasný alias CP5 → `release-decision.json`), do které všechno ostatní teče jako evidence - včetně P048.
- **Versionovaný protokol v2** pro všechny artefakty, připravený k přímému zobrazení v budoucím GUI, ale GUI není podmínkou fungování.
- **Dvojí povinný PM výstup:** úplný strukturovaný decision brief odvozený z evidence a za ním krátké lidské shrnutí. Ani Reporter, ani Orchestrator nesmí blocker, neověřenou oblast nebo odchylku zamlčet volnou prózou.
- **Bezpečné etapy** - observe/dual-run, kalibrace na známých selháních (E-047-1, E-047-4, E-047-5, E-044, P045), řízený cutover, teprve pak odstranění redundantních kontrol.

**Co tenhle dokument NENÍ.** Není to big-bang přepis, sada nezávislých projektů ani rozhodnutí zachovat dnešní CP topologii. Je to jedna architektura rozdělená do rámcových implementačních etap E0-E11. Tyto etapy nejsou formální AID EPICy; skutečný AID plán vznikne až po schválení master návrhu a E0 topologie.

---

## 1. Grounded audit současného toku

Tato sekce popisuje skutečný stav kódu k 2026-06-22 (AID v2.37.x), ne dokumentaci. Vychází z přímého čtení `plugins/aid-orchestrator/` (skripty, skills, agents, defaults) a reálných evidence artefaktů v `.aid-o/work/evidence/`.

### 1.1 FSM a deterministická vrstva

- **FSM** (`scripts/aid-fsm.sh`, ~2787 řádků): stavy `READY EXECUTE GATES ESCALATION DONE ERROR`. Přechody whitelist (`VALID_TRANSITIONS`). DONE má pod-fáze `review → release` přes `done-advance`.
- **Preconditiony dnes vynucené:**
  - `READY→EXECUTE`: `plan.json` existuje, `total_steps>=1`.
  - `EXECUTE→GATES`: `current_step>=total_steps` + CP3 výstupy (`verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`) existují s validní `classification`.
  - `GATES→DONE`: `gates_report.json` s `overall: pass`.
  - `increment-step`: vyžaduje `step-{N}-verify.md` (jinak `missing_step_verify`), verifier output ne-`pending`, kontrola sha256 `plan.json` (tamper-detection).
  - `done-advance review→release`: existuje `curator-report`, `audit-report`, `pm_decision=merge`, žádné blokující compliance selhání (`fsm_build_failures` + `check-severity.yaml`).
  - `--force` vyžaduje `--reason` (>=20 znaků), loguje `fsm_force_override` do audit logu.
- **Generátory:** `aid-plan-to-epic.sh` (plan.md → EPIC.md, dělí na fáze, strip cross-phase deps), `aid-epic-to-json.sh` (EPIC.md → `plan.json`, Kahn topo-sort cyklů, `VALID_ROLES`, per-step AC pre-flight), `aid-json-to-run.sh` (plan.json → run.md + FSM init), `aid-auto-pipeline.sh` (master), `aid-queue-add.sh` (queue).
- **Gates:** `aid-run-gates.sh` čte gates z `execution.yaml`, per-gate `command/required/max_retries/timeout/pass_criteria`, exit 0=pass / 2=skip / jinak fail; `overall=fail` když libovolná `required` gate selže. Zapisuje `gates_report.json` s `_generated_by`/`_generated_at`/`_command_log`. Konkrétní gates: `tests_pass`, `security_scan_pass` (bandit), `docs_updated`, `scope_check`, `plan_diff`, volitelně `lint_pass`/`type_check`/`build_pass`/`standards_compliance`.
- **Release:** `aid-release.sh` - auto-detekce major/minor/patch z conventional commits, odmítne pokud FSM stav != DONE (nebo `--force`), bumpne verzi v registru souborů, commit + tag, **nepushuje**.
- **Enforcement registry:** kanonický registr je `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (~314 řádků, taxonomie 15 typů enforcementů). Soubor `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` (~278 řádků) je **superseded seed** (header: "do NOT edit it as canonical… future changes go to `defaults/enforcement-registry.yaml`") - CLAUDE.md ho zatím cituje, což je pre-existující nekonzistence v repu, kterou v2 narovná tím, že všechny nové preconditiony registruje do `defaults/`.

### 1.2 Review checkpointy CP1-CP6 (skutečný stav)

| CP | Kde se spouští | Scope | Verdikt | Blokuje? | Reálná díra |
|---|---|---|---|---|---|
| **CP1** | `/aid-plan` Step 9 | obsah plan souboru | `docs-review` + 3 lenses (L1/L2/L3) + adjudikátor `pass/revise/fail` | ne (PM rozhodne), high-risk lenses ano přes evidence files | neověřuje plan-graph, identifier domény, reuse side-efekty, signaturu volání, verzi závislosti, idempotency matrix |
| **CP2** | per step v EXECUTE | step diff `HEAD~1..HEAD` | verifier `pass/fail/skip/pending` | ano | nečelí cross-step kontraktům; happy-path test stačí i u multi-system write |
| **CP3** | EXECUTE→GATES | celý EPIC diff `base..HEAD` | `code-review` + `security` paralelně | ano | nespouští root build/typecheck/test, nečte další fázi, nedělá production reachability ani wire-contract |
| **CP4** | po C+A auto-fix | applied diff | `code-review` | ano | OK ve scope, ale nerekontroluje dotčené delivery checky |
| **CP5** | `done-advance` | čte `blocking_findings:` z audit reportu | jediný boolean | ano (blokuje MERGE) | neagreguje delivery/gate/acceptance evidence; skóre umí přebít |
| **CP6** | `/aid-do` | celý diff | `code-review` | **ne** (vždy advisory) | produkční změna přes `/aid-do` obejde blokující kontroly |

- **High-risk gate:** `behavior_trace_count>0` při `behavior_trace_required:true` (FSM `fsm_check_verifier_output`). Detektor je `aid-prefilter.sh` (exit 0 SKIP / 10 RUN / 20 FAIL), pravidla v `defaults/pre-filter-rules.yaml` (2 skip + 12 fail rules, bash ERE).
- **Dispatch mód:** default `agent_tool` (FSM obejde provenance check, vrací `agent_tool` non-blocking); `subagent` mód (opt-in) vyžaduje `aid-emit-dispatch.sh` start/complete páry.

### 1.3 DONE review, Auditor, Curator, plan-boundary specialisté

- **Sekvence DONE (`skills/pipeline.md` §7):** archiv run → `final_report.md` → **Curator + Auditor PARALELNĚ** → Curator auto-fix (S/M/L) → Auditor auto-fix (auto_fixable) → CP4 → CP5 (boolean check) → PM summary MERGE/FIX/ABORT. Plan-boundary (po posledním EPICu): Simplifier → Reporter → `plan-close`.
- **Auditor** (`agents/auditor.md`): 10 kategorií (5 mandatory + 5 conditional), váhové skóre, `blocking_findings: true|false` jako **první top-level klíč** (FSM čte line-start). **Klíčový dnešní limit:** `blocking_findings:true` se nastaví **jen pro `critical`** (`auditor.md:582,838` - "If ANY finding has severity `critical`"). High findings jsou tedy už konstrukcí ne-blocking, ne jen "skóre přebije blocker". Empiricky: našel prázdný `EpicSpec` v E-047-1, ale klasifikoval ne-blocking. Není outcome-oriented, neběží z čistého kontextu, nereplayuje trace.
- **Curator** (`agents/curator.md`): sběr improvement notes, dedup proti backlogu, návrhy, lessons. Vrací `recommended_disposition: approve|reject|defer`. Běží **paralelně s Auditorem**, takže nemůže spolehlivě konzumovat audit findings. Má de-facto merge-influence přes auto-approve.
- **Simplifier / Reporter** (`agents/simplifier.md`, `reporter.md`): plan-boundary. Reporter má `test_outcome: pass|partial|no-runtime`, povinné `_test_evidence[]`, ale v `agent_tool` módu žádný out-of-band důkaz že test běžel.
- **Compliance** (`compliance.json`): 6 dimenzí (`branch_correct`, `execution_yaml_present`, `gates_generated_by`, `memory_substantive`, `verifier_outputs`, `dod_present`), `overall=pass` když vše ∈ {true, null}. Severity přes `check-severity.yaml` (blocking/advisory), soft-fail když `yq` chybí (vše advisory).

### 1.4 Plánovací řetězec, Writer, Visual Companion, handoff

- **Brainstorming** (`skills/brainstorming.md`): 9 kroků, section-by-section verifikace (critic + ground-truth), interim doc, mockup detekce, **nabídka Visual Companion** pro UI témata. Step 8 deleguje na `plan-writing` skill (Writer).
- **Writer** (`skills/plan-writing.md`): píše plan dokument, quality gates, handoff s 6 možnostmi.
- **Visual Companion** (`skills/visual-companion/SKILL.md`): browser-based, interaktivní mockupy, per-question visual/text decision, P027. **Dnes re-kresluje baseline z kódu** (P048 audit: `SKILL.md:88` "render as it currently looks") - neměří proti reálnému renderu.
- **Handoff do implementátora** (`skills/pipeline.md` §4): "VERBATIM plan content", visual context priorita source > visual-spec.yaml > PNG. **`visual-spec.yaml` ale žádný skript negeneruje** (P048 audit). `agents/implementer.md` je generický, obsahuje slovo "frontend" 0×; frontend chování je v `role-cards.md` (Visual Anchoring).
- **Zásadní mezera:** neexistuje žádný strojově ověřitelný "kontrakt", který by nesl rozhodnutí od brainstormu k implementátorovi a u kterého by se ověřilo, že ho implementátor **spotřeboval**. Vše je instrukce, ne enforcement.

### 1.5 Evidence artefakty (skutečné schéma dnes)

Kořen `.aid-o/work/evidence/{epic_id}/{run_id}/`: `fsm-state.yaml`, `timeline.jsonl`, `plan.json`, `gates_report.json`, `compliance.json`, `final_report.md`, `curator-report.md`, `audit-report.md`, `verifier-output-step-{N}.md`, `verifier-output-cp3-{code-review,security}.md`, `verifier-output-cp4-curator-validation.md`, `steps/step-{N}-verify.md`. CP1 deep: `{plan_id}/cp1-deep/cp1-lens-L{1,2,3}-*.md` + `cp1-adjudicator.md`. Reporter: `.aid-o/reports/{plan_id}-delivery.md`.

**Pozorování pro GUI:** artefakty jsou nehomogenní (mix MD + JSON), jen část nese `base_commit`/`head_commit`, finding IDs nejsou stabilní napříč typy, severity vocabularies se liší (PASS/FAIL/PASS_WITH_NOTES vs Critical/High/Medium/Low vs approve/reject/defer). To je hlavní překážka pro budoucí GUI a zároveň hlavní cíl protokolu v2.

### 1.6 Shrnutí kořenové příčiny

Systém je optimalizovaný na **artifact compliance** a **lokální AC verifikaci**. Chybí mu:
1. závazný, ověřitelný plánovací kontrakt;
2. strojově prokázané předání a spotřeba kontraktu;
3. deterministická blokující delivery vrstva;
4. adaptivní hloubka kontroly podle povrchu;
5. nezávislé outcome ověření z čistého kontextu;
6. jedna autoritativní release decision.
7. spolehlivé předání výsledku PM v technické i jednoduché lidské podobě.

Doc-1, Doc-2 a P048 každý opravují jednu výseč. Tento plán je spojuje.

---

## 2. Konflikty a překryvy mezi třemi vstupními dokumenty

### 2.1 Vztah Doc-1 ↔ Doc-2

**Doc-1** uzavírá třídu *mechanicky nedoručitelný repozitář a rozbité producer-consumer kontrakty* (Delivery Gate DG-01..DG-18, adaptivní profily, IR-1/2/3 kadence, CP5 release policy, fresh-context Auditor).

**Doc-2** tvrdí, že Doc-1 zavírá jen tuhle třídu a NEzavírá *repozitář se sestaví a testy projdou, ale chování porušuje schválený plán napříč runtime hranicemi*. Přidává: acceptance-evidence kontrakt, sémantické behavior traces, fault injection, a CP1 amendmenty (plan-graph, identifier domény, reuse-compat, planned-call feasibility, dependency-API grounding, idempotency state matrix).

**Stav vztahu:** **explicitně komplementární, ne konfliktní.** Doc-1 §3.6 už deklaruje Doc-2 sekce 4-8, 9 a 11.2-11.7 jako **normative companion requirements** a stanoví rozhraní autority:

> "this revalidated main document controls sequencing, adaptive profiles and release enforcement; the companion controls semantic trace depth."

**Skutečné překryvy (nutno sjednotit, ne duplikovat):**

| Téma | Doc-1 | Doc-2 | Sjednocení ve v2 |
|---|---|---|---|
| Producer-consumer kontrakt | DG-05 + CP1 producer-consumer table | §6 wire-shape, §11.4 planned-call | jeden `contract_traces` model; Doc-1 deterministická compile, Doc-2 sémantický trace |
| Wire conformance | DG-14 (real provider→consumer) | §6 (top-level vs nested) | jedna lens `realtime_async`/`api_cross_layer`, DG-14 = deterministická část, behavior trace = sémantická |
| Fallback/recovery | DG-16 | §6 fault injection | DG-16 deterministická probe + behavior trace `fallback_recovery` lens |
| Acceptance evidence | DG-18 (strukturální integrita) | §4 (obsah a význam) | `acceptance-evidence.json`: DG-18 ověří strukturu, CP3/Auditor ověří pravdivost |
| Fresh-context Auditor | §7.1 (replay 1 trace) | §8 (clean context, korelace) | jedno pravidlo: Auditor z čistého kontextu replayuje >=1 detector-selected trace |
| CP1 hloubka | §6.1 (producer-consumer, authority, profil) | §11.2-11.7 (graph, identifier, reuse, call, dep-API, idempotency) | jeden CP1 kontrakt s oběma sadami povinných polí |

**Závěr:** žádný rozpor v záměru. Jediné riziko je **duplicitní implementace** (dvě místa řešící wire-contract). v2 to řeší tím, že každý povrch má jednu lens s deterministickou částí (Delivery Gate) a sémantickou částí (CP3/Auditor trace), sdílející jedno schéma.

### 2.2 Vztah (Doc-1 + Doc-2) ↔ P048

**P048** je konkrétní frontendová implementace jiné osy než Doc-1/Doc-2:

- Doc-1/Doc-2 frontend = **funkční** ("je feature namountovaná, dosažitelná, wire-kompatibilní, poskytuje hodnotu nad reálnými daty") - lenses `frontend_shell_routing`, `realtime_async`, DG-13, DG-15.
- P048 frontend = **vizuální fidelita** ("vypadá výsledek jako schválený návrh, byl delta opravdu aplikována, nezměnilo se zamčené") - `ui-change-contract.yaml`, Playwright capture/compare, pixel + computed-style.

Tyto osy jsou **ortogonální a doplňkové**. Žádná nenahrazuje druhou: P048 prokáže že tlačítko vypadá správně, Doc-1 prokáže že tlačítko je namountované a volá správný endpoint.

**Reálný konflikt č. 1 - druhá release autorita.** P048 je dnes navržen tak, že jeho mechanický verdikt je **FSM hard-fail** v Step 8 (gate kolem frontend dispatche, locus v `aid-fsm.sh` increment-step kontrole): reason kódy `ui_contract_verdict_fail`, `ui_capture_unavailable`, `ui_contract_missing`, `ui_gestalt_unapproved`. To je přesně to, před čím PM varuje: *"P048 verdict může být doménová evidence, ale nesmí vytvořit druhou paralelní release autoritu přímo ve FSM."*
**Řešení v2:** P048 mechanický guard se stává **deterministickým checkem `frontend_visual_fidelity`** uvnitř C1 Delivery Engine (produkuje `verdict.json` jako delivery evidence). Step-local hard-fail zůstává EXECUTE-level kontrolou jednoho kroku, ale **release autorita je výhradně C4/`release-decision.json`**, kam P048 verdict teče jako jeden vstup mezi ostatními.

**Reálný konflikt č. 2 - `/aid-do`.** P048 explicitně defer-uje `/aid-do` UI změny. Doc-1 chce `/aid-do` risk-based blokující pro produkční změny. v2 to sjednocuje bez samostatného CP6 enginu: `/aid-do` `existing_ui` delta je **produkční změna → fast profil C1/C2/C4 blokuje nebo přesměruje na `/aid-run`**.

**Reálný konflikt č. 3 - jednotka kontroly.** P048 zavádí vlastní FSM reason kódy a vlastní evidence root `evidence/{epic_id}/{run_id}/ui/`. v2 to ponechává jako doménový sub-strom, ale `verdict.json` musí nést protokol v2 obálku (sekce 7), aby ho GUI i C4 četly stejně jako ostatní artefakty.

### 2.3 Souhrn rozhodnutí o autoritě

1. **Doc-1 je řídící** pro sekvenci, adaptivní profily a release enforcement.
2. **Doc-2 je řídící** pro sémantickou hloubku traces a acceptance-evidence obsah.
3. **P048 je doménová evidence** (frontend větev), nikoli nezávislá release autorita.
4. **Jediná release autorita = deterministická Release Policy (`release-decision.json`); CP5 je pouze dočasný kompatibilní název vstupního bodu.**

---

## 3. Cílová architektura (AID Control System v2)

### 3.0 Minimální kontrolní topologie

v2 se nenavrhuje podle otázky „jak vylepšit CP1-CP6“, ale podle otázky „jaké odlišné failure classes musí systém zachytit a kde je jejich nejčasnější levný enforcement point“. Cílově existuje pouze pět kontrolních mechanismů:

| Mechanismus | Jedinečná odpovědnost | Typ | Typické výstupy |
|---|---|---|---|
| **C0 Plan Contract Gate** | Je záměr proveditelný, jednoznačný, úplný a ověřitelný před implementací? | deterministické strukturální checks + sémantický plan review | `plan-review.json`, `plan-graph.json`, `contract-manifest.json` |
| **C1 Delivery Engine** | Lze konkrétní revizi sestavit, spustit a mechanicky prokázat podle detekovaných surfaces? | deterministický engine s plugin/lens katalogem | `delivery-gate.json`, check logy, P048 verdict jako sub-evidence |
| **C2 Semantic Review Engine** | Odpovídá skutečné chování schválenému outcome a kontraktům napříč hranicemi? | jeden reviewer engine v režimu `local|wiring|behavior|final` | `semantic-review.json` s mode/checkpoint metadata |
| **C3 Independent Audit** | Dokáže nezávislý čerstvý reviewer vyvrátit PASS claim u rizikové dodávky? | oddělený adversariální agent s input manifestem a provenance | `audit-report.json` |
| **C4 Release Policy** | Jsou všechny profilem vyžadované aktuální důkazy přítomné a bez blockerů? | deterministický agregátor, jediná release eligibility autorita | `release-decision.json` |

Podpůrné funkce nejsou další kontroly:

- Brainstorm, Writer a Visual Companion vytvářejí kontrakt pro C0.
- Implementátor je worker, nikoli verifier.
- Projektové gates jsou pluginy C1, ne paralelní release systém.
- Curator spravuje návrhy/backlog/lessons; nemá correctness ani release autoritu.
- Reporter a PM brief komunikují fakta z evidence; nemají correctness ani release autoritu.
- Simplifier je volitelná plan-boundary údržba.

#### Mapování dnešních CP názvů

| Dnešní označení | v2 význam | Samostatný mechanismus? |
|---|---|---|
| CP1 | vstupní režim C0 | ano pouze jako Plan Contract Gate |
| CP2 | `C2 mode=local`, spuštěný jen když jej vyžaduje profil/kontrakt | ne |
| IR-1 / IR-2 / CP3 | `C2 mode=wiring|behavior|final` nad jedním schématem a jedním reviewer enginem | ne |
| CP4 | invalidace a re-run dotčených C1/C2 checks po opravě | ne |
| CP5 | kompatibilní název pro C4 Release Policy | ne jako LLM review |
| CP6 | fast profil stejných C1/C2/C4 mechanismů pro `/aid-do` | ne |
| P048 | `frontend_visual_fidelity` plugin C1 + `frontend_user_outcome` lens C2 | ne |

#### Kontrolní rozpočet podle rizika

| Profil | Povinné mechanismy | Typická sémantická kadence |
|---|---|---|
| docs/trivial | relevantní C0 struktura + nejmenší C1 + C4 | C2/C3 se skip reason, pokud detektor nenajde behaviorální dopad |
| low, lokální | C0 + C1 + C2 final + C4 | 1 sémantický review |
| medium / jedna hranice | C0 + C1 + C2 wiring/final + C4 | 2 delta/final reviews; C3 jen při explicitním risk triggeru |
| high / mixed / security / data-loss / release-process | C0 + průběžný C1 + C2 wiring/behavior/final + C3 + C4 | nejvýše 3 sémantické reviews + 1 nezávislý audit |

Počet rozhodovacích kol C2 je omezen profilem, ale nesmí zakrýt skutečný provozní náklad. Každé dílčí LLM volání uvnitř lens fan-outu se eviduje samostatně (model, tokeny, wall time); required lens se nesmí tiše vypustit. Výsledný `semantic-review.json` vzniká deterministickým bezztrátovým unionem stabilních finding ID a agregátor nesmí snížit závažnost ani zahodit konflikt. Číselný resource budget se zkalibruje v E10 nad reálnými fixturemi.

#### Control Necessity Test

Každý navržený check, agent dispatch nebo checkpoint musí před implementací doložit:

1. unikátní failure class nebo unikátní nezávislý vstup;
2. proč jej nelze levněji zachytit v dřívějším mechanismu;
3. přesný trigger, stop condition a výstupní schema;
4. alespoň jeden negativní fixture, který bez něj unikne;
5. alespoň jeden pozitivní control, který nesmí blokovat;
6. očekávaný náklad a způsob měření unique detections;
7. zda je skutečně nezávislý, nebo pouze opakuje stejné vstupy/premisy.

Kontrola, která tento test nesplní, se nepřidá. Pokud dvě kontroly hledají stejnou failure class nad stejnými vstupy, sloučí se před implementací; nečeká se automaticky až na E11.

### 3.1 Princip vrstvení

Funkční vrstvy L0-L12 níže popisují pořadí zpracování a artefaktů, **nikoli 13 samostatných kontrol**. Kontrolní logika se implementuje pouze v C0-C4 podle §3.0. L12 (PM komunikace) je deterministická projekce evidence, ne rozhodovací vrstva.

```
PLÁNOVACÍ ŘETĚZEC
  L0  Brainstorm + Writer + Visual Companion  → contract bundle (versioned)
  L1  C0 Plan Contract Gate (CP1 alias)         → plan-review.json, plan-graph, profile
        (producer-consumer, plan-graph, identifier domains, reuse-compat,
         planned-call feasibility, dep-API grounding, idempotency matrix,
         authority/runtime matrix, delivery-evidence plan, integration points,
         UI contract pro existing_ui)

PŘENOS KONTRAKTU
  L2  Contract handoff + consumption proof      → contract-manifest.json
        (hashovaný kontrakt putuje plan.json → dispatch; implementátor mapuje položky
         na změny/důkazy a C2 mapování nezávisle ověří; restatement sám není důkaz)

IMPLEMENTACE + LOKÁLNÍ KONTROLA
  L3  Implementátor (role-based)                → step output + step-verify
  L4  C2 mode=local (CP2 alias, jen dle profilu) → semantic-review-local-{step}.json

DETERMINISTICKÁ DELIVERY VRSTVA (bez LLM)
  L5  C1 Delivery Engine D0/D1                   → delivery-gate.json
        DG-01..DG-18 + frontend_visual_fidelity (P048) + acceptance struct

SÉMANTICKÁ INTEGRAČNÍ VRSTVA
  L6  C2 Semantic Engine wiring/behavior/final   → semantic-review-*.json
        adaptivní lenses incl. frontend_user_outcome, wire, fallback, oracle,
        acceptance-evidence rekonstrukce

PROJEKTOVÉ GATES
  L7  project-specific C1 plugins                → gates_report.json (rozšířený)

NEZÁVISLÉ OUTCOME OVĚŘENÍ
  L8  C3 Independent Audit (risk-triggered)      → audit-report.json
  L9  Curator utility (po Auditorovi, proposal)  → curator-report.json
  L10 affected C1/C2 re-run (CP4 alias)          → updated evidence + invalidation map

JEDNA RELEASE AUTORITA
  L11 C4 Release Policy (CP5 alias)               → release-decision.json
        FSM nabídne MERGE jen když release_ready:true a HEAD odpovídá

KOMUNIKACE S PM
  L12 Deterministický PM brief + Reporter prose  → pm-decision-brief.json + pm-summary.md
        (úplná fakta z evidence + krátké lidské vysvětlení; bez nové autority)
```

### 3.2 Tok pro plný `/aid-run`

```
PLAN
  1. Brainstorm/Writer/Visual Companion → contract bundle (L0)
  2. C0 Plan Contract Gate (CP1 compatibility alias) (L1)
  3. Vyřešit všechny přijaté blokery
  4. EPIC generace až po CP1 pass (FSM precondition)

EXECUTE (per step)
  5. Implementace kroku (L3) + důkaz spotřeby kontraktu (L2)
  6. Step-local deterministické checky deklarované v kroku
  7. C2 local review (CP2 alias) pouze když ho vyžaduje kontrakt/profil (L4)
  8. C2 wiring review na první runnable vertical slice (medium/high profil)

INTEGRATION CANDIDATE (po posledním kroku)
  9. C1 Delivery Engine D0 (L5) - full candidate, incl. frontend_visual_fidelity
 10. C2 behavior review (high profil)
 11. C2 final semantic review (CP3 alias) (L6) konzumuje full diff + D0 + acceptance-evidence
 12. C2 security lens jen když attack-surface pravidla vyžadují
 13. Fix loop: fix → invalidovat a re-run dotčené C1/C2 evidence

GATES
 14. Projektové gates (L7) + coverage/relevance
 15. Bind do delivery evidence setu

DONE / REVIEW
 16. Generace final report z reálné evidence
 17. C3 Independent Audit jen při risk triggeru (L8), fresh context, replay >=1 trace
 18. Curator PO Auditorovi, nebo přímo po final review když C3 není required (L9)
 19. Aplikace schválených auto-fixů
 20. Invalidovat a znovu spustit dotčené C1/C2 checks (CP4 compatibility alias) (L10)
 21. C1 D1 - re-run dotčených checků proti final HEAD
 22. C4 Release Policy (CP5 alias) (L11) → release-decision.json
 23. Vygenerovat `pm-decision-brief.json` a validovat úplnost proti release evidence
 24. PM dostane strukturovaný brief, krátké lidské shrnutí a MERGE jen když release_ready:true a HEAD matchuje
```

### 3.3 Tok pro `/aid-do` (fast mode)

```
IMPLEMENT
  1. Aplikuj task + classify risk a dotčené delivery surfaces
  2. existing_ui delta → odmítnout nebo přesměrovat na /aid-run (P048)
  3. C1 F0 (nejmenší validní profil)
  4. C2 fast review jen když jej profil vyžaduje (CP6 compatibility alias)
  5. Re-run dotčených checků po fixu
  6. Produkční/high-risk změna → blokující release decision
  7. Docs-only/triviální → advisory s explicitními skip důvody
```

### 3.4 Klíčové architektonické invarianty

1. **Deterministické ≠ LLM.** C1/C4 a strukturální část C0 jsou skripty s exit kódy. Sémantická část C0, C2 a C3 jsou LLM úsudek. LLM nikdy nepřevede deterministický `fail` na `pass`.
2. **Detektor vlastní applicability.** Reviewer smí lens přidat, ne odebrat (jen PM waiver).
   Profil se vyhodnocuje nejméně dvakrát: plan-time z deklarovaných surfaces a dependency graphu, potom candidate-time ze skutečného diffu/runtime registrací. Autoritativní profil je union obou. Nově objevený povrch doplní lenses/probes a zneplatní příliš časné PASS artefakty.
3. **Evidence vázaná na revizi.** Každý artefakt nese `base_commit`/`head_commit`/`generated_at`. Stale artefakt nesplní blokující precondition.
4. **Blockers nejsou skóre.** Critical/High blokuje nezávisle na skóre.
5. **Jedna release autorita.** Pouze C4/L11 vypočítává release eligibility. Vše ostatní je vstup.
6. **CP číslo není mechanismus.** CP2/IR/CP3 jsou režimy C2; CP4 je invalidace/re-run; CP5 je alias C4; CP6 je fast profil. Žádný z nich nesmí získat vlastní duplicitní engine nebo schema.
7. **GUI-ready, ale GUI není podmínka.** Artefakty nesou protokol v2 obálku; kontroly fungují bez GUI.
8. **Komunikace nepozmění fakta.** PM brief je deterministická projekce evidence. Lidské shrnutí může fakta vysvětlit, ale nesmí změnit status, vynechat blocker nebo z `unverifiable` udělat „hotovo“.

---

## 4. Role / Authority matrix

| Role | Vlastní třída selhání | Autorita | Smí blokovat? | Smí schválit merge? | Vstupy | Výstupy |
|---|---|---|---|---|---|---|
| **Brainstorm/Writer** (L0) | nekompletní/nejednoznačný záměr | proposal | ne | ne | PM dialog, mockupy | plan draft, contract bundle |
| **Visual Companion** (L0) | re-kreslený vs reálný baseline | proposal | ne | ne | běžící app, PM gestalt | `ui-change-contract.yaml` (před-vyplněný baseline) |
| **C0 Plan Contract Gate** (CP1 alias, L1) | vnitřně nekonzistentní/neproveditelný plán | gate (stop-rule) | **ano** (blokuje EPIC generaci) | ne | plan, codebase, dep graph | `plan-review.json`, `plan-graph`, `review-profile.json` |
| **Implementátor** (L3) | nesprávná implementace kroku | worker | ne | ne | kontrakt (verbatim), role card | step output, consumption proof |
| **C1 Delivery Engine** (L5/L7) | repo nejde install/build/check/test/render nebo selže required doménová probe | **deterministická gate s pluginy** | **ano** (hard) | ne | diff, profil, runtime, project policy | `delivery-gate.json` + plugin evidence |
| **C2 Semantic Review Engine** (CP2/IR/CP3 aliasy, L4/L6) | lokální nebo cross-boundary chování odporuje schválenému kontraktu/outcome | profilovaný reviewer v režimu local/wiring/behavior/final | **ano** (Critical/High stop) | ne | profil, diff range, C1, acceptance | `semantic-review-{mode}.json` |
| **C3 Independent Audit** (Auditor alias, L8) | rizikový PASS claim neobstojí v nezávislém replay | provider-neutral nezávislý audit, veto | **ano** (Critical/High = blocking) | ne | C1, C2, diff, profil, acceptance | `audit-report.json` + provider/model/process provenance + `independence_level` |
| **Curator** (L9) | improvements, dedup, lessons | **proposal-only** | **ne** | **ne** | audit findings (po Auditorovi) | `curator-report.json` (PROPOSALS_READY/NO_PROPOSALS/INPUT_INCOMPLETE) |
| **Simplifier** (plan boundary) | zbytečná složitost | proposal | ne | ne | plan diff | `simplifier-report.json` |
| **Reporter** (plan boundary) | nezávislé runtime ověření a lidský popis dodávky | observační | ne | ne | evidence + controlled runtime runner | `delivery-report.json/.md` + `test_outcome`; není zdrojem release faktů |
| **Affected re-run** (CP4 alias, L10) | oprava zneplatnila nebo regresovala předchozí důkaz | orchestrace C1/C2, ne nový reviewer | **ano** (revert/fix on fail) | ne | applied-fix diff, dependency map | invalidation map + nové C1/C2 evidence |
| **C4 Release Policy** (CP5 alias, L11) | nedostatečná evidence / přetrvávající blocker | **autorita release eligibility** | **ano** | ne; pouze vypočte `release_ready` | všechny required evidence | `release-decision.json` |
| **PM brief generator** (L12) | neúplné nebo nesrozumitelné předání výsledku | deterministická projekce, bez rozhodovací autority | ne | ne | všechny required evidence + release decision | `pm-decision-brief.json` + podklad pro `pm-summary.md` |
| **Gate-fixer** | - | utilita | ne | ne | finding ID, allowed paths | fix + invalidate list |
| **PM** | - | finální lidská autorita | ano | **ano** (jen když je nabídka dovolená release policy, nebo přes explicitní waiver) | release decision + PM brief | rozhodnutí + waivery |

**Zásadní změny oproti dnešku:**
- Curator přestává mít jakoukoli merge-influence (dnes auto-approve), běží **po** Auditorovi.
- CP2, IR-1, IR-2 a CP3 přestávají být navrhovány jako oddělené review systémy; jsou to profilované režimy C2 se společným schématem, findings a invalidací.
- CP4 přestává být samostatný reviewer; znamená pouze re-run dotčených C1/C2 důkazů.
- CP5 přestává být boolean reader i LLM checkpoint; C4 se stává jedinou deterministickou agregační release autoritou.
- CP6 přestává být samostatná větev; je to fast profil C1/C2/C4.
- Auditor přestává blokovat jen na `critical` (dnešní stav, `auditor.md:582`); `blocking_findings` je odvozeno mechanicky z **Critical OR High** (dle R1) a skóre ho nesmí přebít.
- Delivery Gate je nová deterministická blokující vrstva.
- P048 verdict přestává být nezávislá FSM release autorita, stává se delivery evidence.

---

## 5. Artefakty a jejich producenti/spotřebitelé

Všechny nesou protokol v2 obálku (sekce 7). Kanonická cesta `.aid-o/work/evidence/{epic_id}/{run_id}/`.

| Artefakt | Producent | Hlavní spotřebitelé | Blokující pro |
|---|---|---|---|
| `contract-bundle/` (mockupy, ui-change-contract, design tokens) | L0 | implementátor, Delivery Gate | - |
| `contract-manifest.json` (hashy zdrojových kontraktů, dispatch receipt, item→change/evidence map) | L2 + C2 validation | C2, C3 | increment-step (verified consumption) |
| `plan-review.json` + `plan-graph.json` + `review-profile.json` | C0/L1 | EPIC generace, C1-C4 | EPIC generace |
| `semantic-review-{mode}.json` (`local|wiring|behavior|final`) | C2/L4/L6 | FSM, C3, C4 | profilem vyžadovaný assembly point / release |
| `delivery-gate.json` (+ `delivery-gate/{check}.log`) | C1/L5/L7 | C2, C3, C4 | profilem vyžadovaný assembly point / release |
| `ui/verdict.json` (frontend_visual_fidelity) | C1 sub-check (P048) | delivery-gate.json, C4 | step (EXECUTE), C4 (via C1) |
| `acceptance-evidence.json` | C2 final (rekonstrukce) | C3, C4 | C4 |
| `gates_report.json` (+ coverage/relevance) | C1 project plugin adapter | C4 | C4 |
| `audit-report.json` (+ `.md` human) | C3/L8 | Curator, C4 | C4 pokud profilem required |
| `audit-input-manifest.json` | Orchestrator před odděleným dispatch C3 | C3, C4 | audit independence |
| `curator-report.json` | Curator/L9 | PM brief/backlog | - (non-blocking) |
| `invalidation-map.json` + nové C1/C2 artefakty | affected re-run/L10 | C4 | C4 po fixech |
| `release-decision.json` | C4/L11 | FSM (MERGE), GUI | MERGE |
| `pm-decision-brief.json` + `pm-summary.md` | deterministický brief generator + Reporter/Orchestrator | PM, GUI | každé PM rozhodnutí/předání |
| `delivery-report.json/.md` + reporter runtime artifacts | controlled runner + Reporter | PM brief, plan close, GUI | plan-boundary handoff |
| `waiver-{check}.json` | PM | C1, C4 | - (zviditelní jako `unverifiable_with_waiver`) |

**Konzistenční pravidla:**
- `delivery_ready` (C1 D0/D1) a `release_ready` (C4) jsou jediná dvě agregovaná rozhodnutí.
- Žádný LLM artefakt nesmí nastavit `delivery_ready:true` ani `release_ready:true` přímo.
- Artefakt s `head_commit` != current HEAD je `stale` a neprojde jako blokující precondition.
- Plánovací a handoff artefakt je stale také při změně `plan_sha256`, `contract_bundle_sha256` nebo jednotlivého `contract_item_hash`, i když se změna ještě nepromítla do commitu.
- `pm-decision-brief.json` musí obsahovat všechny open/blocking/unverifiable/deviation položky ze vstupů; validátor odmítne brief, který některou z nich vynechá.

---

## 6. Přesné změny skills, instrukcí a skriptů

Konsolidovaná file-by-file mapa (sjednocuje Doc-1 §11.5, Doc-2 §7, P048 kroky a nové požadavky na contract handoff). Sloupec **Etapa** odkazuje na rámcovou implementační etapu v sekci 10, nikoli na již existující AID EPIC.

### 6.1 Plánovací řetězec a contract handoff

| Soubor | Změna | Etapa |
|---|---|---|
| `.aid-o/plans/P048-ui-design-to-code-fidelity-mvp.md` | před EPIC generací append-only amendment: E7A→E7-CAL→E7B, P048 verdict jako DG evidence, user-outcome pro všechny UI módy; konfliktní původní Step 8 explicitně superseded | E7 precondition |
| `skills/brainstorming.md` | emit strukturovaný `contract-bundle` (rozhodnutí, mockupy, ui-change-contract draft); behavioral contract table pro high-risk operace (Doc-2 §7 CP1) | E4 |
| `skills/plan-writing.md` (Writer) | povinné delivery-evidence plan, producer-consumer table, plan-graph zápis, per-step `ui_change_mode`/`ui_change_contract`, positive assertion pro UI-Modify kroky (P048 Step 7) | E4, E7 |
| `skills/visual-companion/SKILL.md` | nahradit "render as it currently looks" reálným capture (Playwright); draft→capture→approve ordering; `gestalt_approval` blok (P048 Step 5) | E7 |
| `commands/aid-plan.md` | C0/CP1 producer-consumer, plan-graph, identifier-domain, reuse-compat, planned-call, dep-API, idempotency, authority/runtime matrix, adaptivní profil, integration points (Doc-1 §6.1 + Doc-2 §11.2-11.7) | E4 |
| `skills/agent-protocol.md` | registrovat hashovaný contract-manifest, dispatch receipt a item→evidence map; inject `ui_change_contract` do frontend dispatch (P048 Step 6) | E2, E7 |
| `skills/role-cards.md` | frontend `## UI Change Contract` protokol (typed delta, no-redesign); consumption proof requirement | E7 |
| `agents/implementer.md` | povinné item→change/evidence mapování proti hashovanému manifestu; implementátorův restatement je orientační a nikdy sám neprokazuje splnění | E4 |

### 6.2 Deterministická Delivery vrstva

| Soubor | Změna | Etapa |
|---|---|---|
| `scripts/aid-delivery-gate.sh` (nový) | profil resolution, DG-01..DG-18, argv-array exec, HEAD-bound JSON + logy | E2 (DG-01..12), E6 (DG-13..18) |
| `scripts/lib/aid-delivery-profile.sh` (nový) | safe profil discovery + command selection | E2 |
| `defaults/policies/delivery-gate.yaml` (nový) | command profily, applicability, unverifiable policy | E2 |
| `defaults/templates/delivery-gate-template.json` (nový) | kanonický artefakt | E1 |
| `lib/ui-fidelity/*.mjs` (P048) | `ui-capture.mjs`, `ui-compare.mjs`, fixtures - jako sub-check `frontend_visual_fidelity` | E7 |
| `scripts/gates/ui-contract-check.sh` (P048) | strukturální validátor kontraktu | E7 |
| `scripts/aid-prefilter.sh` | emit detector-owned `review-profile.json` + `profile_hash`; trace_required nelze vypnout omisí | E3 |
| `defaults/policies/review-profiles.yaml` (nový) | surface→lens/probe matrix + 1/2/3 IR kadence | E3 |

### 6.3 Checkpointy, Auditor, Curator, release

| Soubor | Změna | Etapa |
|---|---|---|
| `skills/review-checkpoint-contracts.md` | definovat jeden C2 kontrakt s `mode=local|wiring|behavior|final`; staré CP2/IR/CP3 názvy jen mapují mode, nevytvářejí vlastní schema/prompt | E5 |
| `agents/verifier.md` | jeden Semantic Review Engine: společné adversariální jádro + profilem vybrané lenses; mode mění rozsah diffu/assembly point, ne autoritu ani formát | E5 |
| `agents/auditor.md` | kategorie K (delivery/integration), strukturální JSON, derived `blocking_findings`, fresh-context replay, anti-patterns | E8 |
| `agents/curator.md` | vyžadovat aktuální audit input, odstranit APPROVED vocabulary (→ PROPOSALS_READY), eskalovat blockery | E8 |
| `agents/gate-fixer.md` | zákaz suppressu evidence, emit `invalidate_delivery_checks`, zákaz tvorby `*_ready:true` | E8 |
| `agents/reporter.md` | JSON+Markdown dual output; facts jen z controlled runner artefaktů; `agent_tool` self-authored soubor není důkaz spuštění; jasné partial/no-runtime vyjádření | E9 |
| `skills/pipeline.md` | nové pořadí, context assembly, fix loops, Auditor-před-Curator, IR kadence, MERGE precondition; každý PM handoff zobrazí nejprve strukturovaný brief a potom krátké lidské shrnutí | E5, E8, E9 |
| `skills/run-management.md` | D0/D1 lifecycle, stale-artifact handling, release-ready semantika | E2, E9 |
| `commands/aid-run.md` | C1 D0 před C2 final, risk-based C3, C1 D1 po affected re-run, C4 release decision | E5, E8, E9 |
| `commands/aid-do.md` | fast profil C1/C2/C4; existing_ui delta odmítnout/přesměrovat | E9 |
| `scripts/aid-fsm.sh` | C1/C2/C3/C4 freshness a profile requirements, verdikt konzumace, waiver, `release_ready` před MERGE; CP názvy jen compatibility mapping | E2, E5, E7, E9 |
| `scripts/aid-run-gates.sh` | coverage/relevance pole, feed do release policy | E2 |
| `scripts/aid-release-policy.sh` (nový) | agregace → `release-decision.json` | E9 |
| `scripts/aid-pm-brief.sh` (nový) | deterministicky agreguje strukturovaný PM brief; kontroluje úplnost blockerů, neověřených oblastí, odchylek a důkazů | E9 |
| `scripts/aid-reporter-run.sh` (nový) | spouští deklarovaný Playwright/smoke/test příkaz, zachytí argv/cwd/exit/time/stdout/digest a vytvoří ne-LLM provenance pro Reporter | E9 |
| `scripts/aid-release.sh` | release jen na `release_ready:true` (konzumuje release-decision) | E9 |

### 6.4 Schémata, policy, registry, testy

| Soubor | Změna | Etapa |
|---|---|---|
| `defaults/schemas/aid-protocol-v2.schema.json` (nový) | sdílená obálka (sekce 7) | E1 |
| `defaults/schemas/{contract-manifest,plan-review,semantic-review,audit,curator,release-decision,pm-decision-brief}.schema.json` (nové) | type-specific payloady; jeden semantic-review schema pro všechny C2 modes; generická obálka nesmí validovat prázdný nebo významově chybný artefakt | E1, následně rozšířit v owning etapě |
| `defaults/templates/review-profile-template.json` (nový) | detekované povrchy, lenses, IR body | E3 |
| `defaults/templates/acceptance-evidence-template.json` (nový) | AC identita, production trace, deviace | E5 |
| `defaults/templates/pm-summary-template.md` (nový) | pevná krátká lidská forma: jednou větou, dodáno, nedodáno/neověřeno, ověření, rizika, rozhodnutí PM | E9 |
| `defaults/policies/review-checkpoints.yaml` | risk modes, Auditor blocker policy, Curator sequencing | E5, E8 |
| `defaults/enforcement-registry.yaml` (kanonický; **ne** superseded seed v `docs/plans/AID-audit-2026-06/`) | registrovat každý nový precondition + jeho instruction home | každá etapa |
| `docs/extending-aid.md` | jak projekty konfigurují delivery profily + enforcement homes | E1, E11 |
| `scripts/tests/test-delivery-gate.sh` (nový) | DG-01..18 + negativní | E2, E6 |
| `scripts/tests/bats/test-aid-fsm.bats` | transition, freshness, verdikt, waiver, release-decision | E2, E9 |
| `scripts/tests/test-control-system-v2-regression.sh` (nový) | E-047-1/4/5, E-044, P045 fixtures | E10 |
| `scripts/aid-control-metrics.sh` (nový) | false-DONE/false-positive/náklady z evidence + timeline → `control-metrics.json` | E10 |

---

## 7. GUI-facing datový kontrakt (protokol v2)

### 7.1 Cíl

Jeden sdílený obal pro **každý** kontrolní artefakt, aby budoucí AID GUI (cockpit/evidence-lifecycle, mimo scope) četlo vše stejně bez znalosti interních skriptů. GUI **není** podmínkou fungování kontrol - obal je čistý nadstandard nad daty, která kontroly stejně produkují.

### 7.2 Sdílená obálka

Každý artefakt (`delivery-gate.json`, `plan-review.json`, `semantic-review-*.json`, `acceptance-evidence.json`, `audit-report.json`, `release-decision.json`, `ui/verdict.json`) MUSÍ na top-level nést:

```json
{
  "protocol_version": "aid-2.0",
  "artifact_type": "delivery_gate | plan_review | contract_manifest | semantic_review | acceptance_evidence | audit | curator | delivery_report | release_decision | ui_fidelity | pm_decision_brief",
  "review_profile": "frontend_shell_routing+realtime_async",
  "profile_hash": "sha256:...",

  "identity": {
    "project_id": "aid-orchestrator",
    "plan_id": "P048",
    "epic_id": "E-047-6_7",
    "run_id": "R-E047-6",
    "step_id": "step_8_frontend | null"
  },

  "subject": {
    "plan_sha256": "sha256:... | null",
    "contract_bundle_sha256": "sha256:... | null",
    "artifact_input_hash": "sha256:..."
  },

  "revision": {
    "base_commit": "9ee518e...",
    "head_commit": "8b8733c...",
    "head_is_current": true,
    "freshness": "current | stale"
  },

  "status": "pass | fail | skip | unverifiable | pending | blocked",
  "decision": {
    "kind": "none | delivery_ready | release_ready",
    "ready": false
  },
  "blocking_reasons": [
    { "finding_occurrence_id": "R-E047-6:DG-BUILD-001", "summary": "root build selhal na chybějícím multer" }
  ],

  "findings": [
    {
      "fingerprint": "sha256:...",
      "occurrence_id": "R-E047-6:DG-BUILD-001",
      "severity": "critical | high | medium | low | info",
      "category": "delivery_integration | wire_contract | wiring | ...",
      "title": "root npm run build exit 1",
      "human_summary": "Sestavení celého repozitáře selhalo, protože server importuje odstraněný multer.",
      "recommended_remediation": "Obnov multer, nebo odstraň zbývající import ve voice.ts.",
      "action_owner": "implementer | reviewer | pm | gate-fixer",
      "evidence_refs": ["delivery-gate/build.log"],
      "log_refs": ["timeline.jsonl#L482"],
      "state_at_generation": "open | resolved",
      "resolution_evidence_refs": []
    }
  ],

  "applicability": {
    "required_lenses": ["production_wiring", "wire_contract"],
    "completed_lenses": ["production_wiring", "wire_contract"],
    "coverage": "direct | partial | none | unknown"
  },

  "provenance": {
    "generated_by": "aid-delivery-gate.sh@2",
    "generated_at": "2026-06-22T15:30:00Z",
    "dispatch_mode": "deterministic | agent_tool | subagent"
  }
}
```

Sdílená obálka řeší pouze společná metadata. Každý `artifact_type` MUSÍ mít vlastní payload schema s povinnými poli a cross-field invarianty. Generický artefakt s platnou obálkou, ale bez seznamu checks/criteria/traces nebo s `status:pass` a `decision.ready:false`, nesmí projít type-specific validací.

**Pozn. (E1 reconciliation, 2026-06-22):** výše uvedená ukázka je pre-E1 draft. E1 (P049) přejmenoval enforced pole: `protocol_version→schema_version`, `head_commit→head_sha`, `base_commit→base_sha`, `decision→verdict`, `generated_by→producer`+`generated_by_tool`, a doplnil `control_protocol` + enforced `subject.subject_hash`. **Autoritativní názvy nese `.aid-o/plans/P049-protocol-v2-schemas.md` Data Model**; tato sekce se čte s tím mapováním.

### 7.3 Mapování na požadavky PM

| PM požadavek | Pole v obálce |
|---|---|
| project/plan/EPIC/run/step identity | `identity.*` |
| verze protokolu a review profil | `protocol_version`, `review_profile`, `profile_hash` |
| status, rozhodnutí, blocking důvody | `status`, `decision`, `blocking_reasons[]` |
| stabilní finding fingerprint + výskyt a severity | `findings[].fingerprint`, `findings[].occurrence_id`, `findings[].severity` |
| lidské shrnutí a doporučená náprava | `findings[].human_summary`, `recommended_remediation` |
| vlastník požadované akce | `findings[].action_owner` |
| applicability a coverage | `applicability.*` |
| evidence a log references | `findings[].evidence_refs`, `log_refs` |
| base/head commit a freshness | `revision.*` |
| hash schváleného plánu/kontraktu | `subject.*` |
| provenance a timestamps | `provenance.*` |

### 7.4 Stabilita finding IDs

Finding fingerprint je deterministický hash `(project_id, artifact_type, check_id, target_path, finding_class)`, **ne** sériové číslo. Re-run stejného problému na stejném cíli dá stejný fingerprint. Jednotlivý výskyt navíc nese vlastní `occurrence_id` odvozené z runu a revize, aby se neslily dva současné nálezy stejné třídy. GUI odvozuje životní cyklus z posloupnosti immutable výskytů; starý artefakt se kvůli `resolved` zpětně nepřepisuje.

### 7.5 Zpětná kompatibilita

- Stávající `.md` artefakty (audit-report.md, curator-report.md) zůstávají jako human-readable; nově se **navíc** generuje `.json` v protokolu v2.
- Pre-v2 evidence dostane `protocol_version: "legacy"` a `legacy_review_contract: true`; nepřepisuje se, GUI ji zobrazí jako historickou.

### 7.6 Závazný komunikační kontrakt s PM

Současný Reporter běží jen na hranici plánu a jeho Markdown je self-authored LLM výstup. Samotná existence reportu ani `_test_evidence[]` proto nezaručuje, že PM dostal úplný a srozumitelný stav. v2 zavádí dva navazující výstupy při **každém PM handoffu** (schválení plánu, blokace/eskalace, EPIC release a uzavření plánu):

1. **`pm-decision-brief.json` - kanonický strukturovaný výstup.** Generuje ho deterministicky `aid-pm-brief.sh` z aktuálních v2 artefaktů. Obsahuje scope, plánované outcomes, skutečně dodané outcomes, nedodané/odložené položky, provedená ověření, open blockery, `unverifiable` oblasti, odchylky, rizika, potřebná rozhodnutí, dostupné volby a evidence refs.
2. **`pm-summary.md` - krátké lidské shrnutí.** Reporter nebo Orchestrator přeloží brief do běžné řeči v pevné struktuře: `Jednou větou`, `Co je hotovo`, `Co není hotovo nebo nelze ověřit`, `Co bylo reálně ověřeno`, `Na co pozor`, `Co potřebuji od tebe`. Výchozí limit je 10 stručných bodů; technické kódy jsou až v odkazu/detailu.

Normativní pravidla:

- nejprve se zobrazí strukturovaný stav, potom jednoduché lidské shrnutí;
- lidské shrnutí nesmí vytvořit ani změnit verdict, severity, ownera nebo release volbu;
- každý blocker, neověřená oblast a neodsouhlasená odchylka z required vstupů musí být v briefu a alespoň souhrnně v lidském textu;
- `test_outcome: partial|no-runtime`, waiver a chybějící runtime důkaz nesmí být popsány jako „vše ověřeno“;
- chybějící required vstup generuje `communication_status: incomplete`, nikoli optimistický report;
- Reporterův runtime test je jeden ze vstupů briefu, nikoli zdroj pravdy pro ostatní kontroly;
- Reporter smí nastavit `test_outcome:pass` pouze nad aktuálním artefaktem z `aid-reporter-run.sh`; ručně vytvořený transcript nebo pouhá existence screenshotu nestačí;
- GUI později zobrazuje stejný `pm-decision-brief.json`; nevytváří vlastní interpretaci release stavu.

Blocking negativní test: odeber z briefu jeden High blocker nebo `unverifiable` required check. `aid-pm-brief.sh --validate` musí selhat a PM handoff se nesmí označit jako kompletní.

---

## 8. Integrace P048 (frontendová větev)

### 8.1 Princip

P048 se začleňuje **jako frontendová větev společného procesu**, ne jako paralelní systém. Tok přesně dle PM zadání:

```
Visual Companion
  → verzovaný UI kontrakt (ui-change-contract.yaml v contract-bundle)
  → Implementátor (constrained na typed delta, consumption proof)
  → mechanická visual-fidelity kontrola      (frontend_visual_fidelity)
  → sémantická kontrola uživatelské hodnoty  (frontend_user_outcome)
  → C1 Delivery / C2 Semantic / případně C3 Audit → C4 Release Policy
```

### 8.2 Dvě rozlišené frontend lenses

| Lens | Otázka | Vrstva | Determinismus |
|---|---|---|---|
| `frontend_visual_fidelity` | Odpovídá implementace schválenému návrhu? (delta aplikována, locked nezměněno) | Delivery Gate (L5) sub-check | **deterministická** (Playwright capture/compare, `ui-compare.mjs`, pixel + computed-style) |
| `frontend_user_outcome` | Dokáže cílový uživatel nad reprezentativními daty zodpovědět schválené otázky a provést zamýšlenou akci? | C2 behavior/final + C3 když required | **sémantická** (behavior trace nad sanitizovaným real-data snapshotem nebo bezpečným live runtime + nezávislý oracle) |

Tyto dvě lenses jsou ortogonální. `frontend_visual_fidelity` z P048 je povinná pro `existing_ui` deltu. `frontend_user_outcome` je povinná pro **každou uživatelsky viditelnou UI změnu**, tedy i `greenfield` a `redesign`; jinak by celá stará cesta Visual Companion → Implementátor zůstala mimo opravu. Outcome kontrakt musí už v CP1 pojmenovat personu, 1-5 rozhodovacích/uživatelských otázek, očekávanou akci, zdroj/oracle dat, významné empty/loading/error/partial stavy a kritéria úspěchu. `frontend_user_outcome` pak chytí "vypadá správně, ale nad reálnými daty je prázdné / dropne záznamy / nesmyslné". Unmounted shell zůstává primárně deterministický DG-13 nález, ne náhrada outcome review.

### 8.3 Co se mění oproti původnímu P048

1. **P048 verdikt přestává být nezávislá FSM release autorita.** Mechanický guard (`ui-compare.mjs`) zůstává, ale jeho `verdict.json` (reason kódy `ui_contract_verdict_fail`/`ui_capture_unavailable`/`ui_contract_missing`/`ui_gestalt_unapproved`):
   - na EXECUTE úrovni je C1 step-local check - smí blokovat increment jednoho kroku;
   - na release úrovni **teče jako `frontend_visual_fidelity` check do `delivery-gate.json`** a odtud do `release-decision.json`. Jediná release autorita zůstává C4.
2. **`gestalt_approval`** zůstává jako hard-checked artefakt (hash decision-sheetu), ale jako součást contract-bundle, ne jako samostatná FSM autorita.
3. **`/aid-do` existing_ui delta** se ve fast profilu klasifikuje jako produkční → odmítnout nebo přesměrovat (uzavírá P048 follow-up).
4. **`verdict.json`** dostává protokol v2 obálku (sekce 7), takže ho C4 i GUI čtou jednotně.
5. **P048 capture jako delivery check:** `frontend_visual_fidelity` v `delivery-gate.yaml` má `required_when: "existing_ui_frontend_changed"`; capture-unavailable = `unverifiable` (blokující při `block_on_unverifiable`), ne warn+skip - konzistentní s DG sémantikou.
6. **P048 plán musí být před generováním EPICů formálně amendován.** Jeho původní Step 8 a původní pořadí EPICů jsou v konfliktu s E7A→E7-CAL→E7B a jednotnou release autoritou. Implementátor nesmí současně následovat starý P048 a tento master plán; E7 začne až po vytvoření hashovaného amendmentu, který konfliktní body označí jako superseded.

### 8.4 Co z P048 zůstává beze změny

- `lib/ui-fidelity/` Node package, determinism harness, typed `delta`/`affected`/`locked`, rest-lock, whole-crop pixel lock, two-part tolerance.
- Contract transport přes `aid-plan-to-epic.sh` + `aid-epic-to-json.sh` (P048 Step 7) - jen rozšířen o protokol v2 a o napojení na review-profile místo izolovaného FSM reason.
- Hermetic fixture testy + mandatory CI job.

### 8.5 P048 jako pilot pro celý v2

P048 je nejhotovější větev (má detailní plán, AC, fixtures). Použije se jako **referenční implementace vzoru** "C1 plugin → delivery evidence → C4". E7 ale musí být dvoustupňová: nejprve vznikne capture/compare/contract jádro, poté proběhne povinná kalibrace na 2-3 PM-schválených reálných selháních a teprve potom se smí zapojit Visual Companion, implementátor, FSM a blocking policy. Globální E10 kalibrace nenahrazuje tuto P048 precondition.

---

## 9. Migrační a rollback strategie

### 9.1 Observe / dual-run princip

Žádná nová blokující kontrola se nezapne přímo. Každá projde:

1. **Observe mód** - kontrola běží, zapisuje artefakt, ale `enforcement: observe` → výsledek je `non-blocking` bez ohledu na verdikt. Měří se applicability, false-positive, doba běhu, dostupnost příkazů.
2. **Dual-run** - nová kontrola běží vedle staré po dobu N reprezentativních EPICů; porovnává se shoda/rozpor.
3. **Blocking** - zapnutí blokování po kalibraci (sekce 10 E10).

Řízeno per-check v `delivery-gate.yaml` / `review-checkpoints.yaml`: `enforcement: observe | dual_run | blocking`. Promotion observe→blocking používá `aid-promote-checks.sh`, ale nesmí stát jen na počtu override: vyžaduje historické negative fixtures, positive controls, reprezentativní vzorek daného surface a PM-klasifikaci false blocks dle §11.2. Explicitní PM promotion je auditovaná výjimka, ne přepsání naměřených dat.

### 9.2 Fail-closed pravidla

- Chybějící policy/config → safe defaults.
- Malformed JSON/YAML → `unverifiable` a blokující pro required artefakty.
- Neznámý ekosystém → není PASS, vyžaduje explicitní příkazy nebo waiver.
- `--force` nevyrobí `delivery_ready:true`/`release_ready:true`; zapíše waiver separátně (`unverifiable_with_waiver`).

### 9.3 Rollback

- Každá etapa je samostatně reverzibilní: nové skripty/skills jsou aditivní; `enforcement: observe` lze kdykoli vrátit z `blocking`.
- Pre-v2 runy běží na `legacy_review_contract: true` a **nesmí být tiše přepsány**.
- Každý run při vzniku explicitně zamkne `control_protocol: legacy|aid-2.0` a `policy_version` do `fsm-state.yaml`/run manifestu. FSM nikdy nevolí parser ani enforcement podle času, mtime nebo implicitního deploy data. Rozběhnutý run svůj protokol uprostřed nemění; migrace vyžaduje explicitní auditovanou operaci.
- Defaults se kopírují při `/aid-init` upgrade **bez přepsání** projekt-lokálních příkazů.

**Rollback FSM preconditionů (nejcitlivější část).** Nové blokující preconditiony ve FSM se nezavádějí jako hard kód, ale jako **policy-gated** přepínače (`enforcement: observe|dual_run|blocking` v `review-checkpoints.yaml` / `delivery-gate.yaml`). Rollback živého preconditionu, který už blokuje běžící runy:
1. přepnout konkrétní check zpět na `enforcement: observe` (okamžitý efekt, žádný redeploy skriptu);
2. rozběhlé runy, které uvízly na novém preconditionu, lze odblokovat existujícím `--force --reason` (zůstává v audit logu jako waiver, nepřepisuje evidence);
3. nový precondition nikdy nemění **whitelist přechodů** (`VALID_TRANSITIONS`), jen přidává policy-gated kontrolu uvnitř - takže rollback nikdy nevyžaduje migraci stavu rozběhnutých runů.
Tím je každý FSM-level enforcement reverzibilní bez dotčení už vytvořených `fsm-state.yaml`.

### 9.4 Kompatibilita evidence

- Evidence bez Delivery Gate zůstává čitelná, ale po enforcement date nesplní release policy.
- `audit-report.md` zůstává; nové runy navíc vyžadují `audit-report.json`.
- CP output parsery akceptují staré soubory pro display; FSM transitions vyžadují v2 schémata pouze u runů explicitně zamčených na `control_protocol: aid-2.0`.

---

## 10. Rámcové implementační etapy (správné pořadí)

Tyto E0-E11 položky nejsou formální AID EPICy. Jsou roadmapou, ze které teprve vznikne schválený AID plán a jeho skutečné EPICy. Princip pořadí: každá etapa uzavírá konkrétní reálnou cestu k false-DONE a je konzumovatelná samostatně. Žádný big-bang.

### E0 - Control Topology Challenge (povinné před E1 a před formálním AID plánem)

**Cíl:** Dokázat, že cílová topologie C0-C4 je nejmenší sada odlišných mechanismů pokrývající známé failure classes, a zabránit automatickému přepsání dnešních CP1-CP6 do šesti nových systémů.

**Obsah:**

- inventář failure classes z Doc-1, Doc-2, P048, E-047-1/4/5, E-044 a P045;
- `failure-mode-control-matrix.json`: každá failure class → nejčasnější owner C0-C4 → trigger → evidence → stop condition → negative fixture;
- `control-topology.yaml`: mechanismy, modes, lenses, compatibility aliases, risk profile a dispatch budget;
- overlap matrix dnešních CP/IR/Auditor/project gates včetně vstupů, výstupů a historicky unikátních nálezů;
- explicitní rozhodnutí `keep_as_mechanism | merge_as_mode | convert_to_plugin | utility_only | remove` pro každý dnešní checkpoint/agent;
- cost model: počet agent dispatchů, deterministických checků a očekávaný p50/p95 čas per profil;
- návrh compatibility vrstvy, aby staré CP názvy bylo možné číst, ale nevznikala pod nimi nová autorita.

**Předběžný cílový verdict, který E0 musí potvrdit nebo vyvrátit daty:**

- CP1 → C0 Plan Contract Gate;
- Delivery Gate + project gates + P048 mechanical → C1 plugins;
- CP2 + IR-1 + IR-2 + CP3 → modes jednoho C2 Semantic Review Engine;
- Auditor → C3 pouze pro risk-triggered profily;
- CP4 → invalidace/re-run C1/C2, žádný nový reviewer;
- CP5 → C4 deterministická Release Policy;
- CP6 → fast profil C1/C2/C4;
- Curator/Reporter/Simplifier → utility/communication, bez correctness authority.

**Acceptance kritéria:**

- [ ] Každá známá failure class má právě jednoho primárního ownera C0-C4; sekundární nezávislý catch je explicitně označen jako defense-in-depth, ne duplicitní autorita.
- [ ] Každý mechanismus/mode/lens projde Control Necessity Testem ze §3.0.
- [ ] CP2/IR/CP3 používají jedno schema, finding model, invalidaci a reviewer engine; liší se jen mode, assembly point a diff range.
- [ ] CP4 nemá samostatný prompt/agent/schema; fix pouze invaliduje a znovu spustí dotčené C1/C2 evidence.
- [ ] CP6 nemá vlastní review implementaci; používá fast profil stejných enginů.
- [ ] Low profil vyžaduje nejvýše jeden C2 dispatch; medium nejvýše dva; high nejvýše tři C2 dispatchy + jeden C3 audit.
- [ ] Docs/trivial profil nespouští C2/C3 bez detekovaného behaviorálního triggeru a zapisuje důvod skipu.
- [ ] P048 přidá lenses/plugin, nikoli nový checkpoint nebo release autoritu.
- [ ] GUI kontrakt čte jednotné C0-C4 artefakty/modes, nikoli hardcoded CP1-CP6 specifické formáty.
- [ ] Nejméně jeden „duplicitní reviewer“ negative design fixture je odmítnut, protože nemá unikátní failure class ani nezávislý vstup.
- [ ] Nejméně jeden positive control pro každý profil prokáže, že minimalizace neblokuje legitimní změnu.
- [ ] PM schválí topology verdict a dispatch budget před E1 a před vytvořením formálního AID plánu.

**Výstupy:** `docs/design/AID-control-system-v2-control-topology.md`, návrhy `control-topology.yaml` a `failure-mode-control-matrix.json`. Žádná změna runtime chování.

### E1 - Protokol v2, schémata, GUI kontrakt, enforcement registry

**Cíl:** Definovat sdílenou obálku a všechna schémata bez změny chování.
**Obsah:** `aid-protocol-v2.schema.json`; type-specific schemas a templaty pro všechny artefakty z §5 (v owning etapě lze doplnit payload pole, ale E1 musí zamknout jejich typ, obálku a non-empty minimum); HEAD + subject-hash freshness pravidlo; explicitní per-run `control_protocol`; registrace v enforcement-registry; `docs/extending-aid.md` skeleton.
**Acceptance kritéria:**
- [ ] Existuje `aid-protocol-v2.schema.json` a type-specific schema pro každý autoritativní artefakt; prázdný payload s platnou obálkou neprojde.
- [ ] Každý template nese kompletní obálku (sekce 7.2) včetně `identity`, `subject`, `revision`, deterministického fingerprintu a occurrence ID.
- [ ] Finding fingerprint generátor je deterministický a project-scoped; occurrence ID odlišuje jednotlivé runy/revize (unit test).
- [ ] Změna necommitnutého plánu nebo contract bundle zneplatní navázané review/handoff artefakty přes subject hash.
- [ ] Run explicitně zamkne `control_protocol` a nelze jej tiše přepnout podle data nasazení.
- [ ] Žádná změna runtime chování (jen schémata + dokumentace).
**Negativní fixtures:** artefakt bez `head_sha` (E1 název, viz §7.2 reconciliation) → schema fail; finding bez `action_owner` → schema fail.

### E2 - Delivery Gate core (DG-01..DG-12) + FSM state hardening

**Cíl:** Deterministická delivery vrstva v observe módu + uzavřít DG-07 false-DONE díru ve stavu.
**Obsah:** `aid-delivery-gate.sh` (DG-01..12), `aid-delivery-profile.sh`, `delivery-gate.yaml`; argv-array exec; policy-gated FSM hardening pro child step pending / active task counter / `compliance.overall:fail`; `aid-run-gates.sh` coverage/relevance; D0 po posledním kroku. Výchozí živý režim je `observe` a zapisuje `would_block`; blocking chování se v E2 ověřuje fixturem, ne zapnutím na všech bězích.
**Acceptance kritéria:**
- [ ] Leaf package projde, root build selže → `delivery_ready:false` (false-ready regression test).
- [ ] Odstraněná závislost se zbývajícím produkčním importem → DG-06 fail (multer fixture).
- [ ] Zero discovered tests → `unverifiable`, ne pass.
- [ ] Stale HEAD v reportu → blokující.
- [ ] Fixture s `enforcement:blocking` znemožní parent DONE/release při pending child step / active counter; výchozí `observe` pouze zapíše `would_block`.
- [ ] Wrapper propaguje reálný child exit kód (inner fail ≠ outer pass).
- [ ] V observe módu žádné selhání neblokuje, ale vše se zapíše.
**Negativní fixtures:** manifest/lock mismatch → DG-01 fail; vacuous typecheck (jen shim) → DG-09 unverifiable; framework-major startup throw → DG-10 fail.

### E3 - Adaptivní review profil detektor (observe)

**Cíl:** `aid-prefilter.sh` emituje `review-profile.json` z dotčených povrchů; detektor vlastní applicability.
**Obsah:** surface→lens/probe matrix (`review-profiles.yaml`), `profile_hash`, trace_required nelze vypnout omisí, 1/2/3 IR kadence definice. Plan-time profil vznikne z deklarovaných souborů/kontraktů a dependency graphu; candidate-time profil ze skutečného diffu, import/route/registry změn a runtime surfaces. Autoritativní profil je monotónní union, nikdy užší přepočet.
**Acceptance kritéria:**
- [ ] Mixed změna dostane union všech matched lenses, ne dominant label.
- [ ] Neznámý produkční povrch → default `unverifiable`, ne `docs_only`.
- [ ] `review-profile.json` nese `profile_hash`; každý C2/C3 artefakt ho opakuje.
- [ ] Implementátor zasáhne neplánovaný security/realtime/UI povrch → candidate-time profil přidá příslušnou lens a invaliduje neúplné dřívější review.
- [ ] FSM validuje `required_lenses - completed_lenses == empty` (zatím observe).
**Negativní fixtures:** detektor vyžaduje `realtime_async`, reviewer vynechá wire/fallback lens → (v blocking módu) rejected.

### E4 - C0 Plan Contract Gate + contract handoff + consumption proof

**Cíl:** Plánovací kontrakt je ověřitelný a prokazatelně předaný.
**Obsah:** C0/CP1 producer-consumer, plan-graph (topo-sort, cykly), identifier-domain table, reuse-compat, planned-call feasibility matrix, dep-API grounding, idempotency state matrix, authority/runtime matrix, delivery-evidence plan, integration points, behavioral contract table (Doc-1 §6.1 + Doc-2 §11.2-11.7 + §7). Contract handoff: `contract-manifest.json` s hashy zdrojů a každé závazné položky, dispatch receipt a item→changed-file/test/runtime-evidence map. Implementátor mapování navrhne. E4 vytvoří policy-gated FSM hook a stav `pending/unverifiable`; autoritativní C2 local/final validaci proti diffu a důkazům implementuje až E5. Prosté zopakování textu není proof.
**Acceptance kritéria:**
- [ ] Dvouuzlový cyklus skrytý mezi `Depends on` a prózou → CP1 plan-graph fail (P045 fixture).
- [ ] Jeden identifier ve třech doménách (index/ordinal/slot) → CP1 identifier fail.
- [ ] Reuse komponenty s immediate POST → CP1 reuse-compat fail.
- [ ] ORM field patřící jinému modelu → CP1 feasibility fail.
- [ ] Unversioned install + version-specific API → CP1 dep-API fail.
- [ ] Fail-open idempotency + at-most-once kritérium → CP1 idempotency fail.
- [ ] C0 precondition je policy-gated: fixture v `blocking` režimu zastaví EPIC generaci, výchozí `observe` zapíše `would_block`.
- [ ] Implementátor bez hash-valid item→evidence mapy vytvoří `pending/unverifiable` consumption stav; autoritativní blokování čeká na E5 C2 local.
- [ ] Kontrakt změněný po dispatchi zneplatní mapu přes subject hash; E5 doplní nezávislé obsahové ověření.
**Negativní fixtures:** kompletní P045-style plán (všechny soubory existují, sekce kompletní) musí selhat na graph/identifier/reuse/call/dep/idempotency.

### E5 - C2 Semantic Review Engine + adaptivní modes + acceptance-evidence

**Cíl:** Jeden Semantic Review Engine poskytuje local/wiring/behavior/final režimy bez duplicitních promptů, schémat a findings; acceptance-evidence je rekonstruováno nezávisle.
**Obsah:** společné adversariální jádro a `semantic-review.schema.json`; profilem vybrané lenses; `mode=local` pro contract/high-risk step (CP2 alias), `mode=wiring|behavior` pro assembly points (IR aliasy), `mode=final` pro full diff + D0 + acceptance-evidence (CP3 alias); 20 mandatory final checks z Doc-1 §6.3 jako lens katalog, ne vždy stejný obří prompt; `acceptance-evidence.json` rekonstrukce z autoritativních AC (Doc-2 §4-5); risk-based security lens.
**Acceptance kritéria:**
- [ ] C2 final neprojde bez aktuální C1 evidence.
- [ ] Acceptance-evidence pokrývá každý autoritativní AC; chybějící/změněné/neschválené deviace → block.
- [ ] Mutace odstraňující asertované chování stále projde testem → DG-18/C2 final fail (E-044 fixture).
- [ ] Medium/high profil nesmí přeskočit povinné 2/3 integration reviews.
- [ ] C2 wiring High defect → blokuje další implementaci do recheck.
- [ ] Test mění schválené `403` na `401` → requirement drift fail.
- [ ] Local/wiring/behavior/final výstupy validuje jedno schema a sdílejí stabilní finding fingerprinty; mode nevytváří novou autoritu.
- [ ] Low profil bez local triggeru nespouští per-step C2 a přesto projde final C2.
**Negativní fixtures:** E-044 sémantický fixture (commit po endpoint return, cleanup kolem flush, field lineage, 8 testů kde 2 scénáře chybí, requirement drift). `message` vs `detail` response shape patří deterministickému C1 DG-14 v E6, ne C2.

### E6 - DG-13..DG-18 (wiring, wire-contract, route, fallback, oracle, acceptance struct)

**Cíl:** Sémanticky-hraniční deterministické probes.
**Obsah:** DG-13 production reachability, DG-14 real provider-consumer wire, DG-15 navigation/dispatch conformance, DG-16 fallback/recovery probe, DG-17 independent oracle/no-drop, DG-18 acceptance structural integrity.
**Acceptance kritéria:**
- [ ] Exportovaný unit-tested ale unmounted feature → DG-13 fail (E-047-5 fixture).
- [ ] Real WS provider emituje nested `data`, consumer čte top-level → DG-14 fail.
- [ ] Generated `/plan/:id` bez matching `/plans/:id` route → DG-15 fail.
- [ ] Fallback projde izolovaně, ale mounted app ho nevolá → DG-13/DG-16 fail.
- [ ] Analytics self-consistent, ale dropne záznamy vs oracle → DG-17 fail.
**Negativní fixtures:** E-047-5 unmounted-hook/wire-drift fixture; E-047-4 analytics-drop fixture.
E-044 `message` vs `detail` je další DG-14 response-shape fixture.

### E7 - Integrace P048 (frontend větev)

**Cíl:** P048 jako `frontend_visual_fidelity` delivery check + `frontend_user_outcome` lens, ne nezávislá FSM autorita.
**Obsah ve třech povinných podetapách:**
1. **E7A foundation:** `lib/ui-fidelity/`, capture/compare, contract schema, hermetic fixtures a CI bez napojení na blocking FSM.
2. **E7-CAL hard gate:** PM předem vybere 2-3 reálná selhání; na nich se ověří cross-stack capture, tolerance, typed delta a negative controls. Neúspěšná kalibrace blokuje E7B.
3. **E7B wiring:** `ui-contract-check.sh`; Visual Companion reálný capture + `gestalt_approval`; frontend role card UI Change Contract protokol; contract transport přes generátory; `verdict.json` v protokolu v2; `/aid-do` existing_ui odmítnutí/přesměrování; `frontend_user_outcome` contract a lens pro existing_ui, greenfield i redesign.
**Acceptance kritéria:**
- [ ] `existing_ui` step s FAIL verdiktem → step-local block (EXECUTE) a `frontend_visual_fidelity:fail` v delivery-gate.json.
- [ ] P048 verdikt teče do `release-decision.json` jako vstup, **ne** jako nezávislý MERGE blok ve FSM.
- [ ] Capture-unavailable na existing_ui → `unverifiable` (blokující), ne warn+skip.
- [ ] Absent/mismatched gestalt_approval → block.
- [ ] Contract round-trip plan → EPIC → plan.json nese `ui_change_mode` + `ui_change_contract`.
- [ ] `/aid-do` existing_ui delta → odmítnuto/přesměrováno na `/aid-run`.
- [ ] E7B nelze zahájit bez podepsaného kalibračního záznamu pro 2-3 PM-schválené reálné případy; hermetic fixture sama nestačí.
- [ ] Každá user-visible UI změna má `frontend_user_outcome` kontrakt s personou, otázkami/akcemi, datovým oraclem a významnými stavy, bez ohledu na `existing_ui|greenfield|redesign`.
- [ ] C2 behavior/final ověří outcome nad sanitizovaným snapshotem odvozeným z reálných dat nebo bezpečným live runtime; self-consistent synthetic fixture sama nestačí.
**Negativní fixtures:** un-applied delta → `delta_not_applied`; locked color change → `locked_violation`; všechny P048 Step 10 E2E scénáře.

### E8 - C3 Independent Audit + Curator sequencing + affected re-run

**Cíl:** Risk-triggered nezávislé outcome ověření, Curator bez merge-influence a opravy bez samostatného CP4 review systému.
**Obsah:** C3/Auditor kategorie K (delivery/integration), strukturální `audit-report.json`, mechanicky odvozené `blocking_findings` (**Critical OR High → true**, dle R1), fresh-context replay >=1 detector-selected trace, anti-patterns. Orchestrator před dispatch vytvoří `audit-input-manifest.json` s allowlistem autoritativního plánu, diffu, raw evidence a vybraných traces; předchozí PASS shrnutí a implementátorova narace jsou označeny jako untrusted nebo z kontextu vynechány. C3 používá provider-neutral adapter a reportuje `provider`, `model`, process provenance a `independence_level: context_only|cross_model|cross_provider`; profil určuje minimální požadovanou úroveň. Autoritativní C3 PASS vyžaduje samostatný agent context **a zároveň** out-of-band provenance start/complete svázanou s hashem input manifestu. Referenční externí backend je Codex CLI přes `codex exec`, ale pouze když adapter mechanicky prokáže dostupnost CLI, auth a schema-valid non-interactive běh; model/agent nesmí sám "uhodnout", že běží v CLI nebo IDE, ani tím nahradit provenance. Nedostupný profilem požadovaný provider/model znamená `unverifiable`, ne falešný PASS. Curator běží po C3, nebo přímo po C2 final pokud C3 není profilem required. Oprava vytvoří `invalidation-map.json` a znovu spustí dotčené C1/C2; nevzniká samostatný CP4 reviewer/prompt/schema. Gate-fixer nesmí suppressovat evidence.
**Acceptance kritéria:**
- [ ] `blocking_findings` se odvozuje mechanicky z **Critical OR High** (ne jen Critical jako dnes); unit test ověří, že samotný High finding → `blocking_findings:true`.
- [ ] Auditor skóre 95 + High finding → release blocked (skóre nepřebije blocker).
- [ ] Auditor běží z čistého kontextu a reportuje, který trace nezávisle replayoval.
- [ ] Dispatch bez samostatného agent contextu, hash-bound input manifestu a out-of-band start/complete provenance nemůže vydat autoritativní Auditor PASS; samotný typ `agent_tool` není důkaz ani automatický fail.
- [ ] `audit-input-manifest.json` hashově váže vstupy; dodatečně podstrčené implementační shrnutí invaliduje provenance.
- [ ] Provider-neutral adapter umí alespoň jeden externí reviewer backend (referenčně Codex CLI); report rozlišuje `context_only`, `cross_model` a `cross_provider` a profil může minimální úroveň vynutit.
- [ ] Codex backend se spouští pouze přes samostatný `codex exec --ephemeral --sandbox read-only --ask-for-approval never` proces s `--output-schema` / schema-valid poslední zprávou; adapter nejdřív ověří `command -v codex`, `codex exec --help` nebo sanity run a dostupnou auth. Pokud detekce selže, výsledek je `unavailable/unverifiable`, ne fallback na self-claim aktuálního agenta.
- [ ] Curator report obsahující EPIC `APPROVED` verdikt → schema rejected/ignored.
- [ ] Curator startuje až po `audit-report.json` (head_matches).
- [ ] Compatibility `CP4 pass` bez re-run dotčených C1/C2 důkazů → C4 odmítne.
- [ ] Oprava dotýkající se pouze lokálního C1 checku nespouští celý C2/C3 cyklus; dependency/invalidation map určí minimální bezpečný re-run.
- [ ] Žádný `cp4.json` self-contained PASS nemůže nahradit aktuální affected C1/C2 evidence.
**Negativní fixtures:** audit s `overall:fail` koexistující s parent DONE → DG-07/C4 fail.

### E9 - C4 Release Policy + fast profile + PM communication

**Cíl:** Jedna release eligibility autorita; `/aid-do` používá stejné enginy v menším profilu a PM dostává úplný výstup.
**Obsah:** C4 `aid-release-policy.sh` → `release-decision.json`; FSM MERGE jen na `release_ready:true` + HEAD match; C1 D1 po fixech; `/aid-do` fast profil stejných C1/C2/C4 mechanismů (CP6 alias), ne vlastní reviewer; `aid-release.sh` konzumuje release-decision; waiver artefakt bez PASS rewrite; opravený Reporter s controlled runtime runnerem a `delivery-report.json/.md`; `aid-pm-brief.sh` + pevný `pm-summary.md` pro plánové schválení, blokaci/eskalaci, EPIC release a plan close.
**Acceptance kritéria:**
- [ ] C4 agreguje všechny required vstupy do HEAD-bound rozhodnutí.
- [ ] FSM nabídne MERGE jen když `release_ready:true` a HEAD odpovídá.
- [ ] Produkční `/aid-do` změna nemůže obejít blokující C1/C2/C4 přes legacy advisory CP6 cestu.
- [ ] `/aid-do` neobsahuje separátní CP6 prompt/schema/autoritu; pouze sestaví fast profil a spustí C1/C2/C4.
- [ ] Forced waiver zůstává viditelný a nepřepíše check na PASS.
- [ ] Release decision stale vůči HEAD → MERGE nenabídnut.
- [ ] PM před každým rozhodnutím dostane validní strukturovaný brief a krátké lidské shrnutí v pevné struktuře.
- [ ] Brief vynechávající jediný blocker, `unverifiable` required check nebo neodsouhlasenou odchylku → handoff validation fail.
- [ ] Lidské shrnutí nesmí tvrdit „hotovo/ověřeno“, pokud strukturovaný brief obsahuje `partial`, `unverifiable`, waiver nebo nedodaný outcome.
- [ ] Reporter `test_outcome:pass` bez current-HEAD controlled-run provenance → report schema/policy fail.
**Negativní fixtures:** všech 17 CP/FSM testů z Doc-1 §13.2 (orig. 1-12 + 13-17 pro adaptivní profil/IR).

### E10 - Kalibrace na známých selháních + dual-run metriky

**Cíl:** Důkaz, že vrstvené kontroly nesouhlasí čestně a release zůstává bezpečný.
**Obsah:** kompozitní regression fixtures E-047-1, E-047-4, E-047-5, E-044, P045; měření false-DONE/false-positive/nákladů (sekce 11); dual-run porovnání nový vs starý proces; promotion observe→blocking dle empirického kritéria. Toto je systémová kalibrace po integraci; nenahrazuje E7-CAL před P048 wiringem.
**Acceptance kritéria:**
- [ ] E-047-1 fixture: C2 local může pass, C1 fail (DG-05/06/08..18), C2 final fail, C3 blocking, C4 release_ready:false.
- [ ] E-044 fixture: C1 DG-14 fail na response shape, C2 fail na transaction/acceptance/requirement drift, C3 blocking, C4 release_ready:false.
- [ ] P045 fixture: CP1 structure pass, ale graph/identifier/reuse/call/dep/idempotency fail, EPIC generace blokována.
- [ ] Dual-run: žádný fixture nedosáhne `release_ready:true`.
- [ ] Naměřené false-positive rate < práh pro promotion (sekce 11).
**Negativní fixtures:** samotné kompozitní fixtures jsou test.

### E11 - Řízený cutover + datově podložené další zjednodušení

**Cíl:** Po E0 design-time sloučení odstranit pouze další redundance, které lze potvrdit až provozními daty.
**Obsah:** cutover blocking; stop unconditional security lens na non-security diff; odstranění duplicitní command narration z LLM promptů; agenti konzumují structured gate summaries místo re-run; tracking escaped defects + false blocks před odstraněním nejistých defense-in-depth checks. E11 není první okamžik zjednodušení: zjevné duplicity CP2/IR/CP3, CP4 a CP6 byly sloučeny už v E0.
**Acceptance kritéria:**
- [ ] Po cutoveru žádný legacy run tiše přepsán.
- [ ] Odstranění redundance jen pro kontroly s prokázanou nulovou unique detekcí v E10 datech.
- [ ] Escaped-defect tracking aktivní a reportovaný.

---

## 11. Měření: false-DONE, false-positive, náklady

### 11.0 Měřicí harness (odkud data jdou)

Metriky nejsou ruční odhad. Počítá je nový skript `scripts/aid-control-metrics.sh` (E10) z existujících strojových zdrojů:
- **vstupy:** `release-decision.json`, `delivery-gate.json`, `audit-report.json` (per run), `timeline.jsonl` (`fsm_force_override`, `fsm_done_advance_blocked/recovered`, `gate_*`, `_command_log`), `waiver-*.json`, agregovaná `enforcement-registry.yaml`.
- **výstup:** `.aid-o/work/evidence/_metrics/control-metrics.json` (protokol v2 obálka) + markdown přehled (reuse vzoru `aid-promote-checks.sh --format markdown`).
- **baseline:** před zapnutím blokování se v observe/dual-run období (E2-E9) sbírá baseline per check - bez baseline se check nesmí promovat na `blocking` (R-promotion v 11.2). Pro false-DONE neexistuje historická číselná baseline, proto se používá **regression-fixture floor**: každá známá historická díra (sekce 12) MUSÍ zůstat chycená; nová uniklá díra → nový fixture, který se nikdy nesmí znovu otevřít.

### 11.1 False-DONE (uniklé selhání)

- **Definice:** EPIC dosáhl `release_ready:true`, ale následně se ukázal nedoručitelný/nesprávný.
- **Metrika:** počet escaped integration defects objevených po C4 / celkový počet releasů.
- **Zdroj:** post-release incidenty + regression fixtures (každá známá historická díra musí zůstat chycená).
- **Cíl:** monotónně klesající; každý nový escaped defect → nový negativní fixture (E10) → nesmí znovu uniknout.

### 11.2 False-positive (falešný blok)

- **Definice:** kontrola blokovala release, který byl ve skutečnosti správný.
- **Metrika:** false-block rate = waivery s důvodem "false positive" / celkové bloky, per check.
- **Promotion gate:** observe→blocking vyžaduje současně: všechny historické negative fixtures chycené, reprezentativní positive controls bez bloku, PM-klasifikované false blocks pod 5 % a minimální vzorek per surface. `force_override_rate[check] < 0.05` přes N>=5 EPICů je pouze technický floor, nikoli důkaz přesnosti; waiver může být legitimní výjimka i nesprávně obejitý blocker.
- **Cíl:** udržet pod 5 % per blokující check; check překračující práh se vrací do observe.

### 11.3 Náklady kontrol

- **Metriky:** median/p95 doba C1 per check; počet C2 dispatchů per profil/mode; duplicate-finding rate mezi C2 modes a C3; % zelených C1 checks s `relevance:none`; C2 findings duplikující deterministická selhání; tokeny per review.
- **Zdroj:** `timeline.jsonl` + `_command_log` + token-count lib.
- **Cíl:** "Success is not more findings. Success is fewer false-ready releases with acceptable execution time." Redundantní kontroly se odstraní v E11 jen na základě těchto dat.

### 11.4 Korelace nezávislosti

- **Metrika:** počet C3 blockerů missnutých C2; počet nezávisle replayovaných traces vs počet PASS artefaktů.
- **Účel:** detekovat correlated self-confirmation (více agentů sdílí stejnou chybnou premisu).

---

## 12. Negativní regression fixtures (konsolidováno)

Každá známá historická díra se stává trvalým negativním fixturem. Žádný se nesmí po opravě znovu otevřít.

| Fixture | Reprodukuje | Očekávaný výsledek | Etapa |
|---|---|---|---|
| **E-047-1** | shared contract builduje sám, server importuje odstraněný dep, další fáze importuje chybějící symboly, vacuous typecheck, zero-test workspace | C1 fail (DG-05/06/08/09), C2 final fail, C3 blocking, C4 false | E2, E10 |
| **E-047-4** | analytics dropne reálné plány, ale synthetic fixtures projdou | DG-17 fail, frontend_user_outcome fail | E6, E10 |
| **E-047-5** | WS/polling hooks existují, ale shell je nemountuje; server emituje nested `data`, GUI čte top-level; `/plan/` vs `/plans/` | DG-13/DG-14/DG-15 fail | E6, E7, E10 |
| **E-044** | commit po endpoint return, cleanup kolem flush ne commit, UI message vs detail, 8 testů kde 2 scénáře chybí, 403→401 drift | C1 DG-14 response-shape fail + C2 semantic/acceptance fail, C3 blocking, C4 false | E5, E6, E10 |
| **P045** | dvouuzlový cyklus skrytý v próze, identifier ve 3 doménách, ORM field cizího modelu, reuse s immediate POST, unversioned dep + old API, fail-open idempotency vs at-most-once | CP1 graph/identifier/reuse/call/dep/idempotency fail, EPIC generace blokována | E4, E10 |
| **P048 visual** | un-applied delta, locked color change, capture-absent, gestalt mismatch | delta_not_applied / locked_violation / unverifiable / ui_gestalt_unapproved | E7 |
| **false-ready state** | parent DONE při pending child step, active counter, `compliance.overall:fail` | DG-07/C4 fail | E2, E8 |

---

## 13. Rozhodnutí PM (schváleno 2026-06-22)

**STATUS: všech R1-R8 schváleno PM dne 2026-06-22 podle doporučeného balíku.** Níže je závazné znění; pod ním zůstává původní zdůvodnění jako záznam. Tato rozhodnutí spolu se schváleným E0 topology verdict budou vstupem do formálního AID plánu; nejsou to otevřené otázky.

| # | Rozhodnutí (schváleno) |
|---|---|
| R1 | Blokovat na **Critical + High**. |
| R2 | Required `unverifiable` **blokuje**; waiver musí být **explicitní a auditovaný**. |
| R3 | C2 security lens **risk-based**; `/aid-do` fast profil pro produkci **risk-based blokující**. |
| R4 | P048 verdikt **blokuje krok (EXECUTE) i vstupuje do C4 přes C1**; release autorita zůstává C4. |
| R5 | Consumption proof **jen pro detector-required / non-empty kontrakt**. |
| R6 | Kalibrační kandidáty (2-3 reálná UI selhání) **navrhne agent, PM potvrdí před E7A**; **E7-CAL musí PASS před E7B**. |
| R7 | **E7A může začít po E3**; **E7B až po E6 a E7-CAL**. |
| R8 | Legacy evidence **jen forward / read-only, bez sémantického backfillu**. |

Původní zdůvodnění (záznam):

**R1 - Block severities.**
Blokovat na Critical + High (doporučeno, dle Doc-1 §17), nebo jen Critical? High zahrnuje věci jako "removed dep with remaining import". ⭐ **Doporučení: Critical + High.**
*Důvod: většina E-047 defektů byla High, ne Critical; blokování jen Critical by je propustilo.*

**R2 - `unverifiable` jako blokující.**
Required check, který nelze spustit (chybí runtime, malformed evidence), blokuje (doporučeno), nebo propouští s varováním? ⭐ **Doporučení: blokující pro required, s PM waiver cestou.**
*Důvod: "neznámý ekosystém → PASS" byla díra v E-047 (zero-test workspace exit 0).*

**R3 - CP3 security a CP6 mód.**
Risk-based (doporučeno), always, nebo disabled? Risk-based ušetří náklady na docs/types, ale spoléhá na detektor. ⭐ **Doporučení: risk-based pro CP3 security, risk-based blokující pro CP6 produkce.**
*Důvod: dnešní unconditional dual dispatch dělá low-value review pro types/docs a stejně mine integraci.*

**R4 - P048 step-local hard-fail vs jen delivery evidence.**
Má `frontend_visual_fidelity` FAIL blokovat i increment-step jednoho kroku (jako CP2), nebo jen téct do delivery-gate/CP5? ⭐ **Doporučení: oboje - step-local block v EXECUTE (rychlá zpětná vazba) + delivery evidence pro release. Release autorita zůstává CP5.**
*Důvod: PM zadání zakazuje druhou release autoritu ve FSM, ne step-local kontrolu; CP2 funguje stejně.*

**R5 - Rozsah consumption proof.**
Má implementátor prokazovat spotřebu kontraktu u každého kroku, nebo jen u kroků s netriviálním kontraktem (UI, public API, high-risk)? ⭐ **Doporučení: jen u kroků s deklarovaným kontraktem (contract-manifest non-empty); ostatní prázdné pole validní.**
*Důvod: vyhnout se ceremonii u čistě interních kroků, konzistentní s CP2 consumer-array logikou.*

**R6 - Kalibrační dataset pro E7-CAL a E10.**
P048 má HARD precondition: 2-3 reálné selhané UI implementace před wiring částí (E7B). Kdo a kdy je vybere? ⭐ **Doporučení: PM vybere konkrétní case z historie (WAN/Sousto/cockpit) před E7A; E7-CAL proběhne po foundation a musí PASS před E7B.**
*Důvod: hermetic fixture dokáže jen plumbing; cross-stack determinismus je nutné ověřit na reálném stacku.*

**R7 - Pořadí E6 vs E7.**
DG-13..18 (E6) před P048 integrací (E7), nebo P048 jako pilot vzoru první? ⭐ **Doporučení: E6 před E7 dle sekvence, ale P048 `ui-compare.mjs` posloužit jako referenční vzor "deterministický check → evidence → CP5" už při návrhu DG-13..18.**
*Důvod: DG-13/14/15 (reachability, wire, route) jsou obecnější a P048 z nich těží.*

**R8 - Hloubka GUI obálky pro legacy artefakty.**
Backfillovat protokol v2 obálku na historickou evidence (jako u compliance backfill), nebo jen forward? ⭐ **Doporučení: jen forward; legacy dostane `protocol_version:"legacy"`, GUI zobrazí read-only.**
*Důvod: backfill sémantiky (severity, finding IDs) na staré .md reporty je nespolehlivý a drahý.*

---

## 14. Co tento plán záměrně NEdělá (non-goals)

- Nenahrazuje projektové testy generickými Delivery Gate checky.
- Nedělá z každého C2 mode plný repository audit.
- Nepouští každý příkaz pro každou docs-only změnu.
- Nepoužívá LLM skóre jako release rozhodnutí.
- Nedělá z Curatora dalšího code reviewera.
- Neimplementuje cockpit/evidence-lifecycle GUI (mimo scope); jen připravuje datový kontrakt.
- Negarantuje korektnost z jedné kontroly - spoléhá na odlišné, neduplicitní vrstvy.
- Neodstraňuje PM waivery; zůstávají explicitní, scoped, auditovatelné.

---

## 15. Doporučené pořadí další práce

R1-R8 a T1-T6 jsou schválené; E0 i formální roadmapa jsou hotové. Další kroky jsou:

1. **E1 executable plán:** použít session prompt z `docs/plans/AID-control-system-v2-session-prompts.md`; nevytvářet plány pro E2-E11 předem.
2. **E1 implementace:** schémata + protokol podle minimální C0-C4 topologie, bez runtime změny.
3. **E2** (C1 core + DG-07 state hardening) v observe.
4. **E3** (review profil detektor) v observe.
5. **E4** (C0 + contract handoff producer) - plánovací kvalita a policy-gated consumption hook.
6. **E5** (C2 + autoritativní consumption/acceptance evidence), **E6** (DG-13..18 C1 plugins), **E7A → E7-CAL → E7B** (P048 lenses/plugin).
7. **E8** (C3 + Curator + affected re-run), **E9** (C4 + fast profile + komunikace), **E10** (kalibrace), **E11** (cutover + další datově podložené zjednodušení).

E0 odstraní zjevnou procesní redundanci ještě před implementací. E1-E4 postaví společný základ. E5-E9 přidají sémantickou, vizuální, nezávislou a release vrstvu bez nových paralelních mechanismů. E10-E11 ověří účinnost a odstraní jen redundance, které bylo možné posoudit až z provozních dat.

---

*Tento dokument je schválený master design. Autoritativní pořadí provedení a session prompty jsou v `docs/plans/AID-control-system-v2-roadmap.md`; implementovat vždy pouze aktuálně schválenou fázi.*
