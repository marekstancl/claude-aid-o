---
type: roadmap
status: draft
created: 2026-06-22
author: PM + AI
design_source: docs/AID-control-system-v2-unified-refactor-PLAN.md
topology_source: docs/design/AID-control-system-v2-control-topology.md
note: "Roadmap (multi-fázový master plán). NEkonzumuje plan ID, NEspouští se přímo přes /aid-run. Každá fáze se stane samostatným executable plánem přes Session Prompt, až se staví."
---

# AID Control System v2 - Roadmap (formální AID plán)

## Stakeholder Brief

AID dnes umí prohlásit práci za hotovou, aniž by prokázal, že výsledek jde sestavit, je vnitřně kompatibilní a skutečně dělá to, co bylo schváleno. Tento plán to opravuje jako jeden provázaný kontrolní systém v2 postavený na **pěti mechanismech** (C0 Plan Contract Gate, C1 Delivery Engine, C2 Semantic Review Engine, C3 Independent Audit, C4 Release Policy) místo dnešních šesti volně provázaných checkpointů. Cílem je, aby každá známá třída selhání měla právě jednoho majitele, deterministické kontroly byly oddělené od LLM úsudku, a release rozhodovala jediná autorita. Práce je rozdělená do 12 bezpečných fází (E0 hotová, E1-E11 čekají), kde každá uzavírá konkrétní reálnou cestu k falešně zelenému výsledku a navazuje na předchozí. Nové preconditiony se nejprve zapojují v observe/dual-run a obecně blokují až po kalibraci; P048 má vlastní dřívější promotion až po povinné E7-CAL. Výstupem nejsou izolované opravy, ale jeden systém s versionovaným protokolem artefaktů připraveným pro budoucí GUI. Hlavní riziko - tichý nárůst kontrol bez nárůstu jistoty - hlídá E0 topology challenge, který je už schválený. Tento dokument je roadmap: každá fáze se mění na samostatný spustitelný AID plán teprve ve chvíli, kdy se začne stavět, takže nevzniká 11 plánů najednou.

## Context

Vznik plánu si vyžádaly tři vstupní audity a jedna reálná řada incidentů:

- `docs/AID-CP1-CP6-review-instruction-audit-and-refactor.md` (Doc-1) - mechanická nedoručitelnost a rozbité producer-consumer kontrakty (Delivery Gate DG-01..18, adaptivní profily, IR kadence, release policy).
- `docs/AID-CP1-CP6-review-instruction-audit-second-opinion.md` (Doc-2) - sémantické cross-boundary selhání (acceptance-evidence, behavior traces, fault injection, CP1 plan-executability).
- `.aid-o/plans/P048-ui-design-to-code-fidelity-mvp.md` (P048) - frontendová vizuální fidelita.

Plný grounded audit současného stavu, konflikty/překryvy vstupů, cílová architektura, role matrix, artefakty, protokol v2, migrace a měření jsou v master design dokumentu `docs/AID-control-system-v2-unified-refactor-PLAN.md`. Topologie pěti mechanismů a důkaz minimality (44 failure classes → majitelé) jsou v `docs/design/AID-control-system-v2-control-topology.md` (E0, schváleno PM 2026-06-22).

Tento roadmap je **AID-konzumovatelná** projekce těch dvou dokumentů: nepřepisuje jejich detail, ale strukturuje práci do fází se session prompty.

## Goal

Nahradit dnešní CP1-CP6 + Auditor + Curator + gates jedním kontrolním systémem v2 z pěti mechanismů C0-C4, který deterministicky prokáže doručitelnost, sémanticky ověří chování, nezávisle audituje rizikové dodávky a rozhoduje release přes jedinou autoritu - postaveno v bezpečných, kalibrovaných fázích.

## Scope

**In scope:**
- Pět mechanismů C0-C4 a jejich modes/lenses/pluginy dle E0 topologie.
- Versionovaný protokol v2 artefaktů (GUI-ready, GUI není podmínka).
- Začlenění P048 jako frontendové větve (C1 visual fidelity plugin + C2 user_outcome lens), ne druhá release autorita.
- Observe/dual-run, kalibrace na E-047-1/4/5, E-044, P045, řízený cutover.
- Compatibility vrstva (staré CP názvy jako read-only aliasy).

