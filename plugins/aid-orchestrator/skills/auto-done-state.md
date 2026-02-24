# Auto-Mode DONE State Protocol

**Skill:** auto-done-state
**Dependencies:** epic-orchestration, epic-queue, auto-escalation, permission-sandwich

---

## TL;DR

This skill defines the **DONE state behavior for FIRST AID auto-mode** -- the autonomous
EPIC execution mode where the Orchestrator processes an approved queue without PM
involvement. In auto-mode, the DONE state makes release decisions automatically (no PM
ask), transitions to the next queued EPIC, and aggregates summary data across all EPICs
for a final session report when the queue completes.

**Key difference from manual DONE:** In manual mode, PM is asked about version bumps for
intermediate EPICs and sees each completion summary interactively. In auto-mode, the
Controller follows deterministic rules: intermediate EPICs defer bumps, last/standalone
EPICs bump mandatorily, and summaries accumulate silently until the session ends.

---

## Terminology

| Term | Meaning |
|------|---------|
| **Auto-mode DONE** | The DONE state when running under FIRST AID autonomous execution |
| **Release decision** | Whether to bump version files and create git tag/release |
| **Queue transition** | Moving from one completed EPIC to the next queued EPIC |
| **Summary aggregation** | Collecting per-EPIC metrics into a session-wide report |
| **Final session report** | The comprehensive report generated when the queue is empty or stopped |
| **EPIC position** | Whether an EPIC is standalone, intermediate, or last in the queue |

---

## 1. Auto-Mode DONE State Overview

The auto-mode DONE state extends the standard DONE state from `skills/epic-orchestration.md`
(Section 12). All standard DONE actions still execute in order. This skill defines the
**auto-mode overrides and additions** that replace PM-interactive steps with autonomous
decisions.

### 1.1 Standard DONE Actions (Preserved)

These actions from `skills/epic-orchestration.md` Section 12 execute identically in
auto-mode. They are listed here for completeness but are NOT redefined:

| Action | Description | Auto-Mode Change |
|--------|-------------|-----------------|
| Run file status update | Update frontmatter to `status: completed` | None |
| Branch merge | Merge `epic/{epic_id}` to base branch | None |
| EPIC file status update | Mark EPIC as "Completed" | None |
| Run archive | Move run file to `runs/archive/` | None |
| Active work update | Update `active-work.md` | None |
| Final report generation | Create `final_report.md` | Enhanced (Section 5) |
| POST-PROCESSING (Auditor) | Dispatch Auditor, store audit report | None |
| Qdrant metrics | Store EPIC-level metrics to Qdrant | None |
| Archive logic | Archive run, update counters, archive EPIC/Plan | None |
| Example EPIC extraction | Extract reusable patterns to Qdrant | None |

### 1.2 Auto-Mode Overrides

These DONE actions are modified or replaced in auto-mode:

| Action | Manual Mode | Auto-Mode |
|--------|------------|-----------|
| Release decision | PM asked for intermediate EPICs | Deterministic (Section 2) |
| Completion summary | Presented to PM interactively | Logged silently, aggregated (Section 5) |
| EPIC Queue check | Auto-pickup with status update | Auto-pickup with summary aggregation (Section 3) |
| Session end | N/A (single EPIC) | Permission restore + final report (Section 4) |

---

## 2. Release Decision Protocol (Auto-Mode)

In auto-mode, the Controller makes release decisions without PM interaction. The decision
is deterministic based on the EPIC's position in the queue.

### 2.1 EPIC Position Detection

```
DETECT_EPIC_POSITION(epic_id):

  1. Read .aid-o/04-engine/epic-queue.yaml
  2. Count EPICs with status "queued" (not including current "running" EPIC):
     remaining_queued = count(queue.entries WHERE status = "queued")
  3. Count total EPICs in the session:
     total_session = count(queue.entries WHERE status IN ["running", "queued", "completed"])
  4. Determine position:
     IF total_session == 1:
       → position = "standalone"
     ELIF remaining_queued == 0:
       → position = "last"
     ELSE:
       → position = "intermediate"
  5. RETURN position
```

### 2.2 Release Decision Matrix

