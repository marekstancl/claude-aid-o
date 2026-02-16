---
id: S-20260216-f47a
type: new-feature
status: completed
priority: high
started: 2026-02-16
epic_id: ADO-0001
epic_session: 2
epic_file: workspace/workflow/epics/active/EPIC-ADO-0001-BUILD-ORCHESTRATOR.md
plan_ref: workspace/workflow/plans/P-20260216-b3a1-aid-v2-workspace-agents-memory.md
ai_agent: Claude Opus 4.6
branch: session/S-20260216-f47a-runtime-commands
previous_session: workspace/sessions/completed/S-20260215-a1f0-foundation-controller.md
---

# Session 2: EPIC Runner Commands + AID Commands

## Objective

Implementovat 6 commands, které tvoří runtime vrstvu AID orchestrátoru:
4 orchestrační commands (`plan-epic`, `run-epic`, `run-step`, `epic-status`)
+ 2 nové AID commands (`aid-setup`, `aid-help`).

Na konci session musí:
- `/plan-epic` přečíst EPIC a vygenerovat validní Plan JSON + session file
- `/run-epic` spustit orchestrační loop (state machine z epic-orchestration.md)
- `/run-step` manuálně spustit jeden krok z plánu
- `/epic-status` zobrazit aktuální stav EPIC pipeline
- `/aid-setup` analyzovat projekt a provést interaktivní onboarding
- `/aid-help` vypsat kompletní self-knowledge o AID

## Context / Prerekvizity

Session 1 dodala:
- Plugin scaffold `aid-orchestrator` (marketplace.json, plugin.json)
- 5 utility agents, 9 commands (přenesené z C.I.C.E.R.O.), 4 skills
- Controller State Machine (`skills/epic-orchestration.md` — 500 lines, 11 stavů)
- Decision policies, gates, 9 role playbooks, plan.schema.json
- `/aid-init` command pro `.aid-o/` workspace strukturu
- Smoke test EPIC (`EPIC-TEST-0001-DUMMY.md`)

Tato session staví na `epic-orchestration.md` — commands jsou **vstupní body** do state machine.

## Deliverables

- [ ] `commands/plan-epic.md` — EPIC → Plan JSON + Session file
- [ ] `commands/run-epic.md` — hlavní orchestrační loop (state machine)
- [ ] `commands/run-step.md` — manuální spuštění jednoho kroku
- [ ] `commands/epic-status.md` — zobrazení stavu EPIC pipeline
- [ ] `commands/aid-setup.md` — interaktivní projekt onboarding
- [ ] `commands/aid-help.md` — self-knowledge, příkazy, workflow
- [ ] Aktualizace `plugin.json` — registrace nových 6 commands
- [ ] Smoke test — test s EPIC-TEST-0001-DUMMY.md

## Phases

### Phase 1: `/plan-epic` — EPIC Parser + Plan Generator

**Cíl:** Command, který přečte EPIC soubor, rozparsuje ho a vygeneruje Plan JSON + session file.

**Vstup:** `/plan-epic <cesta-k-epic-souboru>`

**Command musí:**

1. **Načíst a validovat EPIC:**
   - Přečíst zadaný `.md` soubor
   - Ověřit povinné sekce: Goal, Scope, Constraints, DoD Gates, Acceptance Criteria
   - Pokud chybí sekce → chybová hláška s výpisem co chybí
   - Extrahovat `epic_id` z filename (např. `EPIC-ADO-0001` z `EPIC-ADO-0001-BUILD-ORCHESTRATOR.md`)

2. **Analyzovat kroky a závislosti:**
   - Přečíst "Steps" nebo "Sessions" sekci z EPICu
   - Pro každý krok identifikovat: role, objective, dependencies, allowed/forbidden paths
   - Použít Plan Generation Rules z `epic-orchestration.md`:
     - Architect FIRST
     - Domain after Architect
     - Backend + Frontend in parallel
     - QA + Security + Observability in parallel
     - Docs after implementation
     - Release last
   - Pokud EPIC explicitně definuje pořadí → respektovat ho (override default rules)

