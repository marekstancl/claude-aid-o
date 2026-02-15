# Claude Code Multi-Agent Orchestration Guide

> Kompletni prirucka k nativni multi-agent orchestraci v Claude Code
> pro projekt AI Development Orchestrator (ADO).
>
> Posledni aktualizace: 2026-02-15

---

## 1. Co stavime a proc

### Problem

Mas fungujici **single-agent** framework (Agent Skills v4.0 pro C.I.C.E.R.O.) —
jeden Claude Code agent zvlada: plan -> detail plan -> session -> tasky -> QC ->
atomicke commity -> gates -> HITL schvaleni.

Ale pro slozitejsi projekty (napr. ERP s 10+ moduly) chces **paralelni agenty
se specializovanymi rolemi**, ktere ridi centralni orchestrator.

### Reseni: ADO (AI Development Orchestrator)

Evoluce single-agenta do **Controller + Workers** architektury:

```
Dnes (single-agent):             Cil (ADO):

  Claude Code session            Controller (hlavni session)
       |                              |
    jeden agent                  +----+----+----+----+----+
    vsechny role                 |    |    |    |    |    |
                                 AR  DOM  BE   FE   QA  SEC  ...
                                 (9 specializovanych roli)
```

### Proc NE externi framework (CrewAI, LangGraph...)

| Aspekt | Externi framework | Nativni Claude Code |
|--------|-------------------|---------------------|
| Agenti umi | Jen generovat text | Cist/psat soubory, spoustet prikazy, git, testy |
| Vystup | Text v output/ | Realny commitnuty kod |
| Quality gates | Musis implementovat | Uz mas hotove (6 gates) |
| PM kontrola | Zadna | GO/REVISE/STOP na kazdem kroku |
| Scope enforcement | Zadne | Agent smi editovat jen povolene cesty |
| Cena | API tokeny per agent call | Zahrnuto v Claude Code session |
| LLM vendor | Libovolny (vyhoda) | Jen Claude (omezeni) |
| Infrastruktura | Python venv, pip, API keys | Zadna — jen Markdown soubory |

**Rozhodnuti:** Nativni Claude Code pokryva 80-90% ADO specifikace. Zbytek
(multi-provider, REST API, dashboard) je Phase F-G — optional nice-to-have.

---

## 2. Jak to funguje v Claude Code

### Tri vrstvy orchestrace

```
Vrstva 1: Commands (uzivatel vyvola)
  /plan-epic, /run-epic, /run-step, /epic-status
  = orchestracni prikazy, ktere ridí cely pipeline
      |
Vrstva 2: Agents (command nebo hlavni session dispatche)
  .claude/agents/architect.md, backend.md, qa.md, ...
  = specializovani subagenti, kazdy se svou roli
      |
Vrstva 3: Skills (automaticky se aktivuji)
  quality-gates, coding-standards, session-management, ...
  = guardrails a pravidla, ktera agenti dodrzuji
```

### Mechanismus: `.claude/agents/*.md`

Kazdy soubor v `.claude/agents/` se stane subagent. Definujes ho ciste v Markdownu:

```markdown
---
name: backend-developer
description: Implementuje backend kod podle architektonickeho navrhu
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---

# Backend Developer

## Tvoje role
Jsi senior Python/FastAPI developer...

## Pravidla
- NIKDY nemen API kontrakty bez schvaleni Architecta
- ...
```

**To je vse.** Zadny Python, zadny framework. Claude Code to nacte a muzes ho
dispatchnout pres Task tool.

### Jak se subagent spousti

Hlavni session (ty + Claude) pouzije `Task` tool:

```
Task(
  subagent_type="general-purpose",
  description="Implement backend for Orders",
  prompt="
    Jsi Backend Developer. Tvoje pravidla jsou v .claude/agents/backend.md.

    ## Kontext
    EPIC: EPIC-ERP-0003-ORDERS
    Architektura: [obsah ADR-0003]
    Domenovy model: [obsah domain.py]

    ## Ukol
    Implementuj FastAPI endpoints pro Orders modul.
    Pracuj POUZE v src/backend/orders/ a tests/orders/.

    ## Vystup
    Commitni kod do branch epic/ERP-0003-backend.
  "
)
```

