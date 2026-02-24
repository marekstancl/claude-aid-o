# Auto-Mode Escalation Protocol

**Skill:** auto-escalation
**Dependencies:** epic-orchestration, slack-mcp, retry-engine, gates-engine, epic-queue

---

## TL;DR

This skill defines the escalation protocol for **FIRST AID auto-mode** -- the autonomous
EPIC execution mode where the Orchestrator processes an approved queue without continuous
PM involvement. Escalation is the **only mandatory PM touchpoint** in auto-mode. It
distinguishes agent-resolvable issues (handled silently) from PM-required issues (pause,
notify, wait for decision). When an escalation triggers, auto-mode pauses, progress is
saved, and the PM receives a structured notification with options including a new
`continue-manual` option to switch to manual orchestration at a natural pause point.

**Principle:** Auto-mode runs silently until it cannot. Then it pauses cleanly, tells the
PM exactly what happened, and waits.

---

## 1. Escalation vs Non-Escalation Decision

Before raising an escalation, the Orchestrator MUST classify the issue. Only issues that
genuinely require human judgment trigger an escalation. Everything else is handled by
agents autonomously.

### 1.1 Decision Algorithm

```
ON_ISSUE(issue):
  1. Classify issue severity and type (see Section 2 Trigger Matrix)
  2. CHECK non-escalation conditions (Section 3):
     IF matches non-escalation pattern:
       → Handle autonomously (log, retry, backlog, or auto-fix)
       → RETURN (no escalation)
  3. CHECK trigger matrix (Section 2):
     IF matches trigger:
       → Execute PAUSE protocol (Section 4)
       → Send PM notification (Section 5)
       → WAIT for PM decision (Section 6)
  4. IF no match in either list:
     → Default: treat as MEDIUM severity
     → Log to improvement_notes for Curator
     → Continue execution
```

### 1.2 Key Distinction

| Category | What happens | PM involved? |
|----------|-------------|--------------|
| **Escalation** | Auto-mode pauses, PM notified with options | Yes -- blocking |
| **Non-escalation** | Agent handles autonomously, logs evidence | No -- silent |
| **Unknown** | Default to non-escalation (log + continue) | No -- logged for Curator |

---

## 2. Escalation Trigger Matrix

These 16 triggers are the exhaustive list of conditions that pause auto-mode and require
PM input. Each trigger has a unique ID for tracking in evidence and Qdrant.

### 2.1 CRITICAL Triggers (Immediate Pause)

| ID | Trigger | Detection Method | Auto-Mode Action |
|----|---------|-----------------|------------------|
| **E1** | Step fails 2x + fresh approach fails | `plan_progress.json`: step has 2 failed dispatches AND gate-fixer/re-dispatch also failed | PAUSE auto-mode, notify PM with full failure history |
| **E2** | Security finding CRITICAL | Security agent or `bandit` output contains `Severity: CRITICAL` or equivalent | PAUSE immediately -- do NOT continue to next step |
| **E4** | Gate fails after 3 retries | `gates_report.json`: gate has `attempts.length >= max_attempts` (default 3) | PAUSE auto-mode, notify PM with retry history |

**CRITICAL triggers halt execution before any further state transitions.** No next step,
no next gate, no further agent dispatches until PM responds.

### 2.2 HIGH Triggers (Pause at Current State)

| ID | Trigger | Detection Method | Auto-Mode Action |
|----|---------|-----------------|------------------|
| **E3** | Security finding HIGH | Security agent output contains `Severity: HIGH` | PAUSE auto-mode after current step completes |
| **E5** | Agent produces no output or errors | Agent dispatch returns empty response, timeout, or exception | PAUSE auto-mode, include agent error details |
| **E6** | Merge conflict (parallel agents) | `git merge --no-commit --no-ff` dry-run fails between parallel branches | PAUSE auto-mode, include conflict file list and diff |
| **E7** | Agent flags "cannot resolve" | Agent output contains `status: "blocked"` or `status: "unable"` | PAUSE auto-mode, include agent's explanation |
| **E8** | Budget exceeded | Cost tracking shows `total_cost > budget_limit` from `cost-optimization.md` | PAUSE auto-mode, include cost report and remaining work estimate |