**Out of scope:**
- Cockpit / evidence-lifecycle GUI (jen datový kontrakt se připravuje).
- Big-bang přepis (zakázán principem).
- Per-fáze executable plány tvořené předem (tvoří se až při stavbě dané fáze přes session prompt).

## Approach

**Zvolený přístup: failure-class-first, ne checkpoint-first.** Systém se navrhuje podle otázky "jaké odlišné failure classes musí zachytit a kde je jejich nejčasnější levný enforcement point", ne "jak vylepšit CP1-CP6". To vedlo k pěti mechanismům místo třinácti vrstev nebo šesti nových systémů.

**Hierarchie levnosti enforcementu:** C0 plan-time > C1 deterministic > C2 semantic LLM > C3 independent audit. Failure class patří nejlevnějšímu majiteli, který ji spolehlivě chytí.

**Bezpečné fázování:** schémata a deterministická vrstva první (lze observovat bez rizika), instrukční refaktor a release autorita až po kalibraci. Každá nová FSM precondition je od začátku policy-gated (`observe|dual_run|blocking`); v observe režimu zapisuje `would_block`, ale nemění živý přechod. Výjimkou je P048 E7B, které smí zapnout svůj step-local block po vlastní povinné E7-CAL. Ostatní v2 kontroly se promují až v E10/E11.

**Alternativy zamítnuté v E0:** big-bang přepis (riziko), přepis CP1-CP6 do šesti nových systémů (zbytečné zdvojení - prokázáno overlap maticí), jeden obří prompt všem reviewerům (correlated self-confirmation).

## Architecture

Pět mechanismů, jedna release autorita. Detail v `docs/design/AID-control-system-v2-control-topology.md` a `control-topology.yaml`.

| Mechanismus | Odpovědnost | Typ | Vlastní failure classes |
|---|---|---|---|
| **C0 Plan Contract Gate** | Je záměr proveditelný, jednoznačný, úplný, ověřitelný? | deterministic struct + semantic plan review | FC-01..08 (8) |
| **C1 Delivery Engine** | Lze revizi sestavit/spustit/mechanicky prokázat? | deterministic engine s plugin katalogem | FC-10..23, FC-29, FC-33, FC-34, FC-40, FC-41 (19) |
| **C2 Semantic Review Engine** | Odpovídá chování schválenému outcome napříč hranicemi? | jeden LLM reviewer v modes local/wiring/behavior/final | FC-09, FC-24..28, FC-30..32, FC-35 (10) |
| **C3 Independent Audit** | Dokáže nezávislý čerstvý reviewer vyvrátit PASS claim? | risk-gated adversariální agent, provider-neutral | FC-37 (1) |
| **C4 Release Policy** | Jsou všechny profilem vyžádané aktuální důkazy bez blockerů? | deterministic aggregator, jediná release autorita | FC-36, FC-38, FC-39, FC-42, FC-43, FC-44 (6) |

**Mapování starých CP názvů:** CP1→C0; CP2/IR-1/IR-2/CP3→C2 modes; CP4→invalidace+re-run C1/C2; CP5→C4; CP6→fast profil. Curator/Reporter/Simplifier = utility, žádná autorita. Staré názvy jsou read-only aliasy (T4).

## Constraints

Závazná rozhodnutí PM (nesmí se v executable plánech porušit):

**Schválená rozhodnutí R1-R8 (2026-06-22):**
- R1: blokovat na **Critical + High**.
- R2: required `unverifiable` blokuje; waiver explicitní a auditovaný.
- R3: C3 security risk-based; fast profil produkce risk-based blokující.
- R4: P048 verdict blokuje krok (EXECUTE) i vstupuje do C4; release autorita zůstává C4.
- R5: consumption proof jen pro detector-required / non-empty kontrakt.
- R6: kalibrační kandidáty navrhne agent, PM potvrdí před E7A; E7-CAL musí PASS před E7B.
- R7: E7A může začít po E3; E7B až po E6 a E7-CAL.
- R8: legacy evidence jen forward / read-only, bez sémantického backfillu.