Agent bezi ve vlastnim contextu, cte/pise soubory, spousti prikazy, commituje.
Pak vrati report hlavni session.

### Omezeni nativniho pristupu

1. **Jen Claude modely** — nemuzes mixovat GPT-4o a Claude
2. **Subagenti nemuzou spawovat dalsi subagenty** — max 1 uroven hloubky
3. **Paralelni subagenti sdileji filesystem** — resis pres branch per agent
4. **Context window** — kazdy subagent ma svuj context, je omezeny

---

## 3. Mapovani: Co mas -> Co pridas

### Tvuj existujici `claude/` setup (Agent Skills v4.0)

| Komponenta | Soubory | Status |
|------------|---------|--------|
| 5 subagenty | `agents/code-reviewer.md`, `docs-reviewer.md`, `lessons-extractor.md`, `quality-gates-runner.md`, `session-validator.md` | Hotovo |
| 8 commands | `commands/audit.md`, `coding-standards.md`, `docs-protocol.md`, `handoff.md`, `quality-gates.md`, `session-start.md`, `session-end.md`, `testing.md` | Hotovo |
| 11 skills | `skills/agent-core/`, `session-management/`, `quality-gates/`, `git-workflow/`, `testing-workflow/`, `coding-standards/`, `documentation-protocol/`, `project-audit/`, `debugging/`, `project-context-detection/`, `pm-commands/` | Hotovo |
| Hooks | `hooks/pre-commit-guard.sh` | Hotovo |
| Session mgmt | `settings.json` (SessionStart, PreToolUse, Stop hooks) | Hotovo |
| PM workflow | GO/REVISE/STOP/STATUS | Hotovo |

### Co pridas pro ADO

| Komponenta | Soubory | Ucel |
|------------|---------|------|
| **9 role-agents** | `agents/architect.md`, `domain.md`, `backend.md`, `frontend.md`, `qa.md`, `security.md`, `observability.md`, `docs-writer.md`, `release.md` | Specializovane vyvojove role |
| **4 orchestra commands** | `commands/plan-epic.md`, `run-epic.md`, `run-step.md`, `epic-status.md` | Rizeni EPIC pipeline |
| **1 orchestracni skill** | `skills/epic-orchestration/` | Logika Controller state machine |
| **Templates** | `templates/epic.md`, `templates/plan.schema.json` | Sablony pro EPICy a plany |
| **Policies** | `policies/gates.yaml` | Konfigurace quality gates |
| **Playbooks** | `playbooks/architect.md`, `backend.md`, ... | Detailni instrukce pro role |
| **Evidence store** | `evidence/<epic_id>/<run_id>/` | Audit trail kazdeho runu |

### Vysledna struktura

```
ai-orchestrator/
  .claude/
    agents/
      # Existujici (review/QA)
      code-reviewer.md
      docs-reviewer.md
      lessons-extractor.md
      quality-gates-runner.md
      session-validator.md
      # Nove (vyvojove role)
      architect.md
      domain.md
      backend.md
      frontend.md
      qa.md
      security.md
      observability.md
      docs-writer.md
      release.md
    commands/
      # Existujici
      audit.md, quality-gates.md, session-start.md, ...
      # Nove
      plan-epic.md
      run-epic.md
      run-step.md
      epic-status.md
    skills/
      # Existujici (vsechny zustavaji)
      agent-core/, session-management/, quality-gates/, ...
      # Novy
      epic-orchestration/
        instructions.md    # Controller state machine logika
        skill.json
    hooks/
      pre-commit-guard.sh  # Existujici
  templates/
    epic.md                # EPIC sablona
    plan.schema.json       # JSON schema pro Plan
  playbooks/
    architect.md           # Detailni instrukce pro Architect roli
    domain.md
    backend.md
    frontend.md
    qa.md
    security.md
    observability.md
    docs.md
    release.md
  policies/
    gates.yaml             # Gates konfigurace
  evidence/                # Runtime output (gitignored)
    <epic_id>/
      <run_id>/
        plan.json
        gates_report.json
        stage_log.jsonl
        ...
  workspace/               # Existujici runtime state
    active-work.md
    sessions/
    epics/
    ...
  docs/
    MULTIAGENT_GUIDE.md    # Tento dokument
```

