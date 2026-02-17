Run the Controller state machine to orchestrate an EPIC through its full lifecycle: Plan → Execute Steps → Gates → PM Approval → Done.

This is the **main orchestration command** — it implements the entire 11-state Controller from `skills/epic-orchestration.md`. Once started, it runs autonomously, dispatching agents, checking outputs, retrying failures, and only escalating to PM when necessary.

## Usage

```
/run-epic <epic-id-or-path>
/run-epic                      # auto-detect if only one active EPIC
```

**Examples:**
```
/run-epic TEST-0001
/run-epic .aid-o/02-epics/E-20260216-c2d1-user-auth.md
/run-epic                      # picks the only active EPIC
```

## Prerequisites

- `.aid-o/` workspace must exist
- EPIC file must exist in `.aid-o/02-epics/` or at the given path
- Plan JSON should exist (from `/plan-epic`). If not, `/plan-epic` is called automatically.

## Core Instruction

**Read `skills/epic-orchestration.md` FIRST.** It is the authoritative source for the state machine. This command file provides the execution protocol — but the state definitions, evidence formats, and dispatch rules come from that skill.

## State Machine Loop

Implement the following loop. On each state transition, append to `stage_log.jsonl`.

---

### State: IDLE

**Trigger:** Command invocation.

**Actions:**
1. Resolve EPIC file:
   - If path given → use it
   - If epic_id given → search `.aid-o/02-epics/` for matching file
   - If no argument → list EPICs in `.aid-o/02-epics/`, pick if only one, else ask
2. Read and validate EPIC (same validation as `/plan-epic` Step 1)
3. Read `.aid-o/03-config/policies/decision-policies.yaml`
4. Read `.aid-o/03-config/policies/gates.yaml`
5. Find existing Plan JSON (in evidence directory) or generate one:
   - Search `.aid-o/04-engine/evidence/{epic_id}/` for latest `run_id`
   - If plan.json exists → load it
   - If not → run `/plan-epic` logic inline
6. Initialize or load `plan_progress.json`
7. Copy EPIC to evidence (if not already there)

**Evidence:** `epic_input.md` saved to evidence directory.

**Transition:** → PLANNING (if new plan needed) or → PLAN_REVIEW (if plan already exists)

---

### State: PLANNING

**Actions:**
1. If Plan JSON doesn't exist, generate it (same logic as `/plan-epic` Steps 2-4)
2. Validate plan against `.aid-o/03-config/templates/plan.schema.json`
3. Save plan to evidence

**Evidence:** `plan.json` saved.

**Transition:** → PLAN_REVIEW

**On failure:** → ESCALATION ("Plan generation failed: {reason}")

---

### State: PLAN_REVIEW

**Actions:**
1. Present the plan to PM in readable format:
   ```
   EPIC: {title} ({epic_id})
   ====================================
   Steps: {count}
   Parallel groups: {count}
   Roles: {list}
   Budget: ${max_cost}

   Step sequence:
     1. [architect] {objective}
     2. [domain] {objective} (depends on: step 1)
     3. [backend] {objective} ← parallel group 1
     4. [frontend] {objective} ← parallel group 1
     ...

   Gates: {list}

   Proceed? (GO / REVISE / ABORT)
   ```
2. **STOP and wait for PM response.**

**PM Responses:**
- **GO** → save `pm_plan_approval.json`, transition to EXECUTING
- **REVISE** → return to PLANNING with PM feedback, increment plan version
- **ABORT** → transition to DONE (status: aborted)

**Evidence:** `pm_plan_approval.json`:
```json
{
  "epic_id": "{epic_id}",
  "run_id": "{run_id}",
  "timestamp": "{ISO 8601}",
  "decision": "approved|revised|aborted",
  "feedback": "{PM feedback if revised}"
}
```

---

### State: EXECUTING

**Actions:**
1. Read `plan_progress.json` to find next pending step(s)
2. Check dependency graph — only dispatch steps whose dependencies are all "done"
3. Determine if next step(s) form a parallel group

