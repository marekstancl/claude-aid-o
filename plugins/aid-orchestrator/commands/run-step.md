---
name: run-step
description: Run a single step manually
user_invocable: true
---

Manually run a single step from an existing EPIC plan.

Use this to execute one specific agent step without running the full orchestration loop. Useful for debugging, re-running a failed step, or testing individual agents.

## Usage

```
/run-step <epic-id> <step-id>
/run-step <epic-id> --list                              # list available steps
/run-step <epic-id> --analysis-group <group-id>         # run analysis group manually
```

**Examples:**
```
/run-step TEST-0001 step_1_architect
/run-step E-20260216-c2d1 step_3_backend
/run-step TEST-0001 --list
/run-step TEST-0001 --analysis-group analysis_1_security_review
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
4. **Source Plan Loading (Variant B):**
   - Read plan.json → check `source_plan` field
   - If `source_plan` is set and file exists:
     a. Read the source plan file
     b. Find the matching task section for this step:
        - Parse step.objective for plan task reference (e.g., "(Plan: Task A)")
        - Match section headers against step keywords
     c. Store matched section for prompt enrichment
   - If `source_plan` is null or file missing → skip (backward compatible)
5. Build agent prompt (same format as `/run-epic` EXECUTING state):
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

   {IF source_plan_section available:}
   ## Source Plan — Implementation Detail

   The following is the detailed implementation guide from the source plan.
   Use this as your primary reference for WHAT to change and HOW.
   The step definition above provides the structured constraints (allowed paths,
   acceptance criteria). This section provides the implementation specifics.

   {source_plan_section_content}
   {END IF}

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

## Analysis Group Mode (`--analysis-group`)

> **Reference:** Read `skills/parallel-dispatch.md` Section 2 and `skills/analysis-merge.md`.

When `--analysis-group` is provided, run a multi-perspective analysis instead of a step:

### Flow

1. **Load context:** same as Step 1, but find analysis group by `group-id` in `plan.json.analysis_groups`
2. **Validate target:** check `plan_progress.json` — target step MUST be "done"
   ```
   If target step not "done":
     ERROR: Cannot run analysis — target step "{target}" is not completed yet.
     Status: {status}
     Complete the target step first: /run-step {epic_id} {target}
   ```
3. **Dispatch analysis agents** (per `skills/parallel-dispatch.md` analysis protocol):
   - Load target step output: `evidence/steps/{target}/output.md`
   - Load target step diff: `evidence/steps/{target}/diff.patch`
   - Prepare analysis prompts per agent (mode, strategy, playbook)
   - Dispatch ALL analysis agents in parallel (Task tool)
4. **Merge results** (per `skills/analysis-merge.md`):
   - Apply `merge_strategy` from the analysis group definition
   - Generate `analysis_report`
5. **Save evidence:**
   - Raw outputs: `evidence/analysis/{group_id}/raw_{agent}.yaml`
   - Merged report: `evidence/analysis/{group_id}/analysis_report.yaml`
6. **Present result:**
   ```
   Analysis Complete: {group_id}
   ============================
   Target: {target_step_id} ({target_role})
   Agents: {comma-separated list}
   Mode: {mode}
   Strategy: {merge_strategy}

   Findings: {total_count}
     Critical: {N}  High: {N}  Medium: {N}  Low: {N}  Info: {N}

   Top findings:
     1. [{severity}] {finding} — {agent} ({location})
     2. [{severity}] {finding} — {agent} ({location})
     3. [{severity}] {finding} — {agent} ({location})

   Action items: {count}
   Consensus rate: {N}%  (only for consensus strategy)

   Evidence:
     .aid-o/04-engine/evidence/{epic_id}/{run_id}/analysis/{group_id}/

   Full report: analysis_report.yaml
   ```

**If `--list` with analysis groups present:**
```
Analysis groups:
  analysis_1_security_review → step_3_backend [security] (auto, union)
  analysis_2_db_validation → step_3_backend [backend, security] (auto, consensus)
```

## Reference Files

- `skills/epic-orchestration.md` — Section "4. EXECUTING" + "5. PHASE_CHECK" (dispatch protocol, scope check)
- `skills/parallel-dispatch.md` — Parallel dispatch protocol (branch strategy, analysis dispatch)
- `skills/analysis-merge.md` — Analysis merge strategies (union, consensus, weighted)
- `.aid-o/03-config/playbooks/{role}.md` — Agent playbook for the step's role

## Important

- **Does NOT run gates** — this is single-step only. Use `/run-epic` for full pipeline including gates.
- **Does NOT create branches** — operates on the current branch. Branch management is `/run-epic`'s job.
- **Analysis groups are read-only** — they produce reports, not code changes.
- If the step was already "done" in plan_progress.json → ask: "Step already completed. Re-run? (Y/N)"
- Re-running a step overwrites its evidence (prompt, output, diff)