---

## 4. Architektura ADO

### Controller (hlavni session)

Controller je tvoje hlavni Claude Code session. Neni to separatni program —
je to Claude s nactenym `epic-orchestration` skillem, ktery definuje:

- Jak cist EPIC soubor a generovat Plan JSON
- Jak dispathnout agenty (sekvencne vs. paralelne)
- Jak predavat kontext mezi kroky
- Jak resit branch strategii
- Jak spoustet gates
- Jak resit retry loop (max 3)
- Kdy a jak zadat PM o approval

### 9 Worker roli

| Role | Mission | Co produkuje |
|------|---------|--------------|
| **Architect** | ADR + API/event kontrakty + boundaries | `docs/adr/ADR-XXXX.md`, `openapi/*.yaml` |
| **Domain** | Domenovy model, invarianty, eventy, workflow | `src/domain/*.py` |
| **Backend** | FastAPI endpoints, DB, outbox | `src/api/*.py`, `src/db/*.py` |
| **Frontend** | UI proti kontraktum, RBAC guards | `src/frontend/**/*.tsx` |
| **QA** | Nezavisle testy + report | `tests/**/*.py` |
| **Security** | AuthZ, SAST, secrets, nalezy + patch | Security report + patches |
| **Observability** | OTel traces/logs/metrics | Instrumentation code |
| **Docs** | Aktualizace dokumentace + changelog | `docs/**/*.md`, `CHANGELOG.md` |
| **Release** | Deployment config + smoke tests | `Dockerfile`, migration scripts |

### Gates Engine

Konfigurace v `policies/gates.yaml`:

```yaml
gates:
  tests_pass:
    required: true
    command: "pytest -q"
  lint_pass:
    required: true
    command: "ruff check . && ruff format --check ."
  security_scan_pass:
    required: true
    command: "bandit -q -r ."
  docs_updated:
    required: true
    rule: "docs/ must be updated OR include CHANGELOG entry"

retry:
  max_attempts: 3

budget:
  max_llm_cost_per_epic_usd: 50
```

Po dokonceni vsech kroku hlavni session spusti gates. Pri selhani:
1. Identifikuje ktery gate selhal
2. Re-dispatche prislusneho agenta s fix instrukci
3. Opakuje max 3x
4. Pokud stale selhava -> eskalace na PM

### Evidence Store

Kazdy run vytvori audit trail:

```
evidence/<epic_id>/<run_id>/
  epic_input.md          # Puvodni EPIC zadani
  plan.json              # Vygenerovany plan
  stage_log.jsonl        # Prubeh kazdeho kroku
  gates_report.json      # Vysledky gates
  pm_decision.json       # PM rozhodnuti (approve/reject)
  final_report.md        # Celkovy report
```

---

## 5. EPIC lifecycle — krok po kroku

### Krok 1: PM vytvori EPIC

Soubor `workspace/workflow/epics/active/EPIC-ERP-0003-ORDERS.md`:

```markdown
# EPIC: ERP-0003 -- Orders Module

## Kontext
ERP system potrebuje modul pro spravu objednavek.

## Cil
CRUD pro objednavky se stavovym automatem.

## Scope
### Allowed files/paths
- src/backend/orders/
- src/frontend/orders/
- tests/orders/
### Forbidden zones
- src/backend/iam/
- src/backend/pricing/

## Constraints
- tenant_isolation: required
- audit_log: required
- outbox: required

## DoD Gates
- tests_pass
- lint_pass
- security_scan_pass
- docs_updated

## Acceptance Criteria
- [ ] POST /orders vytvori objednavku
- [ ] Stavovy automat: draft -> confirmed -> shipped -> delivered
- [ ] Tenant isolation
- [ ] Event "OrderCreated" pres outbox
```