**For a sequential step:**
1. Update `plan_progress.json`: set step status to "running", set `current_step`
2. Create branch: `epic/{epic_id}/step_{N}_{role}`
3. Load playbook: `.aid-o/03-config/playbooks/{role}.md`
4. Build agent prompt:
   ```
   ## Context
   You are the {role} agent working on EPIC {epic_id}.

   ## Your Playbook
   {content of playbooks/{role}.md}

   ## EPIC Goal
   {EPIC goal section}

   ## Your Task
   **Step:** {step.id}
   **Objective:** {step.objective}
   **Inputs:** {step.inputs — include actual content from previous step outputs}
   **Expected Outputs:** {step.outputs}
   **Constraints:** {step.constraints}

   ## Scope
   **Allowed paths:** {step.allowed_paths}
   **Forbidden paths:** {step.forbidden_paths}
   **IMPORTANT:** Do NOT modify files outside allowed paths.

   ## Previous Step Outputs
   {Read and include outputs from dependency steps in evidence/steps/}

   ## Deliverables
   Produce the following:
   1. Implementation files (within allowed paths)
   2. Output summary (what you did, what you created, decisions made)
   ```
5. Dispatch agent using the Task tool:
   ```
   Task(subagent_type="general-purpose", prompt="{agent prompt}")
   ```
6. Collect output

**For a parallel group:**

> **Reference:** Read `skills/parallel-dispatch.md` Section 2 for the complete protocol.

1. Prepare dispatch for ALL steps in the group (same as sequential, per step)
2. Add "PARALLEL CONTEXT" to each agent's prompt (per `skills/parallel-dispatch.md`):
   - List other agents working in parallel
   - Note agent's branch name
   - Emphasize: ONLY modify files in allowed_paths
3. Create all branches from `epic/{epic_id}/main` (same base commit)
4. Dispatch all agents in a single message with multiple Task tool calls
5. Collect all outputs

**For analysis groups (post-step):**

> **Reference:** Read `skills/parallel-dispatch.md` Section 2 and `skills/analysis-merge.md`.

After a step passes PHASE_CHECK, check for pending analysis:

1. Read `plan.analysis_groups` — find entries where `target` == just-completed step ID
2. If none → skip, proceed normally to NEXT_PHASE
3. For each matching analysis_group:
   a. Prepare analysis prompt per agent (per `skills/parallel-dispatch.md` analysis dispatch):
      - Target step output: `evidence/steps/{target}/output.md`
      - Target step diff: `evidence/steps/{target}/diff.patch`
      - Analysis mode and merge strategy context
      - Agent's playbook (relevant analysis sections)
   b. Dispatch ALL analysis agents in single message (parallel Task calls)
   c. Collect outputs — validate each `analysis_output` YAML
   d. Apply merge strategy (per `skills/analysis-merge.md`):
      - `union` → collect all findings, no dedup
      - `consensus` → only findings confirmed by 2+ agents
      - `weighted` → rank by domain expertise weights
   e. Generate `analysis_report` and save to evidence
   f. **Critical findings → ESCALATION** ("Analysis found {N} critical issues. PM must acknowledge.")
   g. **High findings → log warning**, notify PM (non-blocking)
   h. Medium/low/info → proceed normally
4. Continue to NEXT_PHASE