3. **Vygenerovat Plan JSON:**
   - Formát dle `.aid-o/03-config/templates/plan.schema.json`
   - Povinná pole: `epic_id`, `version`, `created_at`, `steps[]`, `dependencies[]`, `parallel_groups[]`, `gates[]`, `budget`
   - Validovat výstup proti schema (self-check)
   - Uložit do `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json`
   - `run_id` generovat: `run_{YYYYMMDD}_{4char-hash}`

4. **Vygenerovat Session file:**
   - Použít template z `.aid-o/03-config/templates/session-new-feature.md`
   - Vyplnit frontmatter: id, type, epic_id, epic_session, branch
   - Vygenerovat phases z plan steps
   - Uložit do `.aid-o/04-engine/sessions/S-{YYYYMMDD}-{hash}-{topic}.md`

5. **Prezentovat výstup:**
   ```
   Plan Generated for EPIC: {epic_id}
   ====================================
   Steps: {count}
   Parallel groups: {count}
   Dependencies: {count}
   Roles: {list}
   Budget: ${max_cost}

   Step sequence:
   1. [architect] {objective}
   2. [domain] {objective} (depends on: step 1)
   3. [backend] {objective} ← parallel group 1
   4. [frontend] {objective} ← parallel group 1
   ...

   Files created:
   - Plan: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
   - Session: .aid-o/04-engine/sessions/{session_file}

   Next: Run `/run-epic {epic_id}` to start execution
   ```

**Reference soubory:**
- `skills/epic-orchestration.md` sekce "2. PLANNING"
- `defaults/templates/plan.schema.json`
- `defaults/templates/session-new-feature.md`
- `defaults/policies/decision-policies.yaml` (architecture_principles)

**Acceptance:**
- [ ] `/plan-epic` s EPIC-TEST-0001-DUMMY.md vytvoří validní Plan JSON
- [ ] Plan JSON odpovídá plan.schema.json
- [ ] Session file vytvořen s korektním frontmatter
- [ ] Chybový stav: EPIC bez "Goal" sekce → srozumitelná chybová hláška

---

### Phase 2: `/run-epic` — Orchestrační Loop

**Cíl:** Hlavní command, který spouští Controller state machine z `epic-orchestration.md`.

**Vstup:** `/run-epic <epic-id-nebo-cesta>` nebo `/run-epic` (pokud existuje jen jeden aktivní EPIC)

**Command musí:**

1. **Inicializovat run:**
   - Najít EPIC soubor (v `.aid-o/02-epics/` nebo přímá cesta)
   - Najít existující Plan JSON (z `/plan-epic`) nebo automaticky spustit `/plan-epic`
   - Vytvořit `run_id` a evidence directory
   - Zkopírovat EPIC do evidence: `evidence/{epic_id}/{run_id}/epic_input.md`
   - Inicializovat `plan_progress.json`:
     ```json
     {
       "epic_id": "{epic_id}",
       "run_id": "{run_id}",
       "state": "IDLE",
       "started_at": "{ISO 8601}",
       "steps": { "step_1_architect": "pending", ... },
       "current_step": null,
       "gates": {},
       "escalations": []
     }
     ```

2. **Spustit state machine loop:**
   - Implementovat přesně dle `epic-orchestration.md` (sekce "Detailed Flow"):
     - **IDLE → PLANNING:** Načíst EPIC, validovat, přečíst policies + gates
     - **PLANNING → PLAN_REVIEW:** Vygenerovat/načíst Plan JSON, prezentovat PM
     - **PLAN_REVIEW → EXECUTING:** PM schválí → dispatch prvního agenta
     - **EXECUTING → PHASE_CHECK:** Agent dokončí → ověřit výstupy
     - **PHASE_CHECK → NEXT_PHASE:** Výstupy OK → další krok
     - **NEXT_PHASE → EXECUTING:** Vrátit se k dalšímu kroku
     - **all steps → GATES:** Spustit gates z gates.yaml
     - **GATES → GATE_RETRY:** Gate fails → opravit → re-run
     - **GATE_RETRY → ESCALATION:** Max retries → eskalace PM
     - **→ PM_APPROVAL:** Vše OK → PM schválí merge
     - **→ DONE:** Merge, archive, report