### Krok 2: `/plan-epic EPIC-ERP-0003`

Command nacte EPIC a vygeneruje Plan JSON:

```json
{
  "epic_id": "ERP-0003",
  "version": 1,
  "steps": [
    {"id": "S1", "role": "architect", "objective": "ADR + API kontrakty pro Orders",
     "inputs": ["EPIC file"], "outputs": ["docs/adr/ADR-0003.md", "openapi/orders.yaml"]},
    {"id": "S2", "role": "domain", "objective": "Entity Order, stavy, invarianty, events",
     "inputs": ["ADR-0003"], "outputs": ["src/domain/orders.py"]},
    {"id": "S3", "role": "backend", "objective": "FastAPI endpoints + DB + outbox",
     "inputs": ["ADR-0003", "domain model"], "outputs": ["src/api/orders.py"]},
    {"id": "S4", "role": "frontend", "objective": "UI pro spravu objednavek",
     "inputs": ["ADR-0003", "API kontrakty"], "outputs": ["src/frontend/orders/"]},
    {"id": "S5", "role": "qa", "objective": "Testy pro vse",
     "inputs": ["backend code"], "outputs": ["tests/orders/"]},
    {"id": "S6", "role": "security", "objective": "Tenant isolation + SAST",
     "inputs": ["backend code"], "outputs": ["security report"]},
    {"id": "S7", "role": "observability", "objective": "OTel traces",
     "inputs": ["backend code"], "outputs": ["instrumentation"]},
    {"id": "S8", "role": "docs", "objective": "API docs + changelog",
     "inputs": ["all outputs"], "outputs": ["docs/", "CHANGELOG.md"]},
    {"id": "S9", "role": "release", "objective": "Migration + deployment",
     "inputs": ["all outputs"], "outputs": ["migration script", "deployment notes"]}
  ],
  "dependencies": [
    {"before": "S1", "after": "S2", "reason": "Domain needs ADR"},
    {"before": "S2", "after": "S3", "reason": "Backend needs domain model"},
    {"before": "S1", "after": "S4", "reason": "Frontend needs API contracts"},
    {"before": "S3", "after": "S5", "reason": "QA needs backend code"},
    {"before": "S3", "after": "S6", "reason": "Security needs backend code"},
    {"before": "S3", "after": "S7", "reason": "Observability needs backend code"}
  ],
  "parallel_groups": [
    ["S3", "S4"],
    ["S5", "S6", "S7"]
  ]
}
```

Claude ti ukaze plan a ceka na **GO**.

### Krok 3: GO -> `/run-epic`

```
EPIC-ERP-0003 — Starting pipeline

Step S1: Architect
  Dispatching architect agent...
  Agent cte EPIC, generuje ADR + API kontrakty
  -> docs/adr/ADR-0003.md + openapi/orders.yaml
  HOTOVO (45s)

Step S2: Domain
  Dispatching domain agent...
  Kontext: [ADR-0003]
  Agent definuje Order entity, stavy, events
  -> src/domain/orders.py
  HOTOVO (30s)

Step S3 + S4: Backend + Frontend (PARALELNE)
  Dispatching backend agent... (branch: epic/ERP-0003-backend)
  Dispatching frontend agent... (branch: epic/ERP-0003-frontend)
  Backend: endpoints, DB models, outbox DONE (2min)
  Frontend: React components, API calls DONE (2min)

Step S5 + S6 + S7: QA + Security + Observability (PARALELNE)
  Dispatching qa agent...
  Dispatching security agent...
  Dispatching observability agent...
  QA: 12 testu, 12/12 passing DONE
  Security: Tenant isolation OK, zadne nalezy DONE
  Observability: OTel traces pridany DONE

Step S8: Docs
  Dispatching docs agent...
  API docs + CHANGELOG DONE

Step S9: Release
  Dispatching release agent...
  Migration script + deployment notes DONE

GATES
  tests_pass:          PASS (pytest -q -> 12 passed)
  lint_pass:           PASS (ruff check -> clean)
  security_scan_pass:  PASS (bandit -> no issues)
  docs_updated:        PASS (CHANGELOG has entry)

RESULT
  Status: ALL GATES PASSED
  Files changed: 14
  Cost: ~$2.40

Cekam na PM approval: APPROVE / REVISE / REJECT
```

