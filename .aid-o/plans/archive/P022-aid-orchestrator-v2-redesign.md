---
id: P022
type: plan
status: done
created: 2026-03-03
author: PM + Claude Sonnet 4.6
source: REDESIGN-PLAN-v2.md (5-agent synthesis) + CRITICAL-ASSESSMENT.md (11-agent analysis)
---

# Plan: AID Orchestrator v2.0 — Complete Redesign

> **⚠️ SECTIONS PENDING BACKGROUND AGENTS:**
> - `## GUI Redesign` — agent running, will be appended when complete
> - `## VULCAN Integration` — agent running, will be appended when complete

---

## Context

AID Orchestrator v1.7.0 was developed in 14 days (293 commits) and proved its core value: evidence trail, DAG-based multi-agent dispatch, FIRST AID autonomous mode, and Curator automatic fixes (21 oprav implementováno). However, a 11-agent deep assessment (6 research + 5 validators) identified systemic problems that prevent sustainable growth:

1. **~400K prompt tokenů** (z ~1 200 souborů) — LLM musí zpracovat obrovský kontext
2. **FSM v Markdownu je nedeterministický** — token tracking feature implementována jako instrukce, LLM ji ignoroval (0 usage dat v 32 stage_log.jsonl souborech)
3. **36 cyklů cross-referencí** mezi 27 skills — modulární změny způsobují cascade problémy
4. **Žádné CI** pro 92 bash testů a 32 Vitest souborů
5. **UX overhead 30–60 minut** než se napíše první řádek kódu pro jakýkoli task

Redesign zachovává prokázanou hodnotu (FIRST AID, Curator, evidence trail, bash pipeline skripty) a eliminuje vše, co nefunguje nebo duplikuje nativní Claude Code schopnosti.

---

## Goal

Transformovat AID v1.7.0 na v2.0.0 se zachováním 100 % prokázané hodnoty při snížení prompt tokenů o 87 %, eliminaci nedeterministických FSM přechodů a přidání FAST MODE pro tasky < 2 hodiny.

---

## Scope

**In scope:**
- Bash controller layer — `aid-fsm.sh`, `aid-run-gates.sh`, `aid-stage-log.sh`, `aid-token-count.sh`
- Skills konsolidace: 27 → 8 souborů (rewrite from scratch, ne refaktoring — kvůli 36 cyklům)
- Agenti konsolidace: 18 → 8 (parametrický model s role kartami)
- Příkazy konsolidace: 14 → 8 (nový `/aid-do` Fast Mode)
- YAML policy soubory: 10 → 3 (`orchestration.yaml`, `execution.yaml`, `integrations.yaml`)
- CI/CD pipeline pro AID samotný (3 GitHub Actions workflows)
- `packages/aid-contract/` — TypeScript data kontrakt pro GUI
- Oprava backlog sync (IMP-051, IMP-052)
- Curator pre-flight status update protokol
- Validace na externím projektu (assignment1 je ve frontě)

**Out of scope:**
- GUI redesign — čeká na výsledek background agenta (bude jako samostatný EPIC)
- VULCAN integrace — čeká na výsledek background agenta (bude jako samostatný EPIC)
- Rewrite `aid-epic-to-json.sh` do TypeScriptu — odloženo (92 testů prochází, nízká priorita)
- Qdrant learning pro multi-project scénáře — odloženo na po validaci
- Voice dictation, AI Companion features — zrušeno (feature creep)
- Slack MCP jako primární komunikační kanál — degradováno na optional 20-řádkový fallback
- Plugin marketplace distribuce — odloženo na po stabilizaci v2

---

## Approach

### Option A: Phased Rewrite (Doporučeno)

Nové soubory se píší od nuly souběžně s provozem v1.7.0. Po dokončení každé fáze se stará verze smaže. Projekt zůstává funkční po celou dobu redesignu.

**Pros:**
- V1 zůstává plně funkční po celou dobu redesignu (assignment1 lze spustit kdykoli)
- Každá fáze je testovatelná samostatně
- Jednoduchý rollback — staré soubory existují dokud nejsou smazány

**Cons:**
- Přechodný stav kde existují obě verze zároveň
- Vyžaduje explicitní smazání starých souborů na konci každé fáze

### Option B: In-Place Refactoring

Postupné přepisování existujících souborů.

**Pros:** Jeden zdroj pravdy po celou dobu

**Cons:** 36 cyklů cross-referencí znemožňuje částečné změny — každá úprava risuje rozbití jiného souboru. Ověřeno analýzou: "varianta A je rewrite, ne refaktoring."

### Decision

**Chosen:** Option A — Phased Rewrite
**Rationale:** 36 cross-reference cyklů mezi skills znemožňuje inkrementální refaktoring. Každá skill odkazuje průměrně na 3,2 dalších — změna jednoho souboru způsobuje cascade problémy. Rewrite od nuly je jediná cesta k cílovému stavu 0 cyklů.

---

## Architecture

### Dual-Layer Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  VRSTVA 1: BASH CONTROLLER (deterministický)                         │
│                                                                      │
│  aid-fsm.sh          — validace přechodů, state.yaml write           │
│  aid-run-gates.sh    — spustit příkaz, exit code → pass/fail         │
│  aid-stage-log.sh    — append-only JSONL, vždy validní               │
│  aid-token-count.sh  — charcount/ratio → JSON output                 │
│  aid-epic-to-json.sh — Kahnův DAG algoritmus (zachovat beze změny)   │
│  ... 4 další pipeline skripty (zachovat beze změny)                  │
└─────────────────────────┬────────────────────────────────────────────┘
                          │ volání přes Bash tool
┌─────────────────────────▼────────────────────────────────────────────┐
│  VRSTVA 2: LLM (prompt-based, kreativní práce)                       │
│                                                                      │
│  8 skills (Markdown)     — pipeline.md, agent-protocol.md, ...       │
│  8 agenti (Markdown)     — implementer, verifier, curator, ...       │
│  8 příkazů (Markdown)    — aid-do, aid-plan, aid-run, ...            │
│  Role karty              — 30-50 řádků per role v role-cards.md      │
└──────────────────────────────────────────────────────────────────────┘
```

**Klíčový princip:** LLM neřídí přechody stavů — přechody jsou deterministické funkce bash kontroleru na základě exit kódů a existence souborů. LLM operuje UVNITŘ stavů (píše kód, analyzuje, opravuje), ne MEZI nimi.

### Nový 6-stavový FSM

```
PRE-FLIGHT (bash skripty, bez LLM):
  Plan → EPIC → plan.json → run.md
        │
        ▼
    READY ──reject──▶ konec
        │ approve
        ▼
    EXECUTE ◀─────────────────────┐
    (dispatch agent, validate)     │ next step
        │ all steps done           │
        ▼                          │
    GATES (+Curator hook) ─────────┘ retry (max 2)
        │ pass
        ▼
    DONE (merge, archive, queue)

    ESCALATION ◀── any hard failure
        │ fix/skip/abort
        └──▶ EXECUTE nebo konec
```

**Smazány stavy:** PLANNING (→ PRE-FLIGHT bash), PLAN_REVIEW (→ checkpoint v READY), NEXT_PHASE (pointer increment), PHASE_CHECK (→ tail of EXECUTE), GATE_RETRY (→ vnitřní smyčka GATES), CURATOR_RESOLVE (→ post-gate hook), PM_APPROVAL (→ checkpoint v DONE).

### Dva exekuční módy

```
/aid-do <task>              /aid-run [flags]
     │                           │
     ▼                           ▼
FAST MODE                   EPIC MODE
- přímá implementace        - PRE-FLIGHT bash
- git hooks brány           - 6-stavový FSM
- Q-NNN.md quick log        - plná evidence trail
- < 2 min overhead          - Curator, parallelism
```

### Evidence Trail (nový formát)

```
.aid-o/work/evidence/{epic_id}/{run_id}/
  state.yaml        — JEDINÝ mutabilní stavový soubor (crash recovery)
  timeline.jsonl    — append-only event log (nikdy se nemodifikuje)
  steps/
    step_1_architect/output.md
    step_2_backend/output.md
    ...

.aid-o/work/quick/
  Q-001.md          — Fast Mode quick log
  Q-002.md
```

**state.yaml schema:**
```yaml
epic_id: E-003-1_2
run_id: R-E003-1_2-1
state: EXECUTE
current_step: 3
total_steps: 6
mode: auto   # manual | auto
branch: task/E-003-1_2
base_commit: abc123f
gate_retries: 0
escalation_count: 0
started_at: "2026-03-03T10:00:00Z"
```

---

## Data Model

### Plugin File Structure (v2)

```
plugins/aid-orchestrator/
  .claude-plugin/
    plugin.json                    # 8 agents, 8 skills, 8 commands
  agents/ (8 souborů, ~20 řádků každý)
    implementer.md                 # parametrický: načte role kartu dle dispatch
    verifier.md                    # parametrický: načte focus kartu dle dispatch
    gate-fixer.md                  # haiku tier, mechanické opravy
    curator.md                     # sloučený s lessons-extractor
    auditor.md                     # trimmed z 780 na ~400 řádků
    scanner.md                     # zachován
    run-validator.md               # zachován
  commands/ (8 souborů)
    aid-do.md                      # NOVÝ: Fast Mode
    aid-plan.md                    # sloučení brainstorm + write-plan + plan-epic
    aid-run.md                     # update: 6-state FSM + flags
    aid-status.md                  # sloučení epic-status + epic-queue
    aid-init.md                    # sloučení init + setup + auto-detect
    aid-help.md                    # progressive disclosure
    aid-audit.md                   # sloučení audit + analytics
    aid-stop.md                    # zachován
  skills/ (8 souborů)
    agent-protocol.md              # ~250 řádků: I/O format, constraints, boilerplate
    pipeline.md                    # ~1200 řádků: 6-state FSM + dispatch + gates + curator
    planner.md                     # trimmed z 2017 na ~800 řádků
    brainstorming.md               # sloučení 3 souborů, ~400 řádků
    quality-gates.md               # pre-commit 6 bran, standalone
    run-management.md              # run lifecycle, trimmed
    memory.md                      # Qdrant protokol, optional
    role-cards.md                  # ~500 řádků: všechny role a focus karty
  defaults/
    orchestration.yaml             # sloučení 5 policy souborů
    execution.yaml                 # sloučení gates + release-policy
    integrations.yaml              # Qdrant + Slack, optional
    templates/                     # zachovat
  scripts/
    aid-auto-pipeline.sh           # zachovat
    aid-plan-to-epic.sh            # zachovat
    aid-epic-to-json.sh            # zachovat (92 testů prochází)
    aid-json-to-run.sh             # zachovat
    aid-queue-add.sh               # zachovat
    aid-fsm.sh                     # NOVÝ
    aid-run-gates.sh               # NOVÝ
    lib/
      common.sh                    # zachovat
      aid-token-count.sh           # NOVÝ
      aid-stage-log.sh             # NOVÝ
    tests/                         # 92 existujících + ~20 nových

packages/
  aid-server/                      # minimální změny (nové .aid-o/ cesty)
  aid-gui/                         # čeká na GUI agent analýzu
  aid-contract/                    # NOVÝ: TypeScript data kontrakt
    src/
      types.ts                     # AidStageLogEntry, AidPlanProgress, AidGatesReport
      index.ts
    package.json
```

### TypeScript Data Contract (packages/aid-contract/src/types.ts)

```typescript
export type AidFsmState = "READY" | "EXECUTE" | "GATES" | "ESCALATION" | "DONE";

export interface AidStateYaml {
  epic_id: string;
  run_id: string;
  state: AidFsmState;
  current_step: number;
  total_steps: number;
  mode: "manual" | "auto";
  branch: string;
  base_commit: string;
  gate_retries: number;
  escalation_count: number;
  started_at: string; // ISO 8601
}