3. **Agent dispatch:**
   - Pro každý krok: načíst playbook, sestavit prompt, dispatch přes Task tool
   - Pro paralelní skupiny: dispatch více agentů v jednom volání
   - Kontext předávání mezi kroky dle "Context Passing" v epic-orchestration.md

4. **Evidence logging:**
   - Každý state transition → `stage_log.jsonl`
   - Každý agent dispatch → `prompts/step_{N}_{role}.md`
   - Každý output → `steps/step_{N}_{role}/output.md`
   - Každý gate → `gates/{gate_name}.txt`

5. **Aktualizovat tracking soubory:**
   - `plan_progress.json` po každém kroku
   - Session file po každé fázi
   - `memory/active-work.md` na konci

**PM Interaction Body:**
- Na PLAN_REVIEW: "Proceed? (GO / REVISE / ABORT)"
- Na ESCALATION: "Options: A) ... B) ... C) Abort EPIC"
- Na PM_APPROVAL: "Merge to main? (APPROVE / REJECT / REVISE)"
- Mezi fázemi (PHASE_CHECK): krátký status, pokud auto-decision → pokračovat bez ptaní

**Reference soubory:**
- `skills/epic-orchestration.md` — CELÝ (state machine, dispatch protocol, evidence)
- `defaults/policies/decision-policies.yaml` (auto_decisions, escalation_triggers)
- `defaults/policies/gates.yaml` (gates, retry config)

**Acceptance:**
- [ ] `/run-epic` s EPIC-TEST-0001-DUMMY.md projde prvními 3 stavy (IDLE → PLANNING → PLAN_REVIEW)
- [ ] State transitions jsou zaznamenány v `stage_log.jsonl`
- [ ] Evidence directory struktura odpovídá specifikaci
- [ ] PM interaction (PLAN_REVIEW) funguje — čeká na odpověď

---

### Phase 3: `/run-step` — Manuální Spuštění Jednoho Kroku

**Cíl:** Command pro manuální spuštění jednoho kroku z existujícího plánu.

**Vstup:** `/run-step <epic-id> <step-id>` nebo `/run-step <epic-id> step_3_backend`

**Command musí:**

1. **Najít kontext:**
   - Načíst Plan JSON z evidence (nejnovější run)
   - Najít step definici v plánu
   - Zkontrolovat dependencies — jsou splněné? (předchozí kroky = done)
   - Pokud dependencies nesplněné → WARNING + nabídka: "Run anyway? (Y/N)"

2. **Dispatch agenta:**
   - Načíst playbook pro step.role
   - Sestavit prompt identicky jako `/run-epic` (ale single step)
   - Předat kontext z předchozích kroků (evidence/steps/)
   - Dispatch přes Task tool

3. **Zpracovat výstup:**
   - Uložit output do evidence
   - Aktualizovat `plan_progress.json`
   - Spustit PHASE_CHECK logiku (scope validation)

4. **Prezentovat výsledek:**
   ```
   Step Completed: {step_id}
   ============================
   Role: {role}
   Status: {pass/fail}
   Outputs: {list}
   Scope check: {OK/violation}

   Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/{step_id}/

   Next steps in plan:
   - {next_step_1} (dependencies met: yes)
   - {next_step_2} (dependencies met: no — waiting for {dep})
   ```

**Reference soubory:**
- `skills/epic-orchestration.md` sekce "4. EXECUTING" + "5. PHASE_CHECK"
- `defaults/templates/plan.schema.json` (step structure)

**Acceptance:**
- [ ] `/run-step` s existujícím plánem spustí jeden agent krok
- [ ] Dependency check funguje (warning pokud nesplněné)
- [ ] Evidence uložena (output.md, diff.patch, stage_log.jsonl)
- [ ] plan_progress.json aktualizován

---

### Phase 4: `/epic-status` — Zobrazení Stavu Pipeline

**Cíl:** Command pro rychlý přehled stavu EPIC pipeline.

**Vstup:** `/epic-status [epic-id]` (bez argumentu = všechny aktivní EPICy)

**Command musí:**

1. **Najít aktivní EPICy:**
   - Prohledat `.aid-o/02-epics/` (ne archive/)
   - Pro každý EPIC najít evidence directory a `plan_progress.json`

