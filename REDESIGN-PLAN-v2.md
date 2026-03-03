# AID Orchestrator — Master Redesign Plan v2.0

**Datum:** 2026-03-03
**Metoda:** 5 paralelních architektonických agentů + syntéza
**Status:** NÁVRH — čeká na schválení

---

## Přehled: Co se mění a proč

| Metrika | v1.7.0 (aktuální) | v2.0 (cíl) | Redukce |
|---------|-------------------|------------|---------|
| Prompt tokeny | ~400K | ~50K | **-87%** |
| Skill soubory | 27 | 8 | **-70%** |
| Agent soubory | 18 | 8 | **-56%** |
| Příkazy | 14 | 8 | **-43%** |
| Playbooks | 11 | 0 | **-100%** |
| YAML policy souborů | 10 | 3 | **-70%** |
| Soubory při `/aid-init` | ~40 | ~10 | **-75%** |
| FSM stavů | 11 | 6 | **-45%** |
| Cross-reference cykly | 36 | ~0 | **-100%** |
| Deterministický kód | ~5% | ~30% | **+6×** |
| Čas k prvnímu výsledku (jednoduchý task) | 30–60 min | < 2 min | **-95%** |

**Klíčový posun:** LLM dělá tvůrčí práci (kód, analýza, review). Bash řídí stav, loguje, validuje, spouští brány. Markdown instrukce přenáší *záměr*, ne *procedury*.

---

## Část 1: Architektura a FSM

### 1.1 Dva exekuční módy

```
Uživatelský požadavek
        │
        ├── /aid-do nebo přirozený jazyk → FAST MODE
        │   └── přímá implementace + git hooks brány + quick log
        │
        └── /aid-run nebo /aid-plan → EPIC MODE
            └── bash PRE-FLIGHT → 6-stavový FSM → evidence trail
```

**FAST MODE** — pro úkoly < 2 hodiny:
- Žádný Plan, EPIC, plan.json ani FSM
- Implementace přímo, git hooks zajistí brány deterministicky
- Evidence: jeden soubor `.aid-o/work/quick/Q-NNN.md`
- Escalace do EPIC MODE pokud scope exploduje (> 5 souborů, 3+ vrstvy)

**EPIC MODE** — pro úkoly 1+ den nebo noční autonomní běh:
- PRE-FLIGHT bash skripty: Plan → EPIC → plan.json → run.md
- 6-stavový FSM s obnovou po pádu session
- Plná evidence trail, multi-agent DAG dispatch, Curator

### 1.2 Nový 6-stavový FSM (z 11 stavů)

```
PRE-FLIGHT (bash)
Plan → EPIC → plan.json → run.md
          │
          ▼
       READY ─── reject ──▶ konec
          │
          │ approve (PM nebo auto)
          ▼
      ┌─ EXECUTE ◀─────────────┐
      │  (step N, agent dispatch) │
      │  step pass → next step    │
      │  all done ────────────────┘
      │
      │ all steps done
      ▼
     GATES (+ Curator hook)
      │
      ├── pass ──▶ DONE
      │
      └── fail ──▶ ESCALATION
                       │
                       ├── fix ──▶ EXECUTE (rework)
                       ├── skip ──▶ GATES
                       └── abort ──▶ konec
```

**Odstraněné stavy (z v1):** PLANNING (přesun do bash PRE-FLIGHT), PLAN_REVIEW (sloučen s READY), NEXT_PHASE (pointer increment, ne stav), PHASE_CHECK (sloučen s EXECUTE), GATE_RETRY (vnitřní smyčka GATES), CURATOR_RESOLVE (post-gate hook GATES), PM_APPROVAL (checkpoint v DONE).

### 1.3 Klíčová architektonická změna: Dvojvrstvý model