**Schválená rozhodnutí T1-T6 (E0 topology, 2026-06-22):**
- T1: dispatch budget = tvrdý strop **rozhodovacích kol** (ne tvrzení o ceně), PM-waiver výjimka.
- T2: C3 jen high/mixed/security/data-loss/release-process.
- T3: **4** defense-in-depth dvojice (FC-20, FC-33, FC-34, FC-36); FC-29 odstraněna jako duplicita.
- T4: CP názvy jen read-only aliasy, žádná vlastní autorita.
- T5: security split - deterministická dep-audit → C1, threat-model úsudek → C2.
- T6: účtovat rozhodovací kola **i** skutečná model calls / tokeny / wall time (včetně lens fan-outu); numerické stropy se kalibrují v E10.

**Architektonické principy (`docs/plans/AID-v3-principles.md`):**
- Detector without Enforcement is Decoration - každá detekce má pojmenovaný enforcement mechanismus už v designu.
- Deterministické ≠ LLM - LLM nikdy nepřevede deterministický fail na pass.
- Jedna release autorita (C4).
- Jeden mode = jedna rozhodovací autorita; lenses se mohou fan-outovat do více měřených model calls, ale nevytvářejí další autoritu ani obří prompt.
- **Nový evidence systém je cesta ke ZRYCHLENÍ, ne trvalá vrstva navíc.** Cílový stav NENÍ CP1-CP6 + C0-C4 paralelně navždy: paralelní běh je jen přechodová fáze do E10 kalibrace. Současná pomalost pramení z držení starého i nového zároveň + z ručního dověřování (per-step prověrky, ruční CP1-deep, nezávislé verify-plan runy), kterým se supluje to, čemu pipeline zatím neumí věřit sama. Po E10 promotion (observe→blocking) a E11 cutoveru: v2 JSON artefakty = autorita, markdown CP výstupy jen lidské summary, duplicitní staré gates vypnuté, ruční scaffolding zmizí - méně kontrol, ale tvrdších a adaptivních dle profilu rizika. Pozor: staré kontroly se NEvypínají dřív, než nová vrstva na E10 datech prokazatelně pokryje jejich odpovědnost - jinak si jen zrychlíme cestu k falešně zeleným mergům.

## Data Model

Kanonická evidence žije pod `.aid-o/work/evidence/{epic_id}/{run_id}/`. Všechny JSON artefakty používají protokol v2 obálku s identitou, subject hash, HEAD/revision, stavem, stabilními finding ID, provenance a lidským shrnutím. Autoritativní agregace jsou pouze `delivery_ready` z C1 a `release_ready` z C4. Úplný katalog producentů a spotřebitelů je v master plánu §5; E1 musí pokrýt nejméně `contract-manifest`, `plan-review`, `plan-graph`, `review-profile`, `delivery-gate`, `semantic-review`, `acceptance-evidence`, `gates-report`, `audit-input-manifest`, `audit-report`, `curator-report`, `invalidation-map`, `ui-verdict`, `delivery-report`, `waiver`, `release-decision` a `pm-decision-brief`.

## API Design

Tato roadmapa nepřidává síťové API. Veřejným rozhraním jsou CLI/FSM příkazy, JSON schémata a exit kódy. Skripty C1/C4 jsou deterministické, C2/C3 adaptéry produkují schema-valid výstup a FSM konzumuje pouze profilem vyžádané, aktuální a hashově svázané artefakty. CP1-CP6 názvy zůstávají jen read-only compatibility aliasy.

## Implementation Phases

Fáze E0-E11. E0 je hotová a schválená. Každá další se mění na executable plán přes Session Prompt (níže). Plný obsah, acceptance kritéria a negative fixtures každé fáze jsou v master plánu `docs/AID-control-system-v2-unified-refactor-PLAN.md` §10.

**EPIC 0: E0 - Control Topology Challenge** ✅ HOTOVO (schváleno 2026-06-22)
Důkaz, že topologie C0-C4 je nejmenší sada pokrývající 44 failure classes. Výstupy: `docs/design/AID-control-system-v2-control-topology.md`, `control-topology.yaml`, `failure-mode-control-matrix.json`. Žádná runtime změna.

**EPIC 1: E1 - Protokol v2, schémata, GUI kontrakt, enforcement registry**
Sdílená obálka + type-specific schemas pro každý artefakt; deterministický finding fingerprint; per-run `control_protocol` lock; bez změny runtime chování. Odblokuje vše ostatní.