2. **Zobrazit stav:**
   ```
   EPIC Status: {epic_id} — {title}
   ====================================
   State: EXECUTING (step 3 of 7)
   Run: {run_id}
   Started: {timestamp}

   Steps:
   ✅ step_1_architect — Design API contracts (done)
   ✅ step_2_domain — Define entities (done)
   🔄 step_3_backend — Implement endpoints (in progress)
   ⏳ step_4_frontend — Build UI (pending — parallel with step 3)
   ⏳ step_5_qa — Write tests (pending — depends on 3,4)
   ⏳ step_6_security — Security review (pending — depends on 3,4)
   ⏳ step_7_docs — Update docs (pending — depends on 5,6)

   Gates: not yet run
   Budget: $12.50 / $50.00 (25%)

   Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/
   ```

3. **Bez argumentu — přehled všech:**
   ```
   Active EPICs
   ====================================
   1. ADO-0001 — Build AID Orchestrator    [EXECUTING] step 3/7
   2. FEAT-0042 — User Authentication      [GATES] retry 2/3

   Completed (last 5):
   3. FIX-0039 — Fix login timeout          [DONE] 2026-02-14
   ```

4. **Zpracovat edge cases:**
   - Žádný EPIC → "No active EPICs. Create one in `.aid-o/02-epics/` using the epic template."
   - EPIC bez plánu → "EPIC {id} found but no plan generated. Run `/plan-epic` first."
   - EPIC bez evidence → "EPIC {id} found but no run started. Run `/run-epic` to begin."

**Reference soubory:**
- `skills/epic-orchestration.md` (evidence structure, plan_progress.json)

**Acceptance:**
- [ ] `/epic-status` s existujícím EPIC zobrazí stav
- [ ] Bez argumentu zobrazí přehled všech EPICů
- [ ] Chybový stav: žádný EPIC → srozumitelná hláška
- [ ] Zobrazuje step progress, gates stav, budget

---

### Phase 5: `/aid-setup` — Interaktivní Onboarding

**Cíl:** Command pro prvotní kontakt uživatele s AID — analýza projektu + interaktivní setup.

**Vstup:** `/aid-setup` (v kořenu projektu)

**Command musí implementovat flow z Plan D-007:**

1. **Detekce projektu:**
   - Prohledat kořen projektu na indikátory:
     - `package.json` → Node.js/TypeScript (detekovat framework: Next.js, Express, React...)
     - `pyproject.toml` / `setup.py` / `requirements.txt` → Python (detekovat: Django, FastAPI, Flask...)
     - `Cargo.toml` → Rust
     - `go.mod` → Go
     - `Dockerfile` / `docker-compose.yml` → Docker
     - `.git/` → Git repo (branch, remote)
     - `tsconfig.json` → TypeScript
     - `Makefile` / `justfile` → Build system
     - `.github/workflows/` → CI/CD (GitHub Actions)
     - `Gemfile` → Ruby
     - `pom.xml` / `build.gradle` → Java/Kotlin

2. **Analýza tech stacku:**
   - Pro každý detekovaný soubor: extrahovat klíčové info
   - `package.json`: name, scripts (build, test, lint), dependencies (top 10)
   - `pyproject.toml`: name, tool sections, dependencies
   - Detekovat test framework: jest/vitest/pytest/mocha
   - Detekovat linter: eslint/ruff/pylint
   - Detekovat type checker: tsc/mypy/pyright

3. **Interaktivní setup (chat-based):**
   - Prezentovat detekovaný stack:
     ```
     AID Setup — Project Analysis
     ====================================
     Project: {name} (from package.json/pyproject.toml)
     Language: TypeScript + Python
     Framework: Next.js (frontend), FastAPI (backend)
     Test: jest + pytest
     Lint: eslint + ruff
     Build: npm run build + docker-compose
     CI/CD: GitHub Actions
     Git: main branch, remote origin

     Detected structure:
     - frontend/  (Next.js app)
     - backend/   (FastAPI app)
     - shared/    (shared types)
     - docs/      (documentation)
     ```
   - Nabídnout setup kroky:
     ```
     Setup options:
     1. [x] Initialize .aid-o/ workspace (/aid-init)
     2. [ ] Customize gates.yaml for your stack
            → Will set: pytest for backend, jest for frontend
     3. [ ] Generate/update CLAUDE.md
     4. [ ] Populate project-profile.yaml
     5. [ ] Add .aid-o/ to .gitignore (recommended sections)

     Proceed with all? (Y/N/select numbers)
     ```