### 2.3 MEDIUM Triggers (Pause at Phase Boundary)

| ID | Trigger | Detection Method | Auto-Mode Action |
|----|---------|-----------------|------------------|
| **E9** | Scope violation persists after re-dispatch | Agent modifies `forbidden_paths` on 2nd attempt after warning | PAUSE auto-mode, present violation details |
| **E10** | Conflicting outputs (non-merge) | Two agents produce contradictory decisions/designs (detected during `analysis-merge.md`) | PAUSE auto-mode, present both outputs side-by-side |
| **E11** | Plan validation fails in auto PLAN_REVIEW | Auto-mode plan generation produces invalid JSON or fails schema validation | PAUSE auto-mode, PM reviews plan manually |
| **E12** | Last-EPIC guardrail check fails | Queue guardrail: session escalation count >= `max_escalations_per_session` | PAUSE auto-mode, PM reviews before next EPIC starts |
| **E13** | Architecture decision with multiple valid options | Architect agent outputs `decision_type: "requires_pm"` with 2+ options | PAUSE auto-mode, present options with trade-offs |
| **E14** | Test suite red after fix attempt | Test failures persist after 3 gate-fixer cycles (becomes E1) | Agent handles up to 3 cycles autonomously; if still failing, escalate via E1 |
| **E15** | Version detection failure in release | Release sub-phase cannot determine current version from `version_files[]` | PAUSE auto-mode, PM provides version info |
| **E16** | EPIC acceptance criteria ambiguous | Planner or agent flags acceptance criteria as unparseable or contradictory | PAUSE auto-mode, PM clarifies criteria before execution begins |

### 2.4 Trigger Severity → Pause Timing

```
CRITICAL  → Immediate halt. No further work of any kind.
HIGH      → Complete current atomic operation (commit if mid-commit), then pause.
MEDIUM    → Complete current step/phase, then pause at next phase boundary.
```

---

## 3. Non-Escalation Conditions (Agent-Handled)

These issues are resolved autonomously. The Orchestrator logs them but does NOT pause
auto-mode or notify the PM.

### 3.1 Conditions

| Condition | Agent Action | Evidence |
|-----------|-------------|----------|
| Low-severity security findings | Log to `improvement_notes` in step output | `step_output.json` → `improvement_notes[]` |
| Style/formatting lint failures | Auto-fix via gate retry (`ruff check --fix`) | `gates_report.json` → retry attempt |
| Minor test failures (1st or 2nd attempt) | Re-dispatch agent with failure feedback | `stage_log.jsonl` entry |
| Discovered issues MEDIUM/INFO severity | Add to Curator backlog | `backlog.md` entry |
| Curator proposal evaluation | Auto-evaluate via `decision-policies.yaml` rules + Qdrant history | `curator_resolve_report.json` |
| Conditional gate failure (non-required) | Log as warning, continue | `gates_report.json` → status: "warning" |
| Agent produces valid output with minor gaps | Accept output, log gaps in `improvement_notes` | `step_output.json` |
| Flaky test (passes on re-run) | Accept pass result, log flakiness | `gates_report.json` + `improvement_notes` |

### 3.2 Non-Escalation Flow

```
ISSUE DETECTED
  → Classify as non-escalation (match against Section 3.1)
  → Execute agent action (retry, auto-fix, log, backlog)
  → Append to stage_log.jsonl:
    {"state": "{current_state}", "action": "auto_resolved",
     "issue_type": "{type}", "details": "{description}",
     "resolution": "{what was done}"}
  → Continue auto-mode execution
```

### 3.3 Escalation Promotion

A non-escalation issue can PROMOTE to an escalation if it persists:

| Non-Escalation | Promotes To | After |
|----------------|-------------|-------|
| Minor test failure | E1 | 2 re-dispatches + fresh approach fails |
| Style/lint failure | E4 | 3 gate retries exhausted |
| Scope violation (1st) | E9 | Re-dispatch still violates |
| Agent output with gaps | E7 | Agent explicitly flags "cannot resolve" |