**EPIC 2: E2 - C1 Delivery Engine core (DG-01..12) + FSM state hardening**
Deterministická delivery vrstva v observe módu; implementuje policy-gated DG-07 false-DONE rozhodnutí (FC-22). V testu `blocking` přechod zastaví, v živém výchozím `observe` pouze zapíše `would_block`. Negative fixtures: multer (FC-11), vacuous typecheck (FC-14).

**EPIC 2.5: E2.5 - Evidence Pack Verifier CLI** (vsuvka mezi E2 a E3)
Deterministický standalone CLI `aid-evidence-verify.sh`, který automatizuje ruční DONE-ověření evidence packu (git clean, per-artefakt as-of-pack freshness, protokol-v2 validace + fingerprint, TTL/registry, observe-vs-blocking interpretace) → `verification-report.json` (15. protokol-v2 typ) + lidské shrnutí. Bez LLM, bez FSM wiringu; napojení do C4 release policy je E9. Použije se zpětně na E2 i na každou další fázi. Plán P051.

**EPIC 3: E3 - Adaptivní review profil detektor (observe)**
Profile resolver: plan-time + candidate-time union (FC-41), detektor vlastní applicability, `profile_hash`. Strop autorit per profil. Plán P052.

**EPIC 4: E4 - C0 Plan Contract Gate + contract handoff + consumption proof**
Plan-graph, identifier-domain, reuse-compat, planned-call, dep-API, idempotency, authority matrix; hashovaný contract-manifest a policy-gated FSM hook. E4 vytvoří producer kontrakt a `pending/unverifiable` consumption slot; autoritativní C2 local validaci FC-09 doplní až E5. Negative fixture: kompletní P045 plán musí selhat v C0 evaluaci; živé blokování zůstává do promotion v observe.
**Vstup z E3 (P052):** E3 dělá jen *best-effort* plan-time surface extrakci (definovaná Files sekce, jinak `[]`); **autoritativní strukturovaný plan-time kontrakt = E4** (contract-manifest s hashovanými cestami feeduje profile resolver místo best-effort parsování).

**EPIC 5: E5 - C2 Semantic Review Engine (local/wiring/behavior/final) + acceptance-evidence**
Jeden engine, jedno schema, čtyři modes; lenses fan-out bez nové rozhodovací autority a se samostatným resource accountingem; policy-gated `wiring` precondition; acceptance-evidence rekonstrukce. Negative fixture: E-044.
**Vstup z E3 (P052):** E3 jen *deklaruje* `required_lenses` a v observe loguje `missing_lenses` (`completed_lenses` je v E3 vždy prázdné). **E5 musí:** (1) emitovat lens-completion markery, aby `completed_lenses` mělo reálný zdroj; (2) v C2 artefaktech opakovat `profile_hash`; (3) zapnout profil-change invalidaci neúplné starší evidence podle `profile_hash` (E3 hash jen vyrobil, neinvaliduje).

**EPIC 6: E6 - C1 DG-13..18 (wiring, wire, route, fallback, oracle, acceptance struct)**
Sémanticky-hraniční deterministické probes (FC-20, FC-21, FC-29, FC-33, FC-34). Negative fixtures: E-047-5, E-047-4.

**EPIC 7: E7 - P048 frontend větev (E7A → E7-CAL → E7B)**
E7A foundation (capture/compare/contract, hermetic) → E7-CAL povinná kalibrace na 2-3 PM-schválených reálných selháních → E7B wiring (Visual Companion, gestalt, transport, user_outcome lens). C1 visual fidelity plugin + C2 user_outcome lens, ne FSM release autorita.

**EPIC 8: E8 - C3 Independent Audit + Curator sequencing + affected re-run**
Risk-gated nezávislý audit (provider-neutral, independence levels), mechanicky odvozené `blocking_findings` (Critical OR High); Curator po C3; CP4 → invalidace+re-run C1/C2 bez nového reviewera.