```
Vrstva 1 — CONTROLLER (bash + YAML, deterministický)
  - aid-fsm.sh:        validace přechodů, state.yaml
  - aid-run-gates.sh:  spuštění bran, exit code → pass/fail
  - aid-stage-log.sh:  append-only JSONL logging
  - aid-token-count.sh: character → token estimation
  - Existující pipeline skripty (zachovat beze změny)

Vrstva 2 — AGENT PROMPTS (Markdown, LLM)
  - Role playbooks: co agent dělá v daném kroku
  - Dispatch šablona: jak sestavit kontext pro agenta
  - Eskalační šablona: jak prezentovat selhání PM
  - Curator instrukce: co hledat v improvement proposals
```

LLM neřídí přechody stavů — přechody jsou funkce bash kontroleru na základě exit kódů a existence souborů.

### 1.4 Nativní integrace Claude Code (místo vlastních implementací)

| Claude Code schopnost | Nahrazuje v AID v1 | Akce |
|-----------------------|--------------------|------|
| Hooks (pre-commit) | `quality-gates.md`, `gates-engine.md` | Registrovat brány jako CC hooks |
| Task/Agent tool | Vlastní dispatch-protocol | Tenká šablona, ne process-skill |
| EnterWorktree | Vlastní worktree management (300+ řádků) | Eliminovat vlastní logiku |
| TodoWrite | `plan_progress.json` tracking (viditelnost) | Doplňuje `state.yaml` (recovery) |
| Plan mode | `brainstorming.md` (3 soubory, 70 KB) | Smazat všechny tři |

---

## Část 2: Skills a agenti

### 2.1 Konsolidace agentů: 18 → 8

**Parametrický model** — místo 18 pevně daných agentů: 2 generické agenty + 6 role karet.

| Agent v2 | Sloučeno z v1 | Model | Poznámka |
|----------|--------------|-------|----------|
| **implementer** | architect, domain, backend, frontend, observability, release, docs-writer | parametrický | Role karta injekce při dispatch |
| **verifier** | qa, security, code-reviewer, docs-reviewer | parametrický | Focus karta injekce |
| **gate-fixer** | gate-fixer + quality-gates-runner | haiku | Zachovat |
| **curator** | curator + lessons-extractor | sonnet | Zachovat, sloučit |
| **auditor** | auditor (trimmed) | sonnet | Zachovat, zkrátit z 780 na ~400 řádků |
| **scanner** | project-scanner | sonnet | Zachovat |
| **run-validator** | run-validator | haiku | Zachovat (nebo sloučit s gate-fixer) |

**Odstraněno (11 agentů):** code-reviewer, docs-reviewer, lessons-extractor, quality-gates-runner, project-scanner (→ scanner), domain (→ implementer/architect), observability (→ implementer), release (→ bash aid-release.sh).

### 2.2 Role karty a Focus karty

Playbooks (11 souborů, 1 406 řádků) se eliminují. Obsah přechází do:

- **`skills/role-cards.md`** — 30–50 řádků per role (Identity, Capabilities, Constraints, Improvement hints)
- **`skills/agent-protocol.md`** — boilerplate jednou (Input/Output format, git discipline, improvement_notes schema, pre-output quality check)

Příklad role karty (backend, ~25 řádků vs. 346 řádků v v1):
```markdown
## backend
**Identity:** Implementuji server-side kód — API, services, databáze, integrace.
**Capabilities:** [endpoint impl, services, repositories, migrations, auth middleware, integrations]
**Constraints:** MUSÍ dodržet API kontrakt architektury. NIKDY nepíše frontend.
**Improvement hints:** N+1 queries, chybějící retry, swallowed exceptions, logging.
**Model:** opus
```

### 2.3 Konsolidace skills: 27 → 8