---

## 4. Pause Protocol

When an escalation trigger fires, auto-mode must pause cleanly before notifying the PM.

### 4.1 Pause Sequence

```
ESCALATION_TRIGGER(trigger_id, severity, details):

  1. DETERMINE pause timing per Section 2.4:
     CRITICAL → immediate (interrupt current wait/dispatch if possible)
     HIGH     → after current atomic operation completes
     MEDIUM   → after current step/phase completes

  2. SAVE progress snapshot:
     a. Write current state to plan_progress.json:
        - current_step: "{step_id}"
        - current_state: "{state machine state}"
        - completed_steps: [...]
        - pending_steps: [...]
     b. Commit any uncommitted work:
        - IF dirty working tree: git stash save "auto-escalation-{trigger_id}-{timestamp}"
        - Record stash ref in escalation evidence
     c. Write escalation marker to epic-queue.yaml:
        - Current EPIC status → "paused"
        - Queue paused flag → true (no auto-pickup of next EPIC)

  3. BUILD escalation context (Section 4.2)

  4. INCREMENT session escalation counter:
     → Read from .aid-o/04-engine/auto-session.json
     → escalation_count += 1
     → IF escalation_count >= max_escalations_per_session:
       → Set guardrail_breached = true (triggers E12 at next EPIC boundary)

  5. SAVE escalation evidence:
     → Write to evidence/{epic_id}/{run_id}/escalations/escalation_{trigger_id}_{timestamp}.json
```

### 4.2 Escalation Context Object

Every escalation carries a structured context object used by the notification system:

```json
{
  "escalation_id": "ESC-{trigger_id}-{YYYYMMDD-HHmmss}",
  "trigger_id": "{E1-E16}",
  "trigger_name": "{human-readable trigger name}",
  "severity": "CRITICAL|HIGH|MEDIUM",
  "timestamp": "{ISO 8601}",
  "epic_id": "{epic_id}",
  "run_id": "{run_id}",
  "current_state": "{state machine state}",
  "current_step": "{step_id or null}",
  "details": {
    "description": "{what happened}",
    "evidence_path": "{path to relevant evidence file}",
    "history": [
      {"attempt": 1, "action": "{what was tried}", "result": "{outcome}"},
      {"attempt": 2, "action": "{what was tried}", "result": "{outcome}"}
    ]
  },
  "progress": {
    "completed_steps": "{N}",
    "total_steps": "{M}",
    "percentage": "{N/M * 100}%"
  },
  "stash_ref": "{git stash ref or null}",
  "session_escalation_count": "{N} of {max}",
  "recommendation": "{auto-generated recommendation}"
}
```

### 4.3 Auto-Session Tracking

The session counter lives in `.aid-o/04-engine/auto-session.json`:

```json
{
  "session_id": "AUTO-{YYYYMMDD-HHmmss}",
  "started_at": "{ISO 8601}",
  "queue_snapshot": ["E-...", "E-...", "E-..."],
  "max_escalations_per_session": 3,
  "escalation_count": 0,
  "escalations": [],
  "guardrail_breached": false,
  "pm_tuned_max": null
}
```

**PM can tune `max_escalations_per_session`** via the escalation response (see Section 6.3).
The tuned value is stored in `pm_tuned_max` and overrides the default for the remainder
of the session.

---

## 5. PM Notification Format

Escalation notifications in auto-mode extend the existing Slack Type A (Escalation)
format with auto-mode-specific fields and a fourth option (`D: continue-manual`).

### 5.1 Notification via Slack

Uses `send_pm_message("escalation", payload)` from `skills/slack-mcp.md`.

