# Epic State Machine — FSM Core

**Skill:** epic-state-machine
**Dependencies:** epic-orchestration (parent module)

---

## Overview

This module defines the 11-state Finite State Machine (FSM) that drives EPIC orchestration. It contains the state diagram, state definitions, detailed flow for each state (manual-mode behavior), and supporting structures (evidence store, error handling, ID generation).

For auto-mode behavior at each state, **see:** `skills/first-aid-controller.md`
For agent dispatch protocol, **see:** `skills/dispatch-protocol.md`
For quality gates and evaluation, **see:** `skills/gate-evaluation.md`

---

## ID Format

**CANONICAL FORMAT:** `E-{plan_id}-{phase}_{total}`

**Components:**
- `E-` — literal prefix, all EPIC IDs start with this
- `{plan_id}` — 3+ digit plan number without "P" prefix, zero-padded
  (e.g., "015" from P015, "001" from P001)
- `{phase}` — phase number within the plan, 1-indexed integer
- `{total}` — total number of phases/EPICs created from this plan

**Format examples:**
- `E-015-1_2` — Plan P015, phase 1 of 2
- `E-009-1_5` — Plan P009, phase 1 of 5
- `E-001-1_1` — Plan P001, single phase (1 of 1)

**VALIDATION REGEX:** `^E-\d{3,}-\d+_\d+$`

**AD-HOC EPICs** (without a source plan):
- Use ad-hoc counter from counter.yaml
- Format: `E-{ad_hoc_counter}-1_1` (always single phase)
- Example: `E-001-1_1` (first ad-hoc EPIC)

**LEGACY FORMATS** — do NOT generate, read-only for historical evidence:
- `E-YYYYMMDD-NNNN` (timestamp + sequential, pre-v1.0)
- `E-YYYYMMDD-XXXX-slug` (timestamp + hash + description, pre-v1.0)
These formats may appear in old evidence directories (`.aid-o/04-engine/evidence/`).
Do not rename, migrate, or delete them. New EPICs MUST use the canonical format.

**VALIDATION:** Before writing any new EPIC ID to a file (queue, run file, evidence path),
validate against the regex. If validation fails, reject with error:
`"Invalid EPIC ID format: {id}. Expected: E-{plan_id}-{phase}_{total} (e.g., E-015-1_2)"`

---

## State Machine

```
┌──────┐
│ IDLE │
└──┬───┘
   │ receive EPIC
   ▼
┌──────────┐
│ PLANNING │──────────────────────────────┐
└──┬───────┘                              │
   │ Plan JSON generated                  │ planning fails
   ▼                                      ▼
┌─────────────┐                      ┌────────────┐
│ PLAN_REVIEW │                      │ ESCALATION │
└──┬──────────┘                      └────────────┘
   │ PM approves plan                     ▲
   ▼                                      │
┌───────────┐                             │
│ EXECUTING │◄────────────────┐           │
└──┬────────┘                 │           │
   │ step completes           │           │
   ▼                          │           │
┌─────────────┐               │           │
│ PHASE_CHECK │               │           │
└──┬──────┬───┘               │           │
   │      │                   │           │
   │      │ more steps        │           │
   │      └───► NEXT_PHASE ───┘           │
   │                                      │
   │ all steps done                       │
   ▼                                      │
┌───────┐     fail + retries < max        │
│ GATES │────────► GATE_RETRY ────────────┤
└──┬────┘     fail + retries >= max       │
   │                                      │
   │ all pass                             │
   ▼                                      │
┌───────────────────┐                     │
│ CURATOR_RESOLVE   │                     │
└──┬────────────────┘                     │
   │ proposals resolved                   │
   ▼                                      │
┌──────────────┐                          │
│ PM_APPROVAL  │                          │
└──┬───────┬───┘                          │
   │       │                              │
   │       │ rejected                     │
   │       └──────────────────────────────┘
   │ approved
   ▼
┌──────┐
│ DONE │
└──────┘
```

### State Definitions