| EPIC Position | Release Action | Version Bump | Git Tag | GitHub Release | PM Asked? |
|--------------|----------------|-------------|---------|----------------|-----------|
| **Standalone** (1 EPIC in queue) | Mandatory bump | Yes | Per `release-policy.yaml` `auto_tag` | Per `release-policy.yaml` `auto_release` | No |
| **Intermediate** (more EPICs queued) | Auto-DEFER | No | No | No | No |
| **Last** (no more EPICs queued) | Mandatory bump | Yes | Per `release-policy.yaml` `auto_tag` | Per `release-policy.yaml` `auto_release` | No |

### 2.3 Release Decision Algorithm

```
AUTO_RELEASE_DECISION(epic_id):

  1. Execute standard Release Sub-Phase Step 1 (detect version mismatch):
     → Read CHANGELOG, compare to version_files[]
     → IF no mismatch: skip release (same as manual mode)
     → IF no CHANGELOG version header: skip release (same as manual mode)

  2. IF mismatch detected (bump needed):
     a. position = DETECT_EPIC_POSITION(epic_id)

     b. IF position == "intermediate":
        → Auto-defer. No bump, no tag, no release.
        → Log to stage_log:
          {"state": "DONE", "action": "release", "bump_type": "deferred",
           "changelog_version": "{version}", "previous_version": "{previous}",
           "deferred": true, "reason": "Auto-mode: intermediate EPIC — version bump deferred",
           "epic_position": "intermediate", "remaining_queued": {N},
           "mode": "first_aid"}
        → Record in summary aggregation:
          deferred_bump: {epic_id: "{epic_id}", version: "{changelog_version}"}
        → Proceed to branch merge (action 1c in epic-orchestration.md)

     c. IF position == "standalone" OR position == "last":
        → Mandatory bump. Execute Release Sub-Phase Steps 5-9 from
          epic-orchestration.md without PM confirmation.
        → Step 5: Update all version_files[] to CHANGELOG version
        → Step 6: Commit version bump
        → Step 7: IF release-policy.yaml -> release.auto_tag == true:
          Create git tag automatically (no PM confirmation)
          ELSE: Skip tag
        → Step 8: IF release-policy.yaml -> release.auto_release == true:
          Create GitHub Release automatically (no PM confirmation)
          ELSE: Skip release
        → Step 9: Log release result to stage_log
        → Record in summary aggregation:
          version_bump: {epic_id: "{epic_id}", version: "{version}",
                         bump_type: "{major|minor|patch}", tag_created: true|false}

  3. Error handling (auto-mode specific):
     → IF version detection fails (malformed CHANGELOG, unparseable files):
       → Trigger escalation E15 per auto-escalation.md
       → Escalation pauses auto-mode, PM provides version info
       → After PM response, resume release sub-phase
     → IF git tag or gh release fails:
       → Log warning, continue (non-blocking, same as manual mode)
       → Do NOT escalate — tag/release failures are non-blocking
```

### 2.4 Deferred Bump Accumulation

When intermediate EPICs defer their version bump, the deferred state is tracked in
`auto-mode-state.yaml` so the last EPIC knows a bump is pending:

```yaml
# In auto-mode-state.yaml -> summary -> deferred_bumps
deferred_bumps:
  - epic_id: "E-20260224-0001"
    changelog_version: "1.2.0"
    deferred_at: "2026-02-24T14:30:00Z"
  - epic_id: "E-20260224-0002"
    changelog_version: "1.2.0"
    deferred_at: "2026-02-24T15:45:00Z"
```

When the last EPIC performs its mandatory bump, it picks up the latest CHANGELOG version
(which may have been updated by intermediate EPICs). The deferred_bumps list is included
in the final session report for traceability.

---

## 3. Queue Transition Protocol (Auto-Mode)

After all DONE actions complete for the current EPIC, the Controller transitions to the
next EPIC in the queue. This extends the EPIC Queue Check (action 10) from
`skills/epic-orchestration.md` with auto-mode summary aggregation.

### 3.1 Queue Transition Algorithm