```
:rotating_light: *AUTO-MODE ESCALATION — {trigger_name}*
:double_vertical_bar: Auto-mode paused
━━━━━━━━━━━━━━━━
*Trigger:* `{trigger_id}` — {trigger_name}
*Severity:* {CRITICAL|HIGH|MEDIUM}
*EPIC:* `{epic_id}` — {epic_title}
*Progress:* {completed_steps}/{total_steps} steps ({percentage}%)
*State:* {current_state} → paused

:clipboard: *What happened:*
{details.description — max 500 chars}

:mag: *What was tried:*
{For each attempt in details.history:}
• Attempt {N}: {action} → {result}

:dart: *Options:*
> :white_check_mark: *A)* Fix — {context-specific fix description}
> :next_track_button: *B)* Skip — continue to next step/gate (mark as skipped)
> :stop_sign: *C)* Abort — stop this EPIC, pause queue
> :arrows_counterclockwise: *D)* Continue manual — finish this EPIC in manual mode

:bulb: *Recommendation:* {auto_recommendation}
:bar_chart: *Session:* Escalation {escalation_count}/{max_escalations_per_session}

_Reply with A, B, C, or D (or start a thread for discussion)_
```

### 5.2 Notification via Chat Fallback

When Slack is not configured, present the same information in the conversation:

```
AUTO-MODE ESCALATION
====================================
Trigger: {trigger_id} — {trigger_name}
Severity: {severity}
EPIC: {epic_id}
Progress: {completed_steps}/{total_steps} steps ({percentage}%)

What happened:
{details.description}

What was tried:
1. {attempt 1 description} → {outcome}
2. {attempt 2 description} → {outcome}

Options:
A) Fix — {context-specific description}
B) Skip — continue to next step/gate
C) Abort — stop this EPIC, pause queue
D) Continue manual — switch to manual orchestration for this EPIC

Recommendation: {auto_recommendation}
Session: Escalation {count}/{max}
====================================
Reply: A / B / C / D
```

### 5.3 Context-Specific Fix Descriptions

The fix option (A) varies per trigger:

| Trigger | Option A Description |
|---------|---------------------|
| E1 | "Provide guidance for a fresh fix approach (resets retry counter)" |
| E2, E3 | "Provide remediation instructions for the security finding" |
| E4 | "Provide manual fix guidance for the failing gate (resets retry counter)" |
| E5 | "Investigate agent error and re-dispatch with guidance" |
| E6 | "Resolve merge conflict manually, then resume" |
| E7 | "Provide resolution guidance for the blocked agent" |
| E8 | "Increase budget limit and continue" |
| E9 | "Adjust scope boundaries (allowed/forbidden paths)" |
| E10 | "Choose between the conflicting outputs" |
| E11 | "Review and approve/revise the generated plan" |
| E12 | "Review session health and decide: continue auto or switch to manual" |
| E13 | "Select the preferred architecture option" |
| E14 | (Handled via E1 after 3 cycles) |
| E15 | "Provide the correct version string" |
| E16 | "Clarify the ambiguous acceptance criteria" |

### 5.4 Auto-Generated Recommendations

The Orchestrator generates a recommendation based on trigger context:

```
GENERATE_RECOMMENDATION(escalation_context):

  IF trigger_id = E1:
    IF all attempts used same approach → "A (fix) — previous attempts used same strategy, PM insight may unlock a different approach"
    ELSE → "C (abort) — multiple distinct strategies failed, may need requirements rethink"

  IF trigger_id in [E2]:
    → "A (fix) — CRITICAL security issue must be resolved before continuing"

  IF trigger_id = E3:
    → "A (fix) — HIGH security finding should be addressed; B (skip) acceptable if finding is a false positive"

  IF trigger_id = E4:
    IF gate is required AND security-related → "A (fix) — security gate failure needs human review"
    IF gate is required AND test-related → "A (fix) — test failure after 3 retries suggests a deeper issue"
    IF gate is required AND lint-related → "B (skip) — lint issue unlikely to block functionality"

  IF trigger_id in [E5, E7]:
    → "A (fix) — agent error may be transient; re-dispatch with guidance"

  IF trigger_id = E6:
    → "A (fix) — merge conflict must be resolved to continue"

  IF trigger_id = E8:
    → "D (continue-manual) — budget exceeded, manual mode avoids further autonomous spend"

  IF trigger_id in [E10, E13]:
    → "A (fix) — PM judgment needed to choose between options"

  IF trigger_id in [E11, E16]:
    → "A (fix) — clarification will unblock the pipeline"

  IF trigger_id = E12:
    → "D (continue-manual) — session escalation limit reached, manual oversight recommended"

  IF trigger_id = E15:
    → "A (fix) — provide version info to unblock release"

  DEFAULT:
    → "A (fix) — issue appears resolvable with PM guidance"
```