| Skill v2 | Obsah | Nahrazuje |
|----------|-------|-----------|
| **agent-protocol.md** | I/O format, constraints, improvement_notes schema | agent-core + improvement-proposals + playbook boilerplate |
| **pipeline.md** | 6-stavový FSM, dispatch template, gate evaluation, escalation triggers, curator, DONE, auto-mode, queue | epic-orchestration + epic-state-machine + dispatch-protocol + gate-evaluation + first-aid-controller + auto-done-state + auto-escalation + parallel-dispatch + gates-engine + retry-engine + analysis-merge + cost-optimization + epic-queue + slack-mcp |
| **planner.md** | Plan → EPIC → JSON logika | planner + plan-writing (zmenšit z 85 KB) |
| **brainstorming.md** | Brainstorming flow (pokud nezvolíme CC Plan mode) | brainstorming + brainstorming-workflow + brainstorming-knowledge |
| **quality-gates.md** | Pre-commit 6 bran (standalone) | quality-gates |
| **run-management.md** | Run file lifecycle, checkpoints | run-management |
| **memory.md** | Qdrant protokol (optional) | memory-mcp + knowledge-acquisition (selective) |
| **role-cards.md** | Všechny role/focus karty | 11 playbooks |

**Eliminováno bez náhrady:** token-estimator (→ bash script), workflow-intelligence (→ nativní LLM), analytics (→ GUI), slack-mcp (→ 20 řádků v pipeline.md).

**Odhad tokenů po konsolidaci:** ~50K (z ~400K = -87%)

### 2.4 Curator redesign — zachovat, zjednodušit

Curator funguje (21 implementovaných oprav prokázáno). Problém: backlog sync je nekompletní.

**Oprava:** Pre-flight status update PŘED implementací (ne po):
```
1. Approve proposal → zapsat status: "implementing" do backlog.md
2. Implementovat fix
3. Výsledek → update na "implemented" nebo "deferred: fix failed"
```

Pokud agent selže uprostřed, status "implementing" je viditelný — PM může rozhodnout. Atomický zápis → žádný backlog drift.

**Zjednodušení 3-tier evaluace:**
- Zachovat: YAML pravidla (funguje)
- Eliminovat: Qdrant tier 2 (nikdy neprodukoval užitečná data pro single-project)
- Default: approve S effort, defer M/L

---

## Část 3: UX a příkazy

### 3.1 Nový příkazový systém: 8 příkazů (z 14)

**5 core příkazů (viditelné každému):**

| Příkaz | Nahrazuje | Popis |
|--------|-----------|-------|
| `/aid-do <task>` | NOVÝ | Fast mode — implementuj teď, zaloguj co bylo |
| `/aid-plan [mode]` | /aid-brainstorm + /aid-write-plan + /aid-plan-epic | Design před implementací |
| `/aid-run [flags]` | /aid-run-epic + /aid-first-aid | Orchestrovaný pipeline |
| `/aid-status [target]` | /aid-epic-status + /aid-epic-queue | Stav všeho |
| `/aid-help [topic]` | /aid-help | Dokumentace (výrazně zkrácená) |

**3 advanced příkazy:**

| Příkaz | Nahrazuje | Popis |
|--------|-----------|-------|
| `/aid-init` | /aid-init + /aid-setup | Setup workspace + auto-detekce stacku |
| `/aid-audit [type]` | /aid-audit + /aid-analytics | Health check projektu |
| `/aid-stop` | /aid-stop | Emergency halt |

**Eliminováno:** /aid-brainstorm, /aid-write-plan, /aid-plan-epic (→ /aid-plan), /aid-first-aid (→ /aid-run --auto), /aid-epic-status, /aid-epic-queue (→ /aid-status), /aid-research (nativní WebSearch), /aid-setup (→ /aid-init).

### 3.2 /aid-do — Fast Mode (nový)

```
/aid-do add login button with Google OAuth
══════════════════════════════════════════
Context: React + FastAPI, no existing auth
Approach: NextAuth.js + FastAPI callback
Scope: ~4 files

Working...

[implementace]

Done. 4 files changed.
Evidence: .aid-o/work/quick/Q-003.md
Time: 4m 12s

Tip: Pro multi-day features zkus /aid-plan.
```

**Auto-escalace** do EPIC MODE když:
- > 5 souborů přes 3+ vrstvy
- DB migrace potřeba
- Uživatel říká "je to větší než jsem čekal"

### 3.3 Terminologie — přechod na plain English