**Evidence per step:**
- Save prompt: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/prompts/step_{N}_{role}.md`
- Save output: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/output.md`
- Generate diff: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/diff.patch`
- Append to `stage_log.jsonl`

**Evidence per analysis group (additional):**
- Raw agent outputs: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/analysis/analysis_{N}_{purpose}/raw_{agent}.yaml`
- Merged report: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/analysis/analysis_{N}_{purpose}/analysis_report.yaml`

**Transition:** → PHASE_CHECK

---

### State: PHASE_CHECK

**Actions:**
1. For each just-completed step, verify:
   - **Outputs present?** Check if expected outputs (from plan) were produced
   - **Scope respected?** Check that only `allowed_paths` were modified (compare with `forbidden_paths`)
   - **No errors?** Agent completed without error
2. Apply auto-decision logic from `decision-policies.yaml`:

| Condition | Action |
|-----------|--------|
| Outputs present AND within scope | → NEXT_PHASE |
| Outputs present AND scope violation | Re-dispatch once with warning, then ESCALATION |
| No outputs OR agent error | → ESCALATION |

3. For parallel groups: check ALL agents in the group before transitioning

**Parallel group additional checks** (per `skills/parallel-dispatch.md` Section 3-4):
1. Collect all modified files across all agents in the parallel group
2. If any file modified by 2+ agents → potential conflict
3. Dry-run merge (by step number order):
   ```
   git checkout epic/{epic_id}/main
   For each step branch (ascending step number):
     git merge --no-commit --no-ff epic/{epic_id}/step_{N}_{role}
     If conflict → git merge --abort → ESCALATION (with conflict details)
     If clean → git merge --abort (was just a test)
   ```
4. If all dry-run merges clean → actually merge branches (same order)
5. Record merge results in `evidence/parallel_groups/group_{N}/merge_log.json`

**Evidence:** Append check result to `stage_log.jsonl`.

**Transition:** → NEXT_PHASE (if pass) or → ESCALATION (if fail)

---

### State: NEXT_PHASE

**Actions:**
1. Update `plan_progress.json`:
   - Mark completed step(s) as "done"
   - Record timestamp and evidence path
2. Check dependency graph for next available step(s):
   - Find steps where ALL dependencies are "done"
   - If multiple independent steps available → they form an ad-hoc parallel group
3. Update session file with step completion

**Transition:**
- If more steps pending → EXECUTING
- If ALL steps done → GATES

---

### State: GATES

> **Reference:** Read `skills/gates-engine.md` for the complete protocol.

**Actions:**
1. Read `skills/gates-engine.md` — follow the Gates Execution Protocol exactly
2. Execute `/run-gates {epic_id}` logic in **non-interactive mode**:
   - Parse `.aid-o/03-config/policies/gates.yaml` (Section 1 of gates-engine.md)
   - Identify required gates; if plan.json specifies a `gates` subset, use only those
   - For each gate: execute per type (command or rule) following Section 2
   - Evaluate `when` conditions for conditional gates
   - Generate `gates_report.json` per Section 3 format (includes attempts array)
   - Store evidence: `gates/{gate_name}.txt` for each executed gate
3. Read `gates_report.json` result and apply next-action logic (Section 3.3):
   - Check `overall` status and per-gate attempt counts
   - Apply auto-decision rules from `decision-policies.yaml`

**Transition:**
- `overall: "pass"` → PM_APPROVAL
- `overall: "fail"` + retries remaining for any failed gate → GATE_RETRY
- `overall: "fail"` + all retries exhausted → ESCALATION

**Evidence:**
- `gates_report.json` — structured report with retry history per gate
- `gates/{gate_name}.txt` — raw output for each executed gate
- Entries in `stage_log.jsonl` for each gate start/complete

---

### State: GATE_RETRY

> **Reference:** Read `skills/retry-engine.md` for the complete protocol.

**Actions:**
1. Read `skills/retry-engine.md` — follow the Retry Decision Protocol (Section 1)
2. For each failed required gate (in `gates.yaml` order):
   a. **Analyze failure** — run Failure Analysis Protocol (Section 2 of retry-engine.md)
      for the specific gate type (tests_pass, lint_pass, security_scan_pass, etc.)
   b. **Dispatch fix agent** — follow Fix Agent Dispatch Protocol (Section 3):
      - Build fix prompt with failure output, analysis, constraints, previous attempts
      - Dispatch `agents/gate-fixer.md` via Task tool
      - Store fix evidence: `gates/retry_{gate_name}_{attempt}.md`
   c. **Re-run failed gate only** — follow Re-run Protocol (Section 4):
      - Verify fix agent made changes (git diff)
      - Re-execute the single failed gate
      - Update `gates_report.json` with new attempt entry
   d. **Evaluate result:**
      - Gate now passes → back to GATES (re-check ALL gates — fix might break others)
      - Gate still fails → increment attempt, check retry count
3. Apply backoff between attempts per gates.yaml config (Section 7 of retry-engine.md)
4. Handle multiple gate failures sequentially (Section 6 of retry-engine.md)

**Transition:**
- Any gate fixed → GATES (full re-check of all gates)
- All retries exhausted for any gate → ESCALATION

**Evidence:**
- `gates/retry_{gate_name}_{attempt}.md` — fix agent output per attempt
- Updated `gates_report.json` — attempts array grows with each retry
- Entries in `stage_log.jsonl` for each fix dispatch and gate re-run

---

### State: ESCALATION

**Trigger:** Gate failure after max retries, agent error, scope violation, budget exceeded, ambiguous criteria.

**Actions:**
1. Determine escalation reason and prepare context
2. **For gate failures** (from GATE_RETRY): follow `skills/retry-engine.md` Section 5 —
   compile full escalation report with all attempt outputs and fix descriptions
3. Present to PM:

   **Gate failure escalation format:**
   ```
   GATE ESCALATION
   ====================================
   EPIC: {epic_id}
   Gate: {gate_name}
   Attempts: {max_attempts}/{max_attempts} exhausted

   Gate command: {command}
   Pass criteria: {pass_criteria}

   Last failure output:
   {last attempt output — truncated to key error}

   Fix attempts:
   1. {attempt 1}: {fix description} → {outcome}
   2. {attempt 2}: {fix description} → {outcome}
   3. {attempt 3}: {fix description} → {outcome}

   Other gates: {N} passed, {M} skipped

   Options:
   A) Skip this gate — proceed with warning (marked skipped_by_pm)
   B) Manual fix — provide guidance, I'll retry (resets attempt counter)
   C) Abort EPIC run

   Recommendation: {based on context}
   ```

   **Non-gate escalation format:**
   ```
   ESCALATION — {trigger_reason}
   ================================
   EPIC: {epic_id}
   State: {state that caused escalation}
   Details: {failure details}

   Options:
   A) {context-specific option}
   B) {context-specific option}
   C) Abort EPIC

   Recommendation: {auto recommendation based on context}
   ```
4. **STOP and wait for PM decision.**

**PM Responses:**
- **Skip (A)** → mark gate as `skipped_by_pm` in gates_report.json, proceed to GATES re-check
- **Manual fix (B)** → reset attempt counter, apply PM guidance, dispatch fix agent, re-run gate
- **Abort (C)** → transition to DONE (status: aborted)
- **Fix (non-gate)** → apply PM's instructions, return to the appropriate state

**Evidence:** Save `pm_decision.json`:
```json
{
  "timestamp": "{ISO 8601}",
  "trigger": "{escalation reason}",
  "gate": "{gate_name or null}",
  "attempts_exhausted": "{count or null}",
  "options_presented": ["skip", "manual_fix", "abort"],
  "pm_decision": "{chosen option}",
  "pm_feedback": "{additional instructions}",
  "pm_reason": "{reason for skip if applicable}"
}
```

---

### State: PM_APPROVAL

**Actions:**
1. Compile final summary:
   ```
   EPIC COMPLETE — Ready for Merge
   ====================================
   EPIC: {title} ({epic_id})
   Steps completed: {N}/{total}
   Steps skipped: {count} (if any)
   Gates: ALL PASS
   Escalations: {count}
   Evidence: .aid-o/04-engine/evidence/{epic_id}/{run_id}/

   Changes:
   - {file count} files changed
   - {commit count} commits
   - Branches: {list}

   Merge to main? (APPROVE / REJECT / REVISE)
   ```
2. **STOP and wait for PM decision.**

**PM Responses:**
- **APPROVE** → transition to DONE
- **REJECT** → transition to ESCALATION (with PM feedback for re-work)
- **REVISE** → return to EXECUTING with PM's specific revision instructions

**Evidence:** Append to `pm_decision.json`.

---

### State: DONE

**Actions:**
1. If status = approved:
   a. Merge step branches (or note for manual PR creation)
   b. Update EPIC file status to "Completed"
   c. Archive session file: move to `.aid-o/04-engine/sessions/archive/`
   d. Update `.aid-o/04-engine/memory/active-work.md`
2. If status = aborted:
   a. Log abort reason
   b. Update EPIC file with abort note
3. Generate `final_report.md`:
   ```markdown
   # EPIC Run Report: {epic_id}

   ## Summary
   - Status: {completed|aborted}
   - Duration: {start} → {end}
   - Steps: {completed}/{total} (skipped: {count})
   - Gates: {pass_count}/{total_count}
   - Retries: {count}
   - Escalations: {count}

   ## Steps
   | # | Role | Status | Evidence |
   |---|------|--------|----------|
   | 1 | architect | done | steps/step_1_architect/ |

   ## Gate Results
   | Gate | Status | Attempts |
   |------|--------|----------|
   | tests_pass | pass | 1 |

   ## Decisions
   {List of PM decisions from escalations}

   ## Evidence
   All artifacts: .aid-o/04-engine/evidence/{epic_id}/{run_id}/
   ```
4. Print completion message

**Evidence:** Save `final_report.md`.

---

## Evidence Logging

Every state transition MUST append a line to `stage_log.jsonl`:

```json
{"timestamp": "{ISO 8601}", "state": "{state_name}", "step": "{step_id or null}", "action": "{what happened}", "details": "{context}", "result": "{pass|fail|pending}"}
```

**Examples:**
```json
{"timestamp": "2026-02-16T10:00:00Z", "state": "IDLE", "step": null, "action": "load_epic", "details": "Loaded EPIC TEST-0001 from .aid-o/02-epics/", "result": "pass"}
{"timestamp": "2026-02-16T10:01:00Z", "state": "EXECUTING", "step": "step_1_architect", "action": "dispatch_agent", "details": "Dispatching architect with health check context", "result": "pending"}
{"timestamp": "2026-02-16T10:05:00Z", "state": "PHASE_CHECK", "step": "step_1_architect", "action": "check_outputs", "details": "Outputs: openapi_spec.yaml, ADR-001.md. Scope: OK", "result": "pass"}
```

## Branch Management

> **Reference:** Read `skills/parallel-dispatch.md` Section 1 for the complete branch strategy.

```
Base branch:
  epic/{epic_id}/main — created at EPIC start from current HEAD of main