```
AUTO_QUEUE_TRANSITION(completed_epic_id, completion_status):

  1. AGGREGATE current EPIC results into session summary (Section 5.1)

  2. COMPLETE current EPIC in queue:
     → Call epic-queue.complete(completed_epic_id, completion_status)
       - completion_status = "completed" (normal) or "failed" (aborted)

  3. CHECK guardrails before loading next EPIC:
     a. Read auto-session.json:
        → IF guardrail_breached == true (escalation budget exceeded):
          → Trigger E12 per auto-escalation.md
          → PM must decide: continue auto / switch manual / abort
          → IF PM says continue: reset guardrail, proceed to step 4
          → IF PM says manual or abort: STOP (no queue transition)
     b. Read epic-queue.yaml:
        → IF paused == true:
          → Log: "Queue paused, skipping auto-pickup"
          → Send Status Update (Slack Type G):
            "Queue paused. {completed_count} EPICs completed, {remaining} waiting."
          → STOP (no queue transition)
     c. IF completion_status == "failed":
        → Queue auto-pauses (safety guard from epic-queue.md)
        → Send Escalation (Slack Type A):
          "EPIC {completed_epic_id} failed. Queue auto-paused.
           {completed_count} EPICs completed, {remaining} remaining."
        → STOP (no queue transition)

  4. FIND next EPIC:
     → next_epic = epic-queue.next()
     → IF next_epic is null:
       → Queue empty. All EPICs processed.
       → Execute SESSION_COMPLETE protocol (Section 4)
       → STOP

  5. LOAD next EPIC:
     a. Mark next EPIC as running: epic-queue.start(next_epic.epic_id)
     b. Update auto-mode-state.yaml:
        - current_epic: next_epic.epic_id
        - current_epic_started_at: {ISO 8601 now}
        - epics_completed: {increment}
     c. Send Status Update (Slack Type G):
        "Auto-starting next EPIC: {next_epic.epic_id}
         Progress: {completed_count}/{total_count} EPICs"
     d. Log to stage_log:
        {"state": "DONE", "action": "queue_transition",
         "completed_epic": "{completed_epic_id}",
         "next_epic": "{next_epic.epic_id}",
         "queue_progress": "{completed}/{total}"}

  6. TRANSITION to IDLE state:
     → Controller begins new orchestration loop with next_epic.path
     → State: DONE -> IDLE (new EPIC loaded)
     → All standard IDLE actions execute (EPIC validation, branch creation,
       cross-project knowledge read)
```

### 3.2 Queue Transition Timing

The queue transition happens AFTER all DONE state actions complete for the current EPIC:

```
DONE state execution order:
  1. Run file status update
  2. Release sub-phase (with auto-mode decision from Section 2)
  3. Branch merge
  4. EPIC file status + archive
  5. Final report generation
  6. POST-PROCESSING (Auditor)
  7. Qdrant metrics
  8. Archive logic + final commit
  9. Example EPIC extraction
  10. Completion summary (logged, not presented — Section 5.1)
  11. Stage log final entry
  ─── everything above is standard DONE ───
  12. Queue transition (this section)
       → aggregate summary
       → check guardrails
       → find next EPIC
       → load and start, OR session complete
```

### 3.3 Branch Management Across EPICs

Each EPIC creates its own branch in the IDLE state (`epic/{epic_id}`). The previous
EPIC's branch is merged and deleted during its DONE state (action 1c). The next EPIC
starts with a clean working tree on the base branch.

```
EPIC 1: epic/E-001 → merge to main → delete epic/E-001
EPIC 2: epic/E-002 (branched from main, which now includes EPIC 1) → merge → delete
EPIC 3: epic/E-003 (branched from main, which now includes EPICs 1+2) → merge → delete
```

If the branch merge for the current EPIC fails (merge conflict), it escalates to PM
per the standard DONE behavior. Auto-mode pauses until PM resolves the conflict.

---

## 4. Session Complete Protocol

When the queue is empty (no more EPICs with status "queued") or the session is stopped,
the Controller executes the session completion sequence.

### 4.1 Session Complete Trigger Conditions

| Condition | Trigger |
|-----------|---------|
| Queue empty | `epic-queue.next()` returns null after last EPIC completes |
| PM aborts queue | PM chooses "abort" at an escalation point |
| PM switches to manual | PM chooses "continue-manual" at an escalation point |
| All EPICs failed | Queue auto-pauses after failure (handled by Section 3.1 step 3c) |

### 4.2 Session Complete Sequence

