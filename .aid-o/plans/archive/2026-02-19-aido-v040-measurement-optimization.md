# AIDo v0.4.0 — Measurement & Optimization

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build infrastructure for measuring AID performance (benchmarks, token tracking), validate worktree parallelism, optimize speed, reduce git noise from orchestration artifacts, fundamentally redesign the Planner for parallelism-first execution, close the Plan-to-EPIC pipeline gap (auto-conversion + inline execution), and ensure zero detail loss from source plans through the entire execution pipeline (Variant B: EPIC references plan, agents read both).

**Architecture:** All changes are to markdown/YAML files within the `plugins/aid-orchestrator/` directory (agents, commands, skills, defaults). No compiled code. Verification is via `claude plugin validate` and manual command testing.

**Tech Stack:** Markdown, YAML, JSON (Claude Code plugin system)

**Source:** Deferred tasks from v0.3.0 (Tasks 7, 24, 25) + new .aid-o gitignore requirement + Qdrant storage path fix + v0.3.0 testing feedback + planner parallelism brainstorm.

**Context:** MAX plan (flat rate) — token cost is irrelevant, only SPEED matters.

**Dependency:** v0.3.0 must be implemented first (especially Task 6: Qdrant metrics, Task 10: Planner optimization).

---

## Task Order & Dependencies

```
Task A (gitignore) → no deps, do first
Task D (EPIC detail level + plan_ref + EPIC Subagent Template) → parallel s I+J (mění: template, example, planner Step 1, brainstorming.md template section)
Task E (Qdrant path fix) → no deps, do early (before any Qdrant setup)
Task F (user_invocable) → no deps, CRITICAL — do first
Task G (MCP followup) → no deps
Task H (rich PLAN_REVIEW + agent dispatch enrichment) → no deps, synergizes with I (waves shown in PLAN_REVIEW)
Task I (wave assembly + sessions) → no deps, MUST be done with J+K together
Task J (step decomposition) → no deps, MUST be done with I+K together
Task K (critical path analysis) → depends on I+J (needs waves + decomposition)
Task L (optimization strategy rewrite) → depends on I+J+K (needs all planner changes)
Task M (plan-epic: plan detection + EPIC generation + source plan enrichment) → depends on D (needs updated EPIC template + plan_ref)
Task N (brainstorm: inline execution plan) → depends on F + D (F adds frontmatter; D updates brainstorming.md template section before N updates flow diagram)
Task O (execution chain: source plan integration) → depends on M + H (M adds source_plan to plan.json; H adds dispatch logic to epic-orchestration.md)
```

Tasks A, D, E, F, G, H are independent and can be parallelized (wave 0 candidates).
Tasks I, J, K, L form a dependency chain (planner redesign): I+J parallel → K → L.
Task M depends on D (EPIC template + plan_ref). Task N depends on F + D (frontmatter + brainstorming.md template).
Task O depends on M + H (source_plan field + dispatch enrichment logic). M and N are independent of each other.

**Variant B pipeline (zero detail loss):**
```
Source Plan (.aid-o/01-plans/) ──────────────────────────────┐
       ↓                                                      │
EPIC (.aid-o/02-epics/) ← plan_ref set (Task D)              │
       ↓                                                      │
plan.json ← source_plan field (Task M) ← enriched from plan  │
       ↓                                                      │
Session ← phases enriched from source plan (Task M)           │
       ↓                                                      │
Agent dispatch ← source plan section in prompt (Tasks H + O) ─┘
```

---

## Summary

| Phase | Tasks | Description |
|---|---|---|
| Critical Fixes | F, G | user_invocable frontmatter + MCP onboarding followup |
| Infrastructure | A, E | Git hygiene + Qdrant path fix |
| UX | H | Rich PLAN_REVIEW with wave/session detail + agent dispatch source plan enrichment |
| EPIC Quality | D | EPIC detail level — typed artifacts, Hints, plan_ref enforcement, EPIC Subagent Template update |
| Planner Redesign | I, J, K, L | Wave assembly + step decomposition + critical path + optimization strategy |
| Pipeline | M, N | plan-epic accepts plans (auto-EPIC + source plan enrichment) + brainstorm inline execution |
| Execution Chain | O | Source plan integration into run-step, run-epic, plan.schema.json |
| **TOTAL** | **13 active tasks** | **~32 files modified, ~3 new files** |

---

## Task A: Selective .aid-o Gitignore

**Why:** `.aid-o/04-engine/` generates dozens of files per EPIC run (sessions, evidence, stage_log, gates_report). These runtime artifacts create git noise that distracts from actual project changes. Design artifacts (plans, epics, config) should remain versioned.

**Decision:** Selective ignore — version `01-plans/`, `02-epics/`, `03-config/`. Ignore `04-engine/`. Evidence data lives in Qdrant (v0.3.0 Task 6) + locally, not needed in git.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/.gitignore` (new file — default gitignore template)
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (make gitignore automatic in Option 1 init)

**Step 1: Create default .gitignore template**

Create new file `plugins/aid-orchestrator/defaults/.gitignore`:

```gitignore
# AID Orchestrator — runtime engine artifacts (not versioned)
# Plans, EPICs, and config ARE versioned (design artifacts)
.aid-o/04-engine/
```

This file serves as the template that gets appended to the project's `.gitignore` during setup.

**Step 2: Make gitignore automatic in aid-setup Option 1 (init)**

In `plugins/aid-orchestrator/commands/aid-setup.md`, modify Option 1 "Initialize .aid-o/" (currently lines ~260-290) to include automatic gitignore configuration as part of init:

```markdown
### Option 1: Initialize .aid-o/ workspace

After creating the `.aid-o/` directory structure:

1. Check if `.gitignore` exists in project root
2. If yes: check if `.aid-o/04-engine/` rule already exists (grep)
3. If not present: append the AID gitignore block from `defaults/.gitignore`
4. If `.gitignore` doesn't exist: create it with the AID rules

The appended block:
```
# AID Orchestrator — runtime artifacts
.aid-o/04-engine/
```

IMPORTANT: Never overwrite existing .gitignore rules. Always append.

This makes Option 5 (Add .aid-o/ to .gitignore) effectively automatic —
it happens as part of init. Option 5 remains available for manual re-runs
but is no longer needed as a separate selection.
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/defaults/.gitignore \
       plugins/aid-orchestrator/commands/aid-setup.md
git commit -m "feat(setup): add selective .aid-o gitignore — automatic during init

Runtime artifacts (.aid-o/04-engine/) now automatically ignored during
Option 1 init. Design artifacts (plans, epics, config) remain versioned.
Evidence data available via Qdrant. Option 5 becomes automatic."
```

---

## Task D: EPIC Detail Level + plan_ref Enforcement + EPIC Subagent Template — Planner-Ready Input Quality

**Why:** Nový planner (Tasks I-L) potřebuje z EPICu dostatek informací pro wave assembly, step decomposition a critical path analysis. Dosavadní EPIC template je příliš vágní — PM napíše jen adresáře místo souborů, artifacts bez typů, AC bez struktury. Planner pak plánuje naslepo. Navíc EPIC `plan_ref` pole existuje ale nikdo ho neenforcuje — bez něj se ztrácí odkaz na zdrojový plán a jeho implementační detail. EPIC Subagent Template v brainstorming.md explicitně zahazuje detail ("High-Level Steps") místo aby zachoval vazbu na plán.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/epic.md`
- Modify: `plugins/aid-orchestrator/defaults/templates/epic-example.md`
- Modify: `plugins/aid-orchestrator/skills/planner.md` (Step 1 — input validation)
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` (EPIC Subagent Prompt Template, lines 194-300)

### Co v EPICu chybí pro nový planner

| Sekce | Teď | Potřeba pro planner |
|-------|-----|---------------------|
| Context | Volný text | Tech stack, greenfield/brownfield, existující patterny |
| Scope | Adresáře (`backend/app/tasks/`) | Konkrétní soubory (`backend/app/tasks/models.py, routes.py, service.py`) |
| Artifacts | Volný seznam | Typované: `endpoint:`, `model:`, `component:`, `config:`, `doc:` — planner potřebuje layer typy pro step decomposition (Task J) |
| Steps | PM definuje ručně, povinné | Optional hints — planner generuje z artifacts + AC. Pokud PM definuje, planner je bere jako constraints, ne jako finální plán |
| AC | Checkboxy bez struktury | Formát `[role] criterion` — planner ví, který agent verifikuje |
| Complexity | Neexistuje | Hint: `expected_steps: 5-8` nebo `complexity: high` — planner ví, zda aktivovat critical path (Task K) |

### Step 1: Rozšířit EPIC template (`epic.md`)

Změny v template:

**Context** — přidat guidance:
```markdown
## Context

<!-- REQUIRED for planner quality: -->
<!-- - Tech stack (e.g. FastAPI + React + PostgreSQL) -->
<!-- - Greenfield (new module) vs. brownfield (modifying existing) -->
<!-- - Existing patterns to follow (e.g. "follows same structure as users/ module") -->
<!-- - Prior work this builds on (e.g. "extends auth from EPIC-003") -->
```

**Scope** — přidat expected files:
```markdown
### Allowed files/paths
- <!-- Directories: backend/app/tasks/ -->
- <!-- Specific files (helps planner scope agents): -->
  - <!-- backend/app/tasks/models.py -->
  - <!-- backend/app/tasks/routes.py -->
  - <!-- backend/app/tasks/schemas.py -->
