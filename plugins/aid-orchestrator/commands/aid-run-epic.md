---
name: aid-run-epic
description: Execute full EPIC orchestration pipeline
user_invocable: true
---

Run the Controller state machine to orchestrate an EPIC through its full lifecycle: Plan → Execute Steps → Gates → PM Approval → Done.

This is the **main orchestration command** — it implements the entire 11-state Controller from `skills/epic-orchestration.md`. Once started, it runs autonomously, dispatching agents, checking outputs, retrying failures, and only escalating to PM when necessary.

## Usage

```
/aid-run-epic <epic-id-or-path>
/aid-run-epic                      # auto-detect if only one active EPIC
```

**Examples:**
```
/aid-run-epic TEST-0001
/aid-run-epic .aid-o/02-epics/E-20260216-c2d1-user-auth.md
/aid-run-epic                      # picks the only active EPIC
```

## Prerequisites

- `.aid-o/` workspace must exist
- EPIC file must exist in `.aid-o/02-epics/` or at the given path
- Plan JSON should exist (from `/aid-plan-epic`). If not, `/aid-plan-epic` is called automatically.

## Core Instruction

**Read `skills/epic-orchestration.md` FIRST.** It is the authoritative source for the state machine. This command file provides the execution protocol — but the state definitions, evidence formats, and dispatch rules come from that skill.

**Read `skills/slack-mcp.md` for PM communication.** All PM-facing messages (plan review, escalation, merge approval) use the Slack MCP protocol with chat fallback.

## PM Communication Protocol

All PM communication uses the abstraction from `skills/slack-mcp.md`:

1. **`resolve_pm_channel()`** — reads `.aid-o/03-config/policies/slack-config.yaml`,
   returns `{ mode: "slack", config }` or `{ mode: "chat" }`.
2. **`send_pm_message(type, payload)`** — formats and sends message via Slack MCP
   (or presents in chat if fallback).
3. **`wait_pm_response(message_ref, timeout_type)`** — waits for PM reply via Slack
   (or chat). Handles timeouts with configurable default actions.

On first use in a run, call `resolve_pm_channel()` once and cache the result.
If Slack is configured, also send a Type G Status Update: `:rocket: EPIC started`.

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
2. Read and validate EPIC (same validation as `/aid-plan-epic` Step 3)
3. Read `.aid-o/03-config/policies/decision-policies.yaml`
4. Read `.aid-o/03-config/policies/gates.yaml`
5. **Create evidence directory:** `mkdir -p .aid-o/04-engine/evidence/{epic_id}/{run_id}/`
   (also create subdirectories: `steps/`, `prompts/`, `gates/`, `analysis/`, `discovered_issues/`, `reviews/`, `parallel_groups/`)
6. Find existing Plan JSON (in evidence directory) or generate one:
   - Search `.aid-o/04-engine/evidence/{epic_id}/` for latest `run_id` (most recent by directory name — run IDs use ISO timestamp prefix)
   - If plan.json exists → load it
   - If not → run `/aid-plan-epic` logic inline
7. Initialize or load `plan_progress.json`
8. Copy EPIC to evidence (if not already there)
9. **Source Plan Loading (Variant B):**
   - Check plan.json `source_plan` field
   - If set and file exists:
     a. Load source plan into memory for the duration of the run
     b. Log: "Source plan loaded: {source_plan} ({line_count} lines)"
     c. Source plan is passed to epic-orchestration.md EXECUTING state
        for per-step section extraction during agent dispatch
   - If null or missing → log: "No source plan (standalone EPIC)" → continue normally

**Evidence:** `epic_input.md` saved to evidence directory.

**Transition:** → PLANNING (if new plan needed) or → PLAN_REVIEW (if plan already exists)

---

### State: PLANNING

