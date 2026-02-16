Manually run a single step from an existing EPIC plan.

Use this to execute one specific agent step without running the full orchestration loop. Useful for debugging, re-running a failed step, or testing individual agents.

## Usage

```
/run-step <epic-id> <step-id>
/run-step <epic-id> --list          # list available steps
```

**Examples:**
```
/run-step TEST-0001 step_1_architect
/run-step E-20260216-c2d1 step_3_backend
/run-step TEST-0001 --list
```

## Prerequisites

- Plan JSON must exist for the EPIC (run `/plan-epic` first)
- Evidence directory must exist

## Flow

### Step 1: Load Context

1. Find the EPIC's evidence directory: `.aid-o/04-engine/evidence/{epic_id}/`
2. Find the latest `run_id` (most recent subdirectory)
3. Load `plan.json` — find the requested step definition
4. Load `plan_progress.json` — check current state

**If step_id not found:**
```
ERROR: Step "{step_id}" not found in plan for EPIC {epic_id}

Available steps:
  step_1_architect — Design API contracts (done)
  step_2_domain — Define entities (pending)
  step_3_backend — Implement endpoints (pending)
  ...
```

**If `--list` flag:** Show all steps with status and exit.

### Step 2: Dependency Check

1. Find all dependencies for this step in `plan.json` → `dependencies[]`
2. Check `plan_progress.json` — are all dependency steps "done"?
3. If dependencies NOT met:
   ```
   WARNING: Dependencies not met for {step_id}

   Required (not done):
   - step_1_architect (status: pending)
   - step_2_domain (status: pending)

   Run anyway without dependency outputs? (Y/N)
   ```
4. **STOP and wait for response** if dependencies are unmet

### Step 3: Dispatch Agent

1. Read step definition from plan:
   - `role`, `objective`, `inputs`, `outputs`, `constraints`
   - `allowed_paths`, `forbidden_paths`
2. Load playbook: `.aid-o/03-config/playbooks/{role}.md`
3. Load previous step outputs (if dependencies are met):
   - For each dependency: read `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/{dep_step}/output.md`
4. Build agent prompt (same format as `/run-epic` EXECUTING state):
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
   **Inputs:** {step.inputs — include actual content from dependency outputs}
   **Expected Outputs:** {step.outputs}
   **Constraints:** {step.constraints}

   ## Scope
   **Allowed paths:** {step.allowed_paths}
   **Forbidden paths:** {step.forbidden_paths}
   **IMPORTANT:** Do NOT modify files outside allowed paths.

   ## Previous Step Outputs
   {Content from dependency step outputs, if available}

   ## Deliverables
   Produce the following:
   1. Implementation files (within allowed paths)
   2. Output summary (what you did, what you created, decisions made)
   ```
5. Dispatch via Task tool:
   ```
   Task(subagent_type="general-purpose", prompt="{agent prompt}")
   ```
6. Collect output

### Step 4: Save Evidence

1. Save prompt: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/prompts/step_{N}_{role}.md`
2. Save output: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/{step_id}/output.md`
3. Generate diff (if applicable): `.aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/{step_id}/diff.patch`
4. Append to `stage_log.jsonl`

### Step 5: Phase Check

1. Verify outputs:
   - Expected outputs present? (from plan step definition)
   - Scope respected? (only allowed_paths modified)
2. Report result:
   - **PASS:** outputs present, scope OK
   - **SCOPE_VIOLATION:** forbidden paths modified → warn
   - **NO_OUTPUT:** agent produced nothing → warn

### Step 6: Update Progress

1. If check passed: update `plan_progress.json` → set step to "done"
2. If check failed: keep step as "pending", report the issue

### Step 7: Present Result

```
Step Completed: {step_id}
============================
Role: {role}
Status: {pass|scope_violation|no_output}
Objective: {objective}

Outputs:
  - {output_1}
  - {output_2}

Scope check: {OK | VIOLATION: modified {path}}

Evidence:
  .aid-o/04-engine/evidence/{epic_id}/{run_id}/steps/{step_id}/

Plan progress:
  ✅ step_1_architect (done)
  ✅ step_2_domain (done)
  ✅ step_3_backend (done) ← just completed
  ⏳ step_4_frontend (pending — dependencies met: yes)
  ⏳ step_5_qa (pending — dependencies met: no, waiting for step_4)

Next: /run-step {epic_id} {next_available_step}
      or /run-epic {epic_id} to continue full orchestration
```

## Reference Files

- `skills/epic-orchestration.md` — Section "4. EXECUTING" + "5. PHASE_CHECK" (dispatch protocol, scope check)
- `.aid-o/03-config/playbooks/{role}.md` — Agent playbook for the step's role

## Important

- **Does NOT run gates** — this is single-step only. Use `/run-epic` for full pipeline including gates.
- **Does NOT create branches** — operates on the current branch. Branch management is `/run-epic`'s job.
- If the step was already "done" in plan_progress.json → ask: "Step already completed. Re-run? (Y/N)"
- Re-running a step overwrites its evidence (prompt, output, diff)