| Starý termín | Nový termín |
|-------------|-------------|
| CURATOR_RESOLVE | Auto-fix |
| PHASE_CHECK | Step review |
| PM_APPROVAL | Your approval |
| GATE_RETRY | Retry (test failed) |
| aspirin / steroids | Standard mode / Autonomous mode |
| Plan → EPIC → Run | Plan → Task → Run |
| Dispatch | Assign |
| Evidence store | Work log |
| stage_log.jsonl | timeline.jsonl |

### 3.4 Progressive disclosure

- **Level 0** (nový uživatel): žádné příkazy — AID se auto-spustí a nabídne (A) prostě to udělej / (B) naplánuj nejdřív
- **Level 1** (Beginner): `/aid-do`, `/aid-plan` — pokrývá 80% denní práce
- **Level 2** (Intermediate): + `/aid-run`, `/aid-status`, `/aid-help`
- **Level 3** (Advanced): + `/aid-init`, `/aid-audit`, `/aid-stop`

### 3.5 /aid-init redesign — 10 souborů místo 40

**Při inicializaci se vytvoří pouze:**
```
.aid-o/
  config/
    project.yaml          (auto-detekovaný stack)
    permissions.yaml      (standard/autonomous mode)
  work/
    active.md
    timeline.jsonl
    backlog.md
  plans/                  (prázdný adresář)
  tasks/                  (prázdný adresář)
```

Zbytek (gates.yaml, dispatch config, auto-mode config, queue) se vytvoří **lazy** při prvním použití příslušné funkce.

**Auto-init:** `/aid-init` se spustí automaticky při prvním použití jakéhokoli `/aid-*` příkazu — uživatel nikdy nemusí init volat manuálně.

---

## Část 4: Quality systém a CI

### 4.1 CI pipeline (aktuálně chybí)

**3 nové GitHub Actions workflows:**

**`ci.yml`** (každý PR + push do main):
- bash testy: `scripts/tests/run-all-tests.sh` (92 testů)
- TypeScript: `npm test` (32 Vitest souborů)
- Build check: `npm run build` pro aid-gui + aid-server
- Security regression: path traversal check (CWE-22)

**`markdown-lint.yml`** (pouze při změně skills/commands/agents):
- "Last Updated" footer přítomen
- Soubory < 800 řádků (warning, ne fail)
- MUST Rules sekce na začátku souboru

**`version-sync.yml`** (pouze main):
- Všech 8 version locations musí souhlasit

### 4.2 Deterministické vs. LLM brány (split 7:1)

| Brána | Typ v1 | Typ v2 | Implementace |
|-------|--------|--------|--------------|
| tests_pass | command | **deterministická** | exit code |
| lint_pass | command | **deterministická** | exit code |
| security_scan | command | **deterministická + required** | exit code |
| scope_check | rule (LLM) | **deterministická** | bash + git diff + allowed_paths |
| type_check | command | **deterministická** | exit code |
| build_pass | command | **deterministická** | exit code |
| version_consistency | neexistuje | **deterministická** | bash grep |
| docs_updated | rule (LLM) | **LLM, conditional** | zachovat, degradovat na optional |

### 4.3 Retry pravidla (per-gate místo globálních)

| Brána | Max pokusů | Po vyčerpání |
|-------|-----------|--------------|
| tests_pass | 2 | escalate |
| lint_pass | 0 (auto-fix příkazem) | warn |
| security_scan | 2 | escalate_urgent |
| scope_check | 0 | okamžitá eskalace |
| docs_updated | 1 | skip_with_warning |

Globální budget: max 10 LLM volání pro gate-fixing per EPIC.

### 4.4 FAST vs. EPIC brány

**FAST MODE** (git hooks, žádný LLM):
- Testy existující kod neporušují
- Žádné secrets v staged files
- Commit message format (regex)
- Build pokud se změnil frontend

**EPIC MODE** (plná sada + Curator post-gate hook):
- Všechny brány z tabulky výše
- Curator VŽDY po gatách (ne jen pokud zbyde čas)