| State | Entry Action | Exit Condition | Evidence |
|-------|-------------|----------------|----------|
| **IDLE** | Load EPIC file, validate structure | EPIC parsed successfully | `epic_input.md` saved |
| **PLANNING** | Read EPIC → generate Plan JSON per `plan.schema.json` | Valid Plan JSON produced | `plan.json` saved |
| **PLAN_REVIEW** | Send plan to PM via Slack (or chat fallback), show steps + dependencies + parallel groups | PM says GO | `pm_plan_approval.json` |
| **EXECUTING** | Dispatch current step's agent (per role playbook); dispatch analysis_groups post-step (per `parallel-dispatch.md`) | Step produces expected outputs; analysis reports generated | `stage_log.jsonl` entry, step evidence in `steps/step_N_role/` |
| **PHASE_CHECK** | Verify step outputs; merge analysis results; check parallel conflicts (per `parallel-dispatch.md`) | Auto-decision per `decision-policies.yaml`; critical analysis findings → ESCALATION | Check result in `stage_log.jsonl` |
| **NEXT_PHASE** | Advance to next step (or next parallel group) | Next step ready | Updated `plan_progress.json` |
| **GATES** | Run all gates from `gates.yaml` | All required gates pass | `gates_report.json` |
| **GATE_RETRY** | Generate fix instructions from gate failure, re-dispatch | Fix applied, re-run gate | Retry entry in `gates_report.json` |
| **ESCALATION** | Send failure to PM via Slack (or chat fallback) with options | PM decides (fix/skip/abort) | `pm_decision.json` |
| **CURATOR_RESOLVE** | Dispatch Curator + Lessons-Extractor in parallel; auto-evaluate proposals via `decision-policies.yaml` rules + Qdrant history; dispatch fix agents for approved proposals; write lessons to workspace files | All proposals resolved, fixes complete | `curator_resolve_report.json`, updated `backlog.md`, updated `lessons-learned.md` |
| **PM_APPROVAL** | Send final results to PM via Slack (or chat fallback) | PM approves merge | `pm_decision.json` |
| **DONE** | Merge branch, archive evidence, run Auditor, extract example pattern (if eligible), send summaries via Slack, check Epic Queue for auto-pickup | — | `final_report.md`, `audit-report.md`, `slack_log.jsonl` |

### PARALLEL_EXECUTING Sub-State (FIRST AID Only)

`PARALLEL_EXECUTING` is a sub-state of the FIRST AID outer state machine's `QUEUE_PROCESSING` state. It is NOT part of the per-EPIC 11-state FSM above. It activates when the Controller detects two or more independent EPICs in the queue that can execute concurrently in isolated git worktrees.

```
QUEUE_PROCESSING
  ├── (sequential) → execute single EPIC via 11-state FSM → QUEUE_ADVANCE
  └── (parallel)   → PARALLEL_EXECUTING
                        ├── Agent 1: EPIC A (own worktree, full 11-state FSM)
                        ├── Agent 2: EPIC B (own worktree, full 11-state FSM)
                        └── Agent 3: EPIC C (own worktree, full 11-state FSM)
                      → sequential merge to main
                      → QUEUE_ADVANCE
```

**When active:** `auto-mode-state.yaml` shows `session.progress.current_state = "PARALLEL_EXECUTING"` and `session.parallel_execution.active = true`.

**Independence requirement:** EPICs must have non-overlapping file scopes and no declared dependencies. The full independence detection algorithm is defined in `commands/aid-first-aid.md` Section 3.1. The condensed checklist is in `skills/first-aid-controller.md` Section "QUEUE_PROCESSING -- Auto-Mode Behavior".

**Safety limits:** Maximum 3 parallel agents (`MAX_PARALLEL_AGENTS`). Disk space is verified before spawning. Worktrees are cleaned up after completion (mandatory). See `commands/aid-first-aid.md` Section 3.4 for all safety guards.

**Escalation:** Shared escalation budget across all parallel agents. Any escalation pauses ALL agents. See `commands/aid-first-aid.md` Section 3.3.

---

## Detailed Flow

### 1. IDLE → PLANNING

**Trigger:** `/aid-run-epic <epic-file>` command or Controller receives EPIC path.