```
SESSION_COMPLETE():

  1. GENERATE final session report (Section 5.2):
     → Read auto-mode-state.yaml summary data
     → Compile cross-EPIC statistics
     → Write to .aid-o/04-engine/evidence/auto-session-report-{session_id}.md

  2. RESTORE permissions:
     → Execute RESTORE_PERMISSIONS from skills/permission-sandwich.md (Section 4)
     → This restores .claude/settings.json from the backup
     → If restore fails: warn PM (non-blocking per permission-sandwich.md)

  3. UPDATE auto-mode-state.yaml:
     session_status: "completed"
     completed_at: {ISO 8601 now}
     summary:
       ... (finalized summary data)

  4. UPDATE epic-queue.yaml:
     → Verify all processed EPICs have correct final status
     → paused flag remains as-is (true if aborted, false if completed normally)

  5. SEND final session notification:
     → Via Slack (Type G - Status Update) or chat fallback
     → See Section 5.3 for notification format

  6. PRESENT final session report to PM:
     → Display the session report in conversation (or Slack)
     → This is the ONLY PM-facing summary for the entire auto-mode session
     → The PM sees this after all EPICs have been processed

  7. LOG session completion:
     → stage_log.jsonl (in the last EPIC's evidence directory):
       {"state": "DONE", "action": "session_complete",
        "session_id": "{session_id}",
        "total_epics": {N}, "completed": {N}, "failed": {N},
        "duration_minutes": {N}}

  8. TRANSITION to terminal IDLE:
     → Controller returns to IDLE state with no active EPIC
     → Auto-mode is fully complete
```

### 4.3 Partial Session Complete

If the session ends early (PM abort or manual takeover), the report still generates
with whatever data is available:

```
PARTIAL_SESSION_COMPLETE(reason):

  1. GENERATE partial session report:
     → Include all completed EPIC data
     → Mark current EPIC status as "aborted" or "manual_takeover"
     → List remaining queued EPICs as "not_started"

  2. RESTORE permissions (same as full completion)

  3. IF reason == "abort":
     → Queue remains paused
     → PM must manually resume when ready

  4. IF reason == "manual_takeover":
     → Current EPIC continues in manual mode
     → Queue paused until current EPIC finishes + PM resumes
     → Session report notes: "Session interrupted — continuing {epic_id} manually"
```

---

## 5. Summary Aggregation

Auto-mode tracks metrics across all EPICs in the session. Data is accumulated after each
EPIC completes and compiled into a final report when the session ends.

### 5.1 Per-EPIC Summary Collection

After each EPIC's DONE state completes (before queue transition), the Controller extracts
metrics from the EPIC's evidence and appends them to `auto-mode-state.yaml`:

```
AGGREGATE_EPIC_SUMMARY(epic_id, run_id):

  1. READ evidence files:
     → plan_progress.json → step counts, completion status
     → gates_report.json → gate results, retry counts
     → stage_log.jsonl → timing data, state transitions
     → final_report.md → duration, escalation count
     → escalations/ directory → escalation details (if any)

  2. EXTRACT per-EPIC metrics:
     epic_summary:
       epic_id: "{epic_id}"
       run_id: "{run_id}"
       status: "completed|failed|aborted"
       steps_total: {N}
       steps_completed: {N}
       steps_failed: {N}
       steps_skipped: {N}
       gates_total: {N}
       gates_passed: {N}
       gates_failed: {N}
       gate_retries: {N}
       gates_skipped_by_pm: {N}
       escalations: {N}
       escalation_triggers: ["E1", "E4", ...]
       escalation_resolutions: ["fix", "skip", ...]
       duration_minutes: {N}
       started_at: "{ISO 8601}"
       completed_at: "{ISO 8601}"
       version_bump:
         performed: true|false
         version: "{version}" | null
         bump_type: "major|minor|patch|deferred"
         tag_created: true|false
       key_artifacts: ["path/to/file1", "path/to/file2", ...]
       evidence_path: ".aid-o/04-engine/evidence/{epic_id}/{run_id}/"

  3. APPEND to auto-mode-state.yaml -> epic_summaries[]:
     → This array grows with each completed EPIC

  4. UPDATE running totals in auto-mode-state.yaml -> summary:
     total_epics: {increment}
     completed_epics: {increment if completed}
     failed_epics: {increment if failed}
     total_steps: {+= steps_total}
     successful_steps: {+= steps_completed}
     failed_steps: {+= steps_failed}
     total_escalations: {+= escalations}
     escalations_by_type:
       E1: {+= count of E1 triggers}
       E4: {+= count of E4 triggers}
       ...
     total_gate_retries: {+= gate_retries}
     gates_skipped: {+= gates_skipped_by_pm}
     version_bumps:
       - {epic: "{epic_id}", version: "{version}", type: "{bump_type}"}
     duration_minutes: {sum of all EPIC durations}
```