### Krok 4: PM rozhoduje

- **APPROVE** -> merge branches, uzavri EPIC, archivuj evidenci
- **REVISE: "Pridej rate limiting"** -> re-dispatch security agenta
- **REJECT** -> rollback, uzavri jako failed

---

## 6. Jak vypadaji agent soubory

### Priklad: `.claude/agents/backend.md`

```markdown
---
name: backend-developer
description: >
  Implementuje backend kod (FastAPI, SQLAlchemy, DB migrace)
  podle architektonickeho navrhu a domenovoho modelu.
  Pouzij kdyz EPIC plan ma krok s role "backend".
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---

# Backend Developer Agent

## Tvoje role
Jsi senior Python/FastAPI developer. Implementujes kod presne
podle architektonickeho navrhu (ADR) a domenovoho modelu.

## Vstup (ocekavany kontext)
- ADR dokument (architektura, API kontrakty)
- Domenovy model (entity, events, invarianty)
- EPIC scope (allowed/forbidden paths)

## Pravidla
1. NIKDY nemen API kontrakty — to je zodpovednost Architecta
2. Pouzij outbox pattern pro eventy (pokud EPIC vyzaduje)
3. Kazda funkce musi mit type hints a docstring
4. Pouzij async pro I/O operace
5. Pracuj POUZE v allowed paths z EPIC scope
6. Nepis testy — to je zodpovednost QA agenta
7. Commituj do feature branch, NIKDY do main

## Vystup
- Funkcni FastAPI endpoints
- SQLAlchemy modely + migrace
- Outbox integrace (pokud pozadovano)
- Report: co jsem implementoval, jaky soubory, co otestovat

## Coding Standards
Nacti a dodrzuj `.claude/skills/coding-standards/instructions.md`
```

### Priklad: `.claude/agents/architect.md`

```markdown
---
name: architect
description: >
  Vytvari ADR (Architecture Decision Records), API kontrakty
  (OpenAPI) a event schemas. Neimplementuje features.
  Pouzij jako prvni krok v EPIC pipeline.
tools: Read, Write, Grep, Glob, WebSearch
model: sonnet
---

# Architect Agent

## Tvoje role
Jsi software architekt. Navrhujes, NEIMPLEMENTUJES.

## Vstup
- EPIC soubor s pozadavky a scope

## Vystup
1. ADR dokument (docs/adr/ADR-XXXX.md)
   - Kontext, rozhodnuti, dusledky
   - API endpointy (method, path, request/response)
   - Datovy model (entity, fields, types)
2. OpenAPI spec (pokud API endpointy)
3. Event schema (pokud async komunikace)

## Pravidla
1. Neimplementuj zadny feature kod
2. Navrhuj pro jednoduchost (YAGNI)
3. Respektuj existujici architekturu (cti project-context/)
4. Definuj jasne boundaries — co je IN scope, co OUT
5. Pojmenuj endpointy podle REST konvenci
```

### Jak Claude Code pouziva tyto soubory

1. Agent soubory se automaticky indexuji pri startu session
2. Hlavni session je muze dispatchnout pres Task tool
3. `model: sonnet` urcuje jaky Claude model subagent pouzije
4. `tools:` omezuje jake nastroje subagent muze pouzit
5. `description:` pomaha Claude rozhodnout kdy agenta pouzit

---

## 7. Orchestracni commands

### `/plan-epic <EPIC-ID>`