**Actions:**
1. If Plan JSON doesn't exist, generate it (same logic as `/aid-plan-epic` Steps 4-7)
2. Validate plan against `.aid-o/03-config/templates/plan.schema.json`
3. Save plan to evidence
4. **Generate session file** following Session Creation Protocol (`commands/aid-plan-epic.md` Step 8)
5. **Validate session file** completeness (per `skills/epic-orchestration.md` Session File Quality Check):
   - Objective: 3+ sentences with success criteria
   - Scope: explicit IN (3+) and OUT (2+) lists
   - Phases: each has Goal, Agent/Role, Inputs, Outputs, Constraints, Acceptance (3+)
   - Dependencies table present
   - Quality Gates listed
   - If any check fails → fix before proceeding

**Evidence:** `plan.json` + session file saved.

**Transition:** → PLAN_REVIEW

**On failure:** → ESCALATION ("Plan generation failed: {reason}")

---

### State: PLAN_REVIEW

**Actions:**
1. Format plan summary (per `skills/slack-mcp.md` Type B — Plan Approval):
   ```
   EPIC: {title} ({epic_id})
   Steps: {count} ({parallel_groups} parallel groups, {analysis_groups} analysis groups)
   Roles: {list}
   Budget: ${max_cost}

   Step sequence:
     1. [architect] {objective}
     2. [domain] {objective} (depends on: step 1)
     3. [backend] {objective} ← parallel group 1
     4. [frontend] {objective} ← parallel group 1
     ...

   Gates: {list}
   ```
2. Send via PM Communication Protocol:
   ```
   message_ref = send_pm_message("plan_approval", {
     epic_id, epic_title, total_steps, parallel_groups,
     analysis_groups, agent_roles, step_summary, run_id
   })
   ```
3. Wait for PM response:
   ```
   response = wait_pm_response(message_ref, "plan_approval")
   ```
4. **If Slack:** Orchestrator continues when PM responds in Slack.
   **If chat:** STOP and wait for PM response in conversation.

**PM Responses:**
- **GO** (`response_type: "go"`) → save `pm_plan_approval.json`, transition to EXECUTING
- **REVISE** (`response_type: "revise"`) → return to PLANNING with PM feedback (`response.feedback`), increment plan version
- **ABORT** (`response_type: "abort"`) → transition to DONE (status: aborted)
- **Timeout** (`response.auto: true`) → execute `timeout_actions.plan_approval` from config

**Evidence:** `pm_plan_approval.json`:
```json
{
  "epic_id": "{epic_id}",
  "run_id": "{run_id}",
  "timestamp": "{ISO 8601}",
  "decision": "approved|revised|aborted",
  "feedback": "{PM feedback if revised}",
  "channel": "slack|chat",
  "latency_minutes": {N}
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
   - If playbook not found: ESCALATION ("Missing playbook for role '{role}'. Run /aid-init or create `.aid-o/03-config/playbooks/{role}.md`")
4. **Memory context retrieval** (per `skills/memory-mcp.md` → `memory_context_for_step()`):
   - Read `.aid-o/03-config/policies/memory-config.yaml`
   - IF `memory.enabled` AND `memory.search.pre_step_search`:
     - `qdrant-find(query=step.objective, collection_name=config.collection_name)`
     - Filter by `min_score`, limit to `top_k`
     - Format as `## MEMORY CONTEXT (from past sessions)` block
   - IF disabled or unavailable → skip (empty string), proceed normally