**EPIC 9: E9 - C4 Release Policy + fast profile + PM communication**
Jediná release eligibility autorita → `release-decision.json`; `/aid-do` fast profil stejných enginů; PM brief sekvenčně z release-decision (žádný cyklus); opravený Reporter s controlled runner.
**Vstup z E3 (P052):** freshness ověření `profile_hash` (že review evidence vznikla proti aktuálnímu profilu) je C4/E9 odpovědnost (`freshness_verified_by: C4` v topologii); E3 hash jen vyrobil.
**Vstup z E8 (P057), odloženo do E9/C4 — viz BACKLOG.md „E8 Deferred":** (1) **skutečné odstranění/nahrazení Curator merge-authority** (auto-approve `recommended_disposition`, FC-38) - E8 udělalo jen sequencing+vocabulary, protože merge-influence je release-policy teritorium a sdílený kontrakt s gate-fixer/simplifier; (2) **C4 konzumace** `audit-report.json` + `curator-report.json` + `invalidation-map.json` do `release-decision.json`; (3) **UI verdict** z E7 (`frontend_visual_fidelity` → delivery-gate → release).

**EPIC 10: E10 - Kalibrace na známých selháních + dual-run metriky**
Kompozitní regression fixtures E-047-1/4/5, E-044, P045; měření false-DONE/false-positive/nákladů; numerické budget stropy; promotion observe→blocking. Toto teprve prokáže, že systém kontroluje stejně dobře jako nezávislý audit.

**EPIC 11: E11 - Řízený cutover + datově podložené zjednodušení**
Cutover blocking; odstranění redundancí potvrzených až provozními daty (E0 už sloučil zjevné duplicity).

**Pořadí závislostí:** E1 → E2/E3 (observe); E4 po E3; E5 po E2+E4; E6 po E5. E7A může běžet po E3 paralelně s E4-E6, E7-CAL po E7A a E7B až po E6+E7-CAL. E8 core může začít po E6, ale UI audit aktivuje až po E7B. E9 vyžaduje E8+E7B; potom E10 → E11. E1-E4 = první **základní/prerequisite slice**, nikoli první živě blokující slice.

## Commands for Detailed Plan Generation

> **DŮLEŽITÉ:** Před napsáním plánu každé fáze musí writer:
> 1. přečíst aktuální stav dotčených souborů v `plugins/aid-orchestrator/`,
> 2. porovnat, co master plán a topologie očekávají, vs co reálně existuje,
> 3. identifikovat stuby/placeholdery vs funkční kód,
> 4. přizpůsobit plán realitě - nepřepisovat funkční, opravit rozbité.
>
> Každá fáze se generuje až ve chvíli, kdy se začíná stavět (ne všechny najednou).
>
> Detailní copy-paste prompty: `docs/plans/AID-control-system-v2-session-prompts.md`.

## Session Prompts for Detailed Plans

Každý blok zkopíruj do nového Claude Code okna, až přijde řada na danou fázi. Fáze stav před sebou: E0 hotová.

### E1 - Protokol v2 a schémata

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E1: Protokol v2 a schémata
```
**Context pro writer:** Napiš executable plán pouze pro fázi E1 (master plán §10 → E1). Cíl: `aid-protocol-v2.schema.json` + type-specific schemas pro všechny artefakty z Data Model sekce této roadmapy; deterministický finding fingerprint; per-run `control_protocol` lock; enforcement-registry zápis do `defaults/enforcement-registry.yaml` (NE superseded seed). Žádná runtime změna - jen schémata + dokumentace. Reference: master §5/§7 a `control-topology.yaml`. Acceptance + negative fixtures dle master §10 E1.

### E2 - C1 Delivery Engine core + FSM state hardening

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E2: C1 core a FSM state hardening
```
**Context pro writer:** Executable plán pro E2. Cíl: `aid-delivery-gate.sh` (DG-01..12), `aid-delivery-profile.sh`, `delivery-gate.yaml`, argv-array exec; policy-gated FSM hardening proti false-DONE. Výchozí živý režim `observe` zapisuje `would_block`; fixture s `enforcement:blocking` musí přechod zastavit. Reference: Doc-1 §5 DG-01..12, master §9.1/§10 E2, `control-topology.yaml` C1 plugin_catalog. Vstup: E1 schémata. Negative fixtures: multer FC-11, vacuous typecheck FC-14, manifest/lock mismatch.