**Actions:**
1. Read EPIC file, validate it has required sections (Goal, Scope, Constraints, DoD, Acceptance Criteria)
2. Read `.aid-o/03-config/policies/decision-policies.yaml` for architecture principles
3. Read `.aid-o/03-config/policies/gates.yaml` for gate definitions
4. Read relevant playbooks from `.aid-o/03-config/playbooks/`
5. **Memory System Probe** (non-blocking):
   a. Read `.aid-o/03-config/policies/memory-config.yaml`
   b. IF `memory.enabled: true`:
      1. Attempt `qdrant-store` tool availability check (ping/list operation)
      2. IF tool available: log to stage_log:
         `{"state": "IDLE", "action": "memory_probe", "status": "available"}`
      3. IF tool unavailable: log WARNING to stage_log:
         `{"state": "IDLE", "action": "memory_probe", "status": "unavailable", "warning": "Qdrant MCP server not reachable — memory features degraded"}`
         Continue without memory (graceful degradation).
   c. IF `memory.enabled: false`:
      Log to stage_log:
      `{"state": "IDLE", "action": "memory_probe", "status": "disabled"}`
   d. This probe validates Qdrant availability early, before any step attempts
      to store metrics or query cross-project knowledge. Failures are warnings
      only — they never block EPIC execution.
6. **Run Branch Creation:**
   a. Check if git is initialized:
      - Run `git rev-parse --is-inside-work-tree` (suppress errors)
      - If not a git repo: skip branch management, log to stage_log:
        `{"state": "IDLE", "warning": "git not initialized — branch management disabled"}`
        Proceed without branching.
   b. If git is available:
      1. Ensure working tree is clean: `git status --porcelain`
         - If dirty: warn PM, suggest committing or stashing first
      2. Create run branch from current HEAD:
         `git checkout -b epic/{epic_id}`
      3. Log to stage_log:
         `{"state": "IDLE", "action": "branch_created", "branch": "epic/{epic_id}"}`
      4. Record branch in plan_progress.json:
         ```json
         "branch": "epic/{epic_id}",
         "base_commit": "{HEAD sha before branch}"
         ```
   c. All subsequent agent dispatches include in their prompt:
      ```
      GIT CONTEXT:
      - You are on branch: epic/{epic_id}
      - Commit your changes after each meaningful piece of work
      - Use conventional commits: type(scope): description
      - Types: feat, fix, refactor, test, docs, chore
      - Do NOT push to remote
      - Do NOT switch branches
      ```
7. Transition to PLANNING

#### Cross-Project Knowledge Read (IDLE state)

Before generating the plan, search Qdrant for relevant cross-project knowledge:

1. Check `memory-config.yaml` -> `memory.enabled` AND `cross_project.enabled`
2. If both true:
   a. Read `project-profile.yaml` for current project's `tech_stack`
   b. `qdrant-find` with query = "{EPIC goal} {tech_stack_summary}"
   c. Filter: exclude entries where `metadata.project_name == current_project`
   d. Take top `cross_project.max_results` entries (default: 3)
   e. Format as CROSS-PROJECT KNOWLEDGE block:
      ```
      CROSS-PROJECT KNOWLEDGE (from Qdrant):
      - [{source_project}] {lesson/pattern/decision text}
      - [{source_project}] {lesson/pattern/decision text}
      ```
   f. Pass to Planner as additional context
3. If Qdrant unavailable or `cross_project.enabled: false`:
   Skip silently, log to stage_log:
   `{"state": "IDLE", "action": "cross_project_search", "status": "skipped", "reason": "qdrant_unavailable|disabled"}`

**Evidence:** Copy EPIC to `.aid-o/04-engine/evidence/{epic_id}/{run_id}/epic_input.md`

### 2. PLANNING

**Actions:**
1. Analyze EPIC to identify required roles and their sequence
2. Build dependency graph (which steps depend on which)
3. Identify parallel groups (steps that can run concurrently)
4. Generate Plan JSON conforming to `.aid-o/03-config/templates/plan.schema.json`
5. Validate Plan JSON against schema
6. Generate run file following Run Creation Protocol (`commands/aid-plan-epic.md` Step 8)
7. Validate run file completeness (see Run File Quality Check below)

**Plan Generation Rules:**
- Architect always runs first (contracts before implementation)
- Domain runs after Architect (needs contracts)
- Backend + Frontend can run in parallel (both depend on contracts)
- QA + Security + Observability can run in parallel (all depend on implementation)
- Docs runs after implementation steps
- Release runs last (needs all gates to pass)