Per-step branches:
  epic/{epic_id}/step_{N}_{role}

Merge strategy:
  Sequential: step branch FROM epic/{epic_id}/main → merge back after PHASE_CHECK pass
  Parallel: all branches fork FROM epic/{epic_id}/main (same base) → merge one-by-one (by step number) after all pass
  Analysis: NO branches — analysis agents are read-only (reports only, no code changes)
  Final: epic/{epic_id}/main → PR to project main branch

If git operations fail: log warning, continue without branching
(branching is helpful but not blocking for the orchestration)
```

## Budget Tracking

Track estimated LLM cost throughout the run:
- Each Task tool dispatch ≈ estimate based on prompt size
- If cost exceeds `budget.warn_at_percentage` (80%) → warn PM
- If cost exceeds `budget.max_llm_cost_usd` → ESCALATION

## Reference Files

- **PRIMARY:** `skills/epic-orchestration.md` — state machine definitions, dispatch protocol, evidence formats
- `skills/planner.md` — plan generation: dependency graph, parallel groups, analysis groups
- `skills/parallel-dispatch.md` — branch strategy, parallel dispatch protocol, conflict detection
- `skills/analysis-merge.md` — analysis group merge strategies (union, consensus, weighted)
- `defaults/policies/decision-policies.yaml` — auto-decisions, escalation triggers
- `defaults/policies/gates.yaml` — gate definitions, retry config
- `defaults/templates/plan.schema.json` — plan validation (includes `analysis_groups`)

## Important

- **Read `skills/epic-orchestration.md` BEFORE starting the loop** — it is the single source of truth
- **STOP at PM checkpoints** — PLAN_REVIEW, ESCALATION, PM_APPROVAL require human response
- **Auto-decide where possible** — use `decision-policies.yaml` to minimize PM interruptions
- **Evidence is mandatory** — every transition logs to `stage_log.jsonl`
- If resuming an interrupted run: read `plan_progress.json` to find where to continue
- If `$ARGUMENTS` is empty and multiple EPICs exist → list them and ask which to run