5. Build agent prompt:
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

   {IF memory_context is not empty:}
   ## MEMORY CONTEXT (from past sessions)
   _The following knowledge was retrieved from past sessions via vector memory.
   Use as reference — do not blindly follow if project context has changed._

   {memory_context from step 4}
   {END IF}

   ## Deliverables
   Produce the following:
   1. Implementation files (within allowed paths)
   2. Output summary (what you did, what you created, decisions made)
   3. (Optional) If you discover problems outside your task scope, add a `## DISCOVERED ISSUES` section:
      - Format: `- **[SEVERITY]** Description` where SEVERITY is CRITICAL/HIGH/MEDIUM/INFO
      - Each issue needs: `- Impact:` and `- Recommendation:` sub-bullets
      - CRITICAL = blocks further work. HIGH = should be addressed. MEDIUM/INFO = nice to know.
      - Only report genuine issues — do not pad this section.
   ```

**Re-dispatch prompt (when acceptance validation fails or reviewer rejects):**

If PHASE_CHECK determines the step must be re-dispatched (acceptance not met or reviewer rejected), use this extended prompt instead of the base prompt:

   ```
   ## Context
   You are the {role} agent working on EPIC {epic_id}.
   **THIS IS A RE-DISPATCH.** Your previous output did not meet acceptance criteria.

   ## Your Playbook
   {content of playbooks/{role}.md}

   ## EPIC Goal
   {EPIC goal section}

   ## Your Task
   **Step:** {step.id}
   **Objective:** {step.objective}
   **Inputs:** {step.inputs}
   **Expected Outputs:** {step.outputs}
   **Constraints:** {step.constraints}

   ## Scope
   **Allowed paths:** {step.allowed_paths}
   **Forbidden paths:** {step.forbidden_paths}
   **IMPORTANT:** Do NOT modify files outside allowed paths.

   ## Previous Step Outputs
   {Read and include outputs from dependency steps in evidence/steps/}

   ## Feedback from Previous Attempt
   **Attempt:** {cycle_number} of {max_review_fix_cycles}
   **Reason for re-dispatch:** {acceptance_not_met | reviewer_rejected}

   ### What went wrong:
   {If acceptance_not_met: list specific criteria that were NOT met, with evidence}
   {If reviewer_rejected: include full reviewer feedback from review evidence file}

   ### Previous attempts:
   {For cycle > 1:}
   - Attempt 1: {summary of what agent did} → {why it was rejected}
   - Attempt 2: {summary} → {outcome}

   ## Deliverables
   Produce the following:
   1. **Fix the specific issues listed above** — address each piece of feedback
   2. Output summary (what you changed, how you addressed each issue)
   3. (Optional) `## DISCOVERED ISSUES` section (same format as base prompt)

   **IMPORTANT:** Focus on fixing the identified issues. Do not redo work that was already accepted.
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
| Acceptance criteria met (verified from output.md) | → NEXT_PHASE |
| Acceptance unclear, review_required_when matches | Dispatch code-reviewer, then re-check |
| Acceptance clearly NOT met | Re-dispatch agent with feedback (max 2 cycles), then ESCALATION |
| CRITICAL discovered issue reported | Triage: auto-fix or ESCALATION (step blocked) |
| HIGH discovered issue reported | Log to backlog + PM Slack notification (non-blocking) |

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

4. **Acceptance Validation** (per `decision-policies.yaml` → `content_quality`):
   - Read agent's `output.md` from evidence
   - Compare against step acceptance criteria from plan.json
   - Auto-accept: simple roles (docs, config, release), ≤3 criteria, all verifiable
   - Review required: complex roles (architect, backend, frontend, security), 5+ criteria, unclear items
   - If review needed: dispatch `code-reviewer` agent with output.md + plan criteria + git diff
   - Review result: APPROVED → proceed; REJECTED → re-dispatch original agent with feedback
   - Max 2 review-fix cycles, then ESCALATION