```

**Artifacts** — typované:
```markdown
## Artifacts

<!-- Type each artifact for planner layer detection: -->
<!-- endpoint: POST /api/v1/tasks, GET /api/v1/tasks, ... -->
<!-- model: tasks table (id, title, status, tenant_id, timestamps) -->
<!-- component: TaskBoard, TaskCard, TaskForm -->
<!-- config: deployment config, env vars -->
<!-- doc: API docs, ADR, CHANGELOG -->
- endpoint:
- model:
- component:
- doc:
```

**Steps** — optional, hints:
```markdown
## Steps (Role Pipeline)

<!-- OPTIONAL: If you define steps, the Planner treats them as constraints. -->
<!-- If omitted, the Planner generates steps from Artifacts + AC + Scope. -->
<!-- Tip: For complex EPICs (7+ expected steps), define at least the critical path. -->
```

**Complexity hint** — nová sekce (volitelná):
```markdown
## Hints (Optional)

<!-- Help the planner make better decisions: -->
- expected_steps: <!-- e.g. 5-8 -->
- complexity: <!-- low | medium | high -->
- parallelism_potential: <!-- low | medium | high -->
- notes: <!-- e.g. "backend and frontend are fully independent" -->
```

### Step 2: Aktualizovat example (`epic-example.md`)

Přepsat example tak, aby demonstroval nový formát. Klíčové změny:

1. **Context** — přidat: "FastAPI + React + PostgreSQL stack. Greenfield feature — new bounded context, no existing task code. Follows same module pattern as `backend/app/users/`."

2. **Scope** — rozšířit o konkrétní soubory (ne jen adresáře). Ukázat rozdíl: adresář = "agent smí tady pracovat", soubor = "planner ví přesně co vznikne".

3. **Artifacts** — typovat:
   ```
   - endpoint: POST /api/v1/tasks (create), GET /api/v1/tasks (list, paginated), GET /api/v1/tasks/{id} (detail), PATCH /api/v1/tasks/{id} (update), DELETE /api/v1/tasks/{id} (soft delete)
   - model: tasks (id, title, description, status, tenant_id, created_by, created_at, updated_at)
   - component: TaskBoard (list + filter), TaskCard (single task), TaskForm (create/edit), TaskFilter (status/date)
   - config: OpenAPI spec (openapi_tasks.yaml)
   - doc: ADR-015-task-state-machine.md, docs/api/tasks.md, CHANGELOG.md
   ```

4. **Steps** — přepsat jako optional hints s komentářem: "Planner may reorganize these into waves. Dependencies are constraints, roles are hints."

5. **Hints** — přidat:
   ```
   - expected_steps: 7-9
   - complexity: medium
   - parallelism_potential: high (backend + frontend nezávislé po architect)
   ```

6. **AC** — přidat role prefix kde má smysl:
   ```
   - [backend] POST /api/v1/tasks returns 201 with valid JSON payload
   - [backend] Tenant isolation: user A cannot see user B's tasks
   - [frontend] TaskBoard renders with loading, empty, and data states
   - [qa] Unit test coverage > 80% for backend/app/tasks/
   - [security] No HIGH/CRITICAL findings in security scan
   ```

### Step 3: Planner input validation

Přidat do `planner.md` na začátek flow (Step 1, před parsing) validaci EPIC kvality:

```
1. RECEIVE EPIC → validate sections:
   a. REQUIRED: Goal, Scope (with ≥1 path), DoD (≥1 gate), AC (≥3 criteria)
   b. RECOMMENDED: Artifacts (typed), Context (with stack info), Hints
   c. If Artifacts are untyped → infer types from text (best effort)
   d. If Steps are missing → planner generates from Artifacts + AC (normal flow)
   e. If Steps present → treat as constraints, validate deps, allow planner to add/split
   f. If Scope has only directories (no files) → planner infers files from Artifacts
   g. WARNING (not blocking): If AC < 5 or Artifacts empty → flag in PLAN_REVIEW
      as "Low-detail EPIC — plan quality may be reduced. Consider adding typed artifacts."
```

### Step 4: plan_ref Enforcement in EPIC Template

**Problem:** EPIC frontmatter has `plan_ref: null` but nobody enforces it. When an EPIC is generated from a plan (via brainstorm or plan-epic), the reference to the source plan is lost. Without `plan_ref`, the execution pipeline cannot access the plan's implementation detail.

In `epic.md`, change the frontmatter guidance:

```yaml
---
status: done
plan_ref: null             # REQUIRED when EPIC comes from a plan (set to plan filename)
                           # null ONLY for standalone EPICs (no source plan)
plan_epics_total: null     # copied from plan for quick reference (null for standalone)
sessions_total: 1          # from Session Breakdown (1 = single session)
sessions_completed: 0      # incremented at each session DONE
---
```

Add a comment block after frontmatter:

```markdown
<!-- plan_ref: Links this EPIC to its source plan in .aid-o/01-plans/.
     When set, the execution pipeline reads the source plan for implementation detail.
     Agents receive relevant plan sections alongside EPIC step definitions.
     This is Variant B: EPIC = structured spec, Plan = implementation guide, both read during execution. -->
