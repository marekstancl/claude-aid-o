---
_generated_by: aid-orchestrator:reporter@E-046-3_3
_generated_at: "2026-06-19T08:00:00Z"
plan_id: P046
epics: ["E-046-1_3", "E-046-2_3", "E-046-3_3"]
test_outcome: no-runtime
_test_evidence:
  - "reporter/test-suite.txt"
---

# Zpráva o dodání — P046: Oprava CP vynucovací vrstvy + hranice plánu + sledování CP1 toku

_Plán P046 · EPIC-y E-046-1_3, E-046-2_3, E-046-3_3 · 2026-06-19_

## 1. Co bylo dodáno

P046 pokrývá tři fáze práce na tom, jak AID vynucuje kontrolní body (checkpointy) a hranici plánu. Před tímto plánem existovaly mechanismy pro kontrolu kvality (auditor, kurátor, zjednodušovač) na papíře, ale nebylo nic, co by zabránilo jejich obejití — "touch ca-review-complete" stačilo ke splnění podmínky i bez toho, aby jediný specialista skutečně běžel.

### EPIC E-046-1_3 — Oprava vynucovací vrstvy CP (migrace producent→konzument)

Tato fáze opravila mrtvý init gate, který nikdy nevynucoval nic, protože skript kontroloval soubor, který přestal existovat po přejmenování adresáře. Přesunula smlouvy mezi checkpointy z interní logiky producenta (skript `aid-fsm.sh`) do dokumentu konzumenta (`review-checkpoint-contracts.md`) tak, aby pravidla přečetl a dodržel ten, kdo je musí dodržovat — agent provádějící review. Přidala per-checkpoint rozsah diffu: CP2 vidí jen diff aktuálního kroku, CP3 celý diff EPIC-u od základního commitu, CP4 diff po aplikaci kurátora.

### EPIC E-046-2_3 — Vynucování hranice plánu (plan-close, toggle-skip, CI floor)

Tato fáze nahradila syrový `touch` na konci plánu skutečným příkazem `plan-close`, který prověří přítomnost všech čtyř povinných zpráv (auditor, kurátor, zjednodušovač, zpráva o dodání) před zápisem markeru. Pokud některý specialista chybí, příkaz selže s pojmenováním chybějícího souboru.

Klíčové části:

- **Příkaz `plan-close`** (`aid-fsm.sh plan-close <epic_id> <evidence_dir> <project_root>`): Blokuje hranici plánu, dokud nejsou přítomny všechny čtyři zprávy. Přidán do `pipeline.md §7`.
- **Toggle-skip s auditem**: Pokud projekt zakáže zjednodušovač nebo reportéra v `execution.yaml`, `plan-close` přeskočí kontrolu té zprávy — ale zapíše záznam do `audit-log.jsonl` s tím, co bylo přeskočeno a proč. Zakázání specialisty zanechá stopu.
- **CI floor manifest**: Protože `.aid-o/work/evidence/` je v `.gitignore`, vzdálené CI nemůže kontrolovat lokální důkazní soubory. Řešením je committed manifest (`.aid-o/reports/{plan_id}-boundary.md`) s přehledem provenance, který přečte GitHub Actions required check (`defaults/ci/plan-boundary-required-check.yml`). Tím pádem CI selže při merge, pokud manifest chybí nebo nemá `boundary_complete: true`.
- **13 nových bats testů**: `test-plan-close.bats` (9 testů) a `test-ci-floor.bats` (4 testy) pokrývají každou blokovací cestu, oba toggle-skip scénáře, zápis audit-logu a výstupní kódy CI checku.
- **GAP-1 fix**: `.gitignore` chyběl výjimku `!.aid-o/reports/`, takže delivery reporty a boundary manifesty nikdy nebyly commitnuty. Opraveno přidáním výjimky — jak do repo `.gitignore`, tak do šablony, kterou `/aid-init` zapíše do consumer projektů.

