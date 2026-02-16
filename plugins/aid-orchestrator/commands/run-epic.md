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
1. Prepare dispatch for ALL steps in the group (same as sequential, per step)
2. Dispatch all agents in a single message with multiple Task tool calls
3. Collect all outputs

**Evidence per step:**
- Save prompt: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/prompts/step_{N}_{role}.md`
- Save output: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/output.md`
- Generate diff: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/diff.patch`
- Append to `stage_log.jsonl`

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

**Actions:**
1. Read `.aid-o/03-config/policies/gates.yaml`
2. Identify required gates from the plan's `gates` array
3. For each required gate:
   a. If gate has a `command` → execute it (via Bash tool)
   b. If gate has a `rule` → evaluate it manually
   c. Record result: pass/fail + output
4. Generate `gates_report.json`:
   ```json
   {
     "epic_id": "{epic_id}",
     "run_id": "{run_id}",
     "timestamp": "{ISO 8601}",
     "gates": [
       {
         "name": "tests_pass",
         "status": "pass|fail",
         "output": "{command output or evaluation}",
         "attempt": 1
       }
     ],
     "overall": "pass|fail",
     "next_action": "pm_approval|gate_retry"
   }
   ```

**Transition:**
- ALL required gates pass → PM_APPROVAL
- ANY required gate fails → GATE_RETRY

**Evidence:** Save `gates_report.json`, save individual gate outputs to `gates/{gate_name}.txt`.

---

### State: GATE_RETRY

**Actions:**
1. Read failed gates from `gates_report.json`
2. Check retry count against `gates.yaml` → `retry.max_attempts` (default: 3)
3. If retries remaining:
   a. Analyze failure output — determine what needs to be fixed
   b. Generate fix instructions:
      ```
      Gate "{gate_name}" failed (attempt {N}/{max}).
      Error: {gate output}
      Fix: {specific instructions based on failure analysis}
      ```
   c. Dispatch appropriate agent to fix (usually backend or security role)
   d. Re-run ONLY the failed gate
   e. Update `gates_report.json` with retry result
4. If fixed → back to GATES (re-check all)
5. If max retries exceeded → ESCALATION

**Evidence:** Retry entries appended to `gates_report.json`.

---

### State: ESCALATION

**Trigger:** Gate failure after max retries, agent error, scope violation, budget exceeded, ambiguous criteria.

**Actions:**
1. Determine escalation reason and prepare context
2. Present to PM:
   ```
   ESCALATION — {trigger_reason}
   ================================
   EPIC: {epic_id}
   State: {state that caused escalation}
   Details: {failure details}

   Options:
   A) {first option from decision-policies.yaml escalation_triggers}
   B) {second option}
   C) Abort EPIC

   Recommendation: {auto recommendation based on context}
   ```
3. **STOP and wait for PM decision.**

**PM Responses:**
- **Fix** → apply PM's instructions, return to the appropriate state
- **Skip** → mark as skipped in progress, continue to next state
- **Abort** → transition to DONE (status: aborted)

**Evidence:** Save `pm_decision.json`:
```json
{
  "timestamp": "{ISO 8601}",
  "trigger": "{escalation reason}",
  "options_presented": ["A", "B", "C"],
  "pm_decision": "{chosen option}",
  "pm_feedback": "{additional instructions}"
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

```
Per-step branches:
  epic/{epic_id}/step_{N}_{role}

Merge strategy:
  Sequential: each step branch created from previous step's branch
  Parallel: all branches created from last sequential step's branch
  Final: PR from last step branch → main

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
- `defaults/policies/decision-policies.yaml` — auto-decisions, escalation triggers
- `defaults/policies/gates.yaml` — gate definitions, retry config
- `defaults/templates/plan.schema.json` — plan validation

## Important

- **Read `skills/epic-orchestration.md` BEFORE starting the loop** — it is the single source of truth
- **STOP at PM checkpoints** — PLAN_REVIEW, ESCALATION, PM_APPROVAL require human response
- **Auto-decide where possible** — use `decision-policies.yaml` to minimize PM interruptions
- **Evidence is mandatory** — every transition logs to `stage_log.jsonl`
- If resuming an interrupted run: read `plan_progress.json` to find where to continue
- If `$ARGUMENTS` is empty and multiple EPICs exist → list them and ask which to run