5. **Discovered Issues Triage** (per `decision-policies.yaml` → `discovered_issues`):
   - Parse `## DISCOVERED ISSUES` from agent's output.md
   - CRITICAL → check auto_fix_patterns → dispatch fix agent or ESCALATION (step blocked)
   - HIGH → log to evidence + backlog.md + PM Slack (non-blocking)
   - MEDIUM/INFO → log to evidence + improvement_notes (non-blocking)
   - Evidence: `evidence/{epic_id}/{run_id}/discovered_issues/step_{N}.md`

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
2. Execute gates engine logic (per `skills/gates-engine.md`) in **non-interactive mode**:
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
- `overall: "pass"` → CURATOR_RESOLVE
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
3. Build escalation payload:

   **Gate failure payload:**
   ```
   trigger_reason: "Gate failure: {gate_name} — {max_attempts} attempts exhausted"
   failure_details: |
     Gate: {gate_name}
     Command: {command}
     Pass criteria: {pass_criteria}
     Last failure: {last attempt output — truncated to key error}
     Fix attempts:
     1. {attempt 1}: {fix description} → {outcome}
     2. {attempt 2}: {fix description} → {outcome}
     3. {attempt 3}: {fix description} → {outcome}
     Other gates: {N} passed, {M} skipped
   fix_option: "Skip this gate — proceed with warning (marked skipped_by_pm)"
   skip_option: "Manual fix — provide guidance, I'll retry (resets attempt counter)"
   recommendation: "{based on context}"
   ```

   **Non-gate escalation payload:**
   ```
   trigger_reason: "{trigger_reason}"
   failure_details: "{failure details — max 500 chars}"
   fix_option: "{context-specific fix option}"
   skip_option: "{context-specific skip option}"
   recommendation: "{auto recommendation}"
   ```

4. Send via PM Communication Protocol (per `skills/slack-mcp.md` Type A — Escalation):
   ```
   message_ref = send_pm_message("escalation", {
     epic_id, epic_title, current_state,
     trigger_reason, failure_details,
     fix_option, skip_option, recommendation
   })
   response = wait_pm_response(message_ref, "escalation")
   ```
5. **If Slack:** Orchestrator continues when PM responds in Slack.
   **If chat:** STOP and wait for PM decision in conversation.