**Run File Quality Check:**
Before transitioning to PLAN_REVIEW, verify the run file passes ALL checks:
- Objective: 3+ sentences with success criteria (not a one-liner)
- Scope: explicit IN (3+ items) and OUT (2+ items) lists
- Phases: each phase has Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance (3+ items)
- Dependencies: table present (or "No inter-phase dependencies" statement)
- Quality Gates: at least one gate listed
If any check fails, fix the run file before proceeding.

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json` + run file

### 3. PLAN_REVIEW

**Communication:** Per `skills/slack-mcp.md` Type B (Plan Approval).

**Actions:**
1. Format plan summary using the **Rich Plan Summary Template** below
2. Send to PM via `send_pm_message("plan_approval", payload)`:
   - **Slack:** Posts Plan Approval message to configured channel, waits for reply
   - **Chat fallback:** Presents plan in conversation, waits for response
3. Wait for PM response via `wait_pm_response(message_ref, "plan_approval")`
4. If GO: transition to EXECUTING
5. If REVISE: return to PLANNING with PM feedback
6. If ABORT: transition to DONE (status: aborted)
7. If timeout: execute `timeout_actions.plan_approval` from `slack-config.yaml`

**Rich Plan Summary Template:**

Present the plan in this format:

```
PLAN_REVIEW: EPIC {epic_id} — {title}

Overview:
  Steps: {count} ({wave_count} waves, {analysis_group_count} analysis groups)
  Roles: {unique roles}
  Runs: {run_count}
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

Run Breakdown:
  Run 1 (waves 0-2, {N} steps): {goal} — {milestone}
  Run 2 (waves 3-4, {N} steps): {goal} — {milestone}

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

**Per-Step Detail Table:**

After the wave-level summary, present the full per-step detail table. This gives
the PM visibility into exactly what each step will produce before approving.

| # | Role | Objective | Files | Tech | AC | Output | Deps |
|---|------|-----------|-------|------|----|--------|------|
| 1 | architect | Design API schema and ADRs | `api/schema.ts` (new), `docs/adr/ADR-001.md` (new) | TypeScript, Zod, OpenAPI 3.x | 3 | OpenAPI spec + 1 ADR ~150 lines | — |
| 2 | domain | Define entity models and invariants | `src/models/user.ts` (new), `src/models/order.ts` (new) | TypeScript, Zod | 4 | 2 entity model files ~200 lines | 1 |
| 3 | backend | Implement API endpoints | `src/routes/users.ts` (new), `src/routes/orders.ts` (new), `src/middleware/auth.ts` (modify) | Express, Prisma, JWT | 5 | 3 endpoint files ~400 lines | 1, 2 |
| 4 | frontend | Build dashboard pages | `src/pages/Dashboard.tsx` (new), `src/components/OrderList.tsx` (new) | React, TanStack Query | 4 | 2 page components ~300 lines | 1 |
| 5 | qa | Write integration tests | `tests/api/users.test.ts` (new), `tests/api/orders.test.ts` (new) | Vitest, Supertest | 6 | 2 test suites ~250 lines | 3 |

**Required per-step fields:**
- **Files:** list of file paths with `(new)` or `(modify)` annotation — explicit paths, not approximate counts
- **Tech:** frameworks, libraries, and patterns the agent will use for this step
- **AC:** count of acceptance criteria this step validates (from plan.json `acceptance_criteria`)
- **Output:** one-line description of expected deliverable with approximate size
- **Deps:** step numbers this depends on (`—` if none)

**Rules for the per-step detail table:**
- Every step in `plan.json` MUST have a row — no steps may be omitted
- File paths MUST be concrete (e.g., `src/routes/users.ts`), not vague (e.g., "route files")
- The `(new)` / `(modify)` annotation is mandatory for every file listed
- If a step touches more than 5 files, list the 5 most significant and add `+{N} more`
- The AC count MUST match the number of acceptance criteria assigned to that step in `plan.json`
- Dependencies reference step numbers from the `#` column, not wave numbers

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_plan_approval.json`

For PLAN_REVIEW auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "PLAN_REVIEW — Auto-Mode Behavior"

### 4. EXECUTING

The EXECUTING state dispatches agents to perform step work. The detailed dispatch protocol (prompt assembly, role selection, parallel dispatch, wiring steps, source plan integration) is defined in `skills/dispatch-protocol.md`.

**High-Level Actions:**
1. Determine next step(s) to execute (respect dependency graph)
2. For sequential steps: dispatch single agent per `skills/dispatch-protocol.md` Sequential Step Dispatch
3. For parallel groups: dispatch all agents concurrently per `skills/dispatch-protocol.md` Parallel Group Dispatch
4. For wiring steps: dispatch with wiring context per `skills/dispatch-protocol.md` Wiring Step Dispatch
5. Post-step analysis (analysis_groups) per `skills/dispatch-protocol.md` Analysis Group Dispatch
6. Transition to PHASE_CHECK

**Context Passing Between Steps:**
```
Step N outputs → saved to .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/
Step N+1 inputs → read from .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/
```

Key context to pass:
- Architect → all: API contracts, ADR decisions
- Domain → Backend: entity definitions, invariants
- Backend → QA: endpoint implementations, test fixtures
- Backend → Security: code to review
- All → Docs: what changed and why

**Evidence:** For each step (all files in `steps/step_{N}_{role}/`):
- `output.md` — agent output (MANDATORY)
- `prompt.md` — dispatch prompt sent to agent
- `diff.patch` — generated diff of file changes
- `review.md` — review feedback (if review dispatched)
- `gate_result.md` — gate results (if applicable)
- Entry in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`

