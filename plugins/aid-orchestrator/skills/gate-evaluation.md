# Gate Evaluation — Quality Gates, Phase Checks, and Resolution

**Skill:** gate-evaluation
**Dependencies:** epic-state-machine, dispatch-protocol, epic-orchestration (parent module)

---

## Overview

This module defines the quality evaluation and resolution states of the EPIC orchestration FSM: PHASE_CHECK, GATES, GATE_RETRY, ESCALATION, CURATOR_RESOLVE, and PM_APPROVAL. These states verify agent outputs, enforce quality gates, handle failures, and manage the approval workflow.

For the FSM definition and state diagram, **see:** `skills/epic-state-machine.md`
For agent dispatch protocol, **see:** `skills/dispatch-protocol.md`
For auto-mode behavior at each state, **see:** `skills/first-aid-controller.md`

---

## PHASE_CHECK

### Agent Output Validation (pre-check)

Before evaluating step outputs normally, validate agent output integrity:

1. **Empty/null output check:**
   - If agent returned empty or null output → status: INCOMPLETE
   - Action: re-dispatch agent (max 1 retry), then ESCALATION

2. **Credit exhaustion detection:**

   CREDIT EXHAUSTION DETECTION:

   Match agent output against these patterns (case-insensitive regex).
   IF any pattern matches → credit_exhaustion = true

   Pattern 1: /exceed(ed)?\s+(your\s+)?(usage|token|rate)\s*(limit|cap|quota)/i
     Matches: "exceeded your usage limit", "exceed token quota", "exceeded rate cap"

   Pattern 2: /insufficient\s+(credits?|funds|balance|quota)/i
     Matches: "insufficient credits", "insufficient quota", "insufficient balance"

   Pattern 3: /(rate|usage|token)\s*(limit|cap|quota)\s*(reached|exceeded|hit)/i
     Matches: "rate limit reached", "usage cap exceeded", "token quota hit"

   Pattern 4: /too\s+many\s+(requests|tokens|api\s+calls)/i
     Matches: "too many requests", "too many tokens", "too many API calls"

   Pattern 5: /(billing|payment|subscription)\s*(issue|problem|error|required)/i
     Matches: "billing issue", "payment required", "subscription error"

   Pattern 6: /429|rate.?limit/i
     Matches: HTTP 429 status codes in error messages, "rate-limit", "rate_limit"

   NOTE: These patterns cover English error messages. Non-English API responses
   may require additional patterns.

   ON MATCH:
   1. Set credit_exhaustion = true
   2. Log: "Credit exhaustion detected: pattern {N} matched on text: '{matched_substring}'"
   3. Trigger existing CREDIT_EXHAUSTION_HANDLER
   4. Do NOT match the same output against remaining patterns (short-circuit after first match)

   IF credit_exhaustion = true → status: CREDIT_EXHAUSTED
   Action:
   a. Save interrupted state immediately:
      - Write `interrupted_step_context.json` to evidence:
        ```json
        {
          "epic_id": "{epic_id}",
          "run_id": "{run_id}",
          "interrupted_step": "{step_id}",
          "interrupted_at": "{ISO 8601}",
          "step_status_before": "running",
          "agent_partial_output": "{first 500 chars of output if any}",
          "git_stash_ref": "{stash ref if stashed}",
          "plan_progress_snapshot": "{copy of plan_progress.json state}"
        }
        ```
      - Run `git stash --include-untracked` to save any uncommitted work
      - Update plan_progress.json: step status → "interrupted"
      - Update auto-mode-state.yaml: mode → "paused", reason → "credit_exhaustion"
   b. Log: {"state": "PHASE_CHECK", "action": "credit_exhaustion_detected", "step": "{step_id}"}
   c. STOP gracefully — do NOT attempt any more agent dispatches

3. **Truncation warning:**
   - If output length < 20% of expected length (based on acceptance criteria count * estimated min output):
     Log WARNING: "Agent output may be truncated (length: {N} chars, expected: {M}+ chars)"
     Flag: POSSIBLY_TRUNCATED (non-blocking warning only)
     Continue with normal evaluation

---

### Output Evaluation

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

### Acceptance Validation

Per `decision-policies.yaml` → `content_quality`:

a. Read agent's `output.md` from `evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/output.md`
b. Read step's acceptance criteria from `plan.json` → `steps[N].outputs` + run file acceptance items
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
e. Evidence: save review to `evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/review.md`
f. Update `plan_progress.json`: increment `steps[step_id].review_cycles`, set `steps[step_id].last_review` to review result summary