---

## Část 5: Technický stack

### 5.1 Markdown vs. Kód — nová hranice

**Přesunout z Markdown do bash:**

```
Token counting      → aid-token-count.sh (charcount / ratio)
Stage log writing   → aid-stage-log.sh (validní JSONL, vždy)
State transitions   → aid-fsm.sh (validace přechodů, state.yaml)
Gate evaluation     → aid-run-gates.sh (exit code, ne LLM hodnocení)
Scope check         → scripts/gates/scope-check.sh
```

**Nové bash skripty:**

```bash
scripts/
  aid-fsm.sh           # Stavový automat: transition_state() s validací
  aid-run-gates.sh     # Gate runner: spustit command, loggovat výsledek
  lib/
    aid-token-count.sh # character-count / 3.5 → estimated_tokens (JSON output)
    aid-stage-log.sh   # aid_log_event() → append do stage_log.jsonl
```

**Zachovat beze změny:** Všech 5 existujících pipeline skriptů (92 testů prochází).

**Volitelný rewrite:** `aid-epic-to-json.sh` do TypeScriptu jako `packages/aid-pipeline/` — opodstatněný pouze pokud plánujeme aktivní vývoj s více contributors.

### 5.2 Config konsolidace: 10 → 3 YAML soubory

**`orchestration.yaml`** (sloučení 5 souborů):
```yaml
language: { document_language: EN }
models:
  opus: [architect, backend, frontend]
  sonnet: [qa, security, docs-writer, curator, auditor]
  haiku: [gate-fixer, run-validator]
dispatch:
  strategy: worktrees
  max_parallel: 4
escalation:
  max_per_session: 3
  triggers: [...]
fsm:
  states: [READY, EXECUTE, GATES, ESCALATION, DONE]
```

**`execution.yaml`** (sloučení 2 souborů):
```yaml
gates:
  tests_pass: { command: "pytest -q", required: true }
  security_scan: { command: "bandit -q -r . -ll", required: true }
  ...
release:
  changelog: CHANGELOG.md
  version_files: [package.json, pyproject.toml]
```

**`integrations.yaml`** (sloučení 2 volitelných souborů):
```yaml
qdrant: { enabled: false, collection: "aid-memory" }
slack:  { enabled: false, channel: "#aid-orchestrator" }
```

`permissions.yaml` a `skill-conflicts.yaml` → odstraněny, obsah přesunout jako inline konstanty do příkazu `/aid-init`.

### 5.3 GUI separace

GUI (aid-server + aid-gui) je de facto již separovaný — server pouze čte soubory, nikdy nepíše. Formalizovat přes **data contract**:

```typescript
// packages/aid-contract/src/types.ts (nový sdílený package)
export interface AidStageLogEntry { timestamp: string; state: AidFsmState; action: string; ... }
export interface AidPlanProgress { steps: Array<{ id: string; status: "pending"|"executing"|"completed"|"failed" }> }
export interface AidGatesReport { gates: Record<string, { result: "pass"|"fail"; exit_code: number }> }
```

Plugin produkuje soubory dle kontraktu. Server konzumuje. Možný deployment jako `npm install -g @aid/server` bez pluginu.

### 5.4 Plugin manifest v2

```json
{
  "agents":   8,  // implementer, verifier, gate-fixer, curator, auditor, scanner, run-validator
  "skills":   8,  // agent-protocol, pipeline, planner, brainstorming, quality-gates, run-management, memory, role-cards
  "commands": 8,  // aid-do, aid-plan, aid-run, aid-status, aid-help, aid-init, aid-audit, aid-stop
  "scripts":  {
    "pipeline": ["aid-auto-pipeline.sh", "aid-plan-to-epic.sh", "aid-epic-to-json.sh", "aid-json-to-run.sh", "aid-queue-add.sh"],
    "runtime":  ["aid-fsm.sh", "aid-run-gates.sh", "aid-token-count.sh", "aid-stage-log.sh"]
  }
}
```