### E3 - Adaptivní review profil detektor

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E3: Adaptivní review profil
```
**Context pro writer:** Executable plán pro E3. Cíl: profile resolver - plan-time z deklarovaných surfaces + candidate-time ze skutečného diffu, autoritativní profil = monotónní union (FC-41); `review-profiles.yaml` surface→lens matrix; `profile_hash`; strop autorit per profil (T1). Observe mód. Reference: master §10 E3, `control-topology.yaml` risk_profiles. Vstup: E1.

### E4 - C0 Plan Contract Gate + contract handoff

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E4: C0 a contract handoff producer
```
**Context pro writer:** Executable plán pro E4. Cíl: C0 struct checks + semantic lenses, hashovaný contract-manifest, implementátor item→change/evidence návrh a policy-gated FSM precondition interface. E4 nevydává autoritativní consumption PASS, protože C2 local vzniká až v E5; do té doby je stav `pending/unverifiable`. C0/EPIC precondition se zapojí v observe a blocking chování se ověří fixturem. Reference: Doc-1 §6.1, Doc-2 §11.2-11.7, master §9.1/§10 E4. Negative fixture: P045.

### E5 - C2 Semantic Review Engine + acceptance-evidence

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E5: C2 Semantic Review Engine
```
**Context pro writer:** Executable plán pro E5. Cíl: jeden C2 engine, jedno `semantic-review.json` schema, modes local/wiring/behavior/final; dokončit FC-09 consumption validaci nad E4 manifestem; lens fan-out, deterministický lossless finding merge; policy-gated wiring precondition; acceptance-evidence; risk-based security lens; T6 accounting. Negative fixture E-044 pro transaction boundary, field lineage, AC-to-test a requirement drift. Response shape FC-29 patří C1/E6, ne C2. Reference: master §9.1/§10 E5 a `control-topology.yaml` C2.

### E6 - C1 DG-13..18 deterministické sémanticko-hraniční probes

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E6: C1 DG-13 až DG-18
```
**Context pro writer:** Executable plán pro E6. Cíl: C1 pluginy production_reachability (DG-13, FC-20), wire_shape_deterministic (DG-14, FC-29), route_resolve (DG-15, FC-21), fallback_forced_failure (DG-16, FC-33), independent_oracle_nodrop (DG-17, FC-34), acceptance_struct (DG-18). Reference: Doc-1 §5 DG-13..18, master §10 E6. Negative fixtures: E-047-5 (unmounted/wire-drift/route), E-047-4 (analytics drop).

### E7 - P048 frontend větev (E7A → E7-CAL → E7B)

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E7: P048 frontend větev
```
**Context pro writer:** Executable plán pro E7 ve třech povinných podetapách. Agent navrhne 2-3 reálné kalibrační případy a PM je potvrdí před E7A (R6). E7A foundation bez blocking FSM; E7-CAL musí PASS; teprve E7B smí zapnout P048 step-local block. E7B zapojí Visual Companion capture/gestalt, role card, contract transport, `ui/verdict.json`, `/aid-do` redirect a `frontend_user_outcome`. P048 není release autorita. Před generací append-only amendment do P048. Reference: master §8/§10 E7.

### E8 - C3 Independent Audit + Curator + affected re-run

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E8: C3 audit a affected re-run
```
**Context pro writer:** Executable plán pro E8. Cíl: provider-neutral C3 audit a independence levels, hash-bound manifest/provenance, mechanické `blocking_findings`, Curator sequencing a affected re-run bez CP4 reviewera. Referenční externí backend je Codex CLI přes `codex exec`, ale E8 musí detekovat schopnost jej spustit mechanicky (`command -v codex`, `codex exec --help`/sanity run, auth OK, schema-valid output); nesmí spoléhat na self-awareness modelu o tom, zda běží v CLI, IDE nebo jiném povrchu. E8 fixture musí prokázat High→blocking, nedostupný required reviewer → `unverifiable`, a neautoritativní PASS bez provenance; C4 konzumaci ověří až E9, protože C4 zde ještě neexistuje. Reference: Doc-2 §8, master §10 E8, `control-topology.yaml` C3.