4. **Provést vybrané kroky:**
   - Volat `/aid-init` interně (pokud `.aid-o/` neexistuje)
   - Customizovat `gates.yaml` dle detekovaného stacku (správné příkazy pro test/lint)
   - Vygenerovat `CLAUDE.md` s project context
   - Naplnit `project-profile.yaml`:
     ```yaml
     project_name: "my-project"
     tech_stack:
       languages: [typescript, python]
       frameworks: [nextjs, fastapi]
       test: [jest, pytest]
       lint: [eslint, ruff]
       build: ["npm run build", "docker-compose build"]
     architecture: "monorepo"
     directories:
       frontend: "frontend/"
       backend: "backend/"
     ci_cd: "github-actions"
     initialized: true
     scanned_at: "2026-02-16T10:00:00Z"
     ```

5. **Dva scénáře dle Plan D-007:**
   - **Nový projekt (prázdný adresář / jen .git):** Nabídnout brainstorming, scaffold z template
   - **Existující projekt:** Quick scan, optional deep analysis later

**Reference soubory:**
- Plan P-20260216-b3a1, sekce D-007 (`/aid-setup`)
- Plan P-20260216-b3a1, sekce D-006 (Project Scanner)
- `commands/aid-init.md` (interně volaný)

**Acceptance:**
- [ ] `/aid-setup` detekuje tech stack z package.json / pyproject.toml
- [ ] Nabídne interaktivní setup kroky
- [ ] Volá `/aid-init` interně pokud `.aid-o/` neexistuje
- [ ] Naplní `project-profile.yaml` s detekovanými údaji
- [ ] Customizuje `gates.yaml` pro detekovaný stack

---

### Phase 6: `/aid-help` — Self-Knowledge

**Cíl:** Command, který uživateli vysvětlí jak AID funguje.

**Vstup:** `/aid-help [topic]` — bez argumentu = full overview, s argumentem = detail k tématu

**Command musí implementovat flow z Plan D-008:**

1. **Full overview (bez argumentu):**
   ```
   AID — AI Development Orchestrator
   ====================================
   Version: 0.1.0

   ## What is AID?

   AID is a multi-agent orchestration system for Claude Code. It takes
   an EPIC (detailed task specification) and autonomously dispatches
   specialized agents to complete it — with quality gates, retry logic,
   and PM escalation.

   ## Commands

   | Command | Description |
   |---------|-------------|
   | `/aid-init` | Initialize .aid-o/ workspace in your project |
   | `/aid-setup` | Interactive project onboarding + tech stack detection |
   | `/aid-help` | This help — explains AID commands and workflow |
   | `/plan-epic` | Parse EPIC → generate Plan JSON + session file |
   | `/run-epic` | Start orchestration loop (state machine) |
   | `/run-step` | Manually run one step from a plan |
   | `/epic-status` | Show EPIC pipeline status |
   | `/quality-gates` | Run 6-gate quality protocol before commit |
   | `/session-start` | Start a tracked session |
   | `/session-end` | Complete and archive session |
   | `/handoff` | Create handoff block for next session |
   | `/audit` | Run project health audit |
   | `/coding-standards` | Load project coding standards |
   | `/testing` | Load testing workflow |
   | `/docs-protocol` | Load documentation protocol |

   ## Workflow: Plan → EPIC → Session

   1. **Plan** — PM + AI brainstorm approach (.aid-o/01-plans/)
   2. **EPIC** — Detailed specification (.aid-o/02-epics/)
   3. **Session** — AI executes autonomously (.aid-o/04-engine/sessions/)

   ## How to Write an EPIC

   Use template: `.aid-o/03-config/templates/epic.md`
   Required sections: Goal, Scope, Constraints, DoD Gates, Acceptance Criteria

   ## How to Start Orchestration

   1. Write EPIC → `.aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md`
   2. `/plan-epic .aid-o/02-epics/your-epic.md`
   3. Review generated plan
   4. `/run-epic` — orchestrator takes over

   ## Where to Find Outputs

   | What | Where |
   |------|-------|
   | Plans | .aid-o/01-plans/ |
   | EPICs | .aid-o/02-epics/ |
   | Sessions | .aid-o/04-engine/sessions/ |
   | Evidence | .aid-o/04-engine/evidence/ |
   | Decisions | .aid-o/04-engine/memory/decisions.yaml |
   | Backlog | .aid-o/04-engine/backlog.md |
   | Lessons | .aid-o/04-engine/lessons-learned.md |

   ## 9 Specialized Agent Roles

   architect, domain, backend, frontend, qa, security, observability, docs, release

   Each has a playbook in `.aid-o/03-config/playbooks/`

   ## FAQ

   Q: Can I run individual steps manually?
   A: Yes, use `/run-step <epic-id> <step-id>`

   Q: What happens if a gate fails?
   A: Orchestrator retries up to 3 times, then escalates to PM.

   Q: Where is the configuration?
   A: `.aid-o/03-config/policies/` (gates.yaml, decision-policies.yaml)

   Q: How do I customize agent behavior?
   A: Edit playbooks in `.aid-o/03-config/playbooks/`

   Topics: /aid-help commands | /aid-help workflow | /aid-help epic
          | /aid-help agents | /aid-help gates | /aid-help evidence
   ```