```markdown
# commands/plan-epic.md

Vygeneruj Plan JSON pro zadany EPIC.

1. Nacti EPIC soubor z workspace/workflow/epics/active/<EPIC-ID>.md
2. Analyzuj scope, constraints, acceptance criteria
3. Vygeneruj Plan JSON dle templates/plan.schema.json
4. Urcit dependencies (ktery krok zavisi na kterem)
5. Identifikuj parallel_groups (co muze bezet soucasne)
6. Uloz plan do evidence/<EPIC-ID>/plan.json
7. Zobraz plan PM a cekej na GO/REVISE
```

### `/run-epic [EPIC-ID]`

```markdown
# commands/run-epic.md

Spust cely EPIC pipeline.

Nacti epic-orchestration skill a proved:
1. Nacti Plan JSON z evidence/<EPIC-ID>/plan.json
2. Pro kazdy krok v poradi (respektuj dependencies):
   a. Vytvor branch pokud paralelni krok
   b. Dispatch agenta dle role (nacti z .claude/agents/<role>.md)
   c. Predej kontext (vystupy predchozich kroku)
   d. Zaznamenej vysledek do stage_log.jsonl
3. Po vsech krocich:
   a. Merge vsechny branches
   b. Spust gates dle policies/gates.yaml
   c. Pri selhani: retry (max 3), pak eskalace PM
   d. Zobraz vysledky a cekej na APPROVE/REVISE/REJECT
4. Pri APPROVE: archivuj evidenci, uzavri EPIC
```

### `/run-step <EPIC-ID> <STEP-ID>`

```markdown
# commands/run-step.md

Spust jeden konkretni krok z EPIC planu manualne.

Pouzij kdyz:
- Chces otestovat jednoho agenta
- Potrebujes re-runovat selhavsi krok
- Debugujes pipeline

1. Nacti Plan JSON
2. Najdi krok dle STEP-ID
3. Over ze dependencies jsou splnene
4. Dispatch agenta
5. Zobraz vysledek
```

### `/epic-status [EPIC-ID]`

```markdown
# commands/epic-status.md

Zobraz aktualni stav EPICu.

1. Nacti EPIC soubor + Plan JSON + stage_log.jsonl
2. Zobraz:
   - Ktere kroky jsou hotove
   - Ktery krok je aktualne v behu
   - Ktere kroky cekaji
   - Gates vysledky
   - Celkovy cas a odhadovany zbytek
```

---

## 8. Fazovy plan implementace

### Phase A: Controller state machine + evidence

**Co postavit:**
- `skills/epic-orchestration/instructions.md` — logika rizeni pipeline
- `evidence/` adresar a zakladni evidence soubory
- Integrace s existujicim session-management skillem

**Acceptance:**
- Dummy EPIC projede end-to-end (i s mock agenty)
- Evidence slozka vznikne s reportem

### Phase B: EPIC Runner CLI + Git adapter

**Co postavit:**
- `commands/plan-epic.md`, `run-epic.md`, `run-step.md`, `epic-status.md`
- Branch naming konvence (`epic/<EPIC-ID>-<role>`)
- Scope enforcement v agent promptech

**Acceptance:**
- PM spusti `/run-epic` a vznikne PR-ready branch + evidence + gates report

### Phase C: Gates engine + Retry loops

**Co postavit:**
- `policies/gates.yaml` loader a runner
- Pass/fail report generace
- Retry loop (max 3) s fix instrukci

**Acceptance:**
- Umi opravit failing gate a projit (demonstrace na umyslem zavedene chybe)

### Phase D: Workers (9 roli)

**Co postavit:**
- `agents/architect.md`, `domain.md`, `backend.md`, `frontend.md`,
  `qa.md`, `security.md`, `observability.md`, `docs-writer.md`, `release.md`
- `playbooks/` — detailni instrukce pro kazdou roli

**Acceptance:**
- Pipeline bezi s realnymi agenty a uklada evidence

### Phase E: Planner + Scheduler paralelizace

**Co postavit:**
- `templates/plan.schema.json` — schema pro Plan JSON
- Plan generator (soucasti `/plan-epic` commandu)
- Scheduler logika (paralelni dispatch, branch per agent, merge)