---

## Část 6: Evidence trail redesign

### 6.1 Dva soubory místo 12+ typů per run

**`state.yaml`** — jediný mutabilní stavový soubor (crash recovery):
```yaml
epic_id: E-003-1_2
state: EXECUTE          # READY | EXECUTE | GATES | ESCALATION | DONE
current_step: 3
total_steps: 6
mode: auto
branch: task/E-003-1_2
base_commit: abc123
gate_retries: 0
escalation_count: 0
```

**`timeline.jsonl`** — append-only event log (evidence trail, nikdy se nemodifikuje):
```jsonl
{"ts":"...","event":"step_dispatch","step":1,"role":"architect","model":"opus"}
{"ts":"...","event":"step_complete","step":1,"result":"pass","duration_s":120}
{"ts":"...","event":"gate_run","gate":"tests","result":"pass","attempt":1}
```

**Crash recovery:** Najdi `state.yaml` kde `state != DONE` → obnov z `current_step` → re-dispatch (idempotentní).

### 6.2 Odstraněno z evidence

- Token estimates (nikdy nefungovaly)
- Separátní `pm_plan_approval.json`, `pm_decision.json`, `gates_report.json`, `curator_resolve_report.json` → vše jako události v `timeline.jsonl`
- `auto-mode-state.yaml` → pole `mode` v `state.yaml`

---

## Část 7: Implementační plán (fáze)

### Fáze 0: Příprava (1–2 dny)

- [ ] Přidat `ci.yml` workflow — bash + Vitest testy (žádný nový kód)
- [ ] Povýšit `security_scan_pass` na `required: true` v gates.yaml
- [ ] Opravit IMP-051, IMP-052 status v backlog.md (jsou fixnuté, jen backlog neaktualizován)
- [ ] Přidat `scope_check` jako deterministický bash skript (nahradit rule gate)

### Fáze 1: Bash controller layer (1 týden)

- [ ] Napsat `aid-fsm.sh` — 7-stavový automat s validací přechodů
- [ ] Napsat `aid-run-gates.sh` — deterministická gate evaluace z gates.yaml
- [ ] Napsat `lib/aid-stage-log.sh` — structured JSONL logging funkce
- [ ] Napsat `lib/aid-token-count.sh` — character→token estimation (nahradit token-estimator.md)
- [ ] Napsat testy pro nové skripty (cílový počet: 20+ nových bash testů)
- [ ] Napsat `aid-release.sh` — přesunout release logiku z release agenta

### Fáze 2: Skills a agenti (1 týden)

- [ ] Napsat `skills/agent-protocol.md` (~250 řádků) — eliminuje boilerplate ze všech playbooks
- [ ] Napsat `skills/role-cards.md` (~500 řádků) — všechny role a focus karty
- [ ] Napsat `skills/pipeline.md` (~1200 řádků) — **nový centrální skill** nahrazující 14 starých
- [ ] Zmenšit `skills/planner.md` — cíl < 400 řádků (z 2017)
- [ ] Sloučit `brainstorming*.md` → jeden soubor (~400 řádků)
- [ ] Zkrátit `agents/auditor.md` (~400 řádků z 780)
- [ ] Sloučit `curator.md` + lessons-extractor → jeden curator agent (~200 řádků)
- [ ] Přepsat role agenty jako tenké parametrické wrappery (~20 řádků každý)
- [ ] Smazat 19 eliminovaných skill souborů + 11 playbooks

### Fáze 3: Příkazy a UX (3–5 dní)

- [ ] Implementovat `/aid-do` (nový FAST MODE příkaz)
- [ ] Sloučit `/aid-brainstorm` + `/aid-write-plan` + `/aid-plan-epic` → `/aid-plan`
- [ ] Sloučit `/aid-epic-status` + `/aid-epic-queue` → `/aid-status`
- [ ] Sloučit `/aid-init` + `/aid-setup` → `/aid-init` s auto-detekcí
- [ ] Přepsat `/aid-first-aid` jako flag `/aid-run --auto`
- [ ] Redesignovat `/aid-help` — progressive disclosure (Level 1-2 default)
- [ ] Aktualizovat `/aid-run-epic` pro nový 6-stavový FSM a bash controller
- [ ] Auto-init logika — spustit init při prvním použití jakéhokoli příkazu