### Discovered Issues Triage

Per `decision-policies.yaml` → `discovered_issues`:

a. Parse `## DISCOVERED ISSUES` section from agent's `output.md` (if present)
b. If no section → skip (no issues reported)
c. For each issue, extract: severity (`[CRITICAL]`/`[HIGH]`/`[MEDIUM]`/`[INFO]`), description, impact, recommendation
d. Triage per severity:
   - **CRITICAL:** Check `auto_fix_patterns` → match → dispatch fix agent; no match → ESCALATION. Current step BLOCKED.
   - **HIGH:** Log to `evidence/steps/step_{N}_{role}/discovered_issues.md`. Forward to later step if natural fit, else create `backlog.md` entry. PM Slack notification (informational). NOT blocking.
   - **MEDIUM/INFO:** Log to `evidence/steps/step_{N}_{role}/discovered_issues.md`. Add to `improvement_notes` (Curator picks up). NOT blocking.
e. Evidence: save all issues to `evidence/{epic_id}/{run_id}/steps/step_{N}_{role}/discovered_issues.md`
f. Run file: add CRITICAL/HIGH issues to Run Log

### Diff Generation (after output verification)

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

### Per-Agent Metrics Capture (PHASE_CHECK)

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

For PHASE_CHECK auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "PHASE_CHECK — Auto-Mode Behavior"

---

## GATES

**Actions:**
1. Read `.aid-o/03-config/policies/gates.yaml`
2. For each required gate:
   a. Run gate command (or check rule)
   b. Record pass/fail + output
3. If ALL required gates pass: transition to CURATOR_RESOLVE
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

---

## GATE_RETRY

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

---

## ESCALATION

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

For ESCALATION auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "ESCALATION — Auto-Mode Behavior"

---

## CURATOR_RESOLVE

**Trigger:** All gates passed (transition from GATES).

**Purpose:** Dispatch Curator + Lessons-Extractor in parallel, auto-evaluate proposals, implement approved fixes, process lessons, and prepare a summary for PM_APPROVAL.

**IMPORTANT — Unconditional Dispatch:** The Curator agent MUST ALWAYS be dispatched
when CURATOR_RESOLVE is entered. The Curator performs its own code review and analysis
to generate proposals -- it does NOT depend on pre-existing `discovered_issues` from
earlier steps. Even if no issues were discovered during PHASE_CHECK, the Curator will
independently analyze code quality, patterns, and improvement opportunities. Never skip
Curator dispatch based on the absence of discovered issues or improvement notes.

**Sub-Steps:**

0. **State Entry (observability — MANDATORY):**

   Log the following entry to `stage_log.jsonl` immediately upon entering CURATOR_RESOLVE:
   ```json
   {"state": "CURATOR_RESOLVE", "action": "state_entered", "timestamp": "{ISO 8601}", "epic_id": "{epic_id}", "run_id": "{run_id}", "details": "CURATOR_RESOLVE entered — dispatching Curator + LE unconditionally"}
   ```
   This entry MUST appear before any agent dispatch. It confirms the state was reached
   and is the primary observability signal for diagnosing Curator activation issues.

1. **Parallel Dispatch (unconditional — no preconditions):**

   a. Dispatch **Curator agent** (`agents/curator.md`, model: sonnet) with:
      - All step outputs: `evidence/{epic_id}/{run_id}/steps/*/output.md`
      - All step diffs: `evidence/{epic_id}/{run_id}/steps/*/diff.patch`
      - Gate results: `evidence/{epic_id}/{run_id}/gates_report.json`
      - Discovered issues (if any): `evidence/{epic_id}/{run_id}/steps/*/discovered_issues.md`
   b. Dispatch **Lessons-Extractor agent** (`agents/lessons-extractor.md`, model: haiku) with:
      - Active run file
      - Git log and diff
   c. Log:
      ```json
      {"state": "CURATOR_RESOLVE", "action": "dispatch_parallel", "details": "Curator + Lessons-Extractor dispatched"}
      ```

2. **Process Curator Output:**

   a. Parse `curator_report.proposals[]` from Curator agent output
   b. If no proposals: log "0 proposals", skip to sub-step 4
   c. For each proposal: run Auto-Evaluate Algorithm (sub-step 3)

