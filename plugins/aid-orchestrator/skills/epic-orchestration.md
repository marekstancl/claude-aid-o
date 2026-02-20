# Epic Orchestration — Controller State Machine

**Version:** 0.1.0
**Skill:** epic-orchestration
**Dependencies:** agent-core, quality-gates, session-management

---

## TL;DR

This skill defines the **Controller** that orchestrates an EPIC through its full lifecycle:
EPIC → Plan → Execute Steps → Gates → PM Approval → Done.

The Controller is a state machine. Every transition produces evidence. Failures trigger retry (max 3) then escalation to PM.

---

## State Machine

```
┌──────┐
│ IDLE │
└──┬───┘
   │ receive EPIC
   ▼
┌──────────┐
│ PLANNING │──────────────────────────────────┐
└──┬───────┘                                  │
   │ Plan JSON generated                      │ planning fails
   ▼                                          ▼
┌─────────────┐                          ┌────────────┐
│ PLAN_REVIEW │                          │ ESCALATION │
└──┬──────────┘                          └────────────┘
   │ PM approves plan                         ▲
   ▼                                          │
┌───────────┐                                 │
│ EXECUTING │◄────────────────┐               │
└──┬────────┘                 │               │
   │ step completes           │               │
   ▼                          │               │
┌─────────────┐               │               │
│ PHASE_CHECK │               │               │
└──┬──────┬───┘               │               │
   │      │                   │               │
   │      │ more steps        │               │
   │      └───► NEXT_PHASE ───┘               │
   │                                          │
   │ all steps done                           │
   ▼                                          │
┌───────┐     fail + retries < max            │
│ GATES │────────► GATE_RETRY ────────────────┤
└──┬────┘     fail + retries >= max           │
   │                                          │
   │ all pass                                 │
   ▼                                          │
┌──────────────┐                              │
│ PM_APPROVAL  │                              │
└──┬───────┬───┘                              │
   │       │                                  │
   │       │ rejected                         │
   │       └──────────────────────────────────┘
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
| **EXECUTING** | Dispatch current step's agent (per role playbook); dispatch analysis_groups post-step (per `parallel-dispatch.md`) | Step produces expected outputs; analysis reports generated | `stage_log.jsonl` entry, `diffs/`, `analysis/` |
| **PHASE_CHECK** | Verify step outputs; merge analysis results; check parallel conflicts (per `parallel-dispatch.md`) | Auto-decision per `decision-policies.yaml`; critical analysis findings → ESCALATION | Check result in `stage_log.jsonl` |
| **NEXT_PHASE** | Advance to next step (or next parallel group) | Next step ready | Updated `plan_progress.json` |
| **GATES** | Run all gates from `gates.yaml` | All required gates pass | `gates_report.json` |
| **GATE_RETRY** | Generate fix instructions from gate failure, re-dispatch | Fix applied, re-run gate | Retry entry in `gates_report.json` |
| **ESCALATION** | Send failure to PM via Slack (or chat fallback) with options | PM decides (fix/skip/abort) | `pm_decision.json` |
| **PM_APPROVAL** | Send final results to PM via Slack (or chat fallback) | PM approves merge | `pm_decision.json` |
| **DONE** | Merge branch, archive evidence, run Curator + Auditor, send summaries via Slack, check Epic Queue for auto-pickup | — | `final_report.md`, `audit-report.md`, `curator_report.json`, `slack_log.jsonl` |

---

## Detailed Flow

### 1. IDLE → PLANNING

**Trigger:** `/run-epic <epic-file>` command or Controller receives EPIC path.

**Actions:**
1. Read EPIC file, validate it has required sections (Goal, Scope, Constraints, DoD, Acceptance Criteria)
2. Read `.aid-o/03-config/policies/decision-policies.yaml` for architecture principles
3. Read `.aid-o/03-config/policies/gates.yaml` for gate definitions
4. Read relevant playbooks from `.aid-o/03-config/playbooks/`
5. **Session Branch Creation:**
   a. Check if git is initialized:
      - Run `git rev-parse --is-inside-work-tree` (suppress errors)
      - If not a git repo: skip branch management, log to stage_log:
        `{"state": "IDLE", "warning": "git not initialized — branch management disabled"}`
        Proceed without branching.
   b. If git is available:
      1. Ensure working tree is clean: `git status --porcelain`
         - If dirty: warn PM, suggest committing or stashing first
      2. Create session branch from current HEAD:
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
6. Transition to PLANNING

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
6. Generate session file following Session Creation Protocol (`commands/plan-epic.md` Step 5)
7. Validate session file completeness (see Session File Quality Check below)

**Plan Generation Rules:**
- Architect always runs first (contracts before implementation)
- Domain runs after Architect (needs contracts)
- Backend + Frontend can run in parallel (both depend on contracts)
- QA + Security + Observability can run in parallel (all depend on implementation)
- Docs runs after implementation steps
- Release runs last (needs all gates to pass)

**Session File Quality Check:**
Before transitioning to PLAN_REVIEW, verify the session file passes ALL checks:
- Objective: 3+ sentences with success criteria (not a one-liner)
- Scope: explicit IN (3+ items) and OUT (2+ items) lists
- Phases: each phase has Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance (3+ items)
- Dependencies: table present (or "No inter-phase dependencies" statement)
- Quality Gates: at least one gate listed
If any check fails, fix the session file before proceeding.

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json` + session file

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

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_plan_approval.json`

### 4. EXECUTING

**Permission Context for Agent Dispatch:**

Before dispatching any agent, load the permission context:

1. Read `.aid-o/03-config/policies/permissions.yaml`
2. Resolve `active_preset` to the preset definition
3. Check `role_overrides` for the agent's role
4. Merge: preset.claude_code_permissions + role_override.additional_permissions
5. Include the resolved permissions in the agent's dispatch prompt as a
   PERMISSIONS CONTEXT block:

```
PERMISSIONS CONTEXT:
- Preset: {active_preset}
- Allowed Bash commands: {merged_permissions_list}
- If a command is not in the allowed list, DO NOT execute it.
  Report status: blocked with the command you need.