### 5.2 Final Session Report

When the session completes (Section 4), the Controller generates a comprehensive report.

#### 5.2.1 Report Location

```
.aid-o/04-engine/evidence/auto-session-report-{session_id}.md
```

Where `{session_id}` matches the session ID from `auto-session.json`
(format: `AUTO-YYYYMMDD-HHmmss`).

#### 5.2.2 Report Template

```markdown
# FIRST AID Session Report: {session_id}

## Session Overview
- **Session ID:** {session_id}
- **Status:** {completed|partial|aborted}
- **Started:** {started_at}
- **Completed:** {completed_at}
- **Duration:** {total_duration_minutes} minutes
- **EPICs processed:** {completed_epics}/{total_epics}

## Summary

| Metric | Value |
|--------|-------|
| Total EPICs | {total_epics} |
| Completed | {completed_epics} |
| Failed | {failed_epics} |
| Total steps | {total_steps} |
| Steps succeeded | {successful_steps} |
| Steps failed | {failed_steps} |
| Gate retries | {total_gate_retries} |
| Gates skipped (PM) | {gates_skipped} |
| Escalations | {total_escalations} |
| Estimated LLM cost | ${estimated_llm_cost_usd} |

## Version Bumps

| EPIC | Version | Bump Type | Tag | Release |
|------|---------|-----------|-----|---------|
{for each version_bump in version_bumps:}
| {epic_id} | {version} | {bump_type} | {tag_created ? "Yes" : "No"} | {release_created ? "Yes" : "No"} |

### Deferred Bumps
{for each deferred_bump in deferred_bumps:}
- {epic_id}: v{changelog_version} deferred at {deferred_at}
  (picked up by final EPIC bump)

## Escalations

| # | EPIC | Trigger | Severity | Resolution | Latency |
|---|------|---------|----------|------------|---------|
{for each escalation in all_escalations:}
| {N} | {epic_id} | {trigger_id} | {severity} | {resolution} | {response_latency_min}m |

### Escalation Budget
- Budget: {max_escalations_per_session} (session limit)
- Used: {total_escalations}
- PM-tuned max: {pm_tuned_max | "none"}
- Guardrail breached: {yes|no}

## Per-EPIC Breakdown

{for each epic_summary in epic_summaries:}
### {epic_id}
- **Status:** {status}
- **Duration:** {duration_minutes} minutes
- **Steps:** {steps_completed}/{steps_total} ({steps_failed} failed, {steps_skipped} skipped)
- **Gates:** {gates_passed}/{gates_total} ({gate_retries} retries)
- **Escalations:** {escalations}
- **Version bump:** {version_bump.performed ? "v" + version_bump.version + " (" + version_bump.bump_type + ")" : "deferred"}
- **Evidence:** {evidence_path}
- **Key artifacts:**
{for each artifact in key_artifacts:}
  - {artifact}

## Evidence Locations
{for each epic_summary in epic_summaries:}
- {epic_id}: {evidence_path}

Session report: .aid-o/04-engine/evidence/auto-session-report-{session_id}.md
```

#### 5.2.3 LLM Cost Estimation

The estimated LLM cost is calculated using the same estimation model from
`skills/epic-orchestration.md` Section 12 (EPIC-Level Metrics to Qdrant):

```
ESTIMATE_LLM_COST(session_summary):

  1. For each EPIC:
     → Read per-step token profile metrics from Qdrant (if available)
       OR estimate from stage_log.jsonl timing data
     → Sum estimated tokens across all steps

  2. Apply cost model:
     → ops_per_minute ~ 3 (from BMK-001 baseline)
     → avg_tokens_per_op ~ 2600
     → estimated_tokens = duration_seconds / 60 * ops_per_minute * avg_tokens_per_op
     → estimated_cost = estimated_tokens * cost_per_token
       (approximate: $0.015 per 1K input tokens, $0.075 per 1K output tokens,
        blended ~ $0.03 per 1K tokens for estimation purposes)

  3. Store in summary:
     estimated_llm_cost_usd: {total across all EPICs}
```