### E9 - C4 Release Policy + fast profile + PM communication

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E9: C4 release a PM komunikace
```
**Context pro writer:** Executable plán pro E9. Cíl: `aid-release-policy.sh` → `release-decision.json` (deterministic aggregator, jediná release autorita); FSM MERGE jen na release_ready:true + HEAD match + `aid-pm-brief.sh --validate` success; PM brief se generuje AŽ z release-decision (žádný cyklus - `pm_brief_is_release_input: false`); `/aid-do` fast profil stejných C1/C2/C4 bez vlastní autority; opravený Reporter s `aid-reporter-run.sh` controlled runner; waiver bez PASS rewrite. Reference: Doc-1 §6.6, master §7.6 + §10 E9, `control-topology.yaml` C4 pm_handoff_sequence. Negative fixtures: 17 CP/FSM testů z Doc-1 §13.2.

### E10 - Kalibrace + dual-run metriky

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E10: Kalibrace a dual-run metriky
```
**Context pro writer:** Executable plán pro E10. Cíl: kompozitní regression fixtures E-047-1/4/5, E-044, P045; `aid-control-metrics.sh` (false-DONE/false-positive/náklady); dual-run nový vs starý proces; numerické budget stropy (T6); promotion observe→blocking dle empirického kritéria + negative fixtures + positive controls. Toto teprve prokáže, že systém kontroluje stejně dobře jako nezávislý audit. Reference: master §10 E10 + §11-12. Vstup: E1-E9.
**Tvrdé preconditions promotion (⚠️ NEZAPOMENOUT):** (1) promotion observe→blocking NESMÍ proběhnout, dokud není vyřešena **stale doprava instrukcí agentům — IMP-179** (`.aid-o/work/backlog.md`; subagent system prompty nepřečtou změnu `agents/*.md` v téže session - dogfood důkaz E-057-2_2) **+ marketplace plugin cache drift** (`docs/plans/2026-06-29-BACKLOG.md` „STALE PLUGIN CACHE", 2026-07-08) - jinak blokující brány poběží se zastaralými instrukcemi; E10 musí rozhodnout fix mechanismus (dispatch-time freshness hash check / restart-požadavek / hot-reload potvrzení). (2) Ověřit metrikami, že **C3 gate reálně naskočil v živých runech** (IMP-177 zavírá E9/P059 EPIC 1 - C3 activation; E10 potvrdí nenulový počet `c3_hook_fired` runů, jinak promotion C3/C4 nemá data). (3) **Pre-E10 hygiene blok (P060)** musí být DONE před E10 kalibrací - 8 potvrzených false-green/stale-evidence oprav legacy vrstvy (gates count, undefined gate, CP3 freshness, CP2 range, cache preflight, commit-path guard, queue revalidace, C4 at-head hardening); bez nich E10 měří zkreslená data. Detail: `docs/plans/2026-06-29-BACKLOG.md` „Pre-E10 control hygiene block" (2026-07-10).

### E11 - Řízený cutover + zjednodušení

```
/aid-plan write docs/plans/AID-control-system-v2-roadmap.md E11: Cutover a zjednodušení
```
**Context pro writer:** Executable plán pro E11. Cíl: cutover blocking; odstranění redundancí s prokázanou nulovou unique detekcí v E10 datech; escaped-defect tracking; legacy runy netknuté (R8). Reference: master §10 E11. Vstup: E10 data.
**De-duplication & speed acceptance (PM 2026-07-10, závazné — ⚠️ E11 bez tohoto NENÍ hotové):** C0-C4 nesmí být trvalá další vrstva. E11 MUSÍ obsahovat: (1) **inventář všech legacy mechanismů** (CP checkpointy, Auditor, Curator, Reporter, Simplifier) s explicitním rozhodnutím per mechanismus: `remove` | `replace_by_c0c4` | `keep_risk_gated` | `keep_alias_only` — podložené E10 unique-detection daty; (2) **acceptance metriky před/po**: dispatch count per EPIC, wall-clock čas pipeline, počet LLM review kroků; (3) **pokud se celkový počet kontrol nesníží, E11 není hotové.** Poznámka Curator (ověřeno 2026-07-10): žádný dokument neslibuje odstranění role — závazný stav je `utility_only`/`authority: none` (topologie E0) + FC-38 (neutralizace auto-approve merge-influence) patří k E10 promotion; o osudu role rozhodne tento inventář, ne implicitně cutover.

## Risks

| Riziko | Pravděpodobnost | Dopad | Mitigace |
|---|---|---|---|
| Tichý nárůst kontrol bez nárůstu jistoty | M | H | E0 Control Necessity Test + tvrdý strop rozhodovacích kol (T1); duplicitní reviewer se odmítne |
| C2 lens fan-out skryje neomezené LLM volání | M | H | T6 resource accounting (model calls/tokeny/čas včetně fan-outu); numerické stropy v E10 |
| Nová blokující kontrola false-blockuje legitimní změnu | M | M | observe → dual-run → blocking; positive controls per profil; promotion gate < 5 % false-block |
| E0 minimalita dokázaná jen vůči 44 známým třídám | M | M | E10 kalibrace na historických selháních + nové escaped defect → trvalý fixture |
| P048 cross-stack determinismus selže na reálném stacku | M | M | E7-CAL hard gate na 2-3 reálných selháních před E7B |
| Velký rozsah (12 fází) → drift mezi roadmap a executable plány | M | M | session prompty self-contained; writer čte reálný stav před každou fází |

## Testing Strategy

- Operativni review flow pro kazdy dalsi plan/EPIC v serii je popsany v
  `docs/AID-control-system-v2-verification-operating-note.md`. Po E-050
  je povinne rozlisit plan-time, EPIC-time, fix-loop a release-time kontrolu.
- Každá fáze má vlastní negative fixture a positive control; fixture ověřuje i `observe` a simulovaný `blocking` režim.
- E2-E9 sbírají baseline v observe/dual-run. E7B je jediná před-E10 výjimka a smí blokovat až po E7-CAL.
- E10 spouští kompozitní historické případy E-047-1/4/5, E-044 a P045, měří false blocks i skutečné LLM náklady a rozhoduje o promotion.
- E11 provede cutover pouze pro checky splňující promotion kritéria; escaped defect vždy vytvoří nový trvalý fixture.

## Migration Plan

V2 artefakty jsou forward-only a legacy evidence zůstává read-only. Nové preconditiony jsou aditivní a policy-gated; během observe/dual-run zůstávají dnešní kontroly aktivní. Rollback znamená přepnutí konkrétního v2 checku z `blocking` zpět na `observe`, nikoli mazání evidence nebo okamžitý návrat starých paralelních autorit. Compatibility CP aliasy a nahrazené legacy cesty se odstraní až po E10 datech a E11 cutoveru.

## Success Criteria

- [ ] Každá z 44 failure classes má v běžícím systému právě jednoho primárního majitele (E0 ✅, ověří E10).
- [ ] Žádný leaf-pass/root-fail, removed-dep, unmounted, data-drop ani plan-graph-cycle fixture nedosáhne `release_ready:true` (E10).
- [ ] E-044, E-047-1/4/5, P045 regression fixtures zůstávají trvale chycené.
- [ ] Jediná release autorita: FSM nabídne MERGE jen na C4 `release_ready:true` + HEAD match + validní úplný PM brief.
- [ ] Dispatch budget v rozhodovacích kolech dodržen per profil; resource accounting měří skutečné náklady.
- [ ] Žádná blokující kontrola zapnutá bez observe/dual-run + kalibrace.
- [ ] False-block rate < 5 % per blokující check.

## Next Steps

1. PM schválí tento roadmap.
2. Začít stavět **E1** přes jeho Session Prompt (`/aid-plan write` → executable plán jen pro E1) → `/aid-run`.
3. Postupovat fázi po fázi dle pořadí závislostí; každou fázi generovat až těsně před stavbou.
4. E10 je rozhodující systémový milník; do té doby jsou obecné v2 kontroly observe/dual-run. Pouze P048 smí po samostatné E7-CAL zapnout schválený step-local block.
5. Po kazdem executable planu a po kazdem EPICu pouzit interaktivni verification loop z operativni poznamky; release nepovolit bez kanonicke evidence proti aktualnimu HEAD.

---

*Roadmap (formální AID plán) pro celý Control System v2. Per-fáze executable plány vznikají přes Session Prompts. Neimplementovat žádnou fázi před vygenerováním jejího executable plánu a PM schválením. Žádný kód zatím implementovaný.*

## P068 amendment (2026-07-26)

E9.5 is inserted between E9 and E10: the plan-boundary layer (P064 substrate +
P068 release boundary) is a distinct phase, not a sub-task of E9, because E10s
calibration promotion depends on the plan-final cadence existing. The T2 row and
the dispatch budget change accordingly: the specialist stack is dispatched once
per PLAN, not once per EPIC.

This tree is gitignored, so this note serves local readers; the durable record is
the tracked enforcement registry.