```

If `permissions.yaml` does not exist or `active_preset` is not set,
default to `recommended` preset behavior.

**Actions:**
1. Determine next step(s) to execute (respect dependency graph)
2. For sequential step:
   a. Create branch: `epic/{epic_id}/step_{N}_{role}` from `epic/{epic_id}/main`
   b. Load role playbook from `.aid-o/03-config/playbooks/{role}.md`
   c. Load source plan detail (Variant B — see **Source Plan Integration** below)
   d. Dispatch agent with context:
      - EPIC specification (relevant sections)
      - Plan step (objective, inputs, outputs, constraints)
      - Source plan implementation detail (if available — see below)
      - Previous step outputs (if dependency)
      - Allowed/forbidden paths
   e. Include cross-project knowledge context (per `skills/memory-mcp.md` Cross-Project Knowledge Protocol):
      - If `memory.cross_project.read_at_executing: true` AND Qdrant available:
        `qdrant-find` query = step objective + role + tech_stack
      - Include top `cross_project.max_results` entries in dispatch prompt
      - If Qdrant unavailable: skip silently (agent works normally)
   e. Agent executes and produces outputs
3. For parallel group (per `skills/parallel-dispatch.md`):
   a. Create branch per agent from `epic/{epic_id}/main` (same base commit)
   b. Add PARALLEL CONTEXT to each prompt (other agents, branch names, scope warning)
   c. Dispatch all agents in the group concurrently (use Task tool with parallel calls)
   d. Collect all outputs
4. Post-step analysis (analysis_groups — per `skills/parallel-dispatch.md` + `skills/analysis-merge.md`):
   a. After step passes PHASE_CHECK, check `plan.analysis_groups` for groups targeting this step
   b. If no analysis groups → skip
   c. If found: dispatch analysis agents (read-only, no branches) in parallel
   d. Collect outputs, apply merge strategy (`skills/analysis-merge.md`)
   e. Generate `analysis_report`, save to `evidence/analysis/`
   f. Critical findings → ESCALATION; high findings → PM warning; others → continue
5. Transition to PHASE_CHECK

**Context Passing Between Steps:**
```
Step N outputs → saved to .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/
Step N+1 inputs → read from .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/
```

Key context to pass:
- Architect → all: API contracts, ADR decisions
- Domain → Backend: entity definitions, invariants
- Backend → QA: endpoint implementations, test fixtures
- Backend → Security: code to review
- All → Docs: what changed and why

**Source Plan Integration (Variant B):**

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

**Evidence:** For each step:
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/output.md`
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}/diff.patch`
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/prompts/step_{N}_prompt.md`
- Entry in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`

### 5. PHASE_CHECK

**Actions:**
1. Verify step produced expected outputs (from plan step definition)
2. Check outputs against `.aid-o/03-config/policies/decision-policies.yaml`:
   - Agent modified only allowed paths? → auto-accept
   - Agent modified forbidden paths? → auto-reject, re-dispatch with warning
   - Outputs match expected artifacts? → auto-accept
   - No output or error? → escalate
3. If parallel group: check all agents in the group, then check for cross-agent conflicts:
   a. Collect all modified files across agents (`skills/parallel-dispatch.md` Section 3-4)
   b. If any file modified by 2+ agents → dry-run merge check
   c. Git merge conflict → ESCALATION with conflict details
   d. Clean merge → record and proceed
4. If analysis results present (from analysis_groups):
   a. Check for critical findings → ESCALATION
   b. Check for high findings → log warning to PM
   c. Merge analysis improvement_notes into step evidence (for Curator)
5. **Acceptance Validation** (per `decision-policies.yaml` → `content_quality`):
   a. Read agent's `output.md` from `evidence/steps/step_{N}_{role}/output.md`
   b. Read step's acceptance criteria from `plan.json` → `steps[N].outputs` + session file acceptance items
   c. For each acceptance criterion, evaluate:
      - Verifiable from output.md + `git diff`? → verify directly
      - Requires domain knowledge beyond Controller's scope? → mark `needs_review`
   d. Decision (per `content_quality` rules):
      - All criteria clearly met → PASS
      - Any `needs_review` AND step matches `review_required_when` → dispatch `code-reviewer` agent
        - Reviewer APPROVED → PASS
        - Reviewer REJECTED (with feedback) → re-dispatch original agent with reviewer feedback
        - Max `max_review_fix_cycles` (default 2) → then ESCALATION
      - Any criterion clearly NOT met → re-dispatch agent with specific feedback (max 2 cycles → ESCALATION)
   e. Evidence: save review to `evidence/{epic_id}/{run_id}/reviews/step_{N}_{role}_review_{cycle}.md`
   f. Update `plan_progress.json`: increment `steps[step_id].review_cycles`, set `steps[step_id].last_review` to review result summary
6. **Discovered Issues Triage** (per `decision-policies.yaml` → `discovered_issues`):
   a. Parse `## DISCOVERED ISSUES` section from agent's `output.md` (if present)
   b. If no section → skip (no issues reported)
   c. For each issue, extract: severity (`[CRITICAL]`/`[HIGH]`/`[MEDIUM]`/`[INFO]`), description, impact, recommendation
   d. Triage per severity:
      - **CRITICAL:** Check `auto_fix_patterns` → match → dispatch fix agent; no match → ESCALATION. Current step BLOCKED.
      - **HIGH:** Log to `evidence/discovered_issues/`. Forward to later step if natural fit, else create `backlog.md` entry. PM Slack notification (informational). NOT blocking.
      - **MEDIUM/INFO:** Log to `evidence/discovered_issues/`. Add to `improvement_notes` (Curator picks up). NOT blocking.
   e. Evidence: save all issues to `evidence/{epic_id}/{run_id}/discovered_issues/step_{N}.md`
   f. Session file: add CRITICAL/HIGH issues to Session Log

#### Diff Generation (after output verification)