**Acceptance:**
- Plan JSON validni dle schema
- Scheduler provede plan s paralelnimi skupinami

### Phase F (optional): CrewAI adapter

CrewAI jako alternativni runtime — governance zustava v Controlleru.
Umozni multi-provider LLM (OpenAI, Claude, Llama).

### Phase G (optional): Ops UI

Dashboard pro vizualizaci: runs, gates, approve/reject, audit trail.

---

## 9. Quick reference

### PM prikazy

| Prikaz | Co dela |
|--------|---------|
| `/plan-epic EPIC-ID` | Vygeneruj plan z EPICu |
| `/run-epic EPIC-ID` | Spust cely pipeline |
| `/run-step EPIC-ID S1` | Spust jeden krok |
| `/epic-status EPIC-ID` | Zobraz stav |
| `GO` | Schval plan/krok |
| `REVISE: instrukce` | Vrat k prepracovani |
| `APPROVE` | Schval vysledek EPICu |
| `REJECT` | Zamitni EPIC |

### Agent role

| Role | Agent soubor | Produkuje |
|------|-------------|-----------|
| Architect | `agents/architect.md` | ADR, OpenAPI, event schemas |
| Domain | `agents/domain.md` | Entity, invarianty, eventy |
| Backend | `agents/backend.md` | FastAPI endpoints, DB, outbox |
| Frontend | `agents/frontend.md` | React UI, API calls |
| QA | `agents/qa.md` | Testy (unit, integration) |
| Security | `agents/security.md` | AuthZ, SAST, nalezy |
| Observability | `agents/observability.md` | OTel instrumentation |
| Docs | `agents/docs-writer.md` | Dokumentace, changelog |
| Release | `agents/release.md` | Dockerfile, migrace, deploy |

### Soubory a cesty

| Co | Kde |
|----|-----|
| Agent definice | `.claude/agents/*.md` |
| Orchestracni commands | `.claude/commands/plan-epic.md`, `run-epic.md`, ... |
| Controller logika | `.claude/skills/epic-orchestration/instructions.md` |
| EPIC sablona | `templates/epic.md` |
| Plan schema | `templates/plan.schema.json` |
| Gates politika | `policies/gates.yaml` |
| Role playbooks | `playbooks/*.md` |
| Evidence output | `evidence/<epic_id>/<run_id>/` |
| Aktivni EPICy | `workspace/workflow/epics/active/` |
| Hotove EPICy | `workspace/workflow/epics/completed/` |

### Dependency chain (typicky EPIC)

```
Architect (S1)
    |
Domain (S2)
    |
Backend (S3)  ←parallel→  Frontend (S4)
    |
QA (S5)  ←parallel→  Security (S6)  ←parallel→  Observability (S7)
    |
Docs (S8)
    |
Release (S9)
```

### Jak pridat novou roli

1. Vytvor `.claude/agents/<role-name>.md` s YAML frontmatter
2. Pridej roli do `templates/plan.schema.json` enum
3. Vytvor `playbooks/<role-name>.md` s detailnimi instrukcemi
4. Otestuj pres `/run-step` na dummy EPICu

### Jak zmenit gates

1. Edituj `policies/gates.yaml`
2. Pridej/odemel gate a jeho command
3. Otestuj pres `/run-epic` na testovacim EPICu

---

## Zdroje a reference

| Zdroj | Popis | Umisteni |
|-------|-------|----------|
| ADO Starter Kit | Blueprint pro implementaci | `_unzipped/ado_starter_kit/` |
| ADO Docs (Grand Finale) | Plna dokumentace ciloveho stavu | `_unzipped/ai_dev_orchestrator_docs/` |
| AI ERP Spec | Specifikace prvniho realneho projektu | `_unzipped/ai_erp_spec/` |
| Existujici claude/ setup | Tvuj single-agent framework | `claude/` |
| Kellerstein marketplace | Priklad deklarativnich agentu | github.com/lukaskellerstein/claude-dev-marketplace |