This is an ESTIMATE, not exact billing. It provides a useful order-of-magnitude figure
for session cost awareness.

### 5.3 Final Session Notification

#### Slack Notification (Type G - Status Update)

```
:checkered_flag: *FIRST AID Session Complete*
━━━━━━━━━━━━━━━━
*Session:* {session_id}
*Duration:* {total_duration_minutes} minutes
*EPICs:* {completed_epics}/{total_epics} completed
  {failed_epics > 0 ? ":warning: {failed_epics} failed" : ""}

*Summary:*
• Steps: {successful_steps}/{total_steps} succeeded
• Gates: {total_gate_retries} retries, {gates_skipped} skipped
• Escalations: {total_escalations}/{max_escalations_per_session} budget
• Version: {last_version_bump ? "v" + version : "no bump"}
• Cost: ~${estimated_llm_cost_usd}

:file_folder: Report: auto-session-report-{session_id}.md
:white_check_mark: Permissions restored to pre-auto-mode state.
```

#### Chat Fallback Notification

```
FIRST AID SESSION COMPLETE
====================================
Session: {session_id}
Duration: {total_duration_minutes} minutes
EPICs: {completed_epics}/{total_epics} completed

Summary:
  Steps: {successful_steps}/{total_steps} succeeded
  Gates: {total_gate_retries} retries, {gates_skipped} skipped
  Escalations: {total_escalations}/{max_escalations_per_session} budget
  Version: {last_version_bump ? "v" + version : "no bump"}
  Cost: ~${estimated_llm_cost_usd}

Report: .aid-o/04-engine/evidence/auto-session-report-{session_id}.md
Permissions restored to pre-auto-mode state.
====================================

What's next?
  1. Review results -- read the session report for details
  2. Check quality -- run /aid-audit for a project health assessment
  3. Start new work -- run /aid-brainstorm or create a new EPIC queue
  4. Analyze performance -- run /aid-analytics to see bottlenecks
```

---

## 6. auto-mode-state.yaml Structure

The session state file tracks all auto-mode data. It is created during FIRST_AID_INIT
(by `skills/permission-sandwich.md`) and updated throughout the session.

### 6.1 Full Schema

```yaml
# Auto-Mode Session State
# Created by: /aid-first-aid command
# Updated by: Controller during auto-mode execution
# Location: .aid-o/04-engine/auto-mode-state.yaml

session_id: "AUTO-20260224-140000"
session_status: "running"  # running | completed | aborted | manual_takeover
started_at: "2026-02-24T14:00:00Z"
completed_at: null          # Set on session completion

current_epic: "E-20260224-0001"
current_epic_started_at: "2026-02-24T14:00:00Z"

# Permissions tracking (managed by permission-sandwich.md)
permissions:
  backup_path: ".aid-o/03-config/permissions-backup.json"
  applied_permissions: [...]
  learned_permissions: [...]

# Summary aggregation (updated after each EPIC completes)
summary:
  total_epics: 3
  completed_epics: 2
  failed_epics: 0
  total_steps: 24
  successful_steps: 22
  failed_steps: 1
  skipped_steps: 1
  total_escalations: 1
  escalations_by_type:
    E4: 1
  total_gate_retries: 5
  gates_skipped: 0
  version_bumps:
    - epic: "E-20260224-0003"
      version: "1.2.0"
      type: "minor"
  deferred_bumps:
    - epic_id: "E-20260224-0001"
      changelog_version: "1.2.0"
      deferred_at: "2026-02-24T14:30:00Z"
    - epic_id: "E-20260224-0002"
      changelog_version: "1.2.0"
      deferred_at: "2026-02-24T15:45:00Z"
  duration_minutes: 120
  estimated_llm_cost_usd: 4.50

# Per-EPIC detail (appended after each EPIC completes)
epic_summaries:
  - epic_id: "E-20260224-0001"
    run_id: "20260224T140000Z"
    status: "completed"
    steps_total: 8
    steps_completed: 8
    steps_failed: 0
    steps_skipped: 0
    gates_total: 4
    gates_passed: 4
    gates_failed: 0
    gate_retries: 2
    gates_skipped_by_pm: 0
    escalations: 0
    escalation_triggers: []
    escalation_resolutions: []
    duration_minutes: 45
    started_at: "2026-02-24T14:00:00Z"
    completed_at: "2026-02-24T14:45:00Z"
    version_bump:
      performed: false
      version: null
      bump_type: "deferred"
      tag_created: false
    key_artifacts:
      - "src/auth/middleware.ts"
      - "src/auth/session.ts"
    evidence_path: ".aid-o/04-engine/evidence/E-20260224-0001/20260224T140000Z/"

  - epic_id: "E-20260224-0002"
    # ... same structure ...
```