3. **Auto-Evaluate Algorithm** (per proposal):

   ```
   for each proposal in curator_report.proposals:
     1. Load curator_auto_rules from decision-policies.yaml
     2. Tier 1 — Check explicit YAML rules:
        - always_approve[] → match on {type, area, priority}?
          → YES: decision = APPROVE. Log rule match.
        - always_reject[] → match?
          → YES: decision = REJECT. Log rule match.
        - always_defer[] → match?
          → YES: decision = DEFER. Log rule match.
     3. Tier 2 — No explicit rule matched → Query Qdrant:
        - Search: type=curator_decision, similar to proposal title+area+type
        - If similarity > learning.similarity_threshold AND
          matching decisions >= learning.min_decisions:
          → Apply majority action from past decisions
          → Log: "learned from {N} past decisions"
        - If Qdrant unavailable: skip Tier 2 gracefully, fall through to Tier 3
     4. Tier 3 — No rule, no Qdrant history:
        → Apply curator_auto_rules.default_action (default: approve)
        → Log: "default rule applied"
   ```

   Rule matching: each rule is `{type?, area?, priority?}`. All specified keys must match.
   `area` uses glob matching. First match wins within each list.

   Decision stage_log entries:

   ```json
   {"state": "CURATOR_RESOLVE", "action": "auto_evaluate", "proposal": "IMP-{NNN}",
    "decision": "approve", "rule": "{matched_rule_or_source}"}

   {"state": "CURATOR_RESOLVE", "action": "auto_evaluate", "proposal": "IMP-{NNN}",
    "decision": "reject", "reason": "{reason}"}

   {"state": "CURATOR_RESOLVE", "action": "auto_evaluate", "proposal": "IMP-{NNN}",
    "decision": "defer", "reason": "{reason}"}
   ```

   Backlog status updates per decision:
   - **APPROVE:** `implementing` → (after fix) `implemented`
   - **REJECT:** `orchestrator-rejected` (reason logged)
   - **DEFER:** `deferred` (reason logged)

4. **Process Lessons-Extractor Output:**

   a. Parse LE report for NEW LESSONS, NEW COMMANDS, NEW GOTCHAS sections
   b. 3-layer dedup for each lesson/gotcha:
      - Layer 1: exact text overlap >90% against local `.aid-o/04-engine/lessons-learned.md`
      - Layer 2: semantic similarity >80% against existing lessons (if embeddings available)
      - Layer 3: Qdrant cross-project dedup >0.85 similarity (if Qdrant available)
   c. Write new lessons to `.aid-o/04-engine/lessons-learned.md`
   d. Write new commands to `.aid-o/04-engine/command-history.md`
   e. Store to Qdrant (if available) with metadata:
      ```json
      {"type": "lesson", "subtype": "lesson|gotcha|command",
       "project_name": "{project_name}", "epic_id": "{epic_id}",
       "area": "{area}", "timestamp": "{ISO 8601}"}
      ```
   f. Log:
      ```json
      {"state": "CURATOR_RESOLVE", "action": "lessons_written",
       "new_lessons": "{N}", "new_commands": "{N}", "duplicates_skipped": "{N}"}
      ```

5. **Dispatch Approved Fixes:**

   For each APPROVED proposal:
   a. Determine agent role from proposal area/type (backend, frontend, docs, etc.)
   b. Dispatch fix agent with:
      - Proposal details (title, area, proposed_action, rationale)
      - Current file contents for the affected area
      - Instruction: implement the proposed fix, produce diff output
   c. Wait for fix completion
   d. Update `backlog.md`: status → `implemented`, `epic_ref`: current EPIC
   e. Store fix output in `evidence/{epic_id}/{run_id}/curator_fixes/fix_{IMP_id}/`
   f. Log each fix:
      ```json
      {"state": "CURATOR_RESOLVE", "action": "fix_completed", "proposal": "IMP-{NNN}",
       "files_modified": ["path/to/file"], "agent": "{role}"}
      ```

   If a fix agent fails: log warning, set proposal status → `deferred` with reason
   "fix attempt failed", continue with remaining fixes.

   No limits on fix size or effort — the Orchestrator approves everything relevant
   regardless of scope.