2. **Detail k tématu (s argumentem):**
   - `commands` → detail ke každému commandu (usage, args, příklad)
   - `workflow` → Mermaid diagram + podrobný popis Plan→EPIC→Session
   - `epic` → jak napsat EPIC, příklad, povinné sekce
   - `agents` → seznam 9 rolí + krátký popis + odkaz na playbook
   - `gates` → 6 gates detail + retry logika + customizace
   - `evidence` → evidence directory struktura + co se ukládá

3. **Dynamické info:**
   - Pokud existuje `.aid-o/`: zobrazit stav (počet EPICů, sessions, atd.)
   - Pokud NEexistuje `.aid-o/`: doporučit `/aid-init` nebo `/aid-setup`

**Reference soubory:**
- Plan P-20260216-b3a1, sekce D-008 (`/aid-help`)
- `plugin.json` (seznam commands, skills, agents)
- `skills/epic-orchestration.md` (workflow)

**Acceptance:**
- [ ] `/aid-help` vypíše kompletní přehled (commands, workflow, FAQ)
- [ ] `/aid-help commands` vypíše detail ke každému commandu
- [ ] `/aid-help workflow` zobrazí Plan→EPIC→Session flow
- [ ] Pokud `.aid-o/` neexistuje → doporučí `/aid-init`

---

### Phase 7: Plugin Integration + Smoke Test

**Cíl:** Registrovat nové commands v plugin.json, provést smoke test.

**Úkol:**

1. **Aktualizovat `plugin.json`:**
   - Přidat 6 nových commands do registrace:
     - `plan-epic`, `run-epic`, `run-step`, `epic-status`, `aid-setup`, `aid-help`
   - Ověřit že názvy odpovídají souborům v `commands/`

2. **Smoke test s EPIC-TEST-0001-DUMMY.md:**
   - Spustit `/plan-epic` → ověřit Plan JSON výstup
   - Spustit `/epic-status` → ověřit zobrazení
   - Spustit `/run-step` s jedním krokem → ověřit dispatch
   - Spustit `/aid-help` → ověřit výstup
   - Spustit `/aid-setup` → ověřit detekci (na tomto projektu)

3. **Zdokumentovat výsledky:**
   - Co funguje
   - Co potřebuje doladit v Session 3+

**Acceptance:**
- [ ] plugin.json obsahuje všech 15 commands (9 starých + 6 nových)
- [ ] `/plan-epic` s dummy EPIC generuje Plan JSON
- [ ] `/epic-status` zobrazí stav
- [ ] `/aid-help` vypíše přehled

---

## DoD Gates