export interface AidTimelineEntry {
  ts: string;       // ISO 8601
  event: string;    // "step_dispatch" | "step_complete" | "gate_run" | "state_enter" | ...
  state?: AidFsmState;
  step_id?: string;
  role?: string;
  model?: string;
  result?: "pass" | "fail";
  duration_s?: number;
  [key: string]: unknown; // extensible
}

export interface AidGatesReport {
  epic_id: string;
  run_id: string;
  overall: "pass" | "fail";
  completed_at: string;
  gates: Record<string, {
    result: "pass" | "fail" | "skipped";
    exit_code: number;
    duration_ms: number;
    output: string;
    attempts: number;
  }>;
}

export interface AidQuickLog {
  id: string;       // Q-001
  task: string;
  started_at: string;
  duration_s: number;
  files_changed: string[];
  commit: string;
  escalated_to_epic: boolean;
}
```

---

## API Design

### Internal Bash Script Interfaces

**aid-fsm.sh**
```bash
# Validace a provedení přechodu
transition_state <from_state> <to_state> <state_file>
# Exit 0 = OK, Exit 1 = invalid transition, stderr = důvod

# Čtení aktuálního stavu
get_current_state <state_file>
# Stdout = state string (READY|EXECUTE|GATES|ESCALATION|DONE)

# Inicializace nového runu
init_state <epic_id> <run_id> <total_steps> <mode> <branch> <base_commit> <state_file>
# Exit 0 = OK, Exit 1 = state_file already exists (prevent duplicate init)
```

**aid-run-gates.sh**
```bash
# Spustit jednu bránu ze gates config
run_gate <gate_name> <command> <timeout_seconds> <log_file>
# Exit 0 = pass, Exit 1 = fail
# Stdout = JSON: {"gate":"tests","result":"pass","exit_code":0,"duration_ms":1234,"output":"..."}