### 5. PHASE_CHECK

For complete PHASE_CHECK logic (output validation, acceptance validation, discovered issues triage, diff generation, per-agent metrics), **see:** `skills/gate-evaluation.md` Section "PHASE_CHECK".

**Auto-Decision Logic:**
```
outputs_present AND within_scope AND acceptance_met → NEXT_PHASE
outputs_present AND within_scope AND acceptance_unclear → dispatch code-reviewer (if review_required_when)
outputs_present AND acceptance_not_met → re-dispatch agent with feedback (max 2 cycles)
outputs_present AND scope_violation → re-dispatch (max 1 retry)
no_outputs OR error → ESCALATION
parallel_merge_conflict → ESCALATION
analysis_critical_findings → ESCALATION
discovered_issue_CRITICAL → triage (auto-fix or ESCALATION)
discovered_issue_HIGH → log + backlog + PM notification (non-blocking)
review_fix_cycles_exhausted → ESCALATION
```

For PHASE_CHECK auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "PHASE_CHECK — Auto-Mode Behavior"

### 6. NEXT_PHASE

**Actions:**
1. Update `plan_progress.json`:
   - Set `steps[step_id].status` to "done"
   - Record final `review_cycles` count and timestamp
2. Check dependency graph for next available step(s)
3. If more steps: transition to EXECUTING
4. If all steps done: transition to GATES

### 7. GATES

For complete gate evaluation logic, **see:** `skills/gate-evaluation.md` Section "GATES".

### 8. GATE_RETRY

For gate retry logic, **see:** `skills/gate-evaluation.md` Section "GATE_RETRY".

### 9. ESCALATION

For escalation handling, **see:** `skills/gate-evaluation.md` Section "ESCALATION".
For ESCALATION auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "ESCALATION — Auto-Mode Behavior"

### 10. CURATOR_RESOLVE

For full Curator resolution protocol, **see:** `skills/gate-evaluation.md` Section "CURATOR_RESOLVE".
For CURATOR_RESOLVE auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "CURATOR_RESOLVE — Auto-Mode Behavior"

### 11. PM_APPROVAL

For PM approval handling, **see:** `skills/gate-evaluation.md` Section "PM_APPROVAL".
For PM_APPROVAL auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "PM_APPROVAL — Auto-Mode Behavior"

### 12. DONE

For complete DONE state actions (run file update, release sub-phase, branch merge, archive, auditor, metrics, queue check), **see:** `skills/first-aid-controller.md` Section "DONE State".

---

## Evidence Store Structure

All step evidence is stored directly in `steps/step_{N}_{role}/`. There are no separate
top-level subdirectories for prompts, reviews, analysis, or discovered issues.

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  epic_input.md              # Original EPIC
  plan.json                  # Generated plan (includes analysis_groups)
  plan_progress.json         # Step completion tracking
  pm_plan_approval.json      # PM's plan approval
  pm_decision.json           # PM decisions (escalations, final approval)
  stage_log.jsonl            # Structured log of all state transitions
  gates_report.json          # Gate results with retry history
  final_report.md            # Summary report
  steps/                     # All step evidence (flat structure)
    step_1_architect/
      output.md              # Agent output (MANDATORY)
      prompt.md              # Dispatch prompt sent to agent
      diff.patch             # Git diff of changes
      review.md              # Review feedback (if review dispatched)
      gate_result.md         # Gate results (if applicable)
      discovered_issues.md   # Discovered issues (if any reported)
      analysis_{purpose}_raw_{agent}.yaml   # Raw analysis output (if analysis group)
      analysis_{purpose}_report.yaml        # Merged analysis report (if analysis group)
    step_2_domain/
      output.md
      prompt.md
      diff.patch
      ...
    step_3_backend/
      output.md
      prompt.md
      diff.patch
      ...
    parallel_group_{N}_merge_log.json   # Parallel group merge evidence
  gates/                     # Gate command outputs
    tests_pass.txt
    lint_pass.txt
    security_scan_pass.txt
    ...