### EPIC E-046-3_3 — Sledování CP1 toku + behavior_trace + CP1-deep

Tato fáze přidala strukturální vynucení a dokumentaci pro dvě zbývající mezery: nedostatečné stopování kritické cesty v CP1 a slepá review na checkpointech bez záznamu, zda agent skutečně sledoval tok aplikace.

**DONE Closure Checklist (`pipeline.md §7`)**: 100+ řádků telemetrické prózy nahrazeno jedenáctisloupkovou tabulkou. Celá sekvence DONE fáze je teď přehledná na jednu obrazovku. Přidán řádek pro CP5 `blocking_findings` check (který dříve v přehledu chyběl). Odstraněna instrukce `touch ca-review-complete` — nahrazena příkazem `aid-fsm.sh plan-close`.

**Pravidlo #21 v `plan-writing.md`** (kritické větve CP1): Nové grounding pravidlo vyžaduje, aby každý branch v CP1 flow tracingu měl explicitní výsledek. Bezejmenná větev (nedokladovaný edge case, nesledované chybové chování) → verdikt `REVISE_REQUIRED`. Součástí je mechanický pre-screen kopírující vzor Rule #19: regex pro handler patterny (`@app.`, `@router.`, `add_route`, `def \w+(.*request`) aktivuje kontrolu. 6 bats testů ověřuje aktivaci pre-screenu.

**`review-checkpoint-contracts.md` (nová skill)**: Dokumentuje smlouvy pro každý checkpoint (CP1–CP6) na jednom místě — rozsah diffu, povinné sekce výstupu, kdy je `behavior_trace_required: true` povinné. Agents ho načtou před review místo toho, aby informace dohledávali v pipeline.md.

**behavior_trace strukturální gate (`aid-fsm.sh`)**: Když diff splňuje high-risk vzor (auth, routes, schema/validace, FSM stav, bezpečnostní sink, platby, dep manifesty), FSM zkontroluje, zda verifier output má `behavior_trace_count > 0`. Gate kontroluje strukturu a neprázdnost — ne kvalitu trace. Je opt-in: pokud `behavior_trace_required` chybí nebo je `false`, gate přeskočí. Funguje pro legacy verifier outputy bez migrace.

**CP1 risk-scaling (`aid-cp1-gate.sh`)**: CP1 má nově dvě úrovně. Low-risk plány (označené `risk: low` v frontmatter) projdou bez CP1-deep evidence. High-risk plány (nebo plány s high-risk patterny v těle) vyžadují tři architekturní lens výstupy + adjudicator verdikt. Adjudicator s neprázdnými `accepted_blockers` gate nesplní. Po 2 revizích s přetrvávajícími blokery se vyžaduje PM eskalace. Path traversal guard na `plan_id` zabraňuje directory traversal přes crafted IDs.

**Enforcement registry** (2 nové záznamy): `cp1_critical_path_flow_trace` a `behavior_trace_high_risk_gate` přidány do `enforcement-registry.yaml` s `deadline` fields — TTL guard tak pokryje i nové mechanismy.

**`extending-aid.md` doplněn**: Sekce "Enforcement Homes Reference" popisuje, kde žijí jednotlivé vynucovací mechanismy (plan-close, CI floor, CP5 contract, behavior_trace gate) pro přispěvatele.

## 2. Jak to vyzkoušet

**Behavior_trace gate (6 bats testů):**

```bash
cd /opt/eco/projects/aid-orchestrator
bats plugins/aid-orchestrator/scripts/tests/bats/test-behavior-trace.bats
```

**Rule #21 pre-screen (6 bats testů — handler fixture aktivace):**

```bash
bats plugins/aid-orchestrator/scripts/tests/bats/test-plan-writing-rules.bats
```

**CP1 risk-scaling gate (16 test scénářů):**

```bash
bash plugins/aid-orchestrator/scripts/tests/test-cp1-gate.sh
```

**Boundary manifesty a CI floor:**