### 6.2 State File Writes

The Controller writes to `auto-mode-state.yaml` at these points:

| Event | Fields Updated |
|-------|---------------|
| Session start (FIRST_AID_INIT) | `session_id`, `started_at`, `session_status`, `permissions` |
| EPIC starts | `current_epic`, `current_epic_started_at` |
| EPIC completes (DONE state) | `epic_summaries[]` (append), `summary` (update totals) |
| Escalation occurs | (Tracked in `auto-session.json`, not here) |
| Version bump performed | `summary.version_bumps[]` (append) |
| Version bump deferred | `summary.deferred_bumps[]` (append) |
| Session completes | `session_status`, `completed_at`, finalized `summary` |

---

## 7. Integration with Existing DONE Actions

### 7.1 Insertion Point in DONE State

The auto-mode logic integrates into the DONE state flow at specific points. The Controller
checks `auto-session.json` or `auto-mode-state.yaml` to determine if it is in auto-mode.

```
DONE_STATE_WITH_AUTO_MODE():

  mode = detect_execution_mode()
  # Mode is "manual" (default) or "first_aid" (auto)
  # Detection: check if auto-mode-state.yaml exists AND session_status == "running"

  1-1a. Run file status update (unchanged)

  1b. RELEASE SUB-PHASE:
      IF mode == "first_aid":
        → Use AUTO_RELEASE_DECISION (Section 2.3) instead of PM interaction
        → Step 4 from epic-orchestration.md is replaced entirely
      ELSE:
        → Standard release sub-phase (PM asked for intermediates)

  1c. Branch merge (unchanged)
  1d-1f. EPIC status, archive, active-work (unchanged)

  2. Final report:
      IF mode == "first_aid":
        → Same report generation, but enhanced with session context
        → Include "EPIC {N} of {total} in auto-mode session {session_id}"
      ELSE:
        → Standard report

  3. POST-PROCESSING (unchanged)
  4. Qdrant metrics (unchanged)
  5-6. Archive logic (unchanged)
  7. Example EPIC extraction (unchanged)

  8. COMPLETION SUMMARY:
      IF mode == "first_aid":
        → Do NOT present to PM interactively
        → Log summary to auto-mode-state.yaml (AGGREGATE_EPIC_SUMMARY)
        → Send brief Slack status update only:
          "EPIC {epic_id} complete ({N}/{total}).
           Steps: {completed}/{total}. Next: {next_epic_id | 'session complete'}"
      ELSE:
        → Present interactive summary per epic-orchestration.md

  9. EPIC QUEUE CHECK:
      IF mode == "first_aid":
        → Execute AUTO_QUEUE_TRANSITION (Section 3.1)
        → Includes guardrail checks, summary aggregation, next EPIC load
      ELSE:
        → Standard epic-queue.md auto-pickup protocol

  10. Final stage log entry (unchanged)
```

### 7.2 Mode Detection

```
DETECT_EXECUTION_MODE():

  1. Check for auto-mode-state.yaml:
     path = ".aid-o/04-engine/auto-mode-state.yaml"
     IF file does not exist: RETURN "manual"

  2. Read session_status field:
     IF session_status == "running": RETURN "first_aid"
     IF session_status == "manual_takeover": RETURN "manual"
     IF session_status in ["completed", "aborted"]: RETURN "manual"

  3. Fallback: RETURN "manual"
```

### 7.3 Curator Findings in Auto-Mode