```

### Step Evidence File Types

| File | Required | Description |
|------|----------|-------------|
| `output.md` | **MANDATORY** | Agent output — must always be written after agent execution |
| `prompt.md` | optional | The dispatch prompt sent to the agent |
| `review.md` | optional | Review feedback from code-reviewer agent |
| `gate_result.md` | optional | Gate check results for this step |
| `diff.patch` | optional | Git diff of changes made by the agent |
| `discovered_issues.md` | optional | Issues discovered by the agent during execution |
| `analysis_*_raw_*.yaml` | optional | Raw output from analysis agents (if analysis group targets this step) |
| `analysis_*_report.yaml` | optional | Merged analysis report (if analysis group targets this step) |

**Rules:**
- No secrets in evidence (redact before saving)
- PII minimized
- Every state transition appends to `stage_log.jsonl`

### stage_log.jsonl Format

Each line is a JSON object:
```json
{"timestamp": "2026-02-15T14:30:00Z", "state": "EXECUTING", "step": "step_1_architect", "action": "dispatch_agent", "details": "Dispatching architect with EPIC context"}
{"timestamp": "2026-02-15T14:32:00Z", "state": "PHASE_CHECK", "step": "step_1_architect", "action": "check_outputs", "details": "Outputs present: openapi_spec.yaml, ADR-001.md", "result": "pass"}
```

---

## Communication Protocol

States PLAN_REVIEW, ESCALATION, and PM_APPROVAL communicate with PM via `skills/slack-mcp.md`.
The DONE state sends audit summaries (Type F). Curator proposals (Type D) and rejection info (Type E) are presented at PM_APPROVAL after CURATOR_RESOLVE.
Status updates (Type G) are sent at key orchestration points (non-blocking, fire-and-forget).

If Slack MCP is not configured (`.aid-o/03-config/policies/slack-config.yaml` missing or
`slack.enabled: false`), all communication falls back to chat-based presentation (pre-Run 6 behavior).

The DONE state checks `.aid-o/04-engine/epic-queue.yaml` (per `skills/epic-queue.md`) and
auto-starts the next queued EPIC if available.

---

## Integration with Run Management

The Controller creates and maintains a run file for each EPIC run:

1. **On PLANNING:** Create run file following Run Creation Protocol (`commands/aid-plan-epic.md` Step 8):
   - Read sources: EPIC, Plan JSON, plan file, previous run, source code, decision policies
   - Map plan.json steps → run phases (1:1, with all 6 subsections per phase: Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
   - Fill Objective (3+ sentences), Context, Scope (IN/OUT), Dependencies, Quality Gates, Run Log
   - Validate completeness before proceeding to PLAN_REVIEW

2. **On each PHASE_CHECK:** Update run file:
   - Mark completed phase acceptance items as checked/failed based on acceptance validation
   - If review dispatched: log review result (approved/rejected + feedback summary)
   - If discovered issues: log CRITICAL/HIGH issues to Run Log with severity and status
   - Add step status + commit hash to Run Log

3. **On analysis complete:** Log analysis_report summary to Run Log

4. **On GATES:** Update run file:
   - Add gate results to Quality Gates section (pass/fail per gate)
   - Update Run Log

5. **On DONE:** Complete run file:
   - Set `status: completed` in frontmatter
   - Final Run Log entry
   - Archive to completed/

Run file frontmatter:
```yaml
id: R-{EPIC_ID}-{run_number}
type: new-feature
status: active
epic_id: {epic_id}
plan_ref: .aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json
orchestrated: true  # marks this as Controller-managed
```

---

## Error Handling Summary

| Error | State | Action |
|-------|-------|--------|
| EPIC file invalid | IDLE | Report error, stay IDLE |
| Plan generation fails | PLANNING | Retry once, then ESCALATION |
| PM rejects plan | PLAN_REVIEW | Return to PLANNING with feedback |
| Agent produces no output | EXECUTING | ESCALATION |
| Agent modifies forbidden paths | PHASE_CHECK | Auto-reject, re-dispatch once |
| Gate fails, retries left | GATES | GATE_RETRY |
| Gate fails, no retries | GATE_RETRY | ESCALATION |
| Budget exceeded | Any | ESCALATION |
| Conflicting parallel outputs | PHASE_CHECK | ESCALATION |
| Git merge conflict in parallel | PHASE_CHECK | ESCALATION with conflict details |
| Analysis critical findings | PHASE_CHECK | ESCALATION (PM must acknowledge) |
| Analysis agent failure | EXECUTING | Skip agent, log warning, proceed |
| PM rejects final | PM_APPROVAL | ESCALATION with feedback |

---

## ID Generation

This section defines the ID format specification and generation protocol for all AID entities. IDs are deterministic, sequential, and encode parent-child relationships.

### ID Format Specification

| Entity | Format | Example | Description |
|--------|--------|---------|-------------|
| Plan | `P{NNN}` | P001, P002 | Zero-padded 3-digit from `plan` counter |
| EPIC from plan | `E-{NNN}-{phase}_{total}` | E-001-1_3 | Plan number + phase X of Y total phases |
| Ad-hoc EPIC (no plan) | `E-{NNN}` | E-001, E-002 | Standalone sequential from `epic` counter |
| Single-phase EPIC | `E-{NNN}-1_1` | E-001-1_1 | Plan number + "1 of 1" phase notation |
| Run | `R-{EPIC_ID}-{run_number}` | R-001-1_3-1 | EPIC ID + sequential run number |

Where `NNN` = zero-padded 3-digit number from `.aid-o/03-config/counter.yaml`.

### Counter File

Location: `.aid-o/03-config/counter.yaml`

The counter file tracks the last-assigned sequential ID for each entity type. Initial values are `0`, meaning the next entity created gets ID `1` (formatted as `001`).

```yaml
plan: 0       # Last assigned plan number. Next: P001
epic: 0       # Last assigned ad-hoc EPIC number. Next: E-001
```

Notes:
- Plan-linked EPICs derive their number from the `plan` counter + phase info, so they do not need a separate counter.
- Runs derive their number from the EPIC (sequential within that EPIC), so no separate counter is needed.
- This is a single-user tool; no concurrency control is required.

### ID Generation Protocol

1. Read `.aid-o/03-config/counter.yaml`
2. Increment the appropriate counter by 1
3. Write updated counter back to file
4. Use the new value to construct the ID

**When to generate each ID type:**

| ID Type | Generated During | Trigger |
|---------|-----------------|---------|
| Plan ID (`P{NNN}`) | `/aid-plan-epic` (PLANNING state) or `/aid-brainstorm` | New plan creation |
| EPIC ID (from plan) | EPIC creation from a plan | Plan approved, EPICs generated |
| EPIC ID (ad-hoc) | Ad-hoc EPIC creation (no parent plan) | `/aid-run-epic` with standalone EPIC |
| Run ID | `/aid-run-epic` (IDLE state) | New run of an existing EPIC |

### Relationship Encoding

The ID scheme encodes parent-child relationships directly in the identifier:

- **Plan number in EPIC ID** links the EPIC to its parent plan. `E-001-2_3` belongs to plan `P001`.
- **EPIC ID in Run ID** links the run to its parent EPIC. `R-001-1_3-1` is a run of EPIC `E-001-1_3`.
- **Ad-hoc EPICs** (created without a plan) get a standalone sequential number from the `epic` counter. They have no plan linkage.
- **Phase notation** (`{phase}_{total}`) encodes "phase X of Y total phases" from the parent plan.

### Examples

```
Plan P001 has 3 EPICs:
  E-001-1_3  (phase 1 of 3)
  E-001-2_3  (phase 2 of 3)
  E-001-3_3  (phase 3 of 3)

Each EPIC can have multiple runs:
  R-001-1_3-1  (first run of E-001-1_3)
  R-001-1_3-2  (second run, if first failed/was aborted)

Ad-hoc EPIC (no plan):
  E-002        (standalone, epic counter incremented)

Single-phase plan:
  P002 -> E-002-1_1 -> R-002-1_1-1
```

### Migration Note

Old IDs (format: `X-YYYYMMDD-XXXX`) will be mapped to new IDs during step 8 of the refactoring plan. The `counter.yaml` initial values (`0`) assume migration will set them to the correct starting point after accounting for existing entities.

---

**Last Updated:** 2026-02-28