```

In `epic-example.md`, update frontmatter to show `plan_ref` in use:

```yaml
---
status: done
plan_ref: 2026-02-15-task-management-plan.md
plan_epics_total: 1
sessions_total: 1
sessions_completed: 0
---
```

### Step 5: Update EPIC Subagent Prompt Template in brainstorming.md

**Problem:** The EPIC Subagent Template (brainstorming.md lines 194-300) explicitly says "Map plan's **High-Level Steps**" and "List concrete deliverables from the plan's **High-Level Steps**". This instructs the AI to drop implementation detail. The template also never sets `plan_ref`.

In `skills/brainstorming.md`, modify the EPIC Subagent Prompt Template (lines 194-300):

**Change 1:** Replace `plan_ref: null` instruction — add after "Fill all sections":
```markdown
   ### Frontmatter
   - Set `plan_ref: {plan_filename}` (the source plan's filename, e.g., `P-20260219-task-mgmt.md`)
   - Set `plan_epics_total: 1` (or as specified in plan)
   - Set `sessions_total:` based on Session Breakdown rules
```

**Change 2:** Replace "High-Level Steps" references with plan-detail-preserving instructions:

Replace (around line 242):
```
   ### Artifacts
   - List concrete deliverables from the plan's High-Level Steps.
```
With:
```
   ### Artifacts
   - List concrete deliverables from ALL plan tasks/steps (not just high-level).
   - Type each artifact: endpoint:, model:, component:, config:, doc:
   - Include specific file paths from the plan where mentioned.
```

Replace (around line 266):
```
   ### Steps (Role Pipeline)
   - Map plan's High-Level Steps to AID roles:
```
With:
```
   ### Steps (Role Pipeline)
   - Map ALL plan tasks to AID roles (each plan task = one EPIC step):
   - Preserve plan Task IDs in objective field (e.g., "Add gitignore (Plan: Task A)")
   - The source plan's implementation detail for each task is accessed via plan_ref
     during execution — the EPIC step is a structured summary, not a replacement.
```

**Change 3:** Add after YAGNI instruction (around line 292):
```markdown
5. IMPORTANT — Zero Detail Loss (Variant B):
   The EPIC does NOT replace the source plan. It adds structure (roles, deps, gates, AC)
   on top of the plan's implementation detail. The plan_ref field ensures agents can
   always access the full plan. Do NOT try to compress all plan detail into the EPIC —
   instead, create a well-structured specification that references the plan.
```

### Step 6: Commit

```bash
git add plugins/aid-orchestrator/defaults/templates/epic.md \
       plugins/aid-orchestrator/defaults/templates/epic-example.md \
       plugins/aid-orchestrator/skills/planner.md \
       plugins/aid-orchestrator/skills/brainstorming.md
git commit -m "feat(epic): enhance EPIC template + plan_ref enforcement + EPIC Subagent update

Typed artifacts (endpoint/model/component/config/doc), specific file paths
in Scope, optional Hints section, role-prefixed AC. plan_ref now REQUIRED
when EPIC comes from a plan (Variant B: zero detail loss). EPIC Subagent
Template updated to set plan_ref and preserve plan task mappings instead
of dropping to High-Level Steps only."
```

---

## Task E: Fix Qdrant Storage Path — Centralized Location

**Why:** Current `aid-setup.md` stores Qdrant data in `.aid-o/qdrant-data/` inside the **project directory**. This is wrong because:
1. Each project gets its own isolated Qdrant — no cross-project knowledge sharing
2. Deleting a project deletes all Qdrant data (lessons, decisions, patterns — gone)
3. Contradicts the design in `memory-mcp.md` which expects one shared `aid-memory` collection for ALL projects

**Fix:** Move Qdrant data path to `~/.local/share/aid-orchestrator/qdrant-data` (XDG standard for persistent application data). MCP registration must be `--scope user` (global, not per-project).

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (Qdrant install command + path + migration check)
- Modify: `plugins/aid-orchestrator/skills/memory-mcp.md` (add Storage Architecture section)

Note: `memory-config.yaml` does NOT need changes — it has no `local_path` field.

**Step 1: Fix Qdrant install command in aid-setup.md**

Change the Qdrant MCP registration from:

```bash
# WRONG — per-project, no cross-project sharing
claude mcp add qdrant-memory \
  --qdrant-local-path .aid-o/qdrant-data \
  -- uvx mcp-server-qdrant
```

To:

```bash
# CORRECT — centralized, all projects share one Qdrant instance
claude mcp add qdrant-memory --scope user \
  --qdrant-local-path ~/.local/share/aid-orchestrator/qdrant-data \
  -- uvx mcp-server-qdrant
```

Key changes:
- `--scope user` → global MCP, available in all projects
- `~/.local/share/aid-orchestrator/qdrant-data` → centralized, survives project deletion

Also add migration check in the same aid-setup.md section:

```markdown
### Migration Check

IF `.aid-o/qdrant-data/` exists in project root:
  WARN PM: "Found local Qdrant data from previous setup. This data should be
  in the centralized location (~/.local/share/aid-orchestrator/qdrant-data).
  Would you like to migrate it? (Y/N)"
  IF Y: move data, remove old directory, re-register MCP with --scope user
  IF N: keep both, warn about potential duplicate entries
```

**Step 2: Add Storage Architecture section to memory-mcp.md**

```markdown
## Storage Architecture

Qdrant data is stored CENTRALLY, not per-project:

- Path: `~/.local/share/aid-orchestrator/qdrant-data`
- MCP scope: `user` (global — available in all projects)
- All projects write to the same `aid-memory` collection
- Entries are tagged with `project_name` in metadata for filtering
- Deleting a project does NOT delete its Qdrant entries
- Cross-project search works because all data is in one place

This is different from `.aid-o/` which is per-project.
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md \
       plugins/aid-orchestrator/skills/memory-mcp.md
git commit -m "fix(memory): centralize Qdrant storage path to ~/.local/share/aid-orchestrator

Previous setup stored Qdrant data in .aid-o/qdrant-data/ per-project, breaking
cross-project knowledge sharing and risking data loss on project deletion.
Now uses centralized ~/.local/share/aid-orchestrator/qdrant-data with --scope user."
```

---

## Task F: Add `user_invocable` Frontmatter to All Commands (CRITICAL)

**Why:** 18 of 19 commands lack YAML frontmatter with `user_invocable: true`. Users must type `/aid-orchestrator:aid-setup` instead of `/aid-setup`. Only `aid-analytics.md` has correct frontmatter. This is the #1 UX pain point from v0.3.0 testing.

**Source:** PROP-20260219-002

**Files:**
- Modify: ALL 18 command files in `plugins/aid-orchestrator/commands/` (except `aid-analytics.md` which is already correct)

**Step 1: Add YAML frontmatter to each command file**

For each command file, prepend YAML frontmatter block. The `name` field must match the filename without `.md`:

| File | name | description |
|------|------|-------------|
| `aid-setup.md` | aid-setup | Interactive project onboarding — detect stack, configure AID |
| `aid-init.md` | aid-init | Initialize .aid-o/ workspace structure |
| `aid-brainstorm.md` | aid-brainstorm | 9-step interactive brainstorming flow |
| `aid-help.md` | aid-help | AID documentation and help topics |
| `run-epic.md` | run-epic | Execute full EPIC orchestration pipeline |
| `plan-epic.md` | plan-epic | Generate Plan JSON from EPIC specification |
| `run-step.md` | run-step | Run a single step manually |
| `epic-status.md` | epic-status | Show pipeline status (steps, gates, budget) |
| `run-gates.md` | run-gates | Run quality gates standalone |
| `epic-queue.md` | epic-queue | EPIC queue management (add, remove, pause) |
| `quality-gates.md` | quality-gates | 6-gate pre-commit protocol |
| `session-start.md` | session-start | Start a tracked session |
| `session-end.md` | session-end | Complete and archive session |
| `handoff.md` | handoff | Create handoff block for next AI session |
| `audit.md` | audit | Project health audit (0-100 score) |
| `coding-standards.md` | coding-standards | Load project coding standards |
| `testing.md` | testing | Load testing workflow and standards |
| `docs-protocol.md` | docs-protocol | Load documentation protocol |

Format for each file — prepend before existing content:

```yaml
---
name: {command-name}
description: {one-line description}
user_invocable: true
---
```

**IMPORTANT:** Do NOT modify any existing content in the files. Only prepend the frontmatter block.

**Step 2: Update README and aid-help command table**

In root `README.md` and `plugins/aid-orchestrator/README.md`, update the commands section to show shorthand syntax (e.g., `/aid-setup` instead of `/aid-orchestrator:aid-setup`).

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/commands/*.md README.md plugins/aid-orchestrator/README.md
git commit -m "fix(commands): add user_invocable frontmatter to all 18 commands

PROP-20260219-002. Users can now type /aid-setup instead of
/aid-orchestrator:aid-setup. All 19 commands have YAML frontmatter
with name, description, and user_invocable: true."
```

---

## Task G: Setup Followup After "All Recommended"

**Why:** When user selects "(A) All recommended" in `/aid-setup`, five options are silently skipped: CLAUDE.md generation (4), .gitignore (5), Slack MCP (6b), auto-detect MCPs (6c), and custom MCPs (6d). Option 5 becomes automatic after Task A, but Options 4, 6b, 6c, 6d should be offered as followup — especially 6c (auto-detect) which is dynamic and highly valuable.

**Source:** PROP-20260219-001

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md`

**Step 1: Add followup after recommended options**

In `aid-setup.md`, after Step 5 "Execute Selected Options" completes all recommended options (1,2,3,6a,7,8,9), add:

```markdown
### Step 5b: Additional Options Followup

After all recommended options complete, if PM selected "(A) All recommended":

Run project-profile auto-detection for MCP candidates:
  1. Check `.git` + remote → GitHub MCP candidate
  2. Check `Dockerfile` or `docker-compose.yml` → Docker MCP candidate
  3. Check `has_frontend: true` in project-profile → Playwright MCP candidate
  4. Check `tech_stack.database` → Postgres/MySQL MCP candidate

Present to PM:

```
Recommended setup complete!

Additional options available:

  (4) CLAUDE.md — Generate project context file for Claude Code
      Adds AID markers to CLAUDE.md so Claude understands your project
      structure, conventions, and workflow.

  (6b) Slack notifications — PM approvals and escalations via Slack
       Requires: Slack app with bot token. See /aid-help slack for setup.

  (6c) Auto-detected MCPs for your stack:
       - GitHub MCP (detected: .git + remote origin)
       - Playwright MCP (detected: has_frontend: true)
       [dynamically generated from project-profile detection above]

  (6d) Custom MCP — Add your own MCP servers manually

Configure any of these? (select numbers, or Enter to skip)
```

Process selected options using existing Step 4 logic for each.
If PM presses Enter/skips: continue to Step 6.

NOTE: Option 5 (.gitignore) is NOT offered here — it becomes automatic
after Task A (selective .aid-o gitignore is applied during init).
```

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/commands/aid-setup.md
git commit -m "fix(setup): add followup after 'All recommended' for skipped options

PROP-20260219-001. After recommended setup, offers CLAUDE.md generation,
Slack MCP, auto-detected MCPs (dynamic from project-profile), and custom
MCPs. Auto-detect runs project analysis to show relevant MCP candidates."
```

---

## Task H: Rich PLAN_REVIEW Detail Template (Wave-Based) + Agent Dispatch Source Plan Enrichment

**Why:** PLAN_REVIEW in `epic-orchestration.md` says "Format plan summary" but doesn't specify what detail to include. Agents show minimal info — role + one-line objective. PMs can't make informed GO/REVISE decisions without seeing what each step will actually produce. After planner redesign (Tasks I-L), PLAN_REVIEW must also show waves, critical path, relaxations, and optimization metrics. Additionally, the EXECUTING state's agent dispatch sends only plan.json step data — agents never receive the source plan's implementation detail, which is the core Variant B bug.

**Source:** PROP-20260219-003 + planner parallelism brainstorm (2026-02-19) + Variant B audit (2026-02-20)

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (PLAN_REVIEW state + EXECUTING state agent dispatch)

**Step 1: Add rich plan summary template to PLAN_REVIEW**

In `skills/epic-orchestration.md`, replace the current PLAN_REVIEW actions (line ~186) with a detailed template:

```markdown
### 3. PLAN_REVIEW

**Communication:** Per `skills/slack-mcp.md` Type B (Plan Approval).

**Actions:**
1. Format plan summary using the **Rich Plan Summary Template** below
2. Send to PM via `send_pm_message("plan_approval", payload)`
3. Wait for PM response via `wait_pm_response(message_ref, "plan_approval")`
4. If GO: transition to EXECUTING
5. If REVISE: return to PLANNING with PM feedback
6. If ABORT: transition to DONE (status: aborted)

**Rich Plan Summary Template:**

Present the plan in this format:

```
PLAN_REVIEW: EPIC {epic_id} — {title}

Overview:
  Steps: {count} ({wave_count} waves, {analysis_group_count} analysis groups)
  Roles: {unique roles}
  Sessions: {session_count}
  Gates: {gate list}

Wave Execution Plan:
  Wave 0: [architect] Design API contracts, data model           ~3 files    —
  Wave 1: [domain]    SQLAlchemy models, schemas                 ~8 files    ← wave 0
           [backend]  Database models + Pydantic schemas          ~5 files    ← wave 0
           └─ analysis: [security] → DB validation
  Wave 2: [backend]  API routers + business logic                ~6 files    ← wave 1
           [frontend] React scaffold, routing, pages             ~10 files   ← wave 0  ← CROSS-DOMAIN PARALLEL
           └─ analysis: [security] → auth review
  Wave 3: [qa]       Backend + frontend tests                    ~8 files    ← wave 2
           [security] Security review                            ~2 files    ← wave 2
           [docs]     API docs + guides                          ~4 files    ← wave 2
  Wave 4: [release]  Version bump + deployment config            ~3 files    ← wave 3

Optimization:
  Critical path: {length} steps (ratio: {ratio})
  Wave density: {avg} steps/wave
  Parallel utilization: {parallel_count}/{total} steps ({percent}%)
  Decompositions: {count} applied
  Relaxations: {count} applied
    {if any:}
    - R1: frontend starts after architect (not domain) — needs contracts only
    - R4: security starts after auth step (not all backend)

Session Breakdown:
  Session 1 (waves 0-2, {N} steps): {goal} — {milestone}
  Session 2 (waves 3-4, {N} steps): {goal} — {milestone}

Acceptance Criteria: {total_count} across {category_count} categories
  - Auth: {count} criteria
  - CRUD: {count} criteria
  - Frontend: {count} criteria
  ...
```

**MUST include for each step:**
- Wave number (which wave it belongs to)
- Role in brackets
- Objective (what it builds, not just "implement backend")
- Approximate file count (new/modified)
- Dependencies (which wave it depends on)
- Cross-domain parallel marker (when different domains run in same wave)
- Analysis group (if any)
- Relaxation marker (if dependency was relaxed)

**MUST include optimization section:**
- Critical path length and ratio
- Wave density (avg steps/wave)
- Parallel utilization (% of steps in multi-step waves)
- Decompositions and relaxations applied (with explanation)

**Evidence:** Save to `evidence/{epic_id}/{run_id}/pm_plan_approval.json`
```

**Step 2: Agent Dispatch Source Plan Enrichment (Variant B)**

**Problem:** The EXECUTING state (around line 200-269) dispatches agents with only plan.json step data (objective, inputs, outputs, constraints). Agents never receive the source plan's implementation detail — exact code snippets, specific line numbers, sub-step instructions. This is the core of the Variant B bug: the plan's 1600+ lines of detail never reach the executing agent.

In `skills/epic-orchestration.md`, modify the EXECUTING state's agent dispatch logic:

**Add to the agent prompt construction (after loading step definition from plan.json):**

```markdown
#### Source Plan Integration (Variant B)

When dispatching an agent for a step, check if source plan detail is available:

1. Read `plan.json` → check for `source_plan` field (path to source .md plan file)
2. If `source_plan` exists AND file is readable:
   a. Read the source plan file
   b. Find the matching task section:
      - Match by step objective keywords against plan section headers
      - Match by explicit plan task reference in step objective (e.g., "(Plan: Task A)")
      - If step.id contains a number, try matching against "## Task {letter}" sections
   c. Extract the full task section content (from header to next ## header)
   d. Include in agent prompt as:

   ```
   ## Source Plan — Implementation Detail

   The following is the detailed implementation guide from the source plan.
   Use this as your primary reference for WHAT to change and HOW.
   The step definition above provides the structured constraints (allowed paths,
   acceptance criteria). This section provides the implementation specifics.

   {extracted_plan_task_section}
   ```

3. If `source_plan` does not exist or is unreadable:
   → Agent proceeds with plan.json step data only (backward compatible)
   → No error, no warning — standalone EPICs work as before

4. IMPORTANT: The source plan section is ADDITIVE — it enriches the agent prompt
   but does NOT override plan.json constraints (allowed_paths, forbidden_paths,
   acceptance_criteria). If there's a conflict, plan.json wins.
```

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/epic-orchestration.md
git commit -m "feat(plan-review): rich plan summary + agent dispatch source plan enrichment

PROP-20260219-003 + Variant B. PLAN_REVIEW now requires file counts, parallel
groups, session breakdown, AC categories. Agent dispatch enriched with source
plan implementation detail when plan_ref/source_plan available. Backward
compatible — standalone EPICs work unchanged."
```

---

## Task I: Wave Assembly + Wave-Based Session Boundaries

**Why:** Current planner treats parallelism as an afterthought — builds DAG, then discovers parallel groups. Sessions are split by domain (backend → frontend → quality), killing cross-domain parallelism. This task introduces "waves" as the primary execution unit and rewrites session boundaries to be wave-based.

**Source:** PROP-20260219-004 + planner parallelism brainstorm (2026-02-19)

**Design decision:** Approach C "Hybrid" — Wave Planner as base + Critical Path as opt-in (Task K).

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (replace Section 2 "Parallel Group Detection" + Section 11 "Session Split Decision" + Section 7 steps 3-6)

### Part 1: Wave Assembly (replaces Section 2 "Parallel Group Detection")

Replace the current Section 2 algorithm (lines ~80-107) with:

```markdown
## 2. Wave Assembly

**Input:** dependency graph (adjacency list from Section 1)
**Output:** `waves[]` array (ordered list of step groups, each wave runs in parallel)

### Algorithm

1. LEVEL ASSIGNMENT via topological sort (unchanged):
   level(S) = 0 if S.depends_on is empty
   level(S) = max(level(dep) for dep in S.depends_on) + 1

2. GROUP by level → level_groups = { level: [step_ids] }

3. FILE CONFLICT CHECK:
   For each level, verify no two steps share allowed_paths.
   IF overlap detected:
     → separate conflicting steps into sequential sub-waves
     → log: "Wave split due to file conflict: {step_A} and {step_B} share {paths}"

4. WAVE FORMATION:
   For each level with 1+ steps (after conflict resolution):
     IF level has <= 4 steps:
       → single wave containing all steps
     IF level has 5+ steps:
       → split into sub-waves of max 4 steps each
       → priority: keep same-domain steps together within sub-wave
       → sub-wave order: lower step numbers first

5. OUTPUT: waves[] array (each wave = array of step_ids)
   waves[0] = [step_1_architect]
   waves[1] = [step_2_domain, step_3a_backend]
   waves[2] = [step_3b_backend, step_4_frontend]  ← cross-domain parallel
   waves[3] = [step_5_qa, step_6_security, step_7_docs]

6. BACKWARD COMPATIBILITY:
   parallel_groups = waves with 2+ steps (for plan.json schema)
   Single-step waves produce no parallel_groups entry.
```

### Example — Waves from the 7-Step Dependency Graph

```
Level 0: [step_1_architect]                    → wave 0 (1 step)
Level 1: [step_2_domain, step_4_frontend]      → wave 1 (2 steps — parallel)
Level 2: [step_3_backend]                      → wave 2 (1 step)
Level 3: [step_5_qa, step_6_security, step_7_docs] → wave 3 (3 steps — parallel)

Result: waves = [[step_1], [step_2, step_4], [step_3], [step_5, step_6, step_7]]
Parallel groups: [[step_2, step_4], [step_5, step_6, step_7]]
```

### Part 2: Wave-Based Session Boundaries (replaces Session Split Decision)

Replace the current Session Split Decision table and rules (around line 722-738) with:

```markdown
### Session Split Decision (Wave-Based)

**Core principle:** Sessions = contiguous sequences of waves that fit context window.
NEVER split by domain. NEVER split inside a wave.

#### Session Boundary Algorithm

1. Start with waves[] from Wave Assembly

2. Assign waves to sessions greedily:
   session_steps = 0
   current_session = []

   FOR each wave W in waves[]:
     IF session_steps + len(W) <= MAX_STEPS_PER_SESSION:
       current_session.append(W)
       session_steps += len(W)
     ELSE:
       Flush current_session → new session
       current_session = [W]
       session_steps = len(W)

3. Validate sessions:
   a. NEVER split inside a wave (wave with 2+ steps = parallel group)
   b. Each session must contain at least 1 gate-worthy milestone
   c. First session always starts with architect
   d. Last session always ends with release (if present)
   e. Each session produces independently testable deliverables

#### MAX_STEPS_PER_SESSION heuristic

| Total EPIC steps | Max per session | Rationale |
|------------------|-----------------|-----------|
| 1-6              | 6 (= 1 session) | Fits single context window |
| 7-10             | 6-7             | 2 sessions, balanced |
| 11-15            | 6               | 2-3 sessions |
| 16+              | 5-6             | 3+ sessions, tighter bounds |

Note: "steps" counts sub-steps from decomposition (Task J).
A wave of 4 parallel steps counts as 4 steps for this limit.

#### Example — 14-step full-stack EPIC after optimization

Note: This example shows the result AFTER step decomposition (Task J) has
split monolithic steps into sub-steps (e.g., step_3a, step_3b).

Waves (from Wave Assembly):
  wave 0: [step_1_architect]
  wave 1: [step_2_domain, step_3a_backend]
  wave 2: [step_3b_backend, step_4_frontend]         ← cross-domain parallel!
  wave 3: [step_5_backend_search, step_6_extension]
  wave 4: [step_7_frontend_pages]
  wave 5: [step_8_frontend_polish]
  wave 6: [step_9_qa, step_10_security, step_11_docs]
  wave 7: [step_12_release]

Sessions (MAX_STEPS_PER_SESSION = 6):
  Session 1 (waves 0-2, 6 steps):
    architect → [domain ‖ backend-data] → [backend-API ‖ frontend-scaffold]
    Milestone: working API + frontend scaffold

  Session 2 (waves 3-5, 4 steps):
    [search ‖ extension] → frontend-pages → frontend-polish
    Milestone: complete frontend + all features

  Session 3 (waves 6-7, 4 steps):
    [QA ‖ security ‖ docs] → release
    Milestone: validated + released

vs. OLD approach (sequential domains):
  Session 1: architect → domain → backend (all 5 steps sequentially)
  Session 2: frontend (all 4 steps sequentially)
  Session 3: QA → security → docs → release

Result: 3 waves of parallel work vs 0 in old approach.
```

### Part 3: Update Plan Generation Flow (Section 7)

In Section 7 "Complete Plan Generation Flow":

**Replace** the existing "DETECT parallel groups" step with:

```
WAVE ASSEMBLY (replaces "DETECT parallel groups"):
  a. Level assignment via topological sort
  b. File conflict check — separate conflicting steps
  c. Group same-level steps into candidate waves
  d. Split waves with 5+ steps into sub-waves of max 4
  e. Output: waves[] array + parallel_groups (backward compat)
  f. Log: wave_count, max_wave_size, parallel_step_count
```

**Add** after all optimization steps, before OUTPUT/VALIDATE:

```
SESSION BOUNDARIES:
  a. Apply wave-based session boundary algorithm (Section 11)
  b. Write ## Session Breakdown into EPIC file
  c. Set EPIC frontmatter: sessions_total: N
  d. Log: session_count, steps_per_session[]
```

Note: Exact step numbers will be determined during implementation when all
tasks (I, J, K, L) are integrated. Use relative positions, not hardcoded numbers.

**Step 1: Implement all three parts in planner.md**

Apply Part 1 (Wave Assembly), Part 2 (Session Boundaries), and Part 3 (Flow update) as described above.

**Step 2: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md
git commit -m "feat(planner): introduce wave-based execution model + wave-based sessions

PROP-20260219-004. Planner now thinks in 'waves' — groups of steps at the
same DAG level that run in parallel (max 4 per wave). Sessions are cut
between waves, not between domains. Backend + frontend in same wave =
same session = parallel execution."
```

---

## Task J: Step Decomposition — Layer-Based Splitting

**Why:** Planner creates one large step per domain (e.g., "all models + schemas + routers"). This blocks other domains from starting until the entire monolithic step finishes. Splitting into smaller steps by layer (data → schema → API) enables earlier parallelization — frontend can start as soon as architect finishes, parallel with backend data layer.

**Source:** PROP-20260219-005 + planner parallelism brainstorm (2026-02-19)

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (add new Section 2b + update Section 7 step 3)

**Step 1: Add Step Decomposition section to planner.md**

Add new Section 2b after Section 2 (Wave Assembly):

```markdown
## 2b. Step Decomposition — Layer-Based Splitting

Step Decomposition runs BEFORE dependency resolution and wave assembly.
It converts coarse EPIC steps into finer-grained sub-steps when this
enables new parallelism opportunities.

### EPIC Type Guard

Layer-based decomposition applies to DEVELOPMENT EPICs only.
Detect EPIC type from typed artifacts (see Task D):

- **Development**: artifacts contain `endpoint:`, `model:`, `component:`
  → apply full layer-based decomposition below
- **Documentation**: artifacts are all `doc:`
  → decompose by TOPIC instead of layer (split "write all docs" into
    "API docs", "user guide", "architecture docs" if they have different deps)
- **Infrastructure/Config**: artifacts are `config:` or devops-oriented
  → decompose by SCOPE (e.g., "CI pipeline" vs "deployment config" vs "monitoring")
- **Mixed**: combination of types
  → apply layer decomposition to dev steps, topic/scope to non-dev steps

### Algorithm (Development EPICs)

For each step S in the parsed EPIC:
  1. EVALUATE split criteria (ALL must be true):
     a. S spans 2+ distinct layers (data, schema, API, service, UI, test, config)
     b. S produces 5+ files (estimated from objective + allowed_paths)
     c. Splitting enables at least 1 new parallel pairing with another domain
     d. Each resulting sub-step would produce 3+ files

  2. IF all criteria met → DECOMPOSE:
     a. Identify layers present in S.objective and S.outputs
     b. Create sub-steps following Layer Hierarchy (below)
     c. Sub-step ID format: step_{N}{letter}_{role}
        (e.g., step_3a_backend, step_3b_backend, step_3c_backend)
     d. Sub-step dependencies:
        - First sub-step inherits ALL of original step's depends_on
        - Each subsequent sub-step depends on its predecessor
        - Steps that depended on the ORIGINAL now depend on the LAST sub-step
     e. Sub-step allowed_paths: subset of original, scoped to layer

  3. IF criteria not met → keep as single step (no change)

### Layer Hierarchy (earlier layers first)

| Priority | Layer | Typical Files |
|----------|-------|---------------|
| 1 | data | models, migrations, database setup, ORM entities |
| 2 | schema | validation schemas, DTOs, type definitions, Pydantic/Zod |
| 3 | API | routers, controllers, endpoints, middleware |
| 4 | service | business logic, utilities, helpers, domain services |
| 5 | UI | components, pages, layouts, styles |
| 6 | test | unit tests, integration tests (per-layer) |
| 7 | config | configuration, deployment, CI, environment |

Adjacent layers (e.g., data+schema) CAN be merged into one sub-step
if they're tightly coupled and splitting them would create trivially
small steps (< 3 files each).

### Example — Backend CRUD decomposition

BEFORE (1 monolithic step):
  step_3_backend: "Implement REST API with models, schemas, routers, tests"
  depends_on: [step_2_domain]
  → Frontend (step_4) must wait for ALL of this to finish

AFTER (3 focused sub-steps):
  step_3a_backend: "Database models + Pydantic schemas" (data + schema layers)
    depends_on: [step_2_domain]
    outputs: models/*.py, schemas/*.py
  step_3b_backend: "API routers + business logic" (API + service layers)
    depends_on: [step_3a_backend]
    outputs: routers/*.py, services/*.py
  step_3c_backend: "Backend unit + integration tests" (test layer)
    depends_on: [step_3a_backend, step_3b_backend]
    outputs: tests/api/*.py, tests/models/*.py

  step_4_frontend: "React components + pages"
    depends_on: [step_1_architect]  ← NOTE: depends on architect, NOT backend!
    → Frontend starts AS SOON AS architect finishes, parallel with backend

Net effect: frontend starts 1-2 waves earlier.

### When NOT to decompose

- Step produces fewer than 5 files total → too small to split meaningfully
- All files are tightly coupled (one endpoint = model + schema + router + test) → splitting breaks cohesion
- Splitting would create more than 4 sub-steps for a single role → diminishing returns
- The EPIC already has 15+ steps → more steps adds overhead, not speed
- Step is a leaf node with no downstream dependents → splitting doesn't enable new parallelism
- EPIC type is documentation/infrastructure and step doesn't span multiple independent topics → topic-based split not applicable
```

**Step 2: Update Section 7 (Plan Generation Flow)**

In Section 7, **add** STEP DECOMPOSITION between PARSE steps and RESOLVE ordering:

```
STEP DECOMPOSITION (after PARSE, before RESOLVE ordering):
  a. Detect EPIC type from artifacts (dev / docs / infra / mixed)
  b. For each step, evaluate split criteria (Section 2b):
     - Dev steps: layer-based (data → schema → API → service → UI → test → config)
     - Docs steps: topic-based (API docs, user guide, architecture)
     - Infra steps: scope-based (CI, deployment, monitoring)
  c. IF criteria met → decompose into sub-steps
  d. Update step list with sub-steps (original step replaced)
  e. Log: decompositions_applied, sub_steps_created, epic_type
```

Note: Exact step number determined during implementation (see Task I note).

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md
git commit -m "feat(planner): add step decomposition — layer-based splitting for parallelism

PROP-20260219-005. Planner decomposes large monolithic steps into layer-based
sub-steps (data → schema → API → test) when this enables cross-domain
parallelism. Frontend starts after architect, not after full backend."
```

---

## Task K: Critical Path Analysis + Dependency Relaxation

**Why:** Even with wave assembly and step decomposition, the planner doesn't actively optimize the critical path — the longest sequential chain through the DAG. For large EPICs (7+ steps), the critical path determines wall-clock time. This task adds explicit critical path analysis and dependency relaxation to shorten it.

**Source:** Planner parallelism brainstorm (2026-02-19) — Approach C "Hybrid" opt-in component

**Prereq:** Tasks I + J (needs waves + decomposition as foundation)

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (add new Section 2c + update Section 7 step 7)

**Step 1: Add Critical Path Analysis section to planner.md**

Add new Section 2c after Section 2b (Step Decomposition):

```markdown
## 2c. Critical Path Analysis (opt-in, 7+ steps)

Critical path analysis is activated when total_steps >= 7. For smaller EPICs,
the overhead of analysis exceeds the benefit.

### Step 1: Compute Critical Path

Critical path = longest chain through DAG measured by step count.

Algorithm:
  1. For each step S in topological order:
     dist(S) = 0 if S.depends_on is empty
     dist(S) = max(dist(dep) + 1 for dep in S.depends_on)
  2. critical_path_length = max(dist(S) for all S)
  3. Backtrack from maximum → identify all steps on critical path
  4. critical_path_ratio = critical_path_length / total_steps

### Step 2: Dependency Relaxation (if ratio > 0.6)

If more than 60% of steps are on the critical path, the DAG is too sequential.
Apply relaxation rules to shorten it.

For each dependency edge ON the critical path, evaluate these rules.

NOTE: Rules R1-R5 are DEVELOPMENT-SPECIFIC. For non-dev EPICs (docs, infra),
CPA still computes critical path and ratio, but relaxation rules don't apply
(no domain-specific heuristics). For mixed EPICs, apply rules only to dev steps.

#### Development Relaxation Rules

RULE R1: "Frontend doesn't need Domain"
  IF: step_{N}_frontend depends on step_{M}_domain
  AND: step_{M}_domain produces only data models (no API contracts)
  AND: step_{1}_architect produced API contracts
  THEN: relax → frontend depends on architect instead of domain
  REASON: Frontend builds against API contracts, not domain internals

RULE R2: "QA can start with partial implementation"
  IF: step_{N}_qa depends on ALL implementation steps
  AND: implementation steps are in different domains (backend vs frontend)
  THEN: split QA into domain-specific sub-steps:
    step_{N}a_qa depends on backend steps only
    step_{N}b_qa depends on frontend steps only
  REASON: Backend tests don't need frontend code and vice versa

RULE R3: "Docs can start after architect"
  IF: step_{N}_docs depends on all implementation steps
  AND: architect step produced contracts/ADRs
  THEN: split docs:
    step_{N}a_docs "API documentation" depends on architect (start early!)
    step_{N}b_docs "Usage guides" depends on implementation (late)
  REASON: API docs come from contracts, not from reading implementation

RULE R4: "Security review of auth can run early"
  IF: step_{N}_security depends on ALL backend steps
  AND: one backend step is specifically auth/security-focused
  THEN: security depends on auth step only (not all backend)
  REASON: Security review of auth doesn't need CRUD endpoints

RULE R5: "Layer split enables cross-domain parallel"
  IF: step on critical path spans 2+ layers
  AND: splitting would allow another domain to start earlier
  THEN: recommend decomposition (Section 2b)
  NOTE: Bridge between decomposition and relaxation — if decomposition
  was skipped for this step, reconsider here.

### Step 3: Safety Net

EVERY relaxation MUST be:
  a. LOGGED in plan metadata:
     {"relaxation": "R1", "original_edge": "domain→frontend",
      "relaxed_to": "architect→frontend",
      "reason": "frontend needs API contracts only, not domain models"}
  b. VISIBLE in PLAN_REVIEW output:
     "Relaxed: frontend starts after architect (not after domain)
      — needs API contracts only"
  c. REJECTABLE by PM at PLAN_REVIEW — PM can reject individual relaxations
  d. RECOVERABLE at runtime — if agent fails due to missing dependency
     (detected at PHASE_CHECK):
     → Controller re-dispatches with original (non-relaxed) dependency
     → Log: "Relaxation R1 failed for step_X — re-run with full deps"
     → This counts against the step's retry limit (not a new mechanism)

### Step 4: Re-optimization

After applying relaxations:
  1. Re-build DAG with relaxed edges
  2. Re-level (topological sort)
  3. Re-assemble waves (Section 2)
  4. Verify: new critical_path_ratio < original ratio
     IF NOT improved: revert ALL relaxations (they didn't help)
  5. Log delta:
     "Critical path reduced from {old} to {new} steps ({percent}% shorter)"
     "Relaxations applied: {count} ({rule_ids})"
```

**Step 2: Update Section 7 (Plan Generation Flow)**

In Section 7, **add** CRITICAL PATH ANALYSIS after WAVE ASSEMBLY:

```
CRITICAL PATH ANALYSIS (opt-in, after WAVE ASSEMBLY):
  IF total_steps >= 7:
    a. Compute critical path (longest DAG chain)
    b. IF critical_path_ratio > 0.6:
       → For dev EPICs: apply relaxation rules R1-R5 (Section 2c)
       → For non-dev EPICs: CPA data only, no relaxation rules
       → Re-level and re-assemble waves
       → Verify improvement, revert if no gain
    c. Log critical path to plan metadata:
       "critical_path": [step_ids on path]
       "critical_path_ratio": 0.57
       "relaxations_applied": [{rule, edge, reason}]
```

Note: Exact step number determined during implementation (see Task I note).

**Step 3: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md
git commit -m "feat(planner): add critical path analysis + dependency relaxation

Opt-in for EPICs with 7+ steps. Computes critical path, applies 5 relaxation
rules (R1-R5) to shorten it. Safety net: PM sees relaxations in PLAN_REVIEW,
can reject individually. Runtime fallback on agent failure."
```

---

## Task L: Rewrite Optimization Strategy (Section 11) — Parallelism-First

**Why:** Current Section 11 "Planner Optimization Strategy" lists priorities as Speed > Quality > Efficiency but doesn't operationalize them. The step planning rules are incomplete (missing wave density, session compactness). Plan quality metrics don't exist. This task rewrites the entire section to match the new parallelism-first architecture.

**Source:** Planner parallelism brainstorm (2026-02-19) — unified optimization framework

**Prereq:** Tasks I + J + K (needs all planner changes as foundation)

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` (rewrite Section 11)

**Step 1: Rewrite Section 11 in planner.md**

Replace the entire Section 11 "Planner Optimization Strategy" with:

```markdown
## 11. Planner Optimization Strategy (Parallelism-First)

### Core Philosophy

The Planner's PRIMARY job is to minimize WALL-CLOCK TIME to EPIC completion.
Not step count. Not token count. WALL-CLOCK TIME.

Wall-clock time ≈ critical_path_length × avg_step_duration
                + session_transitions × ~2 min each
                + overhead (merges, phase checks, wave transitions)

### Optimization Priorities (in order)

1. **PARALLELISM** — minimize critical path length
   - Every step on the critical path is wall-clock time you can't avoid
   - Decompose steps to move work OFF the critical path (Section 2b)
   - Relax dependencies to shorten the critical path (Section 2c)
   - Target: critical_path_ratio < 0.5 (< half of steps on critical path)

2. **WAVE DENSITY** — maximize work per wave
   - Empty slots in a wave = wasted parallelism capacity
   - 4 agents in parallel ≈ same wall-clock time as 1 agent
   - Target: average wave utilization > 2.5 steps/wave

3. **SESSION COMPACTNESS** — minimize session count
   - Each session transition costs: context reload + state verify ≈ 2 min
   - Fewer sessions = less overhead
   - Target: total_steps / session_count >= 4

4. **QUALITY** — ensure outputs meet acceptance criteria
   - Every step has clear, verifiable acceptance criteria
   - Dependencies are explicit — no implicit ordering assumptions
   - Security and QA steps always AFTER implementation
   - Gates validate cumulative quality

5. **EFFICIENCY** — avoid wasted work
   - No redundant steps (don't split what one agent can do well)
   - File scoping: relevant_files per step eliminates blind exploration
   - Dependency outputs are explicit — agents don't guess what prior steps produced

### Step Planning Rules (revised)

#### Universal Rules (all EPIC types)

1. **First step is always wave 0** — architect (dev), lead writer (docs), or scaffold (infra)
2. **Maximum wave size: 4 steps** — soft limit, Controller handles overflow gracefully
3. **NEVER create trivially small steps** (< 3 files) just for parallelism
4. **Prefer wider waves over more waves** — 1 wave of 4 > 2 waves of 2
5. **Verification/review steps ALWAYS after implementation/writing** — QA, security, review

#### Development-Specific Rules

6. **Backend + Frontend ALWAYS parallelize** when contracts exist from architect
   This is the #1 parallelism opportunity in most dev EPICs
7. **Decompose large steps** (5+ files, 2+ layers) into sub-steps
   WHEN this enables at least 1 new parallel pairing (Section 2b)
8. **Domain can parallelize with backend's first sub-step** IF:
   - Domain produces models/entities
   - Backend first sub-step is data layer (schemas, DB setup)
   - They don't touch the same files (non-overlapping allowed_paths)

#### Non-Development Rules

9. **Independent topics ALWAYS parallelize** — "API docs" ‖ "User guide" if different sources
10. **Config steps parallelize when targeting different systems** — CI ‖ deployment ‖ monitoring

### Plan Quality Metrics

Every plan.json MUST include an `optimization_metrics` object:

{
  "optimization_metrics": {
    "total_steps": 14,
    "wave_count": 8,
    "session_count": 3,
    "critical_path_length": 5,
    "critical_path_ratio": 0.36,
    "avg_wave_density": 1.75,
    "parallel_step_count": 10,
    "sequential_step_count": 4,
    "relaxations_applied": 2,
    "decompositions_applied": 1
  }
}

These metrics are:
- Shown in PLAN_REVIEW (so PM sees parallelism quality)
- Stored in evidence (for post-EPIC analysis)
- Fed to /aid-analytics (for cross-EPIC optimization tracking)
- Used by Planner self-improvement (compare metrics across EPICs via Qdrant)

### Session Split Decision (Wave-Based)

[See Task I — this section is fully specified there]
```

**Step 2:** PLAN_REVIEW template already includes optimization metrics display — see Task H (Rich PLAN_REVIEW). No additional changes needed here.

**Step 3: Add new validation rules**

Add to Section 6 (Plan JSON Validation):

| Rule | Check | Error Template |
|------|-------|----------------|
| V-20 | `optimization_metrics` present in plan.json | "Plan missing optimization_metrics" |
| V-21 | `critical_path_ratio` <= 1.0 | "Invalid critical_path_ratio: {value}" |
| V-22 | `wave_count` > 0 | "Plan has no waves" |
| V-23 | All relaxations reference valid step IDs | "Relaxation references unknown step: {id}" |

**Step 4: Commit**

```bash
git add plugins/aid-orchestrator/skills/planner.md \
       plugins/aid-orchestrator/skills/epic-orchestration.md
git commit -m "feat(planner): rewrite optimization strategy — parallelism-first mindset

New Section 11 with 5 optimization priorities (parallelism > wave density >
session compactness > quality > efficiency), revised step planning rules,
plan quality metrics (critical_path_ratio, wave_density, parallel_utilization),
and 4 new validation rules (V-20 through V-23)."
```

---

## Task M: `/plan-epic` — Format Detection + Plan-to-EPIC Auto-Conversion + Source Plan Enrichment

**Why:** `/plan-epic` currently only accepts EPIC files (validates Goal, Scope, DoD Gates, AC). When a PM writes a plan manually in `.aid-o/01-plans/` (like this v0.4.0 plan), there's no way to create an EPIC from it — the command rejects it for missing EPIC sections. This forces PMs to either re-run `/aid-brainstorm` (redundant) or manually write an EPIC from the template (tedious). Additionally, plan.json is built purely from the EPIC — the source plan's implementation detail (exact code, line numbers, sub-steps) is never incorporated into plan.json or the session file. This is the pipeline-level fix for Variant B.

**Source:** v0.4.0 testing — `/plan-epic` called on plan file, failed at Step 1 validation. + Variant B audit (2026-02-20).

**Prereq:** Task D (EPIC template enhancement + plan_ref enforcement) — the auto-generated EPIC quality depends on the template having typed artifacts, Hints, and plan_ref.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/plan-epic.md` (add Steps 0.5 + 0.7, update prerequisites + empty-args)
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` (update /plan-epic documentation)

**Note:** Uses `skills/brainstorming.md` EPIC Subagent Prompt Template (lines 194-300) as READ-ONLY reference — no modifications to brainstorming.md needed here.

### Step 1: Add Format Detection (new Step 0.5)

Insert between `## Flow` header and existing `### Step 1` in `plan-epic.md`:

```markdown
### Step 0.5: Input Format Detection

Before validating EPIC sections, detect whether the input file is a Plan or an EPIC.

1. Read the input file at the given path
2. Detect format using this heuristic (first match wins):
   a. **Frontmatter check:** If YAML frontmatter contains `type: plan` → Plan format
   b. **Header check:** If first H1 header starts with `# Plan:` → Plan format.
      If first H1 header starts with `# EPIC:` → EPIC format
   c. **Section fingerprinting:** Scan for section headers:
      - If file contains BOTH `## DoD Gates` AND (`## Steps (Role Pipeline)` OR `## Steps`) → EPIC format
      - If file contains ANY of (`## High-Level Steps`, `## Approach`, `## Success Criteria`,
        `## Task Order`) AND lacks `## DoD Gates` → Plan format
   d. **Ambiguous:** Ask PM: "This file doesn't match the standard Plan or EPIC format.
      Is this a (P)lan or an (E)PIC?"

3. If EPIC format detected → proceed to Step 1 (no change to existing flow)
4. If Plan format detected → proceed to Step 0.7 (Plan-to-EPIC conversion)
```

### Step 2: Add Plan-to-EPIC Conversion (new Step 0.7)

Insert after Step 0.5:

```markdown
### Step 0.7: Plan-to-EPIC Conversion

When a Plan file is provided instead of an EPIC, auto-generate an EPIC using the
EPIC Subagent Prompt Template from `skills/brainstorming.md`.

1. Read the plan file content (already loaded)
2. Read `skills/brainstorming.md` Section "EPIC Subagent Prompt Template"
3. Read `.aid-o/04-engine/memory/project-profile.yaml` for tech stack context
4. Read `.aid-o/03-config/templates/epic.md` for the EPIC template structure
5. Determine output language:
   - Read `.aid-o/03-config/language.yaml` → `document_language` (default: `EN`)
6. Extract plan_id:
   - From frontmatter `id` field if present (e.g., `P-20260218-v020`)
   - From filename if no frontmatter (e.g., `2026-02-19-aido-v040` → `P-20260219`)
   - Fallback: `P-{YYYYMMDD}-{4char-hash}`
7. Generate EPIC using the EPIC Subagent Prompt Template:
   - Substitute `{plan_content}` with the plan file content
   - Substitute `{project_profile_yaml}` with the project profile
   - Substitute `{epic_template}` with the EPIC template
   - Substitute `{document_language}` with the resolved language
   - Substitute `{plan_id}` with the extracted plan ID
8. Generate EPIC ID: `E-{YYYYMMDD}-{4char-hash}`
9. Generate topic slug from plan title (lowercase, hyphens, max 40 chars)
10. Save EPIC to `.aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md`
11. Present to PM:
    ```
    Input detected as a Plan (not an EPIC).
    ====================================
    Plan: {plan_file_path}
    Generated EPIC: .aid-o/02-epics/E-{id}-{topic}.md

    The EPIC was auto-generated from your plan using the standard template.
    Review it below, then I'll proceed with plan generation.

    [Show EPIC summary: Goal, Scope, Steps count, DoD Gates]

    Proceed with plan generation? (Y/N/Edit)
    ```
12. If PM says Y → proceed to Step 1 with the newly generated EPIC file path
13. If PM says N → stop, tell PM to edit EPIC manually and re-run
14. If PM says Edit → PM modifies sections inline, then proceed to Step 1

IMPORTANT: The generated EPIC is a DRAFT. PM reviews it before plan generation
proceeds. This ensures the Plan-to-EPIC conversion quality is validated.
```

### Step 3: Update Prerequisites and Empty-Args Logic

In `plan-epic.md`:
- Change Prerequisites from "EPIC file must follow the epic template format" to:
  "Input file must be an EPIC (preferred) or a Plan (auto-converted to EPIC)"
- Update empty-args behavior: when args empty, list files from BOTH `.aid-o/02-epics/`
  AND `.aid-o/01-plans/`, marking each as `(EPIC)` or `(Plan)`
- Add `skills/brainstorming.md` to Reference Files section

### Step 4: Update /aid-help documentation

In `commands/aid-help.md`, update the `/plan-epic` entry to show it accepts both formats:

```markdown
### /plan-epic

Parse an EPIC **or Plan** file and generate a Plan JSON + Session file.

**Accepts:**
- EPIC file (`.aid-o/02-epics/E-*.md`) — standard flow
- Plan file (`.aid-o/01-plans/P-*.md` or any plan-format file) — auto-generates EPIC first

**Examples:**
/plan-epic .aid-o/02-epics/E-20260216-c2d1-user-auth.md    # EPIC input
/plan-epic .aid-o/01-plans/2026-02-19-aido-v040.md          # Plan input (auto-converts)
```

### Step 5: Source Plan Enrichment — plan.json `source_plan` Field (Variant B)

**Problem:** plan-epic.md Step 3 (Build Plan JSON) generates plan.json purely from EPIC data. The source plan's implementation detail (code snippets, exact line numbers, sub-step instructions) is lost. plan.json needs a `source_plan` field that the execution chain can follow.

In `plan-epic.md`, modify **Step 3 (Build Plan JSON):**

**Add `source_plan` field to the plan.json structure:**
```json
{
  "epic_id": "{extracted from step 1}",
  "source_plan": "{path to source .md plan file, or null if no plan_ref}",
  "version": 1,
  ...
}
```

**Add logic before plan.json generation:**
```markdown
Before building plan.json, check if the EPIC has a source plan:

1. Read EPIC frontmatter → extract `plan_ref` field
2. If `plan_ref` is set and not null:
   a. Resolve plan file path:
      - If relative: resolve against `.aid-o/01-plans/`
      - If absolute: use as-is
   b. Verify file exists and is readable
   c. Set `source_plan` in plan.json to the resolved path
   d. Read plan file content for enrichment (next step)
3. If `plan_ref` is null or missing:
   a. Set `source_plan: null` in plan.json
   b. Skip enrichment (standard flow)
```

**Add enrichment logic to Step 3 per-step generation:**
```markdown
When building each step in plan.json AND source_plan is available:

For each step S:
  1. Find matching plan task section (by objective keywords or Plan Task ID in objective)
  2. If matched:
     a. Enrich `inputs`: add specific files mentioned in plan task
     b. Enrich `outputs`: add specific files/artifacts from plan task
     c. Enrich `constraints`: add per-task constraints from plan
     d. Enrich `acceptance_criteria`: add verifiable criteria from plan task
  3. If not matched: use EPIC-derived data only (no error)

IMPORTANT: Enrichment is ADDITIVE — EPIC-derived data is the base,
plan task detail supplements it. Never override EPIC constraints with plan data.
```

### Step 6: Source Plan Enrichment — Session Phases (Variant B)

**Problem:** plan-epic.md Step 5 (Session Creation) creates session phases from plan.json steps. Even with enriched plan.json, session phases should directly reference the source plan for Phase Goal expansion.

In `plan-epic.md`, modify **Step 5c (Map Plan JSON to Session Phases):**

**Add after the existing mapping rules:**
```markdown
When creating each Phase AND source_plan is available:

1. Read the matching plan task section
2. Use plan task's detailed description to expand Phase Goal:
   - Instead of just restating the step objective, include WHY this phase
     matters, WHAT specific changes are expected, and KEY decisions from the plan
3. Add to Phase Inputs: "Source plan: {source_plan} (Task {X})"
4. Add to Phase Constraints: any specific implementation constraints from the plan task
   that aren't captured in plan.json (e.g., "never overwrite existing rules — append only")
```

### Step 7: Commit

```bash
git add plugins/aid-orchestrator/commands/plan-epic.md \
       plugins/aid-orchestrator/commands/aid-help.md
git commit -m "feat(plan-epic): accept Plan files + source plan enrichment (Variant B)

/plan-epic now detects whether input is a Plan or EPIC using 3-tier heuristic
(frontmatter → header → section fingerprinting → PM prompt). Plan files are
auto-converted to EPIC using brainstorming.md EPIC Subagent template, saved
to 02-epics/, PM reviews before plan generation proceeds. plan.json gets
source_plan field. Steps enriched from source plan detail. Session phases
enriched with plan task context. Zero detail loss pipeline."
```

---

## Task N: `/aid-brainstorm` — Inline Execution Plan Generation

**Why:** After `/aid-brainstorm` creates a plan (Step 7) and EPIC (Step 8), it hands off to PM with "Next: run /plan-epic then /run-epic". This forces an unnecessary context switch — PM must exit brainstorming and run two more commands. Since the EPIC was just generated (guaranteed valid), we can offer to run the plan-epic flow inline and produce everything in one session.

**Source:** v0.4.0 testing — PM feedback on the brainstorm → plan-epic → run-epic three-command dance.

**Prereq:** Task F (frontmatter) — F adds YAML frontmatter to `aid-brainstorm.md`, must complete before N modifies content. Task D — D updates the EPIC Subagent Prompt Template section in `brainstorming.md` (plan_ref enforcement, step mapping), must complete before N modifies the flow diagram section in the same file.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-brainstorm.md` (add Step 8b, split Step 9)
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` (update Transitioning to Execution flow diagram, lines ~380-392)

### Step 1: Add Step 8b — Execution Plan Option

In `aid-brainstorm.md`, insert between Step 8 and Step 9:

```markdown
### Step 8b: Execution Plan Option

After the EPIC draft is written, offer PM the option to generate the execution plan immediately.

1. Ask PM:
   ```
   EPIC draft written: .aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md

   Would you like to generate the execution plan now?
   (Y) Generate Plan JSON + Session file → ready for /run-epic
   (N) Stop here → review the EPIC draft, then run /plan-epic manually

   Generating now saves a step but skips manual EPIC review.
   ```

2. If PM says N (or skip, later, no):
   → Proceed to Step 9a (standard handoff — no change from current behavior)

3. If PM says Y (or yes, go, generate):
   → Execute the plan-epic flow inline:
   a. Use the EPIC file just written in Step 8 as input
   b. Skip format detection (we know it's a valid EPIC — we just generated it)
   c. Follow `commands/plan-epic.md` Steps 1-6 exactly:
      - Step 1: Load and Validate EPIC
      - Step 2: Analyze Steps, Dependencies, and Parallel Groups
      - Step 2.5: Generate Analysis Groups
      - Step 3: Build Plan JSON
      - Step 4: Save Plan JSON (plan.json + plan_progress.json + epic_input.md)
      - Step 5: Generate Session File
      - Step 6: Present Output
   d. After plan-epic completes → proceed to Step 9b (full pipeline handoff)
```

### Step 2: Split Step 9 into 9a/9b

Replace the existing Step 9 with two variants:

```markdown
### Step 9: Handoff

**9a. Standard Handoff (PM chose N in Step 8b, or Step 8b was skipped):**

[existing Step 9 content — unchanged]

**9b. Full Pipeline Handoff (PM chose Y in Step 8b):**

Present a summary of everything produced:

```
Brainstorming Complete — Full Pipeline Ready
====================================
Topic: {topic}
Plan:    .aid-o/01-plans/P-{id}-{topic}.md
EPIC:    .aid-o/02-epics/E-{id}-{topic}.md
JSON:    .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
Session: .aid-o/04-engine/sessions/S-{id}-{topic}.md

Steps: {count}
Parallel groups: {count}
Roles: {comma-separated list}
Gates: {comma-separated list}

Everything is ready for execution.

Next:
  1. Run /run-epic {epic_id} to start orchestration
  2. Or run /epic-status {epic_id} to review the plan first
```
```

Add `commands/plan-epic.md` and `skills/planner.md` to Reference Files section.

### Step 3: Update Flow Diagram in brainstorming.md

In `skills/brainstorming.md`, replace the "Transitioning to Execution" section (lines ~380-392) with:

```markdown
### Transitioning to Execution

After brainstorming completes, two paths are available:

```
/aid-brainstorm → Plan + EPIC draft
    ├── (Y at Step 8b) Direct pipeline:
    │     EPIC → Plan JSON + Session → ready for /run-epic
    │
    └── (N at Step 8b) Manual review:
          PM reviews EPIC draft → /plan-epic → /run-epic
```

Additionally, `/plan-epic` accepts Plan files directly:

```
PM writes plan in .aid-o/01-plans/
    → /plan-epic → auto-generates EPIC → Plan JSON + Session → /run-epic
```
```

### Step 4: Commit

```bash
git add plugins/aid-orchestrator/commands/aid-brainstorm.md \
       plugins/aid-orchestrator/skills/brainstorming.md
git commit -m "feat(brainstorm): add inline execution plan generation after EPIC creation

After creating Plan (Step 7) and EPIC (Step 8), brainstorm now offers Step 8b:
generate Plan JSON + Session inline. PM can go from idea to /run-epic-ready
in a single brainstorming session. Flow diagram updated."
```

---

## Task O: Execution Chain — Source Plan Integration (Variant B)

**Why:** Task H adds source plan enrichment to the agent dispatch logic in `epic-orchestration.md` (the skill/state machine). But the COMMANDS that invoke this logic — `run-step.md` and `run-epic.md` — also need to know about source plans. Additionally, `plan.schema.json` needs a `source_plan` field so the schema validates plan.json files that include it. Without these changes, the execution chain is incomplete: `epic-orchestration.md` has the logic, but commands and schema don't support it.

**Source:** Variant B audit (2026-02-20) — completing the execution chain.

**Prereq:** Task M (adds `source_plan` field to plan.json) + Task H (adds agent dispatch enrichment logic to epic-orchestration.md)

**Files:**
- Modify: `plugins/aid-orchestrator/commands/run-step.md` (load source plan for agent prompt)
- Modify: `plugins/aid-orchestrator/commands/run-epic.md` (load source plan at startup)
- Modify: `.aid-o/03-config/templates/plan.schema.json` (add `source_plan` field)

### Step 1: Add `source_plan` Field to plan.schema.json

In `.aid-o/03-config/templates/plan.schema.json`, add after `epic_id` field:

```json
"source_plan": {
  "type": ["string", "null"],
  "description": "Path to the source plan .md file (from EPIC plan_ref). Null for standalone EPICs without a source plan. When set, executing agents receive relevant plan sections for implementation detail.",
  "examples": [".aid-o/01-plans/2026-02-19-aido-v040-measurement-optimization.md", null]
}
```

Add `source_plan` to the `required` array if it already includes `epic_id` (make it optional — not in `required`, just defined).

### Step 2: Update run-step.md — Source Plan Loading

In `commands/run-step.md`, modify **Step 3: Dispatch Agent** (around line 64-106):

**Add before the agent prompt construction:**

```markdown
#### Source Plan Loading (Variant B)

Before building the agent prompt:

1. Read plan.json → check `source_plan` field
2. If `source_plan` is set and file exists:
   a. Read the source plan file
   b. Find the matching task section for this step:
      - Parse step.objective for plan task reference (e.g., "(Plan: Task A)")
      - Match section headers against step keywords
   c. Store matched section for prompt enrichment
3. If `source_plan` is null or file missing → skip (backward compatible)
```

**Add to the agent prompt structure (after constraints, before "Execute the step"):**

```markdown
{IF source_plan_section available:}

## Source Plan — Implementation Detail

{source_plan_section_content}

{END IF}
```

### Step 3: Update run-epic.md — Source Plan Loading at Startup

In `commands/run-epic.md`, modify the initialization/startup section:

**Add after loading plan.json (around line 66-68):**

```markdown
#### Source Plan Loading (Variant B)

After loading plan.json:

1. Check plan.json `source_plan` field
2. If set and file exists:
   a. Load source plan into memory for the duration of the run
   b. Log: "Source plan loaded: {source_plan} ({line_count} lines)"
   c. Source plan is passed to epic-orchestration.md EXECUTING state
      for per-step section extraction during agent dispatch
3. If null or missing → log: "No source plan (standalone EPIC)" → continue normally
```

### Step 4: Update Session Template plan_ref Semantics

In `commands/run-epic.md` and `commands/plan-epic.md`, wherever session frontmatter is constructed:

**Change:**
```yaml
plan_ref: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
```

**To:**
```yaml
plan_ref: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
source_plan: {from plan.json source_plan field, or null}
```

This ensures the session file also has a direct reference to the source plan for documentation purposes.

### Step 5: Commit

```bash
git add plugins/aid-orchestrator/commands/run-step.md \
       plugins/aid-orchestrator/commands/run-epic.md \
       .aid-o/03-config/templates/plan.schema.json
git commit -m "feat(execution): source plan integration in run-step + run-epic + schema (Variant B)

Completes the Variant B execution chain: plan.schema.json gets source_plan
field, run-step.md loads source plan section for agent prompt enrichment,
run-epic.md loads source plan at startup for the entire orchestration run.
Backward compatible — standalone EPICs work unchanged."
```