```bash
# Zobrazit committed boundary manifest pro P046:
cat .aid-o/reports/P046-boundary.md

# Zobrazit CI check definici:
cat plugins/aid-orchestrator/defaults/ci/plan-boundary-required-check.yml

# Smoke test plan-close (vyžaduje přítomné zprávy):
mkdir -p /tmp/ev-smoke
touch /tmp/ev-smoke/curator-report.md /tmp/ev-smoke/audit-report.md \
      /tmp/ev-smoke/simplifier-report.md
mkdir -p /tmp/proj-smoke/.aid-o/reports
touch /tmp/proj-smoke/.aid-o/reports/P046-delivery.md
bash plugins/aid-orchestrator/scripts/aid-fsm.sh \
  plan-close E-046-test /tmp/ev-smoke /tmp/proj-smoke
ls /tmp/ev-smoke/ca-review-complete  # musí existovat
```

**Celá testovací sada (nulová regrese):**

```bash
bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
bats plugins/aid-orchestrator/scripts/tests/bats/
```

**Nová skill review-checkpoint-contracts.md:**

```bash
cat plugins/aid-orchestrator/skills/review-checkpoint-contracts.md
```

## 3. Co jsem ověřil

Režim: **no-runtime** — tato dodávka je plugin-interní bash tooling (žádná služba, žádné UI, žádný HTTP endpoint). Testovací sada je jediný runnable povrch. Fallback je oprávněný.

Spustil jsem tři cílové testovací oblasti přímo proti dodanému kódu:

**test-behavior-trace.bats** (6/6 PASS): Potvrzuje, že gate blokuje při `behavior_trace_count=0` + `required=true`, propustí při `required=false` nebo chybějícím poli (opt-in design), a přijme count=1 jako boundary value.

**test-plan-writing-rules.bats** (6/6 PASS): Potvrzuje aktivaci Rule #21 pre-screenu na handler fixtures (`@app.post`, `@router.<method>(`, `add_route(`, `def login(request:`), a non-activation na plain fixture bez handler patternů.

**test-cp1-gate.sh** (16/10 PASS — 16 asercí přes 10 scénářů): Potvrzuje, že high-risk plán bez evidence selže (exit 1), s kompletní evidencí projde, `risk: low` frontmatter exemptuje bez evidence, accepted_blockers v adjudicatoru způsobí selhání, chybějící `--plan` argument vrátí exit 2.

Gates record pro E-046-3_3 (gates_report.json, completed `2026-06-19T04:12:46Z`): `bats_fsm` PASS (49 tests), `bats_all` PASS (139 tests), `shell_pipeline_smoke` PASS (34 suites). Celkový výsledek: **pass**.

Gates record pro E-046-2_3 (z P046-boundary.md provenance, `2026-06-18T19:15:47Z`): 63/63 + 164/164 + 34 suites — vše pass.

Artefakty evidence jsou v `reporter/test-suite.txt` v evidence adresáři tohoto EPIC-u.

## 4. Verdikt auditora

**E-046-3_3**: Skóre 84/100, žádné blokující nálezy. Bezpečnost 100/100. Tři nízké nálezy: `plan-writing.md` datum `Last Updated` neaktualizováno po přidání Rule #21; oba nové záznamy enforcement registry nemají pole `status`; CHANGELOG nemá entry pro tuto verzi. Nic neblokuje merge.

**E-046-2_3**: Skóre 95/100, žádné blokující nálezy (17/17 AC pass). Dva nízké nálezy: test 8 neassertuje pole `specialist` v JSON; `audit-log.jsonl` nemá `blocking_epic`/`blocking_plan` (jsou pouze v `timeline.jsonl`).

## 5. Verdikt kurátora