For each completed step that modified files:

1. Generate diff:
   - If on a step branch: `git diff main...HEAD > diff.patch`
   - If on main branch: `git diff HEAD~{commit_count}..HEAD > diff.patch`
   - If git not available: skip, log warning
2. Save to evidence: `evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/diff.patch`
3. Record in plan_progress.json:
   ```json
   "step_3_backend": {
     "diff_patch": "evidence/{epic_id}/{run_id}/steps/step_3_backend/diff.patch",
     "files_modified": 15,
     "lines_added": 423,
     "lines_removed": 12
   }
   ```

If the diff is empty (step produced no file changes), record:
```json
"diff_patch": null,
"files_modified": 0
```

#### Per-Agent Metrics Capture (PHASE_CHECK)

For each completed step (sequential or parallel):

1. **Controller-measured metrics:**
   - `completed_at`: timestamp when Task tool returned
   - `duration_seconds`: completed_at - dispatched_at
   - `prompt_size_chars`: length of dispatch prompt
   - `output_size_chars`: length of step output

2. **Agent self-reported metrics:**
   - Parse the `## Execution Summary` block from step output
   - Extract: files_read, files_created, files_modified, bash_commands,
     errors, error_details, complexity, bottleneck
   - If Execution Summary block is missing: log warning, proceed with
     controller-only metrics

3. **Update evidence files:**
   - `dispatch_log.json`: per-agent entry with all metrics
   - `plan_progress.json`: per-step timing + complexity
   - `stage_log.jsonl`: timing summary with bottleneck identification:
     ```json
     {"state": "PHASE_CHECK", "step_id": "step_3_backend", "duration_seconds": 323, "complexity": "high", "bottleneck": "writing integration tests", "errors": 2}
     ```

4. **Qdrant metric write (async, non-blocking):**
   If Qdrant available, store execution metric:
   ```json
   {
     "collection_name": "aid-memory",
     "data": "Agent backend completed step_3 in 323s. Complexity: high. Bottleneck: writing integration tests -- read 4 test files for patterns. Errors: 2 (import fix, timeout retry).",
     "metadata": {
       "type": "metric",
       "metric_kind": "agent_execution",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "step_id": "step_3_backend",
       "role": "backend",
       "duration_seconds": 323,
       "complexity": "high",
       "errors": 2,
       "timestamp": "{ISO 8601}"
     }
   }
   ```

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

### 6. NEXT_PHASE

**Actions:**
1. Update `plan_progress.json`:
   - Set `steps[step_id].status` to "done"
   - Record final `review_cycles` count and timestamp
2. Check dependency graph for next available step(s)
3. If more steps: transition to EXECUTING
4. If all steps done: transition to GATES

### 7. GATES

**Actions:**
1. Read `.aid-o/03-config/policies/gates.yaml`
2. For each required gate:
   a. Run gate command (or check rule)
   b. Record pass/fail + output
3. If ALL required gates pass: transition to PM_APPROVAL
4. If ANY required gate fails: transition to GATE_RETRY

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json`:
```json
{
  "epic_id": "{epic_id}",
  "run_id": "{run_id}",
  "timestamp": "{ISO 8601}",
  "gates": [
    {
      "name": "tests_pass",
      "status": "pass",
      "output": "42 passed in 3.2s",
      "attempt": 1
    },
    {
      "name": "security_scan_pass",
      "status": "fail",
      "output": "1 HIGH finding: hardcoded secret in config.py:42",
      "attempt": 1
    }
  ],
  "overall": "fail",
  "next_action": "gate_retry"
}
```

### 8. GATE_RETRY

**Actions:**
1. Read failed gate details from `gates_report.json`
2. Check retry count against `.aid-o/03-config/policies/gates.yaml` retry.max_attempts
3. If retries remaining:
   a. Analyze failure output
   b. Generate fix instructions (what to change and why)
   c. Dispatch appropriate agent to fix (usually backend or security)
   d. Re-run failed gate
   e. Update `gates_report.json` with retry result
4. If max retries exceeded: transition to ESCALATION

**Retry Logic:**
```
attempt = 1
while gate_fails AND attempt <= max_attempts:
    fix_instructions = analyze_failure(gate_output)
    dispatch_fix_agent(fix_instructions)
    gate_result = run_gate(gate)
    attempt += 1
if gate_fails:
    → ESCALATION
```

### 9. ESCALATION

**Trigger:** Gate failure after max retries, agent error, scope violation, budget exceeded, or ambiguous criteria.

**Communication:** Per `skills/slack-mcp.md` Type A (Escalation).

**Actions:**
1. Build escalation payload with trigger reason, failure details, options, recommendation
2. Send to PM via `send_pm_message("escalation", payload)`:
   - **Slack:** Posts Escalation message with options A/B/C, waits for reply
   - **Chat fallback:** Presents failure context in conversation, waits for response
3. Wait for PM response via `wait_pm_response(message_ref, "escalation")`
4. Execute PM's choice:
   - Fix (`response_type: "fix"`) → return to appropriate state with PM guidance
   - Skip (`response_type: "skip"`) → mark as skipped, continue
   - Abort (`response_type: "abort"`) → transition to DONE (status: aborted)
   - Discussion (`response_type: "discussion"`) → incorporate PM's text, re-present options
   - Timeout → execute `timeout_actions.escalation` from `slack-config.yaml`

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_decision.json`

### 10. PM_APPROVAL

**Communication:** Per `skills/slack-mcp.md` Type C (Merge Approval).

**Actions:**
1. Compile final summary payload (steps, gates, changes, evidence path)
2. Send to PM via `send_pm_message("merge_approval", payload)`:
   - **Slack:** Posts Merge Approval message, waits for reply
   - **Chat fallback:** Presents summary in conversation, waits for response