# Spustit všechny brány z execution.yaml
run_all_gates <execution_yaml> <epic_id> <run_id>
# Exit 0 = všechny pass, Exit 1 = alespoň jedna fail
# Stdout = JSON report (kompatibilní s AidGatesReport TypeScript interface)
```

**aid-stage-log.sh**
```bash
# Append jednoho eventu do timeline.jsonl
log_event <timeline_file> <event> [key=value ...]
# Příklad: log_event timeline.jsonl "step_dispatch" state=EXECUTE step_id=step_1_architect role=architect model=opus
# Exit 0 vždy (logging nesmí přerušit pipeline)
```

**aid-token-count.sh**
```bash
# Odhad počtu tokenů
count_tokens <text_or_file> [content_type]
# content_type: prose|code|mixed (default: mixed)
# Stdout = JSON: {"estimated_tokens":1250,"char_count":4375,"content_type":"mixed","ratio":3.5}
# Exit 0 vždy
```

### GitHub Actions Workflow Interfaces

**ci.yml triggers:**
- `push` to `main` branch
- `pull_request` to `main` branch

**ci.yml jobs:**
1. `bash-tests`: `scripts/tests/run-all-tests.sh --verbose` (timeout: 5 min)
2. `vitest`: `npm ci && npm test` (timeout: 10 min)
3. `build-check`: `npm run build` for aid-gui + aid-server (timeout: 10 min)
4. `security-regression`: `node scripts/check-path-validation.js` (timeout: 2 min)

**markdown-lint.yml triggers:**
- `pull_request` when `plugins/aid-orchestrator/{skills,commands,agents}/**` changes

**version-sync.yml triggers:**
- `push` to `main` branch

---

## Implementation Steps

**EPIC 1: Steps 1-5 — Foundation & CI**

### Step 1: CI Workflows — bash testy, Vitest, build, security

**Objective:** Přidat 3 GitHub Actions workflows tak, aby se 92 bash testů a 32 Vitest souborů spouštěly automaticky při každém PR.

**Files:**
- Create: `.github/workflows/ci.yml` — main CI pipeline
- Create: `.github/workflows/markdown-lint.yml` — structural checks pro skill/command Markdown soubory
- Create: `.github/workflows/version-sync.yml` — verze musí souhlasit ve všech 8 lokacích
- Create: `scripts/check-path-validation.js` — regresní test pro CWE-22 path traversal

**Architecture Context:**
Tato fáze nevyžaduje žádné změny v pluginu. Využívá existující `scripts/tests/run-all-tests.sh` (master test runner) a `vitest.config.ts` konfiguraci, které už existují ale nikdy nebyly zahrnuty do CI. CI je vrstva nad stávajícím projektem, nezávislá na redesignu.

**Implementation Detail:**

`ci.yml` — kompletní struktura:
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  bash-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install jq (bash test dependency)
        run: sudo apt-get install -y jq
      - name: Run bash test suite
        run: |
          chmod +x plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
          plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --verbose
        timeout-minutes: 5

  vitest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm test
        timeout-minutes: 10

  build-check:
    needs: [vitest]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm run build
        working-directory: packages/aid-gui
        timeout-minutes: 10

  security-regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - name: CWE-22 path traversal regression
        run: node scripts/check-path-validation.js
        timeout-minutes: 2
```

`markdown-lint.yml` — kontroluje Last Updated footer, délku souboru, MUST Rules umístění:
```yaml
name: Markdown Lint
on:
  pull_request:
    paths:
      - 'plugins/aid-orchestrator/skills/**'
      - 'plugins/aid-orchestrator/commands/**'
      - 'plugins/aid-orchestrator/agents/**'
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check Last Updated footer
        run: |
          missing=$(grep -rL "Last Updated:" plugins/aid-orchestrator/skills/ 2>/dev/null || true)
          [ -z "$missing" ] || (echo "Missing 'Last Updated:' in: $missing" && exit 1)
      - name: Warn on files over 800 lines
        run: |
          find plugins/aid-orchestrator/skills/ -name "*.md" -exec awk \
            'END{if(NR>800)print "WARNING: " FILENAME " has " NR " lines"}' {} \;
```

`scripts/check-path-validation.js` — regresní test: ověří, že `isValidPathComponent` nebo ekvivalentní validace je volána v každém route handleru přijímajícím `epicId`/`runId` z URL params:
```javascript
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const routesDir = path.join(__dirname, '../packages/aid-server/src/routes');
const files = fs.readdirSync(routesDir).filter(f => f.endsWith('.ts'));
let exitCode = 0;

for (const file of files) {
  const content = fs.readFileSync(path.join(routesDir, file), 'utf8');
  const hasRouteParam = /req\.params\.(epicId|runId|id)/.test(content);
  const hasValidation = /isValidPathComponent|validateEpicId|encodeURIComponent|path\.basename/.test(content);
  if (hasRouteParam && !hasValidation) {
    console.error(`FAIL: ${file} reads route params without path validation`);
    exitCode = 1;
  }
}
process.exit(exitCode);
```

**Error Handling:**
- Pokud `run-all-tests.sh` neexistuje nebo nemá execute permission: workflow selže s jasnou chybou; `chmod +x` je součástí kroku
- Pokud `npm ci` selže (package-lock.json conflict): CI selže — opravit lokálně a push
- `security-regression` job: non-zero exit = CI block; přidání nové route bez validace automaticky blokuje merge

**Edge Cases:**
- macOS vs. Linux diff v bash testech: skripty jsou POSIX-compatible; `ubuntu-latest` runner je Linux — stejné prostředí jako produkce
- Vitest timeout pro GUI testy s DOM: `jsdom` environment je nakonfigurován v `vitest.config.ts`, 10 min limit je dostatečný

**Dependencies:**
- No dependencies — lze začít ihned, nezávisí na žádném jiném kroku redesignu

**Acceptance Criteria:**
- [ ] PR otevřený do main spustí všechny 3 workflows automaticky
- [ ] `bash-tests` job: 92 testů prochází bez chyby
- [ ] `vitest` job: všechny Vitest soubory prochází
- [ ] `build-check` job: `npm run build` úspěšný pro aid-gui i aid-server
- [ ] `security-regression` job: prochází (existující CWE-22 opravy z v1.7.0 jsou v pořádku)
- [ ] PR se změnou v `skills/*.md` spustí `markdown-lint.yml`
- [ ] Push do main spustí `version-sync.yml`

**Effort:** M
**AID Role:** backend

---

### Step 2: Backlog sync oprava + Curator pre-flight protokol

**Objective:** Opravit IMP-051 a IMP-052 status v backlog.md a implementovat pre-flight status update v Curator agentovi aby se tento typ nesouladu neopakoval.

**Files:**
- Modify: `.aid-o/04-engine/backlog.md` — přesunout IMP-051, IMP-052 z Active do Implemented
- Modify: `plugins/aid-orchestrator/agents/curator.md` — přidat pre-flight status update protokol
- Modify: `plugins/aid-orchestrator/skills/improvement-proposals.md` — přidat atomic update instrukci

**Architecture Context:**
Curator agent funguje (21 implementovaných oprav potvrzeno) ale backlog sync je nekompletní. IMP-051 a IMP-052 jsou označeny jako `implemented` v `curator_resolve_report.json` souboru pro E-016-1_3, ale v `backlog.md` zůstávají jako `pending`. Root cause: Curator implementuje fix a pak aktualizuje backlog — pokud agent skončí mezi těmito dvěma operacemi, backlog zůstane nekonzistentní.

**Implementation Detail:**

Změna v `backlog.md` — přesunout z `## Active Proposals` do `## Implemented`:
```markdown
## Implemented

| IMP-ID | Type | Area | Summary | Epic Ref | Date |
|--------|------|------|---------|----------|------|
...
| IMP-051 | bug | packages/aid-server/src/pipeline.ts | Fixed pipeline.ts stepsTotal aggregation | E-016-1_3 | 2026-02-27 |
| IMP-052 | bug | packages/aid-gui/src/components/ | Fixed notification click navigation | E-016-1_3 | 2026-02-27 |
```

Změna v `curator.md` — přidat před implementační krok:
```
### Pre-flight Status Update (PŘED implementací)

Pro každý approved proposal:
1. Otevřít backlog.md
2. Nalézt řádek s IMP-NNN
3. Změnit status: `pending` → `implementing` (atomicky)
4. Zavřít soubor

TEK POTÉ spustit implementaci.

Po implementaci:
- Úspěch: status → `implemented`, přidat Epic Ref a datum
- Selhání: status → `deferred`, přidat reason: "fix attempt failed: [detail]"

NIKDY neaktualizovat status až po implementaci bez pre-flight write.
```

Přidat do `improvement-proposals.md` sekci "Backlog Integrity":
```
### Backlog Integrity Rules

1. Status `implementing` = fix probíhá. Pokud session selže, PM vidí tuto hodnotu.
2. Status nikdy neskáče `pending` → `implemented` v jednom kroku.
3. Pokud nalezneš `implementing` starší než 24 hodin → automaticky degradovat na `deferred`.
4. Jeden soubor backlog.md — nikdy nevytvářet kopii.
```

**Error Handling:**
- Pokud curator.md read selže při pre-flight: zalogovat do `timeline.jsonl` a přeskočit tento proposal (nezablokovat ostatní)
- Pokud backlog.md je locked (jiný agent zapisuje): retry 3× s 2s delay, pak eskalovat

**Edge Cases:**
- IMP-NNN v backlog.md neexistuje (byl smazán): zalogovat varování, nevytvářet nový řádek (mohlo být záměrně odstraněno)
- Duplicitní IMP číslo v backlog.md: prvotní scan backlogu při CURATOR_RESOLVE odhalí duplicitu, zalogovat a použít první výskyt

**Dependencies:**
- No dependencies — lze začít ihned

**Acceptance Criteria:**
- [ ] IMP-051 a IMP-052 jsou v sekci `## Implemented` v backlog.md s datem 2026-02-27
- [ ] IMP-051 a IMP-052 nejsou v sekci `## Active Proposals`
- [ ] Curator agent instrukce obsahují pre-flight status update krok PŘED implementačním krokem
- [ ] Status `implementing` existuje jako validní hodnota v backlog.md (v dokumentaci)
- [ ] Simulace: manuálně nastavit IMP test na `implementing` → ověřit, že nová session ho nezmění na `pending`

**Effort:** S
**AID Role:** backend

---

**EPIC 2: Steps 3-7 — Bash Controller Layer**

### Step 3: aid-fsm.sh — Deterministický stavový automat

**Objective:** Implementovat `scripts/aid-fsm.sh` — bash skript, který spravuje FSM přechody deterministicky (exit code, ne LLM instrukce) a udržuje `state.yaml`.

**Files:**
- Create: `scripts/aid-fsm.sh` — hlavní FSM script
- Create: `scripts/tests/test-fsm.sh` — bash testy pro FSM (cíl: 15 testů)
- Modify: `scripts/lib/common.sh` — přidat `require_yq` helper funkci

**Architecture Context:**
`aid-fsm.sh` je jádro bash controller vrstvy. Nahrazuje nedeterministický FSM, který byl implementován pouze jako Markdown instrukce (příklad selhání: token tracking feature nebyla nikdy exekuována přes 32 stage_log.jsonl souborů). Tento skript spravuje `state.yaml` (jediný mutabilní stavový soubor) a logguje do `timeline.jsonl` přes `aid-stage-log.sh`.

**Implementation Detail:**

```bash
#!/usr/bin/env bash
# scripts/aid-fsm.sh — Deterministic FSM for AID Orchestrator v2
# Usage: aid-fsm.sh <command> [args...]
# Commands: init, transition, get-state, advance-step, set-mode

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

# Allowed transitions (source:target)
readonly VALID_TRANSITIONS=(
  "READY:EXECUTE"
  "EXECUTE:GATES"
  "EXECUTE:ESCALATION"   # step failure
  "GATES:DONE"
  "GATES:ESCALATION"     # gate failure after retries
  "ESCALATION:EXECUTE"   # rework after fix
  "ESCALATION:GATES"     # skip step
  "ESCALATION:DONE"      # abort (still archive run)
)

cmd_init() {
  # init <epic_id> <run_id> <total_steps> <mode> <branch> <base_commit> <state_file>
  local epic_id="$1" run_id="$2" total_steps="$3" mode="$4"
  local branch="$5" base_commit="$6" state_file="$7"

  [[ -f "$state_file" ]] && { echo "ERROR: state file already exists: $state_file" >&2; exit 1; }
  mkdir -p "$(dirname "$state_file")"

  cat > "$state_file" <<YAML
epic_id: ${epic_id}
run_id: ${run_id}
state: READY
current_step: 0
total_steps: ${total_steps}
mode: ${mode}
branch: ${branch}
base_commit: ${base_commit}
gate_retries: 0
escalation_count: 0
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
YAML
  echo "OK:READY"
}

cmd_transition() {
  # transition <state_file> <target_state> [reason]
  local state_file="$1" target="$2" reason="${3:-}"
  local current; current=$(yq '.state' "$state_file")

  local key="${current}:${target}"
  local valid=false
  for t in "${VALID_TRANSITIONS[@]}"; do
    [[ "$t" == "$key" ]] && valid=true && break
  done

  if ! $valid; then
    echo "ERROR: Invalid transition ${current} -> ${target}" >&2
    exit 1
  fi

  yq -i ".state = \"$target\"" "$state_file"
  [[ -n "$reason" ]] && yq -i ".last_transition_reason = \"$reason\"" "$state_file"
  echo "OK:${target}"
}

cmd_advance_step() {
  # advance-step <state_file>
  local state_file="$1"
  local current; current=$(yq '.current_step' "$state_file")
  local total; total=$(yq '.total_steps' "$state_file")
  local next=$(( current + 1 ))

  yq -i ".current_step = $next" "$state_file"

  if (( next >= total )); then
    echo "ALL_STEPS_DONE"
  else
    echo "STEP:${next}"
  fi
}

cmd_get_state() {
  local state_file="$1"
  yq '.state' "$state_file"
}

# Dispatch
case "${1:-}" in
  init)       shift; cmd_init "$@" ;;
  transition) shift; cmd_transition "$@" ;;
  advance-step) shift; cmd_advance_step "$@" ;;
  get-state)  shift; cmd_get_state "$@" ;;
  *) echo "Usage: aid-fsm.sh <init|transition|advance-step|get-state> [args]" >&2; exit 1 ;;
esac
```

**Dependency na `yq`:** Script vyžaduje `yq` v4+ pro YAML čtení/zápis. Přidat `require_yq` do `lib/common.sh`:
```bash
require_yq() {
  command -v yq >/dev/null 2>&1 || {
    echo "ERROR: yq is required but not installed. Install: https://github.com/mikefarah/yq" >&2
    exit 1
  }
  local version; version=$(yq --version | grep -o 'v[0-9]*' | head -1 | tr -d 'v')
  (( version >= 4 )) || { echo "ERROR: yq v4+ required, found: $(yq --version)" >&2; exit 1; }
}
```

**Error Handling:**
- `yq` není dostupný: jasná chybová zpráva s install odkazem, exit 1
- `state.yaml` neexistuje při `transition`/`advance-step`: exit 1 s cestou
- `state.yaml` není validní YAML: yq selže s vlastní chybou, propagovat exit 1
- Race condition (dva procesy mění state.yaml): POSIX `flock` přes `cmd_transition` a `cmd_advance_step`

**Edge Cases:**
- Přechod z ESCALATION zpět do EXECUTE: musí resetovat `gate_retries` na 0 (`yq -i ".gate_retries = 0"`)
- `current_step = total_steps - 1` při `advance-step`: vrátit `ALL_STEPS_DONE` místo dalšího step indexu
- `base_commit` obsahuje speciální znaky: uvodit jako YAML string

**Dependencies:**
- Depends on: `scripts/lib/common.sh` — musí existovat (existuje v v1.7.0)
- Blocks: Step 4 (aid-run-gates.sh používá FSM přechody), Step 6 (aid-stage-log.sh loguje po přechodech)

**Acceptance Criteria:**
- [ ] `aid-fsm.sh init E-001 R-001-1 6 auto main abc123 /tmp/test-state.yaml` vytvoří validní YAML soubor se state: READY
- [ ] `aid-fsm.sh transition /tmp/test-state.yaml EXECUTE` → exit 0, stdout "OK:EXECUTE"
- [ ] `aid-fsm.sh transition /tmp/test-state.yaml DONE` z EXECUTE → exit 1 (invalid transition)
- [ ] `aid-fsm.sh advance-step` 6× → výstup "ALL_STEPS_DONE" při 6. volání
- [ ] `aid-fsm.sh init` na existující state soubor → exit 1 (prevent duplicate init)
- [ ] Všechny valid transitions v konstantě jsou testovány v `test-fsm.sh`
- [ ] `scripts/tests/run-all-tests.sh` zahrnuje `test-fsm.sh`

**Effort:** M
**AID Role:** backend

---

### Step 4: aid-run-gates.sh — Deterministická evaluace bran

**Objective:** Implementovat `scripts/aid-run-gates.sh` který čte brány z `execution.yaml`, spouští každý příkaz, vyhodnocuje exit code a produkuje JSON report kompatibilní s `AidGatesReport` TypeScript interface.

**Files:**
- Create: `scripts/aid-run-gates.sh` — gate runner
- Create: `scripts/gates/scope-check.sh` — bash implementace scope_check (náhrada za rule gate)
- Create: `scripts/tests/test-run-gates.sh` — bash testy (cíl: 10 testů)
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` — přidat `type: command|rule` pole, povýšit `security_scan_pass` na `required: true`

**Architecture Context:**
Gate evaluace je v v1.7.0 prováděna `quality-gates-runner` LLM agentem — agent spustí příkaz a "zhodnotí výsledek". Toto je nedeterministické. `aid-run-gates.sh` přebírá tuto roli: čte `execution.yaml`, spouští každý `command:` příkaz přes `bash -c`, kontroluje exit code, logguje výsledek. LLM gate (`docs_updated`) je jedinou výjimkou — script ji přeskočí a vrátí `{"result":"llm-required"}` pro zpracování Controllerem.

**Implementation Detail:**

```bash
#!/usr/bin/env bash
# scripts/aid-run-gates.sh — Deterministic gate evaluation
# Usage: aid-run-gates.sh <execution_yaml> <epic_id> <run_id> <timeline_file>

set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
require_yq

EXEC_YAML="$1"
EPIC_ID="$2"
RUN_ID="$3"
TIMELINE="$4"

overall_result="pass"
gates_json="{}"

# Čtení bran z execution.yaml
gate_names=( $(yq '.gates | keys | .[]' "$EXEC_YAML") )

for gate in "${gate_names[@]}"; do
  gate_type=$(yq ".gates.${gate}.type // \"command\"" "$EXEC_YAML")
  required=$(yq ".gates.${gate}.required // false" "$EXEC_YAML")
  timeout_sec=$(yq ".gates.${gate}.timeout_seconds // 300" "$EXEC_YAML")

  if [[ "$gate_type" == "rule" ]]; then
    # LLM gate — přeskočit, vrátit llm-required
    gate_json=$(jq -n --arg g "$gate" '{"result":"llm-required","exit_code":-1,"duration_ms":0,"output":"","attempts":0}')
    gates_json=$(echo "$gates_json" | jq --arg g "$gate" --argjson v "$gate_json" '. + {($g): $v}')
    continue
  fi

  command=$(yq ".gates.${gate}.command" "$EXEC_YAML")
  attempts=0; result="fail"; exit_code=1; output=""

  for attempt in 1 2; do  # max 2 attempts (1 + 1 retry)
    attempts=$attempt
    start_ms=$(date +%s%3N)
    output=$(timeout "$timeout_sec" bash -c "$command" 2>&1) && exit_code=0 || exit_code=$?
    duration_ms=$(( $(date +%s%3N) - start_ms ))

    if (( exit_code == 0 )); then result="pass"; break; fi

    # Lint auto-fix: spustit fixující příkaz pokud existuje
    auto_fix=$(yq ".gates.${gate}.auto_fix_command // \"\"" "$EXEC_YAML")
    if [[ -n "$auto_fix" && $attempt -eq 1 ]]; then
      bash -c "$auto_fix" >/dev/null 2>&1 || true
      continue  # zkusit znovu po auto-fix
    fi
    break  # žádný auto-fix, konec
  done

  [[ "$result" == "fail" && "$required" == "true" ]] && overall_result="fail"

  gate_json=$(jq -n \
    --arg result "$result" \
    --argjson exit_code "$exit_code" \
    --argjson duration "$duration_ms" \
    --arg output "$output" \
    --argjson attempts "$attempts" \
    '{"result":$result,"exit_code":$exit_code,"duration_ms":$duration,"output":$output,"attempts":$attempts}')
  gates_json=$(echo "$gates_json" | jq --arg g "$gate" --argjson v "$gate_json" '. + {($g): $v}')

  # Log do timeline
  bash "$(dirname "$0")/lib/aid-stage-log.sh" "$TIMELINE" "gate_${result}" \
    "gate=${gate}" "result=${result}" "exit_code=${exit_code}" "duration_ms=${duration_ms}"
done

# Final report (stdout)
jq -n \
  --arg epic "$EPIC_ID" \
  --arg run "$RUN_ID" \
  --arg overall "$overall_result" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson gates "$gates_json" \
  '{"epic_id":$epic,"run_id":$run,"overall":$overall,"completed_at":$ts,"gates":$gates}'

[[ "$overall_result" == "pass" ]] && exit 0 || exit 1
```

`scripts/gates/scope-check.sh` — deterministická náhrada za rule gate:
```bash
#!/usr/bin/env bash
# Zkontroluje, že upravené soubory jsou v allowed_paths pro aktuální krok
# Usage: scope-check.sh <plan_json> <step_id>

PLAN_JSON="$1"; STEP_ID="$2"

allowed=( $(jq -r ".steps[] | select(.id == \"$STEP_ID\") | .allowed_paths[]" "$PLAN_JSON" 2>/dev/null) )
forbidden=( $(jq -r ".steps[] | select(.id == \"$STEP_ID\") | .forbidden_paths // [] | .[]" "$PLAN_JSON" 2>/dev/null) )

changed=$(git diff --name-only HEAD 2>/dev/null || git diff --cached --name-only)

while IFS= read -r file; do
  for pattern in "${forbidden[@]}"; do
    [[ "$file" == $pattern ]] && echo "VIOLATION: $file matches forbidden_path: $pattern" && exit 1
  done
done <<< "$changed"

exit 0
```

**Error Handling:**
- `execution.yaml` neexistuje: exit 1 s cestou, žádný JSON na stdout
- `timeout` příkaz není dostupný: fallback na `bash -c` bez timeoutu + varování na stderr
- `jq` není dostupný: exit 1 s install instrukcí
- Gate příkaz selže s signal (exit > 128): zaznamenat jako fail, output = "killed by signal"

**Edge Cases:**
- Gate `when:` podmínka (conditional gates): přidat `when` evaluaci — pokud podmínka neplatí, vrátit `{"result":"skipped"}`
- `scope_check` gate v FAST MODE: skip (FAST MODE nemá plan.json s allowed_paths)
- Prázdný `gates` v execution.yaml: vrátit `{"overall":"pass","gates":{}}` — prázdná brána = pass

**Dependencies:**
- Depends on: Step 3 (aid-fsm.sh, pro loggování po gate evaluation)
- Depends on: Step 6 (aid-stage-log.sh — musí existovat pro timeline logging)
- Blocks: Step 5 (aid-stage-log.sh je dependency)

**Acceptance Criteria:**
- [ ] `aid-run-gates.sh execution.yaml E-001 R-001-1 timeline.jsonl` produkuje validní JSON na stdout
- [ ] Exit 0 pokud všechny required brány prochází, exit 1 jinak
- [ ] Rule gate (`docs_updated`) vrací `"result":"llm-required"` bez spuštění příkazu
- [ ] Auto-fix pro lint (`ruff --fix`) se spustí automaticky při fail a gate se zkusí znovu
- [ ] `scope-check.sh` detekuje soubory mimo allowed_paths a vrací exit 1
- [ ] `scripts/tests/run-all-tests.sh` zahrnuje `test-run-gates.sh`
- [ ] `security_scan_pass` je v `execution.yaml` s `required: true`

**Effort:** M
**AID Role:** backend

---

### Step 5: aid-stage-log.sh + aid-token-count.sh

**Objective:** Implementovat dvě utility knihovny: `lib/aid-stage-log.sh` pro deterministické JSONL logování a `lib/aid-token-count.sh` pro charcter-based odhad tokenů.

**Files:**
- Create: `scripts/lib/aid-stage-log.sh` — JSONL logging funkce
- Create: `scripts/lib/aid-token-count.sh` — token estimation
- Create: `scripts/tests/test-stage-log.sh` — bash testy (cíl: 8 testů)

**Architecture Context:**
`aid-stage-log.sh` nahrazuje nedeterministické logování kde LLM dostával instrukci "append to stage_log.jsonl" — výsledkem byly nekonzistentní záznamy. Deterministická funkce zajistí, že každý záznam v `timeline.jsonl` je validní JSON s garantovanými poli. `aid-token-count.sh` nahrazuje `token-estimator.md` skill (potvrzeno: 0 usage dat = LLM instrukci ignoroval).

**Implementation Detail:**

`lib/aid-stage-log.sh`:
```bash
#!/usr/bin/env bash
# Append structured JSON event to timeline.jsonl
# Usage: source lib/aid-stage-log.sh && log_event <file> <event> [key=value ...]
# Or standalone: aid-stage-log.sh <file> <event> [key=value ...]

log_event() {
  local timeline_file="$1"; shift
  local event="$1"; shift
  local extras="{}"

  # Parse key=value args
  for arg in "$@"; do
    local key="${arg%%=*}" value="${arg#*=}"
    extras=$(echo "$extras" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
  done

  local entry
  entry=$(jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg event "$event" \
    --argjson extras "$extras" \
    '{"ts": $ts, "event": $event} + $extras')

  # Atomic append: write to tmp, then mv (atomic on same filesystem)
  local tmp_file="${timeline_file}.tmp.$$"
  echo "$entry" >> "$tmp_file"
  cat "$tmp_file" >> "$timeline_file"
  rm -f "$tmp_file"
}

# Standalone usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  log_event "$@"
fi
```

`lib/aid-token-count.sh`:
```bash
#!/usr/bin/env bash
# Estimate token count from text or file
# Usage: aid-token-count.sh [--file path | --text "string"] [--type prose|code|mixed]
# Output: JSON {"estimated_tokens":N,"char_count":N,"content_type":"X","ratio":3.5}

count_tokens() {
  local input="" content_type="mixed"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) input=$(cat "$2"); shift 2 ;;
      --text) input="$2"; shift 2 ;;
      --type) content_type="$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  local char_count=${#input}
  local ratio
  case "$content_type" in
    prose|english) ratio=4.0 ;;
    code)          ratio=3.0 ;;
    yaml|json)     ratio=3.2 ;;
    markdown)      ratio=3.8 ;;
    *)             ratio=3.5 ;;  # mixed default
  esac

  # Integer arithmetic: ceil(char_count / ratio)
  # Use awk for float division
  local estimated_tokens
  estimated_tokens=$(awk -v c="$char_count" -v r="$ratio" 'BEGIN{printf "%d", int(c/r + 0.5)}')

  jq -n \
    --argjson tokens "$estimated_tokens" \
    --argjson chars "$char_count" \
    --arg type "$content_type" \
    --argjson ratio "$ratio" \
    '{"estimated_tokens":$tokens,"char_count":$chars,"content_type":$type,"ratio":$ratio}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  count_tokens "$@"
fi
```

**Error Handling:**
- `jq` není dostupný v `aid-stage-log.sh`: fallback na `echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\"}"` (degraded JSONL bez extras)
- `timeline_file` parent adresář neexistuje: `mkdir -p "$(dirname "$timeline_file")"` před zápisem
- tmp file cleanup při přerušení (SIGINT): `trap 'rm -f "$tmp_file"' EXIT INT TERM`

**Edge Cases:**
- Velmi dlouhý text (> 1 MB) pro `aid-token-count.sh`: `char_count` přetéká 32-bit bash arithmetic → použít `awk` (64-bit float)
- Prázdný string pro `log_event`: přidat validaci, prázdný event string = varování na stderr + skip
- Souběžné zápisy do stejného `timeline_file`: atomický append přes tmp+mv minimalizuje race condition (není 100% safe pro > 2 souběžné procesy)

**Dependencies:**
- Depends on: `jq` a `awk` (dostupné v ubuntu-latest CI)
- No dependency on other steps — nezávislý utility

**Acceptance Criteria:**
- [ ] `log_event timeline.jsonl "step_dispatch" state=EXECUTE role=architect` produkuje validní JSON řádek v souboru
- [ ] Každý JSON řádek v timeline.jsonl je parsovatelný přes `jq . < timeline.jsonl`
- [ ] `count_tokens --text "Hello world" --type prose` vrací `{"estimated_tokens":2,...}`
- [ ] `count_tokens --file large-file.md` pro 10 000 znakový soubor vrací rozumný odhad (±20 %)
- [ ] Souběžné volání `log_event` z 3 procesů neprodukuje nevalidní JSONL

**Effort:** S
**AID Role:** backend

---

**EPIC 3: Steps 6-11 — Skills & Agent Consolidation**

### Step 6: agent-protocol.md + role-cards.md — Eliminace playbook duplikace

**Objective:** Napsat `skills/agent-protocol.md` (sdílený protokol pro všechny agenty) a `skills/role-cards.md` (30-50 řádků per role), čímž se eliminuje 1 306 řádků duplikátního boilerplate z 11 playbooks a 9 agent souborů.

**Files:**
- Create: `plugins/aid-orchestrator/skills/agent-protocol.md` — ~250 řádků
- Create: `plugins/aid-orchestrator/skills/role-cards.md` — ~500 řádků (11 rolí + 4 focus karty)
- Delete: `plugins/aid-orchestrator/defaults/playbooks/architect.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/backend.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/frontend.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/domain.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/qa.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/security.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/observability.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/docs.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/release.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/docs-generic.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/docs-docusaurus.md`
- Delete: `plugins/aid-orchestrator/defaults/playbooks/e2e.md`

**Architecture Context:**
Analýza 11 playbook souborů (1 406 řádků celkem) odhalila, že každý obsahuje ~65-70 řádků identického boilerplate: Git Discipline, Improvement Notes format, Discovered Issues format, Output Requirements, Pre-Output Quality Check. Tyto sekce jsou identické word-for-word ve všech 9 role playbooks. `agent-protocol.md` tyto sekce absorbuje jednou. `role-cards.md` obsahuje pouze unikátní obsah per role (identity, capabilities, constraints, improvement hints) v 30-50 řádcích.

**Implementation Detail:**

`skills/agent-protocol.md` — struktura:
```markdown
# Agent Protocol v2

**Loaded:** Automatically for every dispatched agent before role card.

## Input Format (step_spec)
[Přesná YAML schema step_spec — zkopírovat z aktuálního agent-core.md]

## Output Format (step_output)
[Přesná YAML schema step_output — zkopírovat z aktuálního agent-core.md]

## improvement_notes Format
[Přesná schema + 5 příkladů — zkopírovat z improvement-proposals.md]

## Generic Constraints
- Scope Enforcement: ONLY modify files in step_spec.allowed_paths
- Status values: completed | partial | blocked
- NEVER commit directly — leave git status clean, controller commits

## Git Discipline
[Zkopírovat identickou sekci z playbooks]

## Pre-Output Quality Check
[Zkopírovat identickou sekci z playbooks]

## Execution Summary Format
[Zkopírovat z agent-core.md]
```

`skills/role-cards.md` — jedna karta (backend):
```markdown
## backend

**Identity:** Implement server-side logic — API endpoints, services, repositories,
database migrations, external integrations. Translate Architect contracts and Domain
models into working code.

**Capabilities:**
- REST/GraphQL API endpoints (controllers, request validation, response mapping)
- Service layer (application services, transactions, DI container)
- Data access (repositories, migrations, database indexes, data mappers)
- Middleware (authentication, logging, rate limiting, error handling)
- External service integrations (HTTP clients, retry, circuit breaker)
- Background jobs (async workers, idempotency, cron scheduling)

**Role-Specific Constraints:**
- MUST follow API contracts defined by architect step. Deviations → improvement_note.
- MUST use domain models from domain step. No duplicated business logic in service layer.
- NEVER write frontend code (JSX, CSS, browser APIs).
- NEVER modify database schema without a migration file.

**Improvement Hints:** Watch for N+1 queries, missing caching, swallowed exceptions,
business logic in controllers, missing structured logging, no retry on external calls.

**Model:** opus
```

**Error Handling:**
- Pokud agent dostane role kartu, která neexistuje v `role-cards.md`: fallback na generic implementer prompt (bez role-specific constraints) + logovat warning do `timeline.jsonl`
- Pokud `agent-protocol.md` není načten před role kartou: role karta na začátku odkazuje "FIRST: read skills/agent-protocol.md" — agent si ho musí přečíst

**Edge Cases:**
- Nová role přidána do plánu ale chybí role karta: dispatcher detekuje absenci karty a použije generic template
- Role `e2e` z `e2e.md` playbooku (žádný agent neexistuje): přidat jako focus kartu pro verifier agenta

**Dependencies:**
- No dependencies — lze začít ihned
- Blocks: Step 7 (rewrite agent souborů vyžaduje role-cards.md)

**Acceptance Criteria:**
- [ ] `agent-protocol.md` obsahuje VŠECHNY povinné sekce: Input Format, Output Format, improvement_notes, Generic Constraints, Git Discipline, Pre-Output Quality Check, Execution Summary
- [ ] `role-cards.md` obsahuje karty pro: architect, domain, backend, frontend, qa, security, observability, docs-writer, release, code-review (focus), docs-review (focus), security-audit (focus), e2e (focus)
- [ ] Každá role karta je 30-60 řádků (ne méně, ne více)
- [ ] Všechny 12 playbook souborů jsou smazány
- [ ] Grep na libovolný verbatim playbook text (např. "Git Discipline") nenachází výsledek v smazaných souborech
- [ ] `agent-protocol.md` neobsahuje žádné zakázané fráze ze skill plan-writing.md

**Effort:** M
**AID Role:** architect

---

### Step 7: Rewrite role agentů jako parametrické wrappery + sloučení curator

**Objective:** Přepsat všech 9 role agent souborů jako ~20řádkové parametrické wrappery (implementer.md, verifier.md) a sloučit curator.md + lessons-extractor.md do jednoho agenta.

**Files:**
- Create: `plugins/aid-orchestrator/agents/implementer.md` — ~20 řádků
- Create: `plugins/aid-orchestrator/agents/verifier.md` — ~20 řádků
- Modify: `plugins/aid-orchestrator/agents/curator.md` — sloučit lessons-extractor (~200 řádků výsledek)
- Modify: `plugins/aid-orchestrator/agents/auditor.md` — zkrátit z 780 na ~400 řádků (smazat Token Efficiency H + Deterministic Work I sekce)
- Delete: `plugins/aid-orchestrator/agents/architect.md`
- Delete: `plugins/aid-orchestrator/agents/domain.md`
- Delete: `plugins/aid-orchestrator/agents/backend.md`
- Delete: `plugins/aid-orchestrator/agents/frontend.md`
- Delete: `plugins/aid-orchestrator/agents/qa.md`
- Delete: `plugins/aid-orchestrator/agents/security.md`
- Delete: `plugins/aid-orchestrator/agents/observability.md`
- Delete: `plugins/aid-orchestrator/agents/docs-writer.md`
- Delete: `plugins/aid-orchestrator/agents/release.md`
- Delete: `plugins/aid-orchestrator/agents/lessons-extractor.md`
- Delete: `plugins/aid-orchestrator/agents/code-reviewer.md`
- Delete: `plugins/aid-orchestrator/agents/docs-reviewer.md`
- Delete: `plugins/aid-orchestrator/agents/run-validator.md` (nahrazeno bash validací v aid-fsm.sh)
- Delete: `plugins/aid-orchestrator/agents/quality-gates-runner.md` (nahrazeno aid-run-gates.sh)
- Delete: `plugins/aid-orchestrator/agents/project-scanner.md` (sloučeno do /aid-init)

**Architecture Context:**
Analýza 9 role agent souborů (3 926 řádků celkem) prokázala, že 80 % obsahu je identický boilerplate (Input/Output format, workflow steps, constraints) — nyní v `agent-protocol.md`. Zbývající 20 % je unikátní obsah role — nyní v `role-cards.md`. Agent soubor v v2 je jen router: "načti protocol, načti svou kartu, proveď krok."

**Implementation Detail:**

`agents/implementer.md`:
```markdown
---
name: implementer
model: "{resolved from role-cards.md for this role}"
---

# Implementer Agent

**Protocol:** Read `skills/agent-protocol.md` BEFORE starting.
**Role Card:** Read your role from `skills/role-cards.md` → section `## {role}`.

## Dispatch Parameters

You receive in `step_spec`:
- `role` — which role card to follow (architect, backend, frontend, domain, observability, docs-writer, release)
- Standard step_spec fields (see agent-protocol.md)

## Execution

1. Read `skills/agent-protocol.md` — I/O format, constraints, git discipline
2. Read `skills/role-cards.md` → section matching your `{role}`
3. Follow role Identity, Capabilities, and Constraints
4. Execute step per acceptance criteria
5. Output per agent-protocol.md format (include improvement_notes)

**Last Updated:** 2026-03-03
```

`agents/curator.md` — sloučená verze (klíčové přidané sekce z lessons-extractor):
```markdown
## Lessons Extraction (Combined from lessons-extractor)

After collecting improvement_notes, also collect:
1. **Working Commands:** Any bash/CLI commands that succeeded in this EPIC
   → Store in `.aid-o/work/memory/command-history.md`
2. **Lessons Learned:** Any non-obvious findings about the project or process
   → Store in `.aid-o/work/memory/lessons-learned.md`
3. **Gotchas:** Things that caused unexpected failures
   → Same file as lessons, section "## Gotchas"

Both improvement_notes collection AND lessons extraction happen in single CURATOR_RESOLVE pass.
Output format:
  curator_output:
    proposals: [...]       # improvement proposals (existing)
    lessons: [...]         # NEW: lessons learned
    commands: [...]        # NEW: working commands
    gotchas: [...]         # NEW: gotchas
```

**Error Handling:**
- Controller dostane step s `role: e2e` ale verifier.md nemá e2e focus kartu: použít generic verifier prompt + logovat warning
- Smazání agent souborů zatímco stará version v1 ještě běží: provést smazání až po potvrzení, že žádná v1 session není aktivní

**Edge Cases:**
- `plugin.json` stále odkazuje na smazané agenty: Step 11 (plugin.json update) musí proběhnout souběžně nebo bezprostředně po

**Dependencies:**
- Depends on: Step 6 (role-cards.md musí existovat)
- Blocks: Step 11 (plugin.json update vyžaduje finální seznam agentů)

**Acceptance Criteria:**
- [ ] `implementer.md` je < 25 řádků
- [ ] `verifier.md` je < 25 řádků
- [ ] `curator.md` obsahuje sekci "Lessons Extraction"
- [ ] `auditor.md` je < 420 řádků (z původních 780)
- [ ] Všech 13 smazaných agentů fyzicky neexistuje
- [ ] `plugin.json` neodkazuje na smazané agenty (validace v Acceptance Criteria Step 11)

**Effort:** M
**AID Role:** architect

---

### Step 8: Nový skills/pipeline.md — Centrální FSM skill (14 skillů → 1)

**Objective:** Napsat `skills/pipeline.md` (~1 200 řádků) jako centrální skill, který nahrazuje 14 starých skill souborů obsahujících FSM, dispatch, gate evaluaci, eskalaci a related logiku.

**Files:**
- Create: `plugins/aid-orchestrator/skills/pipeline.md` — ~1 200 řádků
- Delete: `plugins/aid-orchestrator/skills/epic-orchestration.md`
- Delete: `plugins/aid-orchestrator/skills/epic-state-machine.md`
- Delete: `plugins/aid-orchestrator/skills/dispatch-protocol.md`
- Delete: `plugins/aid-orchestrator/skills/gate-evaluation.md`
- Delete: `plugins/aid-orchestrator/skills/first-aid-controller.md`
- Delete: `plugins/aid-orchestrator/skills/auto-done-state.md`
- Delete: `plugins/aid-orchestrator/skills/auto-escalation.md`
- Delete: `plugins/aid-orchestrator/skills/parallel-dispatch.md`
- Delete: `plugins/aid-orchestrator/skills/gates-engine.md`
- Delete: `plugins/aid-orchestrator/skills/retry-engine.md`
- Delete: `plugins/aid-orchestrator/skills/analysis-merge.md`
- Delete: `plugins/aid-orchestrator/skills/cost-optimization.md`
- Delete: `plugins/aid-orchestrator/skills/epic-queue.md`
- Delete: `plugins/aid-orchestrator/skills/token-estimator.md`
- Delete: `plugins/aid-orchestrator/skills/workflow-intelligence.md`
- Delete: `plugins/aid-orchestrator/skills/improvement-proposals.md`
- Delete: `plugins/aid-orchestrator/skills/analytics.md`
- Delete: `plugins/aid-orchestrator/skills/slack-mcp.md`
- Delete: `plugins/aid-orchestrator/skills/agent-core.md`

**Architecture Context:**
`pipeline.md` je jedinou Markdown instrukcí, kterou Controller (orchestrující LLM) potřebuje pro řízení celého EPIC pipeline. Je strukturovaná per-state — Controller čte pouze sekci pro aktuální stav, ne celý soubor. 1 200 řádků je výrazně méně než 14 oddělených souborů (celkem ~8 000 řádků) a eliminuje 36 cyklů cross-referencí.

**Implementation Detail:**

Struktura `pipeline.md`:
```markdown
# AID Pipeline — Controller Reference

## State: READY
[Jak Controller validuje plan.json, co zobrazit PM v manual mode, co udělat v auto mode]

## State: EXECUTE
[Jak sestavit dispatch prompt z role-cards.md, jak volat Task tool, co kontrolovat po dokončení, kdy advance-step vs. escalate]

## State: GATES
[Jak číst výstup aid-run-gates.sh, co dělat s llm-required branch, kdy volat Curator hook, jak retry (max 2), kdy escalate]

## State: ESCALATION
[Jak prezentovat selhání PM, 8 trigger triggers (zjednodušeno z 16), options A/B/C, auto-mode pause + notify]

## State: DONE
[Merge branch, archive run, update queue, version bump pokud release EPIC, final report]

## Auto Mode (FIRST AID)
[Mode flag v state.yaml, autonomous decisions vs. escalation, escalation budget (max 3)]

## Parallel Dispatch
[DAG z plan.json, Task tool parallelism, worktree per EPIC, merge sequence]

## Dispatch Template
[Šablona pro sestavení agent prompt: permissions + EPIC context + step objective + scope + previous outputs]

## Model Tiers
[Tabulka role → model tier (přeneseno z cost-optimization.md)]

## Queue Management
[epic-queue.yaml format, auto-pickup v FIRST AID mode]
```

Klíčový design: Každá sekce je **self-contained** — Controller načte soubor a přejde přímo na `## State: EXECUTE` pro aktuální operaci. Žádné cross-reference na jiné skill soubory.

**Error Handling:**
- Pokud pipeline.md přesáhne 1 500 řádků: split do `pipeline-advanced.md` (parallel dispatch, analytics) a zachovat hlavní soubor < 1 200 řádků
- Controller načte pipeline.md ale nenajde sekci pro aktuální stav: fallback na ESCALATION s reason "FSM state not found in pipeline.md"

**Edge Cases:**
- Slack notifikace zmíněna v ESCALATION sekci: inline 20řádkový protokol (ne celý slack-mcp.md) s graceful degradation pokud MCP není dostupné
- PM_APPROVAL checkpoint (v1): absorbovat do DONE state jako volitelný confirmation krok

**Dependencies:**
- Depends on: Step 6 (role-cards.md pro dispatch template reference)
- Blocks: Step 10 (aid-run-epic.md update vyžaduje nový pipeline.md)

**Acceptance Criteria:**
- [ ] `pipeline.md` je < 1 500 řádků
- [ ] Soubor obsahuje sekce: `## State: READY`, `## State: EXECUTE`, `## State: GATES`, `## State: ESCALATION`, `## State: DONE`, `## Auto Mode`, `## Parallel Dispatch`, `## Dispatch Template`, `## Model Tiers`, `## Queue Management`
- [ ] Žádná sekce neodkazuje na smazané skill soubory
- [ ] 0 forbidden phrases (scan dle plan-writing.md pravidel)
- [ ] 19 smazaných skill souborů fyzicky neexistuje
- [ ] `markdown-lint.yml` CI projde (Last Updated footer přítomen)

**Effort:** L
**AID Role:** architect

---

### Step 9: Konsolidace zbývajících skills (planner + brainstorming + memory + run-management)

**Objective:** Zkrátit `planner.md` (2 017 → ~800 řádků), sloučit 3 brainstorming soubory do jednoho (~400 řádků), zkrátit `memory-mcp.md` (1 084 → ~300 řádků jako `memory.md`), zkrátit `run-management.md` (589 → ~300 řádků). Smazat `knowledge-acquisition.md` a `brainstorming-workflow.md` jako samostatné soubory.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` — zkrátit z 2 017 na ~800 řádků
- Create: `plugins/aid-orchestrator/skills/brainstorming.md` (nová, sloučená verze)
- Rename/Modify: `plugins/aid-orchestrator/skills/memory-mcp.md` → `skills/memory.md`
- Modify: `plugins/aid-orchestrator/skills/run-management.md` — zkrátit na ~300 řádků
- Delete: `plugins/aid-orchestrator/skills/brainstorming-knowledge.md`
- Delete: `plugins/aid-orchestrator/skills/brainstorming-workflow.md`
- Delete: `plugins/aid-orchestrator/skills/knowledge-acquisition.md`

**Architecture Context:**
`planner.md` (85 KB) je největší skill soubor — obsahuje plnou implementaci Plan→EPIC→JSON procesu. Velká část obsahu je duplicitní s bash skriptem `aid-epic-to-json.sh` (Kahnův algoritmus). Zkrátit na esenciální Markdown část: prompt engineering pro step granularity, role assignment, dependency declaration. Bash skript dělá deterministické zpracování. `brainstorming.md` sloučí tři soubory zachováním core flow + workflow detection + knowledge integration jako volitelné sekce.

**Implementation Detail:**
- `planner.md` zkrátit odstraněním: 30řádkové "legacy plan format" sekce, příklady step outputs (přesunout do templates/), duplicitní dependency pravidla (jsou v bash scriptu), workflow detection logika (→ brainstorming.md)
- `brainstorming.md` nová struktura: Core Flow (8 kroků zachovat) + Workflow Detection (z brainstorming-workflow.md, 50 klíčových řádků) + Knowledge Integration (z brainstorming-knowledge.md, 30 klíčových řádků) + Language Handling
- `memory.md`: zachovat Qdrant interface (store/find), smazat examples a aging TTL sekce (→ integrations.yaml)
- `run-management.md`: zachovat Run file lifecycle a session checkpoint protokol, smazat archiving details (→ DONE state v pipeline.md)

**Error Handling:**
- Brainstorming workflow detection odkazuje na Docker templates: přesunout templates do `defaults/templates/docker-compose-template.yml`, ne inline v skill souboru

**Edge Cases:**
- `planner.md` odkazuje na `brainstorming-workflow.md` (smazaný): odstranit reference, nahradit inline poznámkou

**Dependencies:**
- Depends on: Step 8 (pipeline.md — run-management.md reference musí být kompatibilní)
- No blocking dependencies

**Acceptance Criteria:**
- [ ] `planner.md` < 850 řádků
- [ ] `brainstorming.md` < 450 řádků, obsahuje sekce: Core Flow, Workflow Detection, Knowledge Integration, Language Handling
- [ ] `memory.md` < 350 řádků
- [ ] `run-management.md` < 320 řádků
- [ ] 3 smazané brainstorming soubory + `knowledge-acquisition.md` fyzicky neexistují
- [ ] Žádný ze zachovaných skill souborů neodkazuje na smazané soubory

**Effort:** M
**AID Role:** architect

---

**EPIC 4: Steps 10-15 — Commands, UX & Config**

### Step 10: Nový příkaz /aid-do — Fast Mode

**Objective:** Implementovat `/aid-do` příkaz pro Fast Mode — přímá implementace úkolu < 2 hodiny s lightweight evidence logem a auto-escalací do EPIC MODE pokud scope exploduje.

**Files:**
- Create: `plugins/aid-orchestrator/commands/aid-do.md` — Fast Mode command (~150 řádků)
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — přidat aid-do command
- Create: `plugins/aid-orchestrator/skills/fast-mode.md` — Fast Mode helper skill (~100 řádků)

**Architecture Context:**
`/aid-do` je vstupní bod pro 80 % denní práce — tasky < 2 hodiny, jednoduchá implementace bez multi-agent orchestrace. UX cíl: nulový overhead (žádný Plan, EPIC, FSM), výstup do terminálu < 10 sekund. Evidence trail: jeden soubor `Q-NNN.md` v `.aid-o/work/quick/`. Auto-escalace se spustí pokud scope překročí 2 ze 4 triggers: > 5 souborů, 3+ architekturální vrstvy, DB migrace, > 30 min odhad.

**Implementation Detail:**

`commands/aid-do.md` — flow:
```
Step 1: Parse task description ze vstupu
Step 2: Auto-init .aid-o/ pokud neexistuje (7 souborů, silent)
Step 3: Read project-profile.yaml (stack context)
Step 4: Brief codebase scan — relevantní soubory k task description
Step 5: Display single-line preview:
  /aid-do: {task}
  ════════
  Context: {detected_stack}
  Approach: {1-2 sentence plan}
  Scope: ~{N} files

Step 6: Implement directly (native Claude Code behavior)
Step 7: Scope check after first 3 files:
  IF > 5 files OR 3+ layers OR migration:
    Offer escalation to /aid-run
Step 8: Write Q-NNN.md quick log
Step 9: Display completion summary + contextual tip
```

`Q-NNN.md` format:
```markdown
# Q-{NNN}: {task-description}
- Started: {ISO timestamp}
- Duration: {N}m {N}s
- Files changed: {list}
- Commit: {hash}
- Escalated to EPIC: no
```

Quick log numbering: Read `.aid-o/03-config/counter.yaml` → `quick:` field (přidat nové pole). Pokud chybí, inicializovat na 0.

**Error Handling:**
- Task description je prázdná: zobrazit "Usage: /aid-do <task description>" a exit
- `.aid-o/` neexistuje: auto-init (7 souborů), pak pokračovat bez přerušení flow
- Auto-escalation dialog: uživatel odpovídá "N" → pokračovat v Fast Mode s varováním o větší komplexitě

**Edge Cases:**
- Task description je cesta k souboru (e.g., `/aid-do fix ./src/auth.ts`): interpretovat jako "fix problémy v tomto souboru"
- Uživatel použije `/aid-do` v EPIC-managed projektu kde je FIRST AID aktivní: zobrazit varování "FIRST AID je aktivní — /aid-do operuje mimo EPIC pipeline"

**Dependencies:**
- Depends on: Step 5 (aid-stage-log.sh pro zápis Q-NNN.md)
- No blocking dependencies

**Acceptance Criteria:**
- [ ] `/aid-do add dark mode toggle` spustí implementaci bez dotazu na Plan/EPIC
- [ ] Po implementaci existuje `Q-NNN.md` v `.aid-o/work/quick/`
- [ ] Auto-init vytvoří 7 souborů pokud `.aid-o/` neexistuje
- [ ] Auto-escalation dialog se zobrazí pokud > 5 souborů změněno
- [ ] `/aid-do` není v plugin.json jako `aid-do-epic` nebo jiný název — musí být přesně `aid-do`
- [ ] Celkový overhead pro single-file change je < 2 minuty

**Effort:** M
**AID Role:** frontend

---

### Step 11: Konsolidace příkazů (14 → 8) + plugin.json update

**Objective:** Sloučit 14 příkazů do 8, přepsat sloučené command soubory, smazat eliminované, aktualizovat plugin.json manifest.

**Files:**
- Create: `plugins/aid-orchestrator/commands/aid-plan.md` — sloučení brainstorm + write-plan + plan-epic
- Create: `plugins/aid-orchestrator/commands/aid-status.md` — sloučení epic-status + epic-queue
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — sloučení s aid-setup + auto-detect stacku
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (aid-run-epic.md → rename) — nový 6-state FSM
- Modify: `plugins/aid-orchestrator/commands/aid-audit.md` — sloučení s analytics
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — progressive disclosure
- Delete: `plugins/aid-orchestrator/commands/aid-brainstorm.md`
- Delete: `plugins/aid-orchestrator/commands/aid-write-plan.md`
- Delete: `plugins/aid-orchestrator/commands/aid-plan-epic.md`
- Delete: `plugins/aid-orchestrator/commands/aid-epic-status.md`
- Delete: `plugins/aid-orchestrator/commands/aid-epic-queue.md`
- Delete: `plugins/aid-orchestrator/commands/aid-setup.md`
- Delete: `plugins/aid-orchestrator/commands/aid-first-aid.md`
- Delete: `plugins/aid-orchestrator/commands/aid-analytics.md`
- Delete: `plugins/aid-orchestrator/commands/aid-research.md`
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — finální manifest

**Architecture Context:**
`/aid-plan` integruje tři příkazy s jasným sub-mode systémem: `/aid-plan` (interactive), `/aid-plan brainstorm <idea>`, `/aid-plan write <spec>`, `/aid-plan task <plan>`. `/aid-run` nahrazuje `/aid-run-epic` + `/aid-first-aid` (→ `/aid-run --auto`). `/aid-init` absorbuje `/aid-setup` — auto-detekce stacku proběhne vždy při inicializaci.

**Implementation Detail:**

`plugin.json` finální manifest:
```json
{
  "name": "aid-orchestrator",
  "version": "2.0.0",
  "agents": [
    {"name":"implementer","file":"agents/implementer.md"},
    {"name":"verifier","file":"agents/verifier.md"},
    {"name":"gate-fixer","file":"agents/gate-fixer.md"},
    {"name":"curator","file":"agents/curator.md"},
    {"name":"auditor","file":"agents/auditor.md"},
    {"name":"scanner","file":"agents/scanner.md"},
    {"name":"run-validator","file":"agents/run-validator.md"}
  ],
  "skills": [
    {"name":"agent-protocol","file":"skills/agent-protocol.md"},
    {"name":"pipeline","file":"skills/pipeline.md"},
    {"name":"planner","file":"skills/planner.md"},
    {"name":"brainstorming","file":"skills/brainstorming.md"},
    {"name":"quality-gates","file":"skills/quality-gates.md"},
    {"name":"run-management","file":"skills/run-management.md"},
    {"name":"memory","file":"skills/memory.md","optional":true},
    {"name":"role-cards","file":"skills/role-cards.md"}
  ],
  "commands": [
    {"name":"aid-do","file":"commands/aid-do.md"},
    {"name":"aid-plan","file":"commands/aid-plan.md"},
    {"name":"aid-run","file":"commands/aid-run.md"},
    {"name":"aid-status","file":"commands/aid-status.md"},
    {"name":"aid-help","file":"commands/aid-help.md"},
    {"name":"aid-init","file":"commands/aid-init.md"},
    {"name":"aid-audit","file":"commands/aid-audit.md"},
    {"name":"aid-stop","file":"commands/aid-stop.md"}
  ]
}
```

`/aid-help` progressive disclosure — default výstup (Level 1-2):
```
AID v2 — AI Development Orchestrator
═══════════════════════════════════
  /aid-do <task>   Do it now — implements with lightweight log
  /aid-plan [mode] Design before building
  /aid-run [flags] Orchestrated multi-agent pipeline
  /aid-status      What's running, what's queued
  /aid-help        This help

More: /aid-help all   (shows init, audit, stop)
```

**Error Handling:**
- Příkaz `-first-aid` stále v historii Claude Code session: zobrazit "⚠ /aid-first-aid → použijte /aid-run --auto"

**Edge Cases:**
- Uživatel zadá `/aid-brainstorm` (smazaný příkaz): Claude Code zobrazí "command not found" — přidat do aid-help poznámku o přejmenování

**Dependencies:**
- Depends on: Step 8 (pipeline.md), Step 9 (skills konsolidace), Step 10 (/aid-do)

**Acceptance Criteria:**
- [ ] plugin.json obsahuje přesně 7 agents, 8 skills, 8 commands
- [ ] plugin.json neodkazuje na žádný smazaný soubor (verify: `for f in $(jq -r '.agents[].file,.skills[].file,.commands[].file' plugin.json); do [ -f "$f" ] || echo "MISSING: $f"; done`)
- [ ] 9 smazaných command souborů fyzicky neexistují
- [ ] `/aid-help` zobrazuje pouze 5 core příkazů by default
- [ ] `/aid-help all` zobrazuje všech 8 příkazů
- [ ] `/aid-run --auto` spouští FIRST AID mode (ekvivalent starého `/aid-first-aid`)
- [ ] `/aid-plan brainstorm` spouští brainstorm flow (ekvivalent starého `/aid-brainstorm`)

**Effort:** M
**AID Role:** frontend

---

### Step 12: YAML konsolidace (10 → 3 policy souborů) + workspace redesign

**Objective:** Sloučit 10 YAML policy souborů do 3 (`orchestration.yaml`, `execution.yaml`, `integrations.yaml`) a redesignovat `/aid-init` výstup ze 40 souborů na 10.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/orchestration.yaml` — sloučení dispatch-config + decision-policies + dispatch-strategy + language
- Create: `plugins/aid-orchestrator/defaults/execution.yaml` — sloučení gates + release-policy
- Create: `plugins/aid-orchestrator/defaults/integrations.yaml` — sloučení memory-config + slack-config (optional)
- Delete: `plugins/aid-orchestrator/defaults/policies/dispatch-config.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/decision-policies.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/dispatch-strategy.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/gates.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/release-policy.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/memory-config.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/slack-config.yaml`
- Delete: `plugins/aid-orchestrator/defaults/policies/permissions.yaml` (→ inline v aid-init.md)
- Delete: `plugins/aid-orchestrator/defaults/policies/skill-conflicts.yaml` (→ inline v aid-init.md)
- Delete: `plugins/aid-orchestrator/defaults/policies/language.yaml` (→ orchestration.yaml)
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — nový workspace design

**Architecture Context:**
10 policy souborů je překomlikované pro solo developer use case. Klíčové skupiny: (1) orchestrace a dispatch (5 souborů → `orchestration.yaml`), (2) gate execution a release (2 soubory → `execution.yaml`), (3) optional integrace (2 soubory → `integrations.yaml`). `permissions.yaml` a `skill-conflicts.yaml` jsou statické konstanty vhodné jako inline obsah v `/aid-init`.

Nový `/aid-init` workspace (10 souborů místo 40):
```
.aid-o/
  config/
    project.yaml          (auto-detected stack)
    orchestration.yaml    (z defaults/orchestration.yaml)
    execution.yaml        (z defaults/execution.yaml)
  work/
    active.md
    timeline.jsonl
    backlog.md
    memory/
      lessons-learned.md
      command-history.md
  plans/                  (prázdný)
  tasks/                  (prázdný)
```

Lazy-created soubory (na první použití):
- `config/integrations.yaml` — při `/aid-run --auto` nebo Qdrant/Slack detekci
- `work/queue.yaml` — při prvním `/aid-status queue add`
- `work/quick/` — při prvním `/aid-do`

**Implementation Detail:**

`orchestration.yaml` klíčová struktura (viz Architecture část výše pro kompletní schéma).

`execution.yaml` — kritická změna oproti starému `gates.yaml`:
- `security_scan_pass.required: true` (z false)
- Přidat `scope_check` jako `type: command` (náhrada rule gate)
- Přidat `version_consistency` jako conditional command gate

`integrations.yaml` — `enabled: false` pro obě integrace by default.

**Error Handling:**
- Existující `.aid-o/03-config/policies/` adresář: `/aid-init --upgrade` přemigruje soubory a nabídne smazání starých
- `yq` není dostupný pro čtení nových YAML souborů: bash skripty přidají `require_yq` check (Step 3)

**Edge Cases:**
- Projekt-specifická konfigurace v `gates.yaml` (custom příkazy): `/aid-init --upgrade` detekuje nestandardní hodnoty a zachová je v `execution.yaml`
- Migrace z v1.7.0 `.aid-o/` struktury: `/aid-init --upgrade` přejmenuje adresáře (01-plans→plans, 02-epics→tasks, 04-engine→work)

**Dependencies:**
- Depends on: Step 3 (aid-fsm.sh čte state.yaml, ne policy soubory — ale aid-run-gates.sh čte execution.yaml)

**Acceptance Criteria:**
- [ ] `defaults/` obsahuje přesně 3 YAML soubory (orchestration, execution, integrations)
- [ ] 10 starých policy souborů fyzicky neexistuje
- [ ] `execution.yaml` má `security_scan_pass.required: true`
- [ ] `/aid-init` vytvoří přesně 10 souborů v `.aid-o/` (ověřit: `find .aid-o -type f | wc -l == 10`)
- [ ] `aid-run-gates.sh` úspěšně čte brány z nového `execution.yaml`
- [ ] `aid-fsm.sh` úspěšně čte mode z nového `orchestration.yaml`
- [ ] `/aid-init --upgrade` migruje existující v1.7.0 workspace bez ztráty dat

**Effort:** M
**AID Role:** backend

---

### Step 13: packages/aid-contract/ — TypeScript data kontrakt

**Objective:** Vytvořit nový npm package `packages/aid-contract/` s TypeScript typy definujícími formální kontrakt mezi pluginem (data producer) a GUI serverem (data consumer).

**Files:**
- Create: `packages/aid-contract/package.json`
- Create: `packages/aid-contract/tsconfig.json`
- Create: `packages/aid-contract/src/types.ts` — všechny interfacy (viz Data Model sekce)
- Create: `packages/aid-contract/src/index.ts` — re-export
- Modify: `packages/aid-server/package.json` — přidat `@aid/contract` dependency
- Modify: `packages/aid-server/src/routes/*.ts` — importovat typy z kontraktu místo lokálních definicí
- Modify: `packages/aid-server/src/pipeline.ts` — aktualizovat `.aid-o/` cesty pro novou strukturu

**Architecture Context:**
GUI server (`aid-server`) čte `.aid-o/` soubory a streamuje přes WebSocket. Kontrakt definuje přesné schéma souborů, které plugin produkuje a server konzumuje. Bez formálního kontraktu jsou breaking changes v `.aid-o/` formátu neviditelné dokud GUI nespadne. `packages/aid-contract/` jako sdílený npm package umožní statickou validaci TypeScript kompilátorem.

**Implementation Detail:**

`packages/aid-contract/package.json`:
```json
{
  "name": "@aid/contract",
  "version": "2.0.0",
  "description": "TypeScript interfaces for AID Orchestrator file format contract",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}
```

`packages/aid-server/src/pipeline.ts` path updates (nová .aid-o/ struktura):
```typescript
// Stará cesta:
const STAGE_LOG = path.join(aidRoot, '04-engine', 'evidence', epicId, runId, 'stage_log.jsonl');
// Nová cesta:
const TIMELINE = path.join(aidRoot, 'work', 'evidence', epicId, runId, 'timeline.jsonl');

// Stará cesta:
const AUTO_MODE_STATE = path.join(aidRoot, '04-engine', 'auto-mode-state.yaml');
// Nová cesta:
const FSM_STATE = path.join(aidRoot, 'work', 'evidence', epicId, runId, 'state.yaml');
```

**Error Handling:**
- `aid-server` dostane request na `epicId` jehož `state.yaml` neexistuje: return 404 s `{"error":"epic_not_found","epic_id":"E-003"}`
- `timeline.jsonl` má nevalidní JSON řádek (crash uprostřed zápisu): server skip nevalidní řádky a logovat warning, ne 500 error

**Edge Cases:**
- Staré `.aid-o/` s `stage_log.jsonl` (v1.7.0 formát) a nové `.aid-o/` s `timeline.jsonl` (v2): server detekuje oba formáty a mapuje na `AidTimelineEntry` interface
- WebSocket streaming: odeslat `{"event":"format_v2","version":"2.0.0"}` jako první zprávu aby GUI vědělo který formát očekávat

**Dependencies:**
- Depends on: Step 3 (state.yaml schema finální)
- Depends on: Step 5 (timeline.jsonl schema finální)
- Blocks: GUI Redesign EPIC (čeká na tento kontrakt)

**Acceptance Criteria:**
- [ ] `packages/aid-contract/` je validní npm package (`npm run build` → dist/)
- [ ] `packages/aid-server/` importuje typy z `@aid/contract` (ne lokálně definované)
- [ ] `tsc --noEmit` v aid-server prochází bez chyb po přidání kontraktu
- [ ] Server vrací 404 (ne 500) pro neexistující epic_id
- [ ] Nevalidní JSON řádek v timeline.jsonl nespustí server 500

**Effort:** S
**AID Role:** backend

---

**EPIC 5: Steps 14-17 — Validace, QA & Release**

### Step 14: Nové bash testy pro controller layer

**Objective:** Napsat ~25 nových bash testů pro `aid-fsm.sh`, `aid-run-gates.sh`, `aid-stage-log.sh` a `aid-token-count.sh`. Rozšířit `run-all-tests.sh` o nové test soubory. Cíl: 115+ celkových bash testů.

**Files:**
- Create: `scripts/tests/test-fsm.sh` — 15 testů pro aid-fsm.sh
- Create: `scripts/tests/test-run-gates.sh` — 10 testů pro aid-run-gates.sh
- Create: `scripts/tests/test-stage-log.sh` — 8 testů pro aid-stage-log.sh
- Modify: `scripts/tests/run-all-tests.sh` — přidat nové test soubory

**Architecture Context:**
Bash controller layer je jediná deterministická část systému — musí být důkladně testována. Nové testy pokrývají: všechny valid/invalid FSM transitions, gate pass/fail evaluaci, JSONL validitu stage logu, token estimation přesnost. Stávající 92 testů testují pipeline skripty — nové testy testují controller vrstvu.

**Implementation Detail:**

`test-fsm.sh` — klíčové testy:
```bash
# Test: valid transitions
run_test "READY->EXECUTE transition" "aid-fsm.sh transition state.yaml EXECUTE" 0
run_test "EXECUTE->DONE invalid" "aid-fsm.sh transition state.yaml DONE" 1
run_test "advance-step returns ALL_STEPS_DONE at last step" \
  "for i in $(seq 1 6); do aid-fsm.sh advance-step state.yaml; done | tail -1" 0 "ALL_STEPS_DONE"
run_test "init fails on existing state file" \
  "aid-fsm.sh init E-001 R-001 6 auto main abc state.yaml" 1
```

`test-run-gates.sh` — klíčové testy:
```bash
run_test "passing gate returns exit 0" \
  "echo 'gates:\n  test:\n    command: \"exit 0\"\n    required: true\n    type: command' > /tmp/exec.yaml && \
   aid-run-gates.sh /tmp/exec.yaml E-001 R-001 /tmp/tl.jsonl" 0
run_test "failing required gate returns exit 1" \
  "... command: \"exit 1\" ... required: true ..." 1
run_test "rule gate returns llm-required without running command" \
  "... type: rule ..." 0  # (exits 0 because only LLM gate, no required command gates failed)
```

**Error Handling:**
- Test setup/teardown: každý test vytvoří temp directory, cleanup na exit
- Paralelní test execution: žádné sdílené tmp soubory — každý test dostane unikátní prefix

**Edge Cases:**
- `run-all-tests.sh` hledá test soubory globem `test-*.sh`: nové soubory budou automaticky nalezeny
- CI runner má jiný `date` format (macOS vs. Linux): ISO 8601 výstup je konzistentní

**Dependencies:**
- Depends on: Step 3, 4, 5 (testované scripty musí existovat)

**Acceptance Criteria:**
- [ ] `scripts/tests/run-all-tests.sh` reportuje 115+ testů po přidání nových souborů
- [ ] 0 failing testů na čistém clone repositáře
- [ ] CI `bash-tests` job prochází s novými testy
- [ ] Každý valid FSM transition je pokryt minimálně jedním testem
- [ ] Gate evaluation pro pass/fail/skip/llm-required je pokryta

**Effort:** M
**AID Role:** qa

---

### Step 15: Vitest update + TypeScript build verifikace

**Objective:** Aktualizovat Vitest testy pro nové `.aid-o/` cesty (timeline.jsonl místo stage_log.jsonl, work/ místo 04-engine/), ověřit TypeScript build pro aid-server + aid-gui + aid-contract.

**Files:**
- Modify: `packages/aid-server/tests/**/*.test.ts` — aktualizovat mock cesty
- Modify: `packages/aid-gui/tests/**/*.test.ts` — aktualizovat mock data
- Modify: `vitest.config.ts` — přidat aid-contract package

**Architecture Context:**
Vitest testy testují aid-server API routes a GUI komponenty. Změna `.aid-o/` struktury (01-plans→plans, 04-engine→work) rozbije testy které mockují konkrétní cesty. Testy musí být aktualizovány aby odrážely nový kontrakt.

**Implementation Detail:**
- Nalézt všechny Vitest soubory obsahující `04-engine` nebo `stage_log.jsonl`: `grep -r "04-engine\|stage_log" packages/*/tests/ --include="*.ts"`
- Nahradit `04-engine` → `work`, `stage_log.jsonl` → `timeline.jsonl`
- Přidat testy pro nové API endpoints (state.yaml, Q-NNN quick log)

**Error Handling:**
- Vitest mock filesystem (`memfs` nebo `vol`): nová struktura musí být reflektována v mock setup

**Edge Cases:**
- Tests mockují AidStateYaml pro 11 stavů (v1) — aktualizovat na 5 stavů (v2)

**Dependencies:**
- Depends on: Step 13 (aid-contract typy)

**Acceptance Criteria:**
- [ ] `npm test` prochází pro všechny packages
- [ ] `npm run build` prochází pro aid-server, aid-gui, aid-contract
- [ ] 0 TypeScript kompilační chyby po `tsc --noEmit`
- [ ] CI `vitest` a `build-check` joby prochází

**Effort:** S
**AID Role:** qa

---

### Step 16: Validace na assignment1 (external EPIC)

**Objective:** Spustit AID v2 na prvním externím projektu (assignment1 — Crypto/Macro Intelligence Agent, EPIC ve frontě) jako reálný integrace test. Měřit KPIs a porovnat s v1.7.0 assignment2 baseline.

**Files:**
- Read: `/opt/_home/small-personal-projetcs/assignment1/.aid-o/02-epics/E-001-1_1-*.md` — EPIC specifikace
- Monitor: `/opt/_home/small-personal-projetcs/assignment1/.aid-o/work/evidence/` — evidence output
- Create: `VALIDATION-REPORT.md` v ai-orchestrator root — výsledky měření

**Architecture Context:**
assignment1 má aktivní EPIC `E-001-1_1-crypto-macro-intelligence-agent` ve frontě. Je to školní projekt (podobný assignment2 který byl úspěšně dokončen v 1h 5m, 0 eskalací). Validace ověří, že nový bash controller, zredukované skills a parametrické agenty produkují stejně kvalitní výstup jako v1.7.0.

**Implementation Detail:**

KPI tabulka pro měření:
| KPI | Baseline (v1.7.0 / assignment2) | Target (v2.0 / assignment1) |
|-----|----------------------------------|------------------------------|
| Prompt tokeny per dispatch | ~35K (odhadováno) | < 8K (-77%) |
| Čas od `/aid-run` k prvnímu souboru | ~15 min | < 5 min |
| State machine chyby (wrong transition) | neměřeno | 0 |
| Gate false positives | neměřeno | ≤ 1 |
| Curator proposals implemented | assignment2: 0 (jiný projekt) | ≥ 1 |
| Celkový čas EPIC | 1h 5m | < 1h 30m (overhead přijatelný pro learning) |

**Error Handling:**
- Pokud v2 systém selže uprostřed EPIC: `state.yaml` umožní resume; dokumentovat v VALIDATION-REPORT.md jako "crash + resume" test case
- Pokud KPI není měřitelný (token count): použít char count jako proxy

**Edge Cases:**
- assignment1 EPIC byl vytvořen v v1.7.0 formátu: `/aid-init --upgrade` nejprve
- assignment1 závisí na Qdrant MCP (Qdrant agent v tech stacku): ověřit dostupnost před startem

**Dependencies:**
- Depends on: Všechny předchozí kroky (1-15)

**Acceptance Criteria:**
- [ ] EPIC pro assignment1 dokončen bez manuálního zásahu (0 eskalací v auto mode)
- [ ] `VALIDATION-REPORT.md` obsahuje naměřené KPI hodnoty
- [ ] `state.yaml` je validní YAML po celou dobu EPIC
- [ ] `timeline.jsonl` obsahuje validní JSONL (všechny řádky parsovatelné)
- [ ] Aid-server GUI zobrazuje správný stav bez chyb
- [ ] Výstup (Python kód) prochází 50%+ testů (assignment2 dosáhl 50/50)

**Effort:** L
**AID Role:** qa

---

### Step 17: Release v2.0.0

**Objective:** Aktualizovat všech 8 version locations na "2.0.0", napsat CHANGELOG entry, vytvořit git tag, aktualizovat README.

**Files:**
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — version: "2.0.0"
- Modify: `.claude-plugin/marketplace.json` — metadata.version: "2.0.0"
- Modify: `packages/aid-server/package.json` — version: "2.0.0"
- Modify: `packages/aid-gui/package.json` — version: "2.0.0"
- Modify: `packages/aid-contract/package.json` — version: "2.0.0"
- Modify: `CHANGELOG.md` — přidat v2.0.0 sekci
- Modify: `README.md` — aktualizovat feature list, quickstart pro nové příkazy
- Create: `MIGRATION-GUIDE.md` — v1.7.0 → v2.0.0 migrace

**Implementation Detail:**

`CHANGELOG.md` v2.0.0 sekce musí obsahovat:
- Breaking Changes: přejmenované příkazy, nová .aid-o/ struktura
- New Features: /aid-do Fast Mode, bash controller layer, 6-state FSM
- Removed: seznam eliminovaných příkazů, skills, agentů
- Migration: odkaz na MIGRATION-GUIDE.md

`MIGRATION-GUIDE.md` klíčové sekce:
- Příkazy: `/aid-run-epic` → `/aid-run`, `/aid-first-aid` → `/aid-run --auto`, atd.
- `.aid-o/` struktura: 01-plans → plans, 04-engine → work, stage_log.jsonl → timeline.jsonl
- Policy soubory: 10 → 3 (co se přesunulo kam)
- `/aid-init --upgrade`: automatická migrace skript

**Error Handling:**
- Zapomenout aktualizovat jeden z 8 version locations: `version-sync.yml` CI job blokovku merge

**Dependencies:**
- Depends on: Step 16 (validace musí projít před release)

**Acceptance Criteria:**
- [ ] `version-sync.yml` CI job prochází (všech 8 locations = "2.0.0")
- [ ] `git tag v2.0.0` existuje
- [ ] `CHANGELOG.md` obsahuje sekci pro v2.0.0 s Breaking Changes
- [ ] `MIGRATION-GUIDE.md` existuje s kompletním command mapping a .aid-o/ path mapping
- [ ] `README.md` odkazuje na `/aid-do` jako primary entry point (ne `/aid-run-epic`)

**Effort:** S
**AID Role:** release

---

## Sekce čekající na background agenty

> **⚠️ GUI Redesign sekce** — agent analyzuje `packages/aid-gui/` a `packages/aid-server/`. Po dokončení bude přidána jako `## GUI Redesign` sekce s konkrétními kroky. GUI redesign bude pravděpodobně samostatný EPIC (P023).

> **⚠️ VULCAN Integration sekce** — agent hledá VULCAN projekt. Po nalezení bude přidána jako `## VULCAN Integration` sekce. Integrace bude pravděpodobně samostatný EPIC (P024).

---

## Testing Strategy

### Bash Tests (deterministická vrstva)
- Cíl: 115+ testů (z 92 stávajících)
- Nové soubory: `test-fsm.sh` (15), `test-run-gates.sh` (10), `test-stage-log.sh` (8)
- Runner: `scripts/tests/run-all-tests.sh --verbose`
- CI: `bash-tests` job v `ci.yml`

### TypeScript Tests (GUI + server)
- Stávající: 32 Vitest souborů
- Update: cesty pro novou .aid-o/ strukturu
- CI: `vitest` job v `ci.yml`

### Integration Test (validace)
- Step 16: Kompletní EPIC run na assignment1 (real external project)
- Měření KPI tabulky
- Crash recovery test: simulovat přerušení mid-EPIC, ověřit resume

### Structural Tests (Markdown)
- CI: `markdown-lint.yml`
- Kontroly: Last Updated footer, délka < 800 řádků, MUST Rules umístění
- Nelze automaticky testovat sémantiku LLM instrukcí

---

## Constraints

- **Bash kompatibilita:** bash 4.0+ (macOS default je bash 3.2 — uživatelé musí mít `brew install bash`)
- **jq dependency:** jq 1.6+ pro JSON zpracování v bash skriptech
- **yq dependency:** yq v4+ (mikefarah/yq) pro YAML zpracování
- **Node.js:** 20+ pro aid-server, aid-gui, aid-contract
- **Paralelní vývoj:** Fáze 2 (Skills) a Fáze 3 (Commands) jsou nezávislé a lze je provádět souběžně
- **Žádný break pro assignment1:** V1.7.0 musí zůstat funkční dokud není v2.0.0 validováno (Step 16)
- **GUI redesign** je out of scope tohoto plánu — čeká na analýzu background agenta

---

## Risks

| Riziko | Pravděpodobnost | Dopad | Mitigace |
|--------|----------------|-------|----------|
| `pipeline.md` (1 200 řádků) je příliš velký pro efektivní LLM použití | Střední | Vysoký | Strukturovat per-state sekce; Controller čte pouze relevantní sekci |
| Role karty (30-50 řádků) neposkytují dostatek kontextu pro složité role (architect) | Nízká | Střední | Testovat s assignment1; rozšířit konkrétní kartu pokud kvalita klesne |
| `aid-fsm.sh` přidá vlastní komplexitu | Nízká | Střední | Max 300 řádků; FSM jako `case` statement je triviální bash |
| Migrace existujících assignment1 `.aid-o/` workspace selhá | Střední | Střední | `/aid-init --upgrade` + backup `.aid-o.v1-backup/` |
| yq v4 není dostupný v CI runner | Nízká | Vysoký | Přidat `sudo apt-get install -y yq` do `ci.yml` setup kroku |
| 36 cross-reference cyklů způsobí problémy při rewrite skilling | Střední | Střední | Rewrite od nuly (ne refaktoring) eliminuje cykly; žádná migrace starého obsahu |
| GUI server se rozbije po .aid-o/ path změnách | Vysoká | Střední | Step 13 (aid-contract) + Step 15 (Vitest update) zajistí kompatibilitu |
| VULCAN projekt vyžaduje funkce mimo scope redesignu | Neznámá | Neznámá | Čeká na background agent analýzu |

---

## Success Criteria

- [ ] CI pipeline (3 workflows) prochází na každém PR
- [ ] 115+ bash testů, všechny prochází
- [ ] plugin.json obsahuje přesně 7 agentů, 8 skills, 8 příkazů — žádný soubor neodkazuje na neexistující resource
- [ ] `/aid-do "add dark mode"` dokončí implementaci < 2 minuty bez Plan/EPIC
- [ ] `/aid-run --auto` spustí FIRST AID mode (verifikace: assignment1 EPIC dokončen autonomně)
- [ ] `timeline.jsonl` je validní JSONL (všechny řádky parsovatelné `jq . < timeline.jsonl`)
- [ ] `state.yaml` umožní crash recovery: přerušení EPIC + resume ze správného stavu
- [ ] Prompt tokeny per dispatch < 10K (měřeno charcount/3.5 metodou)
- [ ] 0 smazaných souborů odkazovaných z existujících souborů (grep verifikace)
- [ ] assignment1 EPIC dokončen, výstup (kód) prochází testy

---

## Next Steps

- [ ] Schválit plán P022
- [ ] Spustit `/aid-plan-epic P022` → generuje EPICs, plan.json, run files
- [ ] Přidat do EPIC queue: EPIC 1 (CI), EPIC 2 (Bash Controller), EPIC 3-4 (Skills+Commands) souběžně, EPIC 5 (Validace)
- [ ] Doplnit GUI sekci po dokončení background agenta
- [ ] Doplnit VULCAN sekci po dokončení background agenta
- [ ] Spustit `/aid-run --auto` pro kompletní redesign

---

**Last Updated:** 2026-03-03