---

## 6. PM Decision Handling

### 6.1 Response Parsing

Extends the standard Type A parsing from `skills/slack-mcp.md` with option D:

| PM says | Parsed as |
|---------|-----------|
| `A`, `a`, `fix`, `retry` | `{ response_type: "fix" }` |
| `B`, `b`, `skip` | `{ response_type: "skip" }` |
| `C`, `c`, `abort` | `{ response_type: "abort" }` |
| `D`, `d`, `manual`, `continue-manual`, `continue manual` | `{ response_type: "continue_manual" }` |
| Thread reply (other text) | `{ response_type: "discussion", message: "<text>" }` |

### 6.2 Decision Execution

#### Option A: Fix

```
ON_PM_FIX(pm_guidance):
  1. Save PM guidance to pm_decision.json
  2. Reset relevant retry/attempt counter to 0
  3. Build enhanced prompt with PM guidance prepended:
     "## PM Guidance (from escalation {escalation_id})\n{pm_guidance}\n\n{standard prompt}"
  4. Resume auto-mode:
     a. Restore stashed changes (if any): git stash pop
     b. Re-dispatch agent/gate-fixer with enhanced prompt
     c. Set EPIC status in epic-queue.yaml back to "running"
     d. Set queue paused flag back to false
  5. Log to stage_log.jsonl:
     {"state": "ESCALATION", "action": "pm_fix",
      "escalation_id": "{id}", "trigger": "{trigger_id}"}
  6. CONTINUE auto-mode from the interrupted state
```

#### Option B: Skip

```
ON_PM_SKIP(pm_reason):
  1. Save PM decision to pm_decision.json
  2. Mark the triggering item as "skipped_by_pm":
     - Gate failure → gates_report.json: gate status = "skipped_by_pm"
     - Step failure → plan_progress.json: step status = "skipped_by_pm"
     - Security finding → log as "accepted_risk" with PM reason
  3. Resume auto-mode:
     a. Restore stashed changes (if any): git stash pop
     b. Advance to next step/gate/state
     c. Set EPIC status in epic-queue.yaml back to "running"
     d. Set queue paused flag back to false
  4. Log to stage_log.jsonl:
     {"state": "ESCALATION", "action": "pm_skip",
      "escalation_id": "{id}", "trigger": "{trigger_id}",
      "reason": "{pm_reason}"}
  5. CONTINUE auto-mode from the next logical state
```

#### Option C: Abort

```
ON_PM_ABORT():
  1. Save PM decision to pm_decision.json
  2. Transition current EPIC to DONE state with status: "aborted"
  3. Update epic-queue.yaml:
     - Current EPIC status → "failed"
     - Queue paused flag → true (safety: do not auto-pickup next)
  4. Run post-processing (Curator + Lessons-Extractor) even on abort:
     - Evidence is valuable for learning
  5. Log to stage_log.jsonl:
     {"state": "ESCALATION", "action": "pm_abort",
      "escalation_id": "{id}", "trigger": "{trigger_id}"}
  6. Send summary via Slack:
     "EPIC {epic_id} aborted by PM at escalation {trigger_id}.
      Queue paused. {N} EPICs remaining in queue."
  7. STOP auto-mode
```

#### Option D: Continue Manual