6. **Prepare PM Summary:**

   Compile CURATOR_RESOLVE results into structured block for PM_APPROVAL:

   ```
   --- Curator Resolution ---
   Implemented ({count}):
     - IMP-{NNN}: {title} (effort: {effort})
   Rejected by Orchestrator ({count}):
     - IMP-{NNN}: {title}
       Reason: {reason} [Rule: {rule_source}]
   Deferred ({count}):
     - IMP-{NNN}: {title}
       Reason: {reason}
   Lessons: {count} new | Gotchas: {count} new | Commands: {count} new
   ```

   Store as `evidence/{epic_id}/{run_id}/curator_resolve_report.json`

7. **Transition → PM_APPROVAL**

   ```json
   {"state": "CURATOR_RESOLVE", "action": "transition",
    "details": "{approved} approved ({fixed} fixed), {rejected} rejected, {deferred} deferred. → PM_APPROVAL"}
   ```

**Evidence:** Save `.aid-o/04-engine/evidence/{epic_id}/{run_id}/curator_resolve_report.json`

For CURATOR_RESOLVE auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "CURATOR_RESOLVE — Auto-Mode Behavior"

---

## PM_APPROVAL

**Communication:** Per `skills/slack-mcp.md` Type C (Merge Approval).

**Actions:**
1. Compile final summary payload (steps, gates, changes, evidence path)
2. Load `curator_resolve_report.json` from `evidence/{epic_id}/{run_id}/` and include
   Curator summary block in the payload:

   ```
   EPIC Ready for Approval: {epic_id}
   ====================================
   Steps: {completed}/{total} | Gates: {passed}/{total} | Duration: {duration}

   --- Curator Resolution ---
   Implemented ({count}):
     - IMP-{NNN}: {title} (effort: {effort})

   Rejected by Orchestrator ({count}):
     - IMP-{NNN}: {title}
       Reason: {reason} [Rule: {rule_source}]

   Deferred ({count}):
     - IMP-{NNN}: {title}
       Reason: {reason}

   Lessons: {count} new | Gotchas: {count} new

   PM Actions:
     1. APPROVE — merge everything, EPIC done
     2. Override rejected: "fix IMP-{NNN}" — Orchestrator dispatches fix agent
     3. Teach rule: "always approve {type/area}" — added to auto-rules + Qdrant
     4. REJECT — do not merge

   After approval: version bump (if needed) → merge → archive → audit → metrics
   ```

3. Send to PM via `send_pm_message("merge_approval", payload)`:
   - **Slack:** Posts Merge Approval message, waits for reply
   - **Chat fallback:** Presents summary in conversation, waits for response
4. Wait for PM response via `wait_pm_response(message_ref, "merge_approval")`
5. If APPROVE (`response_type: "approve"`): transition to DONE
6. If PM Override — "fix IMP-{NNN}" (override a rejected proposal):
   a. Dispatch fix agent for the specified proposal
   b. Update `backlog.md`: status → `implemented`, actor: `pm-override`
   c. Store PM decision in Qdrant for learning:
      ```json
      {"type": "curator_decision", "action": "approve",
       "proposal_type": "{type}", "proposal_area": "{area}",
       "project_name": "{project_name}", "epic_id": "{epic_id}",
       "pm_instruction": "override rejection", "timestamp": "{ISO 8601}"}
      ```
   d. Log:
      ```json
      {"state": "PM_APPROVAL", "action": "pm_override", "proposal": "IMP-{NNN}"}
      ```
   e. Re-present updated summary to PM (return to action 4)
7. If PM Rule Teaching — "always approve {pattern}" (or similar):
   a. Parse instruction to extract: type, area, or priority pattern
   b. Append to `decision-policies.yaml` → `curator_auto_rules.always_approve[]`
   c. Store in Qdrant as `curator_decision` with `pm_instruction` field
   d. Confirm to PM: "Rule added: always approve {pattern}"
   e. Log:
      ```json
      {"state": "PM_APPROVAL", "action": "rule_learned", "rule": "{pattern}"}
      ```
   f. Re-present updated summary to PM (return to action 4)
8. If REJECT (`response_type: "reject"`): transition to ESCALATION (with PM feedback)
9. If REVISE (`response_type: "revise"`): return to EXECUTING with PM's revision instructions
10. If timeout: execute `timeout_actions.merge_approval` from `slack-config.yaml`

PM override and rule teaching are **non-blocking** — the PM can simply APPROVE without
interacting with the Curator summary at all.

For PM_APPROVAL auto-mode behavior, **see:** `skills/first-aid-controller.md` Section "PM_APPROVAL — Auto-Mode Behavior"

---

**Last Updated:** 2026-02-28