3. Wait for PM response via `wait_pm_response(message_ref, "merge_approval")`
4. If APPROVE (`response_type: "approve"`): transition to DONE
5. If REJECT (`response_type: "reject"`): transition to ESCALATION (with PM feedback)
6. If REVISE (`response_type: "revise"`): return to EXECUTING with PM's revision instructions
7. If timeout: execute `timeout_actions.merge_approval` from `slack-config.yaml`

### 11. DONE

**Actions:**
1. If approved:
   a. **Session File Status Update** (BEFORE archive — MANDATORY):
      1. Read the active session file from `.aid-o/04-engine/sessions/S-*.md`
      2. Update YAML frontmatter:
         - `status: completed`
         - `completed: {ISO 8601 timestamp}`
      3. Update the `Completion:` line in the body to `100%`
      4. Update the last phase status to `done`
      5. Write the updated session file
      6. THEN proceed with archive (copy to archive/ directory)

      The archived copy MUST reflect the completed status. Never archive a session
      that still shows `status: active`.

   b. **Session Branch Merge** (if git available):
      If a session branch was created (check plan_progress.json -> branch):
      1. Verify all gates passed and PM approved
      2. Switch to base branch: `git checkout {default_branch}`
      3. Merge session branch: `git merge epic/{epic_id} --no-ff -m "feat: complete EPIC {epic_id}"`
      4. If merge conflict: escalate to PM (do NOT auto-resolve)
      5. Delete session branch: `git branch -d epic/{epic_id}`
      6. Log to stage_log:
         `{"state": "DONE", "action": "branch_merged", "branch": "epic/{epic_id}"}`

      If no session branch (git not available): skip this step.

   c. Update EPIC file status to "Completed"
   d. Archive session file to `.aid-o/04-engine/sessions/archive/`
   e. Update `.aid-o/04-engine/memory/active-work.md`
2. Generate final report
3. **POST-PROCESSING (Auditor + Lessons-Extractor):**

   **NOTE:** Curator dispatch has been moved to item 9 (mandatory synchronous step).
   Curator MUST run BEFORE the completion summary so proposal count is available.

   a. Dispatch **Auditor agent** (`agents/auditor.md`) — runs 5 audit types
      (code, security, docs, frontend, database), scores project health,
      tracks trend vs previous audit. Report -> `evidence/{epic_id}/audit-report.md`
   b. Dispatch **Lessons-Extractor agent** (`agents/lessons-extractor.md`) —
      parses all step outputs for lessons, commands, and gotchas.
   c. Auditor summary -> PM via Slack Type F (Audit Summary, no reply)
      - If critical findings match `escalation_triggers` -> additional Type A (Escalation)
   d. Auditor findings -> Orchestrator validates -> Curator processes into backlog (item 9)
4. **Lessons-Learned File Update** (ALWAYS — independent of Qdrant):
   After dispatching lessons-extractor agent, parse its output and append new entries
   to `.aid-o/04-engine/lessons-learned.md`:

   1. Read current `lessons-learned.md`
   2. Parse lessons-extractor output for the "NEW LESSONS" table rows
   3. For each new lesson:
      - Check for duplicates (>80% text overlap with existing entries)
      - If not duplicate: append row to the markdown table
   4. Write updated `lessons-learned.md`

   ```yaml
   # Append format per row:
   | {date} | {lesson_text} | {context_from_epic_id} |
   ```

   This step runs ALWAYS, even if Qdrant indexing succeeded. The .md file is
   the durable, human-readable record. Qdrant is the searchable index.

5. **Command-History File Update** (ALWAYS — independent of Qdrant):
   After dispatching lessons-extractor agent, parse its output and append new entries
   to `.aid-o/04-engine/command-history.md`:

   1. Read current `command-history.md`
   2. Parse lessons-extractor output for the "NEW COMMANDS" table rows
   3. For each new command:
      - Check for duplicates (exact command string match)
      - If not duplicate: append row to the markdown table
   4. Write updated `command-history.md`

   ```yaml
   # Append format per row:
   | {command} | {purpose} | {date} |
   ```