```
ON_PM_CONTINUE_MANUAL():
  1. Save PM decision to pm_decision.json
  2. SWITCH execution mode from auto to manual:
     a. Update auto-session.json: mode = "manual_takeover"
     b. Update epic-queue.yaml:
        - Current EPIC status → "running" (still active)
        - Queue paused flag → true (no auto-pickup after this EPIC)
  3. Restore stashed changes (if any): git stash pop
  4. Present current state to PM in conversation:
     "Switched to manual mode.
      Current state: {current_state}
      Current step: {current_step}
      Completed: {completed_steps}/{total_steps}
      The escalation issue ({trigger_id}) still needs resolution.
      How would you like to proceed?"
  5. Log to stage_log.jsonl:
     {"state": "ESCALATION", "action": "pm_continue_manual",
      "escalation_id": "{id}", "trigger": "{trigger_id}"}
  6. CONTINUE in standard (manual) orchestration mode:
     - PM sees every state transition
     - PM approves each step as normal
     - Remaining queue EPICs stay paused until PM explicitly resumes queue
```

**continue-manual vs abort:**

| Aspect | Continue Manual (D) | Abort (C) |
|--------|-------------------|-----------|
| Current EPIC | Continues in manual mode | Stops immediately |
| Remaining steps | PM drives completion | Not executed |
| Post-processing | Runs at normal EPIC completion | Runs immediately (partial) |
| Queue | Paused until EPIC finishes + PM resumes | Paused indefinitely |
| Typical use | "I want to finish this but oversee the rest" | "Stop everything, something is wrong" |

### 6.3 PM Tuning During Escalation

When responding to an escalation, the PM can also tune auto-mode parameters by including
directives in their response:

```
Recognized PM directives (parsed from response text):
- "set max escalations to {N}"  → updates pm_tuned_max in auto-session.json
- "set budget to {N}"           → updates budget limit for current EPIC
- "skip all {trigger_type}"     → adds a session-scoped skip rule

These directives are parsed AFTER the primary option (A/B/C/D) and applied
before resuming execution.
```

---

## 7. Resume Protocol

After PM decides (options A, B, or D), auto-mode must resume cleanly.

### 7.1 Resume Sequence

```
RESUME_AUTO_MODE(pm_decision):

  1. VALIDATE state consistency:
     a. Read plan_progress.json — verify it matches expected state
     b. Read gates_report.json — verify gate states are consistent
     c. If any inconsistency → log warning but proceed (self-healing)

  2. RESTORE working state:
     a. IF stash_ref exists:
        → git stash pop (apply stashed changes)
        → IF conflict: log and proceed without stash (changes were partial)
     b. Verify branch is correct: git branch --show-current

  3. APPLY PM decision:
     a. Option A → re-dispatch with guidance (see Section 6.2)
     b. Option B → advance past skipped item
     c. Option D → switch to manual mode (no resume of auto)

  4. UPDATE tracking:
     a. epic-queue.yaml: EPIC status → "running"
     b. epic-queue.yaml: paused → false (except for option D)
     c. auto-session.json: last_resume timestamp

  5. LOG resume:
     → stage_log.jsonl:
       {"state": "ESCALATION", "action": "auto_resumed",
        "escalation_id": "{id}", "resume_type": "{fix|skip|manual}"}

  6. CONTINUE state machine from interrupted point
```

### 7.2 Resume State Mapping

After an escalation, the Orchestrator returns to the appropriate state:

| Trigger | After Fix (A) | After Skip (B) |
|---------|--------------|----------------|
| E1 (step 2x fail) | EXECUTING (re-dispatch step) | PHASE_CHECK (advance to next step) |
| E2, E3 (security) | EXECUTING (re-dispatch with fix) | PHASE_CHECK (log accepted risk) |
| E4 (gate 3x fail) | GATE_RETRY (reset counter) | GATES (mark gate skipped_by_pm) |
| E5 (agent error) | EXECUTING (re-dispatch agent) | PHASE_CHECK (skip step) |
| E6 (merge conflict) | PHASE_CHECK (after manual resolve) | PHASE_CHECK (pick one branch) |
| E7 (cannot resolve) | EXECUTING (re-dispatch with guidance) | PHASE_CHECK (skip step) |
| E8 (budget exceeded) | EXECUTING (with new budget) | PM_APPROVAL (end early) |
| E9 (scope violation) | EXECUTING (with adjusted scope) | PHASE_CHECK (accept as-is) |
| E10 (conflicting outputs) | PHASE_CHECK (with PM's choice) | PHASE_CHECK (pick first) |
| E11 (plan validation) | PLAN_REVIEW (with fixed plan) | N/A (cannot skip planning) |
| E12 (guardrail check) | PM_APPROVAL (reset counter) | PM_APPROVAL (continue) |
| E13 (arch decision) | EXECUTING (with PM's choice) | EXECUTING (pick first option) |
| E15 (version detection) | DONE (with version info) | DONE (skip version bump) |
| E16 (ambiguous criteria) | PLANNING (with clarification) | EXECUTING (best-effort) |

---

## 8. Escalation Budget

Auto-mode tracks escalation frequency to prevent runaway escalation loops.

### 8.1 Session Budget

```yaml
# Default values (PM can tune via escalation response or queue config)
max_escalations_per_session: 3
```

**Session** = one auto-mode invocation processing the approved EPIC queue (one or more
EPICs). The session starts when auto-mode begins and ends when the queue is empty, the
PM aborts, or the PM switches to manual.

### 8.2 Budget Enforcement

```
ON_ESCALATION(trigger):
  session.escalation_count += 1

  IF session.escalation_count > session.max_escalations_per_session:
    → Trigger E12 (last-EPIC guardrail fails)
    → At next EPIC boundary: force PM_APPROVAL review
    → PM must explicitly choose:
      a. "Continue auto with raised limit" → set new max, resume
      b. "Continue manual" → switch to manual for remaining EPICs
      c. "Abort queue" → stop all remaining EPICs

  The budget applies PER SESSION, not per EPIC. This means:
  - EPIC 1: 2 escalations (2/3)
  - EPIC 2: 1 escalation (3/3 — limit reached)
  - EPIC 3: would trigger E12 guardrail before starting
```

### 8.3 Budget Reset

The budget resets when:
- A new auto-mode session starts (new `/aid-run-epic --auto` invocation)
- PM explicitly resets via escalation response ("set max escalations to {N}")
- PM resumes the queue after a manual pause (`/epic-queue resume`)

The budget does NOT reset when:
- An EPIC completes within the same session
- PM chooses "fix" (A) on an escalation -- that was still an escalation
- PM chooses "skip" (B) -- that was still an escalation

---

## 9. Escalation Evidence

### 9.1 Evidence Structure

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  escalations/
    escalation_E1_20260224-143022.json    # Per-escalation evidence
    escalation_E4_20260224-151500.json
  pm_decision.json                         # Latest PM decision (overwritten)
  auto-session.json                        # Session-level tracking (root level)
```

### 9.2 Per-Escalation Evidence File

```json
{
  "escalation_id": "ESC-E1-20260224-143022",
  "trigger_id": "E1",
  "trigger_name": "Step fails 2x + fresh approach fails",
  "severity": "CRITICAL",
  "timestamp": "2026-02-24T14:30:22Z",
  "epic_id": "E-20260224-fa01",
  "run_id": "20260224T140000Z",
  "current_state": "PHASE_CHECK",
  "current_step": "step_3_backend",
  "details": {
    "description": "Backend agent failed to implement auth middleware. First attempt: wrong import path. Second attempt: correct import but runtime error. Fresh approach (different auth library): compilation error.",
    "evidence_path": "evidence/E-20260224-fa01/20260224T140000Z/steps/step_3_backend/",
    "history": [
      {"attempt": 1, "action": "Dispatch backend agent", "result": "ImportError in auth.py"},
      {"attempt": 2, "action": "Re-dispatch with error feedback", "result": "RuntimeError: missing config"},
      {"attempt": 3, "action": "Fresh approach (different library)", "result": "CompilationError"}
    ]
  },
  "progress": {
    "completed_steps": 5,
    "total_steps": 12,
    "percentage": "41%"
  },
  "stash_ref": "stash@{0}",
  "session_escalation_count": "1 of 3",
  "recommendation": "A (fix) — previous attempts used same strategy, PM insight may unlock a different approach",
  "pm_decision": {
    "option": "A",
    "response_type": "fix",
    "guidance": "Use the built-in auth module from the framework instead of a third-party library. See docs/auth.md.",
    "decided_at": "2026-02-24T14:45:00Z",
    "response_latency_minutes": 15
  }
}
```

### 9.3 Qdrant Storage

After each escalation is resolved, store to Qdrant for cross-project learning:

```json
{
  "type": "escalation",
  "trigger_id": "{E1-E16}",
  "severity": "{CRITICAL|HIGH|MEDIUM}",
  "project_name": "{project_name}",
  "epic_id": "{epic_id}",
  "description": "{details.description}",
  "pm_decision": "{response_type}",
  "pm_guidance": "{guidance text if fix}",
  "resolution_effective": true,
  "timestamp": "{ISO 8601}"
}
```

This enables the system to learn from escalation patterns over time:
- Similar issues that PM always skips can be auto-skipped in future
- Similar issues that PM always fixes with the same guidance can be auto-attempted
- Persistent trigger types may indicate systemic issues worth addressing

---

## 10. Integration Points

### 10.1 Called By

| Caller | When | Notes |
|--------|------|-------|
| `skills/epic-orchestration.md` (PHASE_CHECK) | Agent error, scope violation, conflict | Triggers E1, E5, E6, E7, E9, E10 |
| `skills/epic-orchestration.md` (GATES) | Gate failure after max retries | Triggers E4 |
| `skills/epic-orchestration.md` (PLAN_REVIEW) | Plan validation failure in auto-mode | Triggers E11 |
| `skills/epic-orchestration.md` (EXECUTING) | Security findings from security agent | Triggers E2, E3 |
| `skills/epic-orchestration.md` (PM_APPROVAL) | Guardrail check at EPIC boundary | Triggers E12 |
| `skills/retry-engine.md` | Retries exhausted for gate | Triggers E4 |
| `skills/cost-optimization.md` | Budget exceeded | Triggers E8 |
| `skills/epic-queue.md` | Queue-level guardrail checks | Triggers E12 |
| `commands/aid-run-epic.md` | Any auto-mode execution | All triggers |

### 10.2 Calls To

| Target | When | Purpose |
|--------|------|---------|
| `skills/slack-mcp.md` | Every escalation | Send PM notification (Type A extended) |
| `skills/epic-queue.md` | Pause/resume | Update queue status |
| `skills/retry-engine.md` | After PM fix (A) for gate issues | Re-dispatch with guidance |
| `skills/cost-optimization.md` | After PM budget increase (E8) | Update budget limit |

### 10.3 Consumed By

| Consumer | What it reads | Purpose |
|----------|--------------|---------|
| `skills/epic-orchestration.md` | `auto-session.json` | Check session budget |
| `commands/aid-epic-status.md` | Escalation evidence files | Display escalation history |
| `agents/auditor.md` | All escalation evidence | Trend analysis across EPICs |
| `agents/lessons-extractor.md` | Escalation history | Extract lessons from PM decisions |

---

## MUST Rules

1. **ALWAYS pause auto-mode before notifying PM** -- never notify while still executing
2. **ALWAYS save progress before pausing** -- uncommitted work must be stashed
3. **ALWAYS include the 4 options (A/B/C/D)** in every auto-mode escalation notification
4. **ALWAYS include a recommendation** -- PM should not have to analyze from scratch
5. **ALWAYS track escalation count** per session -- budget enforcement is non-negotiable
6. **NEVER escalate non-escalation conditions** -- agent-resolvable issues must be handled silently
7. **NEVER resume auto-mode without PM response** -- escalation is blocking by definition
8. **NEVER exceed max_escalations_per_session without triggering E12** -- guardrail is mandatory
9. **ALWAYS store escalation evidence** -- every escalation produces a JSON file
10. **ALWAYS update epic-queue.yaml on pause** -- queue must reflect paused state
11. **NEVER auto-decide for PM on CRITICAL triggers** -- CRITICAL always requires human judgment
12. **ALWAYS restore stashed changes on resume** -- no work should be lost during escalation

---

**Last Updated:** 2026-02-24