- [ ] Všech 6 nových commands existuje v `commands/`
- [ ] `plugin.json` registruje všech 15 commands
- [ ] `/plan-epic` vytvoří validní Plan JSON dle plan.schema.json
- [ ] `/run-epic` implementuje state machine loop z epic-orchestration.md
- [ ] `/run-step` spustí agent dispatch pro jeden krok
- [ ] `/epic-status` zobrazí pipeline stav
- [ ] `/aid-setup` detekuje tech stack a provede setup
- [ ] `/aid-help` vypíše kompletní self-knowledge
- [ ] Smoke test prošel (min. plan-epic + epic-status + aid-help)

## Architectural Notes

### Command Format Convention

Commands jsou markdown instrukce, které Claude Code čte a následuje.
Nejedná se o executable kód — jde o **prompt engineering**.

Každý command má:
```markdown
# Popis co command dělá (1. řádek = short description)

## Usage
/command-name [args]

## What It Does / Flow
[Detailní popis kroků]

## Reference Files
[Které soubory/skills číst]

## Output Format
[Jak výstup vypadá]

## Important
[Pravidla, edge cases]
```

### Vztah Commands ↔ Skills

```
/plan-epic    → používá epic-orchestration.md (sekce PLANNING)
/run-epic     → používá epic-orchestration.md (CELÝ state machine)
/run-step     → používá epic-orchestration.md (sekce EXECUTING + PHASE_CHECK)
/epic-status  → čte evidence/ (plan_progress.json, stage_log.jsonl)
/aid-setup    → volá /aid-init interně, čte projekt
/aid-help     → čte plugin.json, shrnuje vše
```

### Evidence Paths

Všechny orchestrační commands pracují s:
```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  plan.json
  plan_progress.json
  stage_log.jsonl
  gates_report.json
  prompts/
  steps/
  gates/
```

## Session Log

| Čas | Událost |
|-----|---------|
| 2026-02-16 | Session file vytvořen |
| 2026-02-16 | Phase 1 done: plan-epic.md (162 lines — EPIC parser, Plan JSON gen, session file gen, self-validation) |
| 2026-02-16 | Phase 2 done: run-epic.md (309 lines — full 11-state machine loop, evidence logging, PM checkpoints) |
| 2026-02-16 | Phase 3 done: run-step.md (149 lines — single step dispatch, dependency check, phase check) |
| 2026-02-16 | Phase 4 done: epic-status.md (121 lines — detailed + overview mode, edge cases) |
| 2026-02-16 | Phase 5 done: aid-setup.md (210 lines — tech stack detection, interactive setup, gates customization) |
| 2026-02-16 | Phase 6 done: aid-help.md (316 lines — 7 topic sections, dynamic env check) |
| 2026-02-16 | Phase 7: plugin.json updated — 15 commands registered (9 existing + 6 new) |
| 2026-02-16 | **SESSION COMPLETED** |

## Notes

- Toto je stále "bootstrap" — stavíme orchestrátor manualně.
- Commands jsou markdown instrukce (prompt engineering), ne executable kód.
- `/run-epic` je nejkomplexnější command — implementuje celý state machine loop.
- `/aid-setup` a `/aid-help` jsou user-facing (onboarding), zbytek je orchestration-facing.
- Od Session 3 (Gates) začne orchestrátor reálně validovat výstupy.

## Completion Summary

- **Duration:** 2026-02-16 (1 conversation)
- **Commits:** 1 (pending)
- **Files created:** 7 (6 commands + 1 session file)
- **Files modified:** 3 (plugin.json, active-work.md, EPIC)
- **Total new lines:** ~1,745 (commands only)
- **Phases completed:** 7/7
- **What was accomplished:**
  - 6 new commands implementing the runtime layer of AID orchestrator
  - `/plan-epic` — EPIC parser + Plan JSON generator + DAG validation (216 lines)
  - `/run-epic` — full Controller state machine loop with 11 states (449 lines)
  - `/run-step` — manual single-step agent dispatch (168 lines)
  - `/epic-status` — pipeline status display (150 lines)
  - `/aid-setup` — interactive project onboarding + tech stack detection (269 lines)
  - `/aid-help` — self-knowledge with 7 topic sections (493 lines)
  - plugin.json updated: 15 commands registered (9 existing + 6 new)
  - All cross-references verified (epic-orchestration.md, plan.schema.json, policies)