**E-046-3_3**: 6 nových návrhů (IMP-115 až IMP-120). Tři S-effort opraveny v rámci review cyklu (fix version stringu v aid-prefilter.sh, oprava integer typů v enforcement-registry.yaml, oprava behavior_trace gate pro záporné hodnoty). IMP-118 (přečíslování kroku 6a) schváleno jako M-effort, odloženo. IMP-119 (frontmatter parser state machine v aid-cp1-gate.sh) schváleno jako M-effort, odloženo. IMP-120 (telemetry reference placement) odloženo — závisí na IMP-047.

**E-046-2_3**: 4 návrhy, všechny aplikovány: extrakce `_aid_read_toggle()` helperu, `set -eo pipefail` do CI YAML, přeposlání `--blocking-epic`/`--blocking-plan` do `fsm_emit_audit_log`, odstranění mrtvého config reference v `aid-audit.md`. CP4 verifier potvrdil správnost.

## 6. Cleanup (Zjednodušovač)

**E-046-3_3** — Zjednodušovač proběhl jako součást kurátor/auditor review cyklu. Výsledky:

- **Hotovo**: Tři S-effort návrhy kurátora aplikovány před finalizací (IMP-115, IMP-116, IMP-117). DONE Closure Checklist v pipeline.md §7 nahradil ~140 řádků prózy přehlednou tabulkou — toto byla primární zjednodušovací akce tohoto EPIC-u.
- **Přeskočeno**: Přečíslování kroku 6a (IMP-118) a frontmatter parser rewrite (IMP-119) jsou M-effort a nejsou blokovací — odkázány do backlogu.
- **Doporučení**: IMP-119 (frontmatter parser v aid-cp1-gate.sh) je nejvyšší priorita pro příští iteraci — medium-priority bug, S/M effort, tichá bezpečnostní záplata pro malformed plány bez uzavírajícího `---`. IMP-120 (placement telemetry reference) by měl počkat na rozhodnutí o IMP-047 (context-load strategie).

**E-046-2_3** — Zjednodušovač proběhl inline s kurátor review cyklem; všechny 4 návrhy aplikovány a ověřeny.

## 7. Upozornění

**Deferované opravy (backlog)**:

- **IMP-119** (M, medium priority) — `aid-cp1-gate.sh` frontmatter parser neopraví malformed plán bez uzavírajícího `---`. V praxi nízké riziko (plány generuje AID), ale správné řešení je two-delimiter state machine. Vhodné pro příští patch EPIC.
- **IMP-120** (L, low priority) — Sekce Telemetry Reference v pipeline.md je 190 řádků pod Closure Checklist, který na ni odkazuje. Pro LLM agenty čtoucí sekvenčně může být mimo okno při DONE fázi. Závisí na IMP-047 strategii; odloženo.
- **IMP-118** (M, low priority) — Krok "6a" v DONE Closure Checklist vypadá jako pod-krok CP4, ale CP5 je nezávislý checkpoint. Jen dokumentační confusion, žádný funkční dopad.

**Zbývající low-severity auditorské nálezy (E-046-3_3)**: `plan-writing.md` datum `Last Updated` (2026-06-03 místo 2026-06-19) — malá oprava. Version string `@v2.35.0` v aid-prefilter.sh byl jedním z S-effort návrhů kurátora — opraveno jako IMP-115.

**CI floor je opt-in**: `plan-boundary-required-check.yml` je doručen jako `defaults/ci/` artefakt pro projekty k instalaci. Plugin nemůže vzdáleně vynucovat branch protection pravidla — to je záměrné (Step 6 spec E-046-2_3).

**CHANGELOG a release commit**: Auditor zaznamenal, že CHANGELOG nemá entry pro funkce tohoto EPIC-u. Release commit (verze 2.34.0) je plánován jako standardní krok po merge — zahrnuje entry pro CP1-deep, behavior_trace gate, DONE Closure Checklist a Rule #21.

Všechna planned deliverables byla dodána. Vynucovací vrstva CP je opravena, hranice plánu je nyní blokovaná reálným gate s auditovaným override path, a CP1 má risk-scaled flow tracing s mechanickým pre-screenem a strukturálním gate.