**PM Responses:**
- **Fix (A)** (`response_type: "fix"`) → apply PM guidance (if `discussion` response, use PM's thread text), return to appropriate state
- **Skip (B)** (`response_type: "skip"`) → mark gate as `skipped_by_pm` in gates_report.json, proceed to GATES re-check
- **Abort (C)** (`response_type: "abort"`) → transition to DONE (status: aborted)
- **Discussion** (`response_type: "discussion"`) → include PM's thread text as context, re-present options (max 3 discussion rounds; after 3 rounds treat as "abort" with PM notification)
- **Timeout** (`response.auto: true`) → execute `timeout_actions.escalation` from config

**Evidence:** Save `pm_decision.json`:
```json
{
  "timestamp": "{ISO 8601}",
  "trigger": "{escalation reason}",
  "gate": "{gate_name or null}",
  "attempts_exhausted": "{count or null}",
  "options_presented": ["fix", "skip", "abort"],
  "pm_decision": "{chosen option}",
  "pm_feedback": "{additional instructions}",
  "pm_reason": "{reason for skip if applicable}",
  "channel": "slack|chat",
  "latency_minutes": {N}
}
```

---

### State: CURATOR_RESOLVE

> **Reference:** Read `skills/epic-orchestration.md` section 10 for the complete protocol.

**Trigger:** All gates passed (transition from GATES).

**Actions:**
1. Dispatch **Curator agent** (`agents/curator.md`, model: sonnet) and **Lessons-Extractor agent**
   (`agents/lessons-extractor.md`, model: haiku) in parallel:
   - Curator inputs: all step outputs, gate results, final report
   - LE inputs: active session file, git log and diff
   - Log: `{"state": "CURATOR_RESOLVE", "action": "dispatch_parallel", "details": "Curator + Lessons-Extractor dispatched"}`
2. Process Curator output — for each proposal, run **Auto-Evaluate Algorithm**
   (3-tier: YAML rules → Qdrant history → default action) per `decision-policies.yaml` → `curator_auto_rules`
3. Process LE output — 3-layer dedup (text >90%, semantic >80%, Qdrant >0.85),
   write to `lessons-learned.md` and `command-history.md`, store to Qdrant
4. Dispatch fix agents for all APPROVED proposals — store fixes in
   `evidence/{epic_id}/{run_id}/curator_fixes/fix_{IMP_id}/`
5. Compile summary block (`curator_resolve_report.json`) with implemented/rejected/deferred counts
6. Log transition: `{"state": "CURATOR_RESOLVE", "action": "transition", "details": "..."}`

**Transition:** → PM_APPROVAL (always — even if 0 proposals)

**Evidence:**
- `curator_resolve_report.json` — structured summary of all proposals and decisions
- Updated `backlog.md` — proposal statuses updated per auto-evaluate decisions
- Updated `lessons-learned.md`, `command-history.md` — new entries from LE
- `curator_fixes/fix_{IMP_id}/` — fix evidence per approved proposal
- Entries in `stage_log.jsonl` for each sub-step

---

### State: PM_APPROVAL

**Actions:**
1. Compile final summary payload:
   ```
   epic_id, epic_title,
   completed_steps, total_steps, skipped_steps,
   file_count, commit_count, branch_list,
   escalation_count,
   evidence_dir
   ```
2. Send via PM Communication Protocol (per `skills/slack-mcp.md` Type C — Merge Approval):
   ```
   message_ref = send_pm_message("merge_approval", {
     epic_id, epic_title, completed, total,
     file_count, commit_count, branch_list, evidence_dir
   })
   response = wait_pm_response(message_ref, "merge_approval")
   ```
3. **If Slack:** Orchestrator continues when PM responds in Slack.
   **If chat:** STOP and wait for PM decision in conversation.

**PM Responses:**
- **APPROVE** (`response_type: "approve"`) → transition to DONE
- **REJECT** (`response_type: "reject"`) → transition to ESCALATION (with PM feedback `response.feedback`)
- **REVISE** (`response_type: "revise"`) → return to EXECUTING with PM's revision instructions (`response.feedback`)
- **Timeout** (`response.auto: true`) → execute `timeout_actions.merge_approval` from config

**Evidence:** Append to `pm_decision.json` (with `channel` and `latency_minutes` fields).

---

### State: DONE

**Actions:**
1. If status = approved:
   a. Merge step branches (or note for manual PR creation)
      - If merge fails (conflict, permissions): create PR instead of merging, log warning, note in final report
   b. Update EPIC file status to "Completed"
      - If EPIC file write fails: log warning, do not block DONE completion
   c. Archive session file: `mkdir -p .aid-o/04-engine/sessions/archive/` then move
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
4. **POST-PROCESSING (Auditor)** (per `skills/epic-orchestration.md` DONE state):
   a. Dispatch **Auditor agent** (`agents/auditor.md`) — runs 5 audit types
   b. If Auditor fails: log warning, note "audit incomplete" in final report, continue
   c. Auditor summary → PM via Slack (per `skills/slack-mcp.md` Type F — Audit Summary)
5. **Memory indexing** (per `skills/memory-mcp.md` → `memory_index_epic()`):
   - Read `.aid-o/03-config/policies/memory-config.yaml`
   - IF `memory.enabled` AND `memory.auto_index.epic_done`:
     - Index EPIC summary → `qdrant-store` (type: decision)
     - Index architectural decisions from architect step → `qdrant-store` (type: decision)
     - Index patterns from agent outputs → `qdrant-store` (type: pattern)
     - Index audit findings from audit-report.md → `qdrant-store` (type: audit_finding)
     - IF `memory.auto_index.gate_results`: index gates summary → `qdrant-store` (type: audit_finding)
   - IF disabled or fails → skip silently, DONE continues normally
6. **Archive Logic** (per `skills/epic-orchestration.md` DONE state item 6):
   - Archive session, update EPIC counter, conditionally archive EPIC and plan
   - EPIC archived only when `sessions_completed == sessions_total`
   - Plan archived only when `epics_completed == epics_total`
7. **Completion Summary** (per `skills/epic-orchestration.md` DONE state item 8):
   Present the structured Completion Summary from `skills/epic-orchestration.md`
   DONE state section. This is the last thing the PM sees -- make it informative
   and actionable. Includes step count, gates, duration, key outputs, and 5
   next-step options (/aid-review, /aid-brainstorm, /aid-plan-epic, /aid-audit, /aid-analytics).
8. Send Status Update: `:checkered_flag: EPIC completed — merged to main`
9. **EPIC QUEUE CHECK** (per `skills/epic-queue.md`):
    a. Read `.aid-o/04-engine/epic-queue.yaml`
    b. IF queue is not paused AND next EPIC exists (status: "queued"):
       - Mark next EPIC as "running" in queue
       - Send Status Update: `:arrows_counterclockwise: Auto-starting next EPIC: {next_epic_id}`
       - Start new run-epic loop with next EPIC (transition: DONE → IDLE → PLANNING)
    c. ELSE:
       - Send Status Update: `:white_check_mark: Queue empty. Orchestrator idle.`
       - Print completion message
10. **Final Stage Log Entry** (MUST be the LAST action in DONE state)

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

## Status Updates

Send informational Slack messages (Type G — Status Update, per `skills/slack-mcp.md`)
at key orchestration points. These are fire-and-forget — never block execution.

| Event | When | Message |
|-------|------|---------|
| EPIC start | IDLE → PLANNING | `:rocket: EPIC started — {step_count} steps planned` |
| Step start | EXECUTING (each step) | `:zap: Step {N}/{total}: {role} started` |
| Step complete | PHASE_CHECK pass | `:white_check_mark: Step {N}/{total}: {role} done ({file_count} files)` |
| Gates start | NEXT_PHASE → GATES | `:mag: All steps complete — running gates...` |
| Gates pass | GATES → PM_APPROVAL | `:white_check_mark: All gates passed — awaiting merge approval` |
| EPIC done | DONE | `:checkered_flag: EPIC completed — merged to main` |
| Queue pickup | DONE → next EPIC | `:arrows_counterclockwise: Auto-starting next EPIC: {id}` |
| Queue empty | DONE, no more EPICs | `:white_check_mark: Queue empty. Orchestrator idle.` |

If Slack is not configured or send fails → silently skip (status updates are non-critical).

## Reference Files

- **PRIMARY:** `skills/epic-orchestration.md` — state machine definitions, dispatch protocol, evidence formats
- **PM COMMS:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback, timeouts
- **QUEUE:** `skills/epic-queue.md` — Epic Queue management, auto-pickup protocol
- `skills/planner.md` — plan generation: dependency graph, parallel groups, analysis groups
- `skills/parallel-dispatch.md` — branch strategy, parallel dispatch protocol, conflict detection
- `skills/analysis-merge.md` — analysis group merge strategies (union, consensus, weighted)
- `defaults/policies/decision-policies.yaml` — auto-decisions, escalation triggers
- `defaults/policies/gates.yaml` — gate definitions, retry config
- `defaults/policies/slack-config.yaml` — Slack channel, timeouts, reminder config
- `defaults/templates/plan.schema.json` — plan validation (includes `analysis_groups`)

## Important

- **Read `skills/epic-orchestration.md` BEFORE starting the loop** — it is the single source of truth
- **Read `skills/slack-mcp.md` for PM communication** — defines message formats and fallback
- **PM checkpoints** — PLAN_REVIEW, ESCALATION, PM_APPROVAL wait for PM via Slack (or chat fallback)
- **Auto-decide where possible** — use `decision-policies.yaml` to minimize PM interruptions
- **Evidence is mandatory** — every transition logs to `stage_log.jsonl`, Slack messages to `slack_log.jsonl`
- If resuming an interrupted run: read `plan_progress.json` to find where to continue
  - If `plan_progress.json` is corrupted or unreadable: rebuild from `stage_log.jsonl` entries (scan for completed steps), or ask PM to confirm which steps are done
- If `$ARGUMENTS` is empty and multiple EPICs exist → list them and ask which to run