### Fáze 4: Config a workspace (2–3 dny)

- [ ] Sloučit 10 YAML souborů do 3 (`orchestration.yaml`, `execution.yaml`, `integrations.yaml`)
- [ ] Aktualizovat bash skripty pro čtení nových config souborů
- [ ] Redesignovat `/aid-init` výstup — cíl: 10 souborů místo 40
- [ ] Lazy initialization pro pokročilé config soubory
- [ ] Aktualizovat plugin.json manifest (8+8+8 → 8 agents, 8 skills, 8 commands)
- [ ] Přidat `packages/aid-contract/` — TypeScript typy pro data kontrakt

### Fáze 5: Validace (1 týden)

- [ ] Spustit nový systém na externím projektu (assignment1 je připraven ve frontě)
- [ ] Srovnat: čas k prvnímu výsledku, qualita evidence, Curator opravy
- [ ] Opravit problémy vzniklé přechodem
- [ ] Aktualizovat dokumentaci (README, CHANGELOG, Docusaurus)
- [ ] Release v2.0.0

---

## Co zachovat bez změny

Tyto části fungují a neměnit je:
1. **5 bash pipeline skriptů** — `aid-auto-pipeline.sh`, `aid-epic-to-json.sh` (Kahnův alg.), `aid-plan-to-epic.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`
2. **92 bash testů** — všechny prochází, rozšířit o nové
3. **Curator auto-fix pro S effort** — funguje, 21 implementovaných oprav
4. **FIRST AID autonomní mód** — prokázal hodnotu na assignment2 (1h 5m, 0 eskalací)
5. **Evidence trail concept** — zjednodušit format, zachovat princip
6. **Model tiers** (opus/sonnet/haiku) — přenést do role-cards.md
7. **GUI** (aid-server + aid-gui) — separátní projekt, zachovat

---

## Rizika a mitigace

| Riziko | Pravděpodobnost | Mitigace |
|--------|----------------|----------|
| `pipeline.md` (1200 řádků) bude příliš komplexní | Střední | Strukturovat per-state sekce, LLM čte relevantní sekci dle aktuálního stavu |
| Role karty (30-50 řádků) nestačí pro složité role | Nízká | Testovat s reálnými EPICs; pokud kvalita klesne, rozšířit konkrétní kartu |
| Bash controller přidá vlastní komplexitu | Střední | Max 500 řádků pro `aid-fsm.sh`. Bash FSM je `case` statement — řešený problém |
| Ztráta Curator hodnoty při zjednodušení | Nízká | Curator zůstává jako post-gate hook; mění se jen trigger mechanismus |
| Fast mode bez evidence v audit-critical projektech | Nízká | Dokumentovat: "pro audit použijte /aid-run". Git commit messages + hook logs = základní evidence |
| Migrace existujících `.aid-o/` workspace | Střední | `/aid-init --upgrade` migrační script; backup `.aid-o.v1-backup/` |

---

## Doporučené pořadí

1. **Fáze 0 nejdřív** — CI přinese okamžitou hodnotu, žádný redesign risk
2. **Fáze 1 (bash layer) před Fází 2 (Markdown)** — deterministic layer je základ pro testování nových skills
3. **Fáze 3 (UX) souběžně s Fází 2** — příkazy a skills jsou nezávislé
4. **Fáze 5 (validace) na skutečném projektu** — assignment1 je ideální kandidát (EPIC ve frontě, external projekt)

---

*Tento dokument byl vygenerován syntézou 5 paralelních architektonických agentů a reflektuje opravená data z Phase 3 CRITICAL-ASSESSMENT.md (Curator funguje, AID stavěl externí projekty).*