6. **Qdrant Project Tagging** (MANDATORY for all Qdrant writes):
   Every `qdrant-store` call in the DONE state MUST include `project_name` in metadata:

   ```json
   {
     "collection_name": "aid-orchestration-log",
     "data": "{lesson_text}",
     "metadata": {
       "project_name": "{from project-profile.yaml -> project_name}",
       "epic_id": "{epic_id}",
       "step_id": "{step_id}",
       "type": "lesson|command|decision|pattern",
       "category": "{category}",
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   **Why:** Qdrant is the cross-project knowledge store. Without `project_name`,
   lessons from different projects are indistinguishable. Agents reading Qdrant
   at IDLE/EXECUTING states filter by relevance but display source project for
   traceability.

   If Qdrant is unavailable: skip gracefully (non-blocking), log warning.
   File-based writes (steps 4 and 5) are the authoritative record.

7. **EPIC-Level Metrics to Qdrant (DONE state)**

   Aggregate all step metrics into an EPIC summary metric:

   ```json
   {
     "collection_name": "aid-memory",
     "data": "EPIC {epic_id} completed: {step_count} steps, {total_duration}s total, {gate_retries} gate retries. Slowest: {slowest_step} ({slowest_duration}s). Most errors: {most_errors_step}.",
     "metadata": {
       "type": "metric",
       "metric_kind": "epic_summary",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "total_duration_seconds": "{sum of all step durations}",
       "step_count": "{count}",
       "gate_retries": "{count}",
       "slowest_step": "{step_id}",
       "most_errors_step": "{step_id}",
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   Also store gate results as metrics:
   ```json
   {
     "collection_name": "aid-memory",
     "data": "Gate {gate_name} result for EPIC {epic_id}: {passed/failed}, {retries} retries, {duration_seconds}s.",
     "metadata": {
       "type": "metric",
       "metric_kind": "gate_result",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "gate_name": "{gate_name}",
       "passed": true,
       "retries": 0,
       "duration_seconds": 45,
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   **Token Consumption Profile to Qdrant:**

   Record the token consumption profile for cross-project analysis via /aid-analytics:
   ```json
   {
     "collection_name": "aid-memory",
     "data": "EPIC {epic_id} token profile: {total_tokens_estimated} total, {agent_execution_pct}% agent execution, {dispatch_pct}% dispatch, {controller_pct}% controller. Active compute: {active_compute_minutes} min. Models: {models_used}.",
     "metadata": {
       "type": "metric",
       "metric_kind": "token_profile",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "total_tokens_estimated": "{estimated from duration and ops}",
       "agent_execution_pct": "{percentage}",
       "dispatch_pct": "{percentage}",
       "controller_pct": "{percentage}",
       "step_count": "{count}",
       "active_compute_minutes": "{total minutes}",
       "models_used": {"opus": 0, "sonnet": 0, "haiku": 0},
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   Per-step token estimate (stored per step):
   ```json
   {
     "collection_name": "aid-memory",
     "data": "Step {step_id} token profile: model={model}, dispatch={dispatch_prompt_tokens} tokens, execution={estimated_execution_tokens} tokens, {duration_seconds}s, {tool_operations_estimated} tool ops.",
     "metadata": {
       "type": "metric",
       "metric_kind": "step_token_profile",
       "project_name": "{project_name}",
       "epic_id": "{epic_id}",
       "step_id": "{step_id}",
       "model": "{opus|sonnet|haiku}",
       "dispatch_prompt_tokens": "{token count}",
       "estimated_execution_tokens": "{estimated from duration}",
       "duration_seconds": "{seconds}",
       "tool_operations_estimated": "{count}",
       "files_in_scope": "{count}",
       "timestamp": "{ISO 8601}"
     }
   }
   ```

   The Controller estimates execution tokens from:
   - `duration_seconds x ops_per_minute_estimate x avg_tokens_per_op`
   - Where ops_per_minute ~ 3, avg_tokens_per_op ~ 2600 (from BMK-001 baseline)

   This is an ESTIMATE, not exact API billing. The estimate provides useful relative
   comparison across steps and EPICs for optimization decisions.

   If Qdrant unavailable: skip metric writes gracefully, log warning. Continue with
   remaining DONE actions.

8. **Archive Logic** (runs AFTER all file writes, BEFORE final commit):

   1. **Archive session:**
      - Move to `.aid-o/04-engine/sessions/archive/{filename}`
      - Update frontmatter: `status: completed`, `completed: {timestamp}`

   2. **Update EPIC counter:**
      - Increment `sessions_completed += 1` in EPIC frontmatter

   3. **Archive EPIC (conditional):**
      - IF `sessions_completed == sessions_total`:
        - Set `status: completed`, `completed: {timestamp}`
        - Move to `.aid-o/02-epics/archive/{filename}`
      - ELSE: EPIC stays active, log "session {N}/{total} done"

   4. **Update Plan counter (conditional):**
      - IF EPIC archived AND `plan_ref` exists:
        - Increment `epics_completed += 1` in plan frontmatter
        - IF `epics_completed == epics_total`:
          - Set `status: completed`, move to `.aid-o/01-plans/archive/`
        - ELSE: plan stays active, log "plan: {N}/{total} EPICs done"

   5. **Stage log:**
      ```json
      {"state": "DONE", "action": "archive", "session_archived": true,
       "epic_archived": true, "epic_sessions": "2/2",
       "plan_archived": false, "plan_epics": "1/3"}
      ```

   6. **Final commit** (includes all archive moves + all DONE writes):
      `git add -A && git commit -m "done({epic_id}): completed, archived [list]"`

   Archive = MOVE (copy + delete original). Active dirs = only pending work.
   All archive ops happen BEFORE commit -- one clean commit for entire DONE state.

9. **Curator Post-Processing (MANDATORY — synchronous)**

   After generating final_report.md and BEFORE presenting the completion summary:

   1. Dispatch Curator agent with:
      - All step outputs from `evidence/{epic_id}/{run_id}/steps/*/step_output.json`
      - Gate results from `evidence/{epic_id}/{run_id}/gates_report.json`
      - Final report from `evidence/{epic_id}/{run_id}/final_report.md`
   2. Wait for Curator output (do NOT dispatch in background)
   3. Process Curator proposals:
      - Write new proposals to `.aid-o/04-engine/backlog.md`
      - Include proposal count in the completion summary
   4. If Slack is enabled: send each proposal as a Type D message for PM review
   5. If Slack is disabled: list proposals in the completion summary for PM to review

   The Curator runs SYNCHRONOUSLY before the completion summary so that the
   summary can include the proposal count and any high-priority findings.

   Curator dispatch prompt template:
   ```
   You are the Curator agent. Analyze the completed EPIC evidence and produce
   improvement proposals for the backlog.

   EPIC: {epic_id}
   Evidence: {evidence_dir}
   Step count: {step_count}
   Gate retries: {retry_count}
   Duration: {total_duration}

   Read: skills/improvement-proposals.md for proposal format.
   Read: agents/curator.md for your full specification.
   ```

   If Curator fails: log warning, set proposal_count = 0, continue (post-processing
   is best-effort but MUST be attempted).

10. **Completion Summary and Next Steps** (presented to PM — LAST before queue check)

   After all DONE state actions complete, present this summary to PM:

   ```
   EPIC Complete: {epic_id}
   ====================================

   Summary:
     - Steps completed: {completed_count}/{total_count}
     - Gates passed: {passed_gates}/{total_gates} ({retry_count} retries)
     - Duration: {total_duration}
     - Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

   Key outputs:
     {list of main artifacts created -- files, endpoints, components}

   What's next?
     1. Review the code -- run /aid-review or examine the changes manually
     2. Start new work -- run /aid-brainstorm to explore a new idea
     3. Continue building -- run /plan-epic with a new EPIC
     4. Check quality -- run /audit for a project health assessment
     5. Analyze performance -- run /aid-analytics to see bottlenecks and optimization tips
     6. Archive -- the session has been archived to sessions/archive/

   Lessons learned: {count} new entries added to lessons-learned.md
   Backlog proposals: {proposal_count} new entries (review with /aid-backlog)
   ```

   The summary MUST include concrete artifact names (not generic descriptions).
   Read the step outputs to list actual files created/modified.

11. Send Status Update (Type G): `:checkered_flag: EPIC completed — merged to main`
12. **EPIC QUEUE CHECK** (per `skills/epic-queue.md`):
   a. Read `.aid-o/04-engine/epic-queue.yaml`
   b. IF queue is not paused AND next EPIC exists (status: "queued"):
      - Mark current EPIC as "completed" in queue
      - Mark next EPIC as "running"
      - Send Status Update: `:arrows_counterclockwise: Auto-starting next EPIC: {next_epic_id}`
      - Transition: DONE -> IDLE (with next EPIC) — start new orchestration loop
   c. IF queue is paused OR empty:
      - Mark current EPIC as "completed" in queue (if in queue)
      - Send Status Update: `:white_check_mark: Queue empty. Orchestrator idle.`
      - Remain in terminal DONE state
13. **Final Stage Log Entry** (MUST be the LAST action in DONE state):
   Append the closing DONE entry to `stage_log.jsonl`:

   ```json
   {"state": "DONE", "timestamp": "{ISO 8601}", "result": "success", "epic_id": "{epic_id}", "run_id": "{run_id}", "summary": "EPIC completed successfully. {step_count} steps, {gate_count} gates, {retry_count} retries."}
   ```

   This MUST be the last line in the stage log. The `result` field MUST be
   `"success"` (not `"pending"`). If the EPIC was aborted, use `"result": "aborted"`.

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/final_report.md`:
```markdown
# EPIC Run Report: {epic_id}

## Summary
- Status: {completed/aborted}
- Duration: {start} → {end}
- Steps: {completed}/{total}
- Gates: {pass_count}/{total_count}
- Retries: {count}
- Escalations: {count}
- LLM Cost: ${estimated}

## Steps
| # | Role | Status | Duration | Branch |
|---|------|--------|----------|--------|
| 1 | architect | done | ... | epic/{epic_id}/step_1_architect |

## Gate Results
| Gate | Status | Attempts |
|------|--------|----------|
| tests_pass | pass | 1 |

## Evidence
All artifacts stored in: .aid-o/04-engine/evidence/{epic_id}/{run_id}/
```

#### Enriched Report Generation from Qdrant

When generating the `final_report.md`, the orchestrator enriches it with data from Qdrant if available:

```
1. Check Qdrant MCP availability
2. IF Qdrant available:
   a. Query collection "aid-orchestration-log" for all events matching this epic_id
   b. Extract per-step timing data from dispatch_event + completion_event pairs:
      - step_duration = completion.timestamp - dispatch.timestamp
      - total_epic_duration = last_completion.timestamp - first_dispatch.timestamp
   c. Extract retry counts: count dispatch_events where retry_count > 0
   d. Extract strategy usage: which dispatch strategy was used per step
   e. Include in final_report.md:
      - Per-step duration breakdown (table with actual seconds/minutes)
      - Total EPIC wall-clock duration
      - Retry summary (which steps retried, how many times)
      - Dispatch strategy summary (worktrees vs branches vs sequential)
      - Fallback events (if any worktree→branch fallbacks occurred)
3. IF Qdrant unavailable:
   a. Fall back to stage_log.jsonl data (existing behavior)
   b. Extract timing from stage_log.jsonl timestamps (less precise)
   c. Note in report: "Timing data from stage_log.jsonl (Qdrant unavailable)"
```

#### Lessons Learned Collection and Storage

After dispatching Curator and Auditor (step 3 of DONE actions), the orchestrator collects and stores lessons learned:

```
1. COLLECT lessons from all agent outputs:
   a. For each step, read output.md from evidence/steps/step_{N}_{role}/output.md
   b. Parse any "## Lessons Learned" or "## LESSONS LEARNED" section
   c. For each lesson entry, extract:
      - category: "process" | "technical" | "architecture" | "testing" | "security" | "tooling"
      - severity: "info" | "warning" | "critical"
      - description: the lesson text
      - recommendation: suggested action (if present)
      - related_steps: which other steps are affected
      - tags: keywords extracted from the lesson

2. STORE each lesson as a lesson_learned_event:
   {
     "event_type": "lesson_learned",
     "epic_id": "{epic_id}",
     "step_id": "{originating step_id}",
     "timestamp": "{ISO 8601}",
     "role": "{agent role that reported the lesson}",
     "category": "{category}",
     "severity": "{severity}",
     "related_steps": [],
     "tags": [],
     "recommendation": "{text}",
     "context": "{brief context of what the agent was doing}"
   }

3. STORAGE targets (try in order):
   a. If Qdrant MCP available:
      Store each lesson via qdrant-store to collection "aid-orchestration-log"
   b. Always (regardless of Qdrant):
      Append to .aid-o/04-engine/lessons-learned.md (file-based fallback)
      Format: markdown section per lesson with epic_id, step_id, category, text
   c. If Qdrant unavailable:
      Also append to .aid-o/logs/orchestration-events.jsonl (for later rehydration)

4. SUMMARY: Include lessons-learned count in final_report.md
   "Lessons Learned: {count} entries collected ({categories breakdown})"
```

---

## Evidence Store Structure

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
  prompts/                   # All prompts sent to agents
    step_1_architect.md
    step_2_domain.md
    ...
  steps/                     # Step outputs
    step_1_architect/
      output.md
      diff.patch
    step_2_domain/
      output.md
      diff.patch
    ...
  parallel_groups/            # Parallel execution evidence
    group_{N}/
      dispatch_log.json       # Dispatch times, prompts
      merge_log.json          # Merge order, conflict checks
      branch_status.json      # Branch names, base commit
  analysis/                   # Multi-perspective analysis results
    analysis_{N}_{purpose}/
      raw_{agent_role}.yaml   # Raw output from each analysis agent
      analysis_report.yaml    # Merged report (per analysis-merge.md)
      dispatch_log.json       # Analysis dispatch times
  gates/                     # Gate command outputs
    tests_pass.txt
    lint_pass.txt
    security_scan_pass.txt
    ...
```

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

## Agent Dispatch Protocol

### Sequential Step Dispatch

```
1. Load playbook: .aid-o/03-config/playbooks/{role}.md
2. Build prompt:
   - System: playbook content
   - Context: EPIC goal + scope + constraints
   - Task: plan step objective + inputs + outputs
   - Previous outputs: evidence from dependency steps
   - Constraints: allowed_paths, forbidden_paths
3. Dispatch via Task tool (subagent_type matching role or general-purpose)
4. Collect output
5. Save to .aid-o/04-engine/evidence/
```

### Parallel Group Dispatch

> **Reference:** `skills/parallel-dispatch.md` for complete protocol.

```
1. Identify all steps in the parallel group
2. For each step: prepare dispatch (same as sequential) + PARALLEL CONTEXT
3. Create all branches from epic/{epic_id}/main (same base commit)
4. Use single message with multiple Task tool calls
5. Collect all outputs
6. Check for conflicts (git dry-run merge + scope violations)
7. If conflicts: → ESCALATION
8. If no conflicts: merge branches into epic/{epic_id}/main, save evidence
```

#### Worktree-Based Parallel Isolation

Before dispatching a parallel group, the orchestrator reads the dispatch strategy to determine the isolation method for concurrent agents.

**Pre-Dispatch:**

```
1. Read `.aid-o/03-config/policies/dispatch-strategy.yaml`
2. Check `dispatch.strategy` value:
   - "worktrees" → use worktree isolation (preferred for parallel groups)
   - "branches"  → use existing branch-based behavior (above)
   - "sequential" → dispatch steps one at a time (no parallelism)
3. If strategy not set → default to "branches" (backward-compatible)
```

**Worktree Strategy (`dispatch.strategy: "worktrees"`):**

```
1. For each step in the parallel group:
   a. Create worktree:
      git worktree add .aid-o/worktrees/{step_id} epic/{epic_id}/step_{N}_{role}
   b. If creation fails:
      - Check dispatch.fallback.on_worktree_failure → try fallback strategy
      - If fallback is "branches": create branch instead (existing behavior)
      - If fallback is "sequential": queue step for sequential execution
      - If dispatch.fallback.log_fallback: true → log fallback event to stage_log.jsonl
   c. Add worktree_path to agent prompt context:
      - worktree_path: .aid-o/worktrees/{step_id}
      - Agent operates within worktree directory (full filesystem isolation)
2. Respect dispatch.worktrees.max_parallel — if group size exceeds limit,
   split into sub-batches of max_parallel and dispatch sequentially
3. Dispatch all agents concurrently (each in its own worktree)

Post-Dispatch (after parallel group completes and PHASE_CHECK passes):
4. For each worktree in the group:
   a. Merge worktree branch back into epic/{epic_id}/main
   b. If dispatch.worktrees.cleanup_on_merge: true →
      git worktree remove .aid-o/worktrees/{step_id}
5. If any agent failed and dispatch.worktrees.cleanup_on_failure: false →
   preserve worktree for debugging (do NOT remove)
6. Record worktree lifecycle in evidence:
   parallel_groups/group_{N}/worktree_status.json
   { step_id, worktree_path, created_at, merged_at, cleaned_up, fallback_used }
```

**Fallback Chain:**

```
worktrees → (on failure) → branches → (on failure) → sequential
Each fallback is configurable in dispatch-strategy.yaml:
  dispatch.fallback.on_worktree_failure: "branches"
  dispatch.fallback.on_branch_failure: "sequential"
```

### Analysis Group Dispatch

> **Reference:** `skills/parallel-dispatch.md` Section 2 + `skills/analysis-merge.md`

```
Triggered: AFTER target step passes PHASE_CHECK (not during execution)
Key difference: Analysis agents are READ-ONLY — no branches, no code changes

1. Check plan.analysis_groups for groups targeting completed step
2. If found: prepare analysis prompts (step output, diff, mode, strategy)
3. Dispatch all analysis agents in parallel (Task tool)
4. Collect analysis_output YAML from each agent
5. Apply merge strategy (union|consensus|weighted) per analysis-merge.md
6. Generate consolidated analysis_report
7. Save to evidence/analysis/
8. Critical findings → ESCALATION
```

### Branch Management

> **Reference:** `skills/parallel-dispatch.md` Section 1 for complete branch strategy.

```
Base branch:
  epic/{epic_id}/main — created from HEAD of main at EPIC start

Per-step branches:
  epic/{epic_id}/step_{N}_{role}

Merge strategy:
  Sequential steps: branch from epic/{epic_id}/main → merge back after pass
  Parallel steps: all fork from epic/{epic_id}/main → merge one-by-one (by step #) after all pass
  Analysis: NO branches (read-only analysis, reports only)
  Final: PR from epic/{epic_id}/main → main
```

---

## Orchestration Logging

The orchestrator logs structured events to Qdrant (vector memory) for observability, reporting, and lessons-learned analysis. All logging is non-blocking: the orchestrator never waits for Qdrant operations to complete before continuing execution.

### Configuration

```
1. Read `.aid-o/03-config/policies/memory-config.yaml`
2. Check `memory.enabled` — if false, skip all Qdrant logging (use JSONL fallback only)
3. Check Qdrant MCP availability — probe `qdrant-store` tool
4. Collection name: "aid-orchestration-log"
```

### Dispatch Event Logging

On every agent dispatch (sequential or parallel), log a `dispatch_event`:

```json
{
  "event_type": "dispatch",
  "epic_id": "{epic_id}",
  "step_id": "{step_id}",
  "timestamp": "{ISO 8601}",
  "role": "{agent role}",
  "status": "dispatched",
  "strategy": "worktrees|branches|sequential",
  "permission_preset": "{preset name from dispatch-strategy.yaml}",
  "worktree_path": "{path or null}",
  "branch_name": "{branch name or null}",
  "retry_count": 0,
  "context_summary": "{brief description of what agent was asked to do}"
}
```

**How to log:**
- If Qdrant MCP available: use `qdrant-store` tool with collection `aid-orchestration-log`
- If Qdrant unavailable: append JSON line to `.aid-o/logs/orchestration-events.jsonl`

### Completion Event Logging

On every agent completion (success or failure), log a `completion_event`:

```json
{
  "event_type": "completion",
  "epic_id": "{epic_id}",
  "step_id": "{step_id}",
  "timestamp": "{ISO 8601}",
  "role": "{agent role}",
  "status": "success|failure|timeout|scope_violation",
  "duration_seconds": 0,
  "exit_reason": "{null or reason string}",
  "files_changed": ["list", "of", "files"],
  "files_changed_count": 0,
  "error_type": "{null or error classification}",
  "retry_scheduled": false
}
```

### Graceful Degradation

All Qdrant operations are wrapped in try/catch equivalent logic. The orchestrator must never fail or block due to Qdrant unavailability.

```
ON QDRANT OPERATION:
  try:
    execute qdrant-store / qdrant-find
  catch (any error):
    1. Log warning to stage_log.jsonl: "Qdrant unavailable — falling back to JSONL"
    2. Write event to fallback file: .aid-o/logs/orchestration-events.jsonl
    3. Continue execution — do NOT retry synchronously, do NOT block

ON STARTUP (IDLE → PLANNING transition):
  1. Check if .aid-o/logs/orchestration-events.jsonl exists and has entries
  2. If entries found AND Qdrant MCP is available:
     a. Read up to max_retry_batch (default 100) entries from JSONL
     b. Attempt to rehydrate each entry into Qdrant collection "aid-orchestration-log"
     c. On success: remove rehydrated entries from JSONL
     d. On failure: leave entries in JSONL, log warning, continue
  3. Rehydration is best-effort — never block EPIC startup
```

**Fallback file format:** `.aid-o/logs/orchestration-events.jsonl` — one JSON object per line, same schema as Qdrant events. File is append-only during execution; only rehydration removes entries.

---

## Communication Protocol

States PLAN_REVIEW, ESCALATION, and PM_APPROVAL communicate with PM via `skills/slack-mcp.md`.
The DONE state sends Curator proposals (Type D), rejection info (Type E), and audit summaries (Type F).
Status updates (Type G) are sent at key orchestration points (non-blocking, fire-and-forget).

If Slack MCP is not configured (`.aid-o/03-config/policies/slack-config.yaml` missing or
`slack.enabled: false`), all communication falls back to chat-based presentation (pre-Session 6 behavior).

The DONE state checks `.aid-o/04-engine/epic-queue.yaml` (per `skills/epic-queue.md`) and
auto-starts the next queued EPIC if available.

## Configuration References

- **Planner:** `skills/planner.md` — dependency graph, parallel groups, analysis groups generation
- **Parallel dispatch:** `skills/parallel-dispatch.md` — branch strategy, dispatch protocol, conflict detection
- **Analysis merge:** `skills/analysis-merge.md` — merge strategies (union, consensus, weighted)
- **PM communication:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback
- **Epic queue:** `skills/epic-queue.md` — queue management, auto-pickup protocol
- **Gates:** `.aid-o/03-config/policies/gates.yaml`
- **Decision policies:** `.aid-o/03-config/policies/decision-policies.yaml`
- **Slack config:** `.aid-o/03-config/policies/slack-config.yaml`
- **Plan schema:** `.aid-o/03-config/templates/plan.schema.json` (includes `analysis_groups`)
- **EPIC template:** `.aid-o/03-config/templates/epic.md`
- **Playbooks:** `.aid-o/03-config/playbooks/{role}.md`
- **Evidence:** `.aid-o/04-engine/evidence/`
- **Epic queue:** `.aid-o/04-engine/epic-queue.yaml`
- **Sessions:** `.aid-o/04-engine/sessions/`
- **Memory:** `.aid-o/04-engine/memory/active-work.md`
- **Dispatch strategy:** `.aid-o/03-config/policies/dispatch-strategy.yaml`
- **Memory config:** `.aid-o/03-config/policies/memory-config.yaml`
- **Orchestration log (Qdrant):** collection `aid-orchestration-log`
- **Orchestration log (fallback):** `.aid-o/logs/orchestration-events.jsonl`
- **Lessons learned (file):** `.aid-o/04-engine/lessons-learned.md`
- **Cost optimization:** `skills/cost-optimization.md` (model selection, file scoping, dispatch optimization)

---

## Integration with Session Management

The Controller creates and maintains a session file for each EPIC run:

1. **On PLANNING:** Create session file following Session Creation Protocol (`commands/plan-epic.md` Step 5):
   - Read sources: EPIC, Plan JSON, plan file, previous session, source code, decision policies
   - Map plan.json steps → session phases (1:1, with all 6 subsections per phase: Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance)
   - Fill Objective (3+ sentences), Context, Scope (IN/OUT), Dependencies, Quality Gates, Session Log
   - Validate completeness before proceeding to PLAN_REVIEW

2. **On each PHASE_CHECK:** Update session file:
   - Mark completed phase acceptance items as checked/failed based on acceptance validation
   - If review dispatched: log review result (approved/rejected + feedback summary)
   - If discovered issues: log CRITICAL/HIGH issues to Session Log with severity and status
   - Add step status + commit hash to Session Log

3. **On analysis complete:** Log analysis_report summary to Session Log

4. **On GATES:** Update session file:
   - Add gate results to Quality Gates section (pass/fail per gate)
   - Update Session Log

5. **On DONE:** Complete session file:
   - Set `status: completed` in frontmatter
   - Final Session Log entry
   - Archive to completed/

Session file frontmatter:
```yaml
id: S-{YYYYMMDD}-{hash}
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

**Version:** 0.4.0
**Last Updated:** 2026-02-20