Curator findings are processed in CURATOR_RESOLVE state (before PM_APPROVAL, before
DONE). In auto-mode, curator findings route to agents for auto-fix as they do in manual
mode. This behavior is already defined in `skills/epic-orchestration.md` Section 10 and
is preserved without modification.

The auto-mode DONE state does NOT change curator handling. It only affects the release
decision, completion summary delivery, and queue transition.

---

## 8. Error Handling

### 8.1 Error Matrix

| Error | Auto-Mode Response | Escalation? |
|-------|-------------------|-------------|
| CHANGELOG version unreadable | Escalate E15 | Yes |
| Version file update fails | Escalate E15 | Yes |
| Git tag creation fails | Log warning, continue | No |
| GitHub Release creation fails | Log warning, continue | No |
| epic-queue.yaml unreadable | Log error, STOP session | No (session ends) |
| auto-mode-state.yaml write fails | Log warning, continue in memory | No |
| Branch merge conflict | Escalate per standard DONE | Yes |
| Auditor dispatch fails | Log warning, continue | No |
| Permission restore fails | Warn PM, continue | No |
| Qdrant unavailable | Skip metric writes, continue | No |

### 8.2 Session Recovery

If the Controller crashes mid-session, the next startup detects the state:

1. `permissions-backup.json` exists -> crash recovery per `skills/permission-sandwich.md`
2. `auto-mode-state.yaml` with `session_status: "running"` -> stale session detected
3. The Controller does NOT auto-resume. It restores permissions and reports:
   "Previous auto-mode session {session_id} did not complete cleanly.
    {completed_epics} EPICs completed before crash.
    Review auto-mode-state.yaml for details.
    To resume, re-queue remaining EPICs and run /aid-first-aid again."

---

## 9. Integration Points

### 9.1 Called By

| Caller | When | Notes |
|--------|------|-------|
| `skills/epic-orchestration.md` (DONE state) | After PM_APPROVAL in auto-mode | Release decision + queue transition |
| `commands/aid-run-epic.md` | Auto-mode EPIC execution | Session lifecycle management |

### 9.2 Calls To

| Target | When | Purpose |
|--------|------|---------|
| `skills/epic-queue.md` | Queue transition | `complete()`, `next()`, `start()` operations |
| `skills/auto-escalation.md` | Guardrail check at EPIC boundary | E12 trigger if budget exceeded |
| `skills/permission-sandwich.md` | Session complete | Restore permissions |
| `skills/slack-mcp.md` | Session complete notification | Type G status update |
| `skills/epic-orchestration.md` | Release sub-phase | Version bump execution |

### 9.3 Consumed By

| Consumer | What it reads | Purpose |
|----------|--------------|---------|
| `commands/aid-epic-status.md` | `auto-mode-state.yaml` | Display session progress |
| `agents/auditor.md` | Session report | Cross-EPIC trend analysis |
| `skills/analytics.md` | `auto-mode-state.yaml` summary | Performance analytics |

---

## 10. MUST Rules

1. **ALWAYS execute all standard DONE actions** before auto-mode additions -- auto-mode extends, never replaces, the base DONE flow
2. **NEVER ask PM about release decisions in auto-mode** -- the decision is deterministic (Section 2.2)
3. **ALWAYS defer version bump for intermediate EPICs** -- only standalone or last EPICs bump
4. **ALWAYS perform mandatory bump for last/standalone EPICs** -- deferral is not an option
5. **ALWAYS aggregate summary data after each EPIC** -- partial data is still valuable if the session stops early
6. **ALWAYS check guardrails before loading the next EPIC** -- escalation budget is enforced at EPIC boundaries
7. **ALWAYS restore permissions when the session ends** -- regardless of how it ends (complete, abort, crash)
8. **ALWAYS generate a final session report** -- even for partial sessions (one EPIC completed is still reportable)
9. **NEVER skip the queue paused check** -- if PM paused the queue during execution, honor it
10. **NEVER auto-resume a crashed session** -- crash recovery restores permissions but does NOT continue execution
11. **ALWAYS write to auto-mode-state.yaml** at each checkpoint -- it is the crash-recovery data source
12. **ALWAYS include evidence paths** in the session report -- the PM must be able to find all artifacts

---

**Last Updated:** 2026-02-24
