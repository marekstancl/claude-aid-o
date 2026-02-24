---
name: aid-first-aid
description: Launch FIRST AID autonomous orchestration mode — process EPIC queue without PM interaction
user_invocable: true
---

Launch **FIRST AID** (Fully Integrated Autonomous Development) mode — autonomous EPIC queue execution with elevated permissions, agent-driven decision-making, and escalation-only PM interaction.

The PM approves the EPIC queue before invocation. Once started, the Orchestrator processes every queued EPIC end-to-end: plan, execute, gate, merge, pick up next. PM is only contacted on escalation (16 defined triggers). Permissions are elevated for the duration and restored on completion.

This is the **top-level autonomous command** — it wraps the entire lifecycle: permission sandwich, mode flag management, queue iteration, and cross-EPIC summary reporting.

## Usage

```
/aid-first-aid                  # Start auto-mode with current queue
/aid-first-aid --resume         # Resume a paused/crashed session
/aid-first-aid --dry-run        # Validate queue and permissions without executing
```

**Examples:**
```
/aid-first-aid                  # Process all queued EPICs autonomously
/aid-first-aid --resume         # Resume from saved progress after crash or /aid-stop
/aid-first-aid --dry-run        # Preview what would happen
```

## Prerequisites

- `.aid-o/` workspace must exist (run `/aid-init` if not)
- EPIC queue must have at least one entry with status `queued` (use `/aid-epic-queue add`)
- `.claude/settings.json` must exist and be valid JSON (or will be auto-created)
- `permissions-auto.yaml` must exist (project, plugin defaults, or will be generated)

## Core Instruction

**Read the following skills BEFORE starting the loop:**
1. `skills/permission-sandwich.md` — permission backup, elevation, restore, crash recovery
2. `skills/auto-escalation.md` — 16 escalation triggers, pause/resume, PM notification
3. `skills/epic-orchestration.md` — state machine (used by `/aid-run-epic` under the hood)
4. `skills/epic-queue.md` — queue operations, auto-pickup, safety guards

**Read `skills/slack-mcp.md` for PM communication.** Escalation notifications and the
final summary report use the Slack MCP protocol with chat fallback.

---

## State Machine

FIRST AID has its own state machine that wraps the per-EPIC orchestration loop.
The per-EPIC execution delegates to `/aid-run-epic` logic (the 11-state machine
from `skills/epic-orchestration.md`).

```
FIRST_AID_INIT → QUEUE_PROCESSING → [per-EPIC: IDLE→...→DONE] → QUEUE_ADVANCE → FIRST_AID_COMPLETE
                                                                       ↑               |
                                                                       └── more EPICs ──┘
```

On each state transition, append to the session-level `stage_log.jsonl`.

---

### State: FIRST_AID_INIT

**Trigger:** `/aid-first-aid` command invocation.

**Actions:**

#### 1. Validate Workspace

```
1. Check .aid-o/ directory exists
   - IF not: ABORT with message:
     "Workspace not initialized. Run /aid-init first."

2. Check .aid-o/04-engine/ directory exists
   - IF not: create it (mkdir -p .aid-o/04-engine/)
```

#### 2. Handle --dry-run Flag

```
IF $ARGUMENTS contains "--dry-run":
  1. Run all validation checks (steps 3-5) without side effects
  2. Display results:
     "DRY RUN — FIRST AID Validation
      ====================================
      Queue:       {N} EPICs queued ({epic_ids})
      Permissions: {source} ({allow_count} allow, {deny_count} deny)
      Settings:    .claude/settings.json ({status: valid|missing|invalid})
      Backup:      {none|orphaned — recovery needed}
      Mode state:  {none|active session exists}

      Ready to start: {YES|NO — {reason}}"
  3. STOP (do not proceed to execution)
```

#### 3. Handle --resume Flag

```
IF $ARGUMENTS contains "--resume":
  → Jump to RESUME_SESSION protocol (see Section: Resume After /aid-stop)
  → Do NOT run fresh initialization
```

#### 4. Check for Active Session

```
1. Read .aid-o/04-engine/auto-mode-state.yaml
   - IF file exists AND session.mode in ["auto", "paused"]:
     → Active session detected.
     → Present to PM:
       "An active FIRST AID session exists.
        Session: {session_id}
        Mode: {mode}
        Progress: {epics_completed}/{epics_total} EPICs
        Current: {current_epic_id} at state {current_state}

        Options:
        A) Resume this session (/aid-first-aid --resume)
        B) Abort this session and start fresh
        C) Cancel (do nothing)"
     → Wait for PM response.
     → OPTION A: execute resume protocol
     → OPTION B: abort existing session (set mode: "aborted", restore
       permissions if backup exists), then continue fresh init
     → OPTION C: STOP
```

#### 5. Validate EPIC Queue

```
1. Read .aid-o/04-engine/epic-queue.yaml
   - IF file does not exist:
     → ABORT with message:
       "No EPIC queue found. Add EPICs to the queue first:
        /aid-epic-queue add <epic-path>"
   - IF file exists but is not valid YAML:
     → ABORT with message:
       "Queue file is corrupted: {parse_error}
        Fix .aid-o/04-engine/epic-queue.yaml manually."

2. Filter queue entries where status == "queued"
   - IF none:
     → ABORT with message:
       "Queue is empty (no EPICs with status 'queued').
        Add EPICs: /aid-epic-queue add <epic-path>"

3. Validate each queued EPIC:
   For each entry with status == "queued":
     a. Check EPIC file exists at entry.path
        - IF not: mark entry as "failed" in queue, log warning
     b. Check EPIC file has required sections (Goal, Scope, Constraints)
        - IF not: mark entry as "failed" in queue, log warning
   After validation:
   - IF all queued EPICs failed validation:
     → ABORT with message:
       "All queued EPICs failed validation. Fix EPIC files and try again."
   - IF some failed:
     → Log warnings for failed ones
     → Continue with remaining valid EPICs

4. Build queue snapshot:
   valid_epics = [list of valid queued epic_ids, sorted by priority then added_at]
```

#### 6. Temp File Cleanup

Per `skills/permission-sandwich.md` Section 5.3:

```
TEMP_FILE_CLEANUP:
  IF .aid-o/03-config/permissions-backup.json.tmp exists:
    → Delete it
    → Log: "Cleaned up orphaned backup temp file"
  IF .claude/settings.json.tmp exists:
    → Delete it
    → Log: "Cleaned up orphaned settings temp file"
```

#### 7. Execute Permission Sandwich — Backup

Per `skills/permission-sandwich.md` Section 1:

```
BACKUP_PERMISSIONS:
  1. Read .claude/settings.json
     - IF missing: create minimal default {"permissions": {"allow": []}}
     - IF invalid JSON: ABORT
  2. Check for orphaned backup (.aid-o/03-config/permissions-backup.json)
     - IF exists: execute CRASH_RECOVERY per Section 5 of permission-sandwich.md
  3. Atomic write backup:
     a. Write to .aid-o/03-config/permissions-backup.json.tmp
     b. Validate temp file
     c. Rename to .aid-o/03-config/permissions-backup.json
     d. Verify content matches original
  4. Log: {"state": "FIRST_AID_INIT", "action": "permissions_backup",
     "backup_path": ".aid-o/03-config/permissions-backup.json",
     "original_allow_count": {N}}
```

**On backup failure:** ABORT. Do not proceed. Per permission-sandwich.md MUST Rule 1:
"ALWAYS backup before elevating. No backup means no restore."

#### 8. Execute Permission Sandwich — Elevate

Per `skills/permission-sandwich.md` Section 2:

```
ELEVATE_PERMISSIONS:
  1. Resolve permissions-auto.yaml (project → defaults → generate)
  2. Parse allow[] + learned[] → effective_allow
  3. Validate against hard-deny list (Section 3) → remove violations
  4. Atomic write elevated .claude/settings.json:
     a. Preserve existing settings structure
     b. Replace permissions.allow[] with effective_allow
     c. Write via temp file + rename
  5. Log: {"state": "FIRST_AID_INIT", "action": "permissions_elevated",
     "source": "{project|defaults|generated}",
     "entries_before": {N}, "entries_after": {M},
     "hard_deny_removed": {count}}
```

#### 9. Initialize Auto-Mode State

Create `.aid-o/04-engine/auto-mode-state.yaml`:

```yaml
session:
  session_id: "FA-{YYYYMMDDTHHMMSSZ}"
  mode: "auto"
  started_at: "{ISO 8601}"
  started_by: "pm"

  queue_snapshot:
    - "{epic_id_1}"
    - "{epic_id_2}"

  permissions:
    backup_path: ".aid-o/03-config/permissions-backup.json"
    elevated_at: "{ISO 8601}"
    source: "{project|defaults|generated}"
    applied_permissions: [{list of effective_allow entries}]
    applied_permissions_count: {N}
    learned_permissions: []

  escalation:
    budget: 3
    count: 0
    history: []

  progress:
    current_epic_id: null
    current_step_id: null
    current_state: "FIRST_AID_INIT"
    epics_completed: 0
    epics_total: {len(valid_epics)}

  aggregate:
    epics_completed: 0
    epics_failed: 0
    epics_deferred_release: 0
    total_steps_executed: 0
    total_steps_skipped: 0
    total_gate_runs: 0
    total_gate_retries: 0
    total_escalations: 0
    total_curator_proposals: 0
    total_curator_implemented: 0
    total_curator_rejected: 0
    total_curator_deferred: 0
    total_lessons_learned: 0
    version_bumps: []
    total_duration_seconds: 0
    per_epic: []
```

#### 10. Display FIRST AID Banner

```
 _______ _____ ____   _____ _______      _    _____ _____
|  _____|_   _|  _ \ / ____|__   __|    / \  |_   _|  __ \
| |__     | | | |_) | (___    | |      / _ \   | | | |  | |
|  __|    | | |  _ < \___ \   | |     / ___ \  | | | |  | |
| |      _| |_| |_) |____) |  | |    / /   \ \_| |_| |__| |
|_|     |_____|____/|_____/   |_|   /_/     \_\_____|_____/

Fully Integrated Autonomous Development
====================================
Session:      {session_id}
EPICs queued: {count}
Permissions:  Elevated ({source}, {allow_count} entries)
Escalation:   Budget {max_escalations_per_session}

Queue:
  1. {epic_id_1} ({priority}) — {title}
  2. {epic_id_2} ({priority}) — {title}

Starting autonomous execution...
====================================
```

**Send Slack Status Update (Type G):**
`:rocket: FIRST AID started — {count} EPICs queued. Session {session_id}.`

#### 11. Create Session Evidence Directory

```
mkdir -p .aid-o/04-engine/evidence/FIRST-AID-{session_id}/
```

Save initial session state to `session-init.json` in this directory.

**Transition:** QUEUE_PROCESSING

**Evidence:** `session-init.json`, `stage_log.jsonl` entries.

---

### State: QUEUE_PROCESSING

**Trigger:** Transition from FIRST_AID_INIT, or from QUEUE_ADVANCE (next EPIC).

**Actions:**

#### 1. Read Mode Flag

```
READ_MODE:
  1. Read .aid-o/04-engine/auto-mode-state.yaml → session.mode
  2. IF mode != "auto":
     → Session was stopped or aborted externally
     → Transition to FIRST_AID_COMPLETE (with current progress)
  3. IF mode == "auto": continue
```

#### 2. Select Next EPIC

```
1. Read .aid-o/04-engine/epic-queue.yaml (from disk, not cached)
2. Call next() logic from skills/epic-queue.md:
   → Filter status == "queued"
   → Sort by priority (critical > high > medium > low), then added_at (FIFO)
   → Return first entry
3. IF no queued EPIC found:
   → Transition to FIRST_AID_COMPLETE
4. IF queued EPIC found:
   → Call start(epic_id) — set status: "running", started_at: now
   → Update auto-mode-state.yaml:
     session.progress.current_epic_id = epic_id
     session.progress.current_state = "EXECUTING"
```

#### 3. Check Escalation Budget Guardrail

Per `skills/auto-escalation.md` Section 8:

```
1. Read session.escalation.count from auto-mode-state.yaml
2. IF count >= session.escalation.budget:
   → Trigger E12 (guardrail breached)
   → Execute escalation protocol per skills/auto-escalation.md Section 4
   → PM decides:
     a. "Continue auto with raised limit" → update budget, resume
     b. "Continue manual" → transition to manual mode, exit auto
     c. "Abort queue" → transition to FIRST_AID_COMPLETE (aborted)
3. IF count < budget: proceed
```

#### 4. Execute EPIC

Delegate to the `/aid-run-epic` orchestration loop. The Controller runs the full
11-state machine from `skills/epic-orchestration.md` with the following auto-mode
overrides:

```
EXECUTE_EPIC(epic_id):
  1. Load EPIC file from queue entry path
  2. Run /aid-run-epic logic with auto-mode context:
     - The Controller reads session.mode at each decision point (PLAN_REVIEW,
       PHASE_CHECK, PM_APPROVAL, DONE) per Section 5.3 of architect design
     - Auto-mode decision behaviors are defined in step_1_architect output,
       Section 1 (Decision Point Mapping)
     - Escalation triggers follow skills/auto-escalation.md
     - Permission learning runs at each PHASE_CHECK per skills/permission-sandwich.md
  3. On EPIC completion (DONE state reached):
     → The DONE state handles: release, merge, Curator, Auditor, memory indexing
     → auto-mode-specific DONE behaviors apply (auto-defer intermediate release,
       auto-approve merge, etc.)
  4. EPIC result: "completed" or "failed" or "aborted"
```

**Key auto-mode overrides within the per-EPIC loop:**

| Decision Point | Manual Behavior | Auto-Mode Behavior |
|----------------|----------------|-------------------|
| PLAN_REVIEW | PM approves GO/REVISE/ABORT | Auto-approve if validation passes; escalate on failure (E11) |
| PHASE_CHECK | Auto-decide or code-reviewer | Same + 1 extra "fresh approach" attempt; escalate after 3 total cycles (E1) |
| GATES | Auto-retry up to max_attempts | Identical to manual |
| PM_APPROVAL | PM approves APPROVE/REJECT/REVISE | Auto-approve; guardrail check on last EPIC (E12 if budget exceeded) |
| DONE release | PM chooses release now/defer | Auto-defer intermediate; mandatory bump on last EPIC |

**On escalation during EPIC execution:**

Per `skills/auto-escalation.md`:
1. Auto-mode pauses (mode set to "paused")
2. Progress saved (plan_progress.json, git stash if needed)
3. PM notified with 4 options: Fix (A) / Skip (B) / Abort (C) / Continue Manual (D)
4. On PM response:
   - Fix/Skip: resume auto-mode, continue from interrupted state
   - Abort: mark EPIC failed, transition to QUEUE_ADVANCE
   - Continue Manual: restore permissions, exit auto-mode, PM drives completion

**Evidence:** Per-EPIC evidence in `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`

**Transition:** QUEUE_ADVANCE (when EPIC reaches DONE or fails)

---

### State: QUEUE_ADVANCE

**Trigger:** Current EPIC completed or failed.

**Actions:**

#### 1. Record EPIC Result

```
1. Read EPIC result from completed DONE state
2. Update epic-queue.yaml:
   → Call complete(epic_id, result_status) from skills/epic-queue.md
   → result_status = "completed" | "failed"

3. Update auto-mode-state.yaml aggregate:
   a. per_epic[] += {
        epic_id, status, steps, gate_retries,
        escalations, duration_seconds, release_action
      }
   b. Increment aggregate counters from EPIC's final_report.md
   c. IF status == "completed": epics_completed += 1
   d. IF status == "failed": epics_failed += 1
```

#### 2. Handle Failed EPIC

Per `skills/epic-queue.md` Auto-Pickup Protocol step 4:

```
IF result_status == "failed":
  → Queue auto-pauses (safety guard):
    epic-queue.yaml → paused: true
  → Send Slack escalation:
    "EPIC {epic_id} failed. Queue auto-paused.
     {N} EPICs remaining. Session {session_id}.
     Investigate and /aid-epic-queue resume to continue."
  → Update auto-mode-state.yaml:
    session.mode = "paused"
    session.progress.current_state = "QUEUE_PAUSED_FAILURE"
  → Wait for PM:
    - "resume" → set paused: false, mode: auto, continue to next
    - "abort" → transition to FIRST_AID_COMPLETE
    - "continue-manual" → restore permissions, exit auto
```

#### 3. Check Queue

```
1. Read mode flag from disk (may have changed via /aid-stop)
   IF mode != "auto": → FIRST_AID_COMPLETE

2. Read epic-queue.yaml from disk
   IF paused == true: → wait (should not reach here, but safety check)

3. Filter status == "queued"
   IF count > 0:
     → Send Slack Status Update:
       ":arrows_counterclockwise: EPIC {completed_epic_id} done.
        Starting next: {next_epic_id}. ({remaining} remaining)"
     → Transition to QUEUE_PROCESSING (next iteration)
   IF count == 0:
     → Transition to FIRST_AID_COMPLETE
```

**Evidence:** Updated `auto-mode-state.yaml`, `epic-queue.yaml`.

---

### State: FIRST_AID_COMPLETE

**Trigger:** Queue empty (all EPICs processed), PM abort, /aid-stop, or mode change.

**Actions:**

#### 1. Determine Completion Status

```
1. Read auto-mode-state.yaml
2. Determine final status:
   - IF all queued EPICs completed: status = "completed"
   - IF PM aborted: status = "aborted"
   - IF /aid-stop invoked: status = "stopped"
   - IF unrecoverable error: status = "error"
```

#### 2. Restore Permissions

Per `skills/permission-sandwich.md` Section 4:

```
RESTORE_PERMISSIONS:
  1. Read .aid-o/03-config/permissions-backup.json
     - IF missing or corrupted: WARN PM (non-blocking), continue
  2. Atomic write restore:
     a. Write backup content to .claude/settings.json.tmp
     b. Validate temp file
     c. Rename to .claude/settings.json
  3. Delete backup file (.aid-o/03-config/permissions-backup.json)
  4. Log: {"state": "FIRST_AID_COMPLETE", "action": "permissions_restored",
     "entries_restored": {N}}
```

**Per permission-sandwich.md MUST Rule 5:** Restore is non-blocking. If it fails,
warn PM and continue with remaining completion actions.

#### 3. Generate Cross-EPIC Summary Report

Read aggregate data from `auto-mode-state.yaml` and compile:

```
FIRST AID Session Complete
====================================
Session:  {session_id}
Status:   {completed|aborted|stopped|error}
Duration: {started_at} -> {completed_at} ({total_duration})
Mode:     Autonomous

Queue Results:
  EPICs completed: {completed}/{total}
  EPICs failed:    {failed}

  +----------------------------+--------+-------+--------+----------+
  | EPIC                       | Steps  | Gates | Escal. | Release  |
  +----------------------------+--------+-------+--------+----------+
  | E-xxx (Title)              | 3/3    | 4/4   | 0      | deferred |
  | E-yyy (Title)              | 5/5    | 4/4   | 1      | deferred |
  | E-zzz (Title)              | 2/2    | 3/3   | 0      | v0.9.0   |
  +----------------------------+--------+-------+--------+----------+

Quality:
  Total gate runs:    {count} ({retries} retries)
  Escalations:        {count}/{budget} budget
  Curator proposals:  {implemented} implemented, {rejected} rejected, {deferred} deferred
  Lessons learned:    {count} new

Version:
  {version info or "No version bump (all deferred)" or "v{old} -> v{new}"}
  Files updated: {count}
  Git tag: {created|skipped}
  GitHub release: {created|skipped}

Permissions:
  Elevated at:  {timestamp}
  Restored at:  {timestamp}
  Source:       {project|defaults|generated}
  Learned:      {count} new permissions

Evidence:
  Per-EPIC: .aid-o/04-engine/evidence/{epic_id}/{run_id}/
  Session:  .aid-o/04-engine/evidence/FIRST-AID-{session_id}/

What's next?
  1. Review changes: git log, /aid-review
  2. Push to remote: git push (if not auto-pushed)
  3. Start new queue: /aid-epic-queue add, then /aid-first-aid
  4. Analyze performance: /aid-analytics
  5. Audit results: /aid-audit
====================================
```

#### 4. Save Summary Report

```
1. Write report to:
   .aid-o/04-engine/evidence/FIRST-AID-{session_id}/summary-report.md

2. Store session summary to Qdrant (if available):
   qdrant-store({
     type: "metric",
     metric_kind: "first_aid_session",
     project_name: "{project}",
     session_id: "{session_id}",
     epics_completed: N,
     epics_failed: M,
     escalations: K,
     duration_seconds: T
   })
```

#### 5. Update Auto-Mode State

```
1. Update .aid-o/04-engine/auto-mode-state.yaml:
   session.mode = "completed"  (or "aborted" or "stopped")
   session.completed_at = {now ISO 8601}
   DO NOT delete the file — useful for /aid-analytics and /aid-audit

2. Log: {"state": "FIRST_AID_COMPLETE", "action": "session_ended",
   "session_id": "{id}", "status": "{status}",
   "epics_completed": N, "total_duration": "{duration}"}
```

#### 6. Send Final Slack Notification

```
IF status == "completed":
  ":checkered_flag: FIRST AID complete — {completed}/{total} EPICs done.
   Session {session_id}. Duration: {duration}."
IF status == "aborted" or "stopped":
  ":stop_sign: FIRST AID {status} — {completed}/{total} EPICs done.
   Session {session_id}. {remaining} EPICs remain in queue."
```

#### 7. Present Report to PM

Display the summary report in the conversation (or via Slack Type F).

**Evidence:** `summary-report.md`, final `auto-mode-state.yaml`.

---

## Resume After /aid-stop

When `/aid-stop` is invoked during auto-mode, it sets `session.mode: "manual"` and
triggers permission restore. The queue and EPIC progress are preserved.

When `/aid-first-aid --resume` is invoked later:

```
RESUME_SESSION:
  1. Read .aid-o/04-engine/auto-mode-state.yaml
     - IF file does not exist:
       → ABORT: "No session to resume. Start fresh with /aid-first-aid."
     - IF session.mode == "completed":
       → ABORT: "Previous session completed. Start fresh with /aid-first-aid."
     - IF session.mode not in ["manual", "aborted", "paused", "stopped"]:
       → ABORT: "Cannot resume from mode '{mode}'."

  2. Present session state to PM:
     "Resume FIRST AID session?
      Session:     {session_id}
      Last status: {mode}
      Progress:    {epics_completed}/{epics_total} EPICs
      Last EPIC:   {current_epic_id} at state {current_state}
      Queue:       {remaining} EPICs remaining

      This will:
      - Re-elevate permissions (permission sandwich)
      - Resume from the next queued EPIC (or retry the paused one)
      - Continue autonomous execution

      Proceed? (yes/no)"

  3. IF PM confirms:
     a. Execute Permission Sandwich — Backup + Elevate (same as fresh init)
     b. Set session.mode = "auto"
     c. Set session.progress.current_state = "QUEUE_PROCESSING"
     d. Log: {"state": "FIRST_AID_RESUME", "action": "session_resumed",
        "session_id": "{id}", "epics_remaining": N}
     e. Display banner:
        "FIRST AID Resumed
         ====================================
         Session:   {session_id}
         Remaining: {N} EPICs
         Progress:  {completed}/{total}
         ====================================
         Continuing autonomous execution..."
     f. Transition to QUEUE_PROCESSING

  4. IF PM declines:
     → STOP (no changes)
```

---

## /aid-stop Integration

The `/aid-stop` command is the PM's mechanism to interrupt auto-mode at any time.
When invoked during a FIRST AID session:

```
AID_STOP (during FIRST AID):
  1. Set auto-mode-state.yaml → session.mode = "manual"
     (Controller reads mode from disk at each decision point — this takes
      effect at the next mode check, per Section 5.3 of architect design)

  2. Wait for current atomic operation to complete:
     - IF mid-step dispatch: wait for agent to finish current step
     - IF mid-gate: wait for current gate command to finish
     - This prevents partial state corruption

  3. Restore permissions:
     Execute RESTORE_PERMISSIONS per skills/permission-sandwich.md Section 4

  4. Save progress:
     → auto-mode-state.yaml already has latest progress
     → plan_progress.json has per-EPIC step progress
     → epic-queue.yaml has queue state

  5. Inform PM:
     "FIRST AID stopped.
      Session:  {session_id}
      Progress: {epics_completed}/{epics_total} EPICs
      Current:  {current_epic_id} at state {current_state}

      Permissions restored to pre-auto-mode state.

      Options:
      - Resume later: /aid-first-aid --resume
      - Continue this EPIC manually: /aid-run-epic {current_epic_id}
      - Check status: /aid-epic-status"
```

---

## Error Handling

### Unrecoverable Errors

If the Controller encounters an error it cannot handle:

```
ON_UNRECOVERABLE_ERROR(error):
  1. Log error to stage_log:
     {"state": "{current_state}", "action": "unrecoverable_error",
      "error": "{error message}"}

  2. Save progress snapshot (same as escalation pause):
     → Write current state to auto-mode-state.yaml
     → Stash uncommitted work if dirty working tree

  3. Restore permissions:
     Execute RESTORE_PERMISSIONS (non-blocking)

  4. Update state:
     → session.mode = "aborted"
     → session.progress.current_state = "ERROR"

  5. Notify PM:
     "FIRST AID encountered an unrecoverable error.
      Error: {error}
      EPIC: {current_epic_id}
      State: {current_state}

      Permissions have been restored.
      Session progress is saved.

      To investigate: /aid-epic-status {current_epic_id}
      To resume: /aid-first-aid --resume"

  6. STOP
```

### Per-State Error Table

| State | Error Condition | Action |
|-------|----------------|--------|
| FIRST_AID_INIT | Workspace missing | ABORT (no cleanup needed) |
| FIRST_AID_INIT | Queue empty | ABORT (no cleanup needed) |
| FIRST_AID_INIT | Backup failure | ABORT (no elevation happened) |
| FIRST_AID_INIT | Elevation failure | Restore backup, ABORT |
| QUEUE_PROCESSING | Mode changed externally | Transition to FIRST_AID_COMPLETE |
| QUEUE_PROCESSING | EPIC file missing | Mark EPIC failed, advance queue |
| QUEUE_PROCESSING | Escalation budget exceeded | E12 trigger, PM decides |
| QUEUE_ADVANCE | Failed EPIC | Auto-pause queue, notify PM |
| FIRST_AID_COMPLETE | Restore failure | Warn PM (non-blocking), continue |
| FIRST_AID_COMPLETE | Summary generation failure | Log error, continue (non-blocking) |

---

## Evidence Logging

Every state transition MUST append a line to the session-level stage log at
`.aid-o/04-engine/evidence/FIRST-AID-{session_id}/stage_log.jsonl`:

```json
{"timestamp": "{ISO 8601}", "state": "{FIRST_AID state}", "epic_id": "{current or null}", "action": "{what happened}", "details": "{context}", "result": "{pass|fail|pending}"}
```

**Examples:**
```json
{"timestamp": "2026-02-24T16:00:00Z", "state": "FIRST_AID_INIT", "epic_id": null, "action": "session_start", "details": "3 EPICs queued, permissions elevated from defaults", "result": "pass"}
{"timestamp": "2026-02-24T16:00:05Z", "state": "QUEUE_PROCESSING", "epic_id": "E-20260224-a1b2", "action": "epic_start", "details": "Starting EPIC 1/3: E-20260224-a1b2 (high)", "result": "pending"}
{"timestamp": "2026-02-24T17:30:00Z", "state": "QUEUE_ADVANCE", "epic_id": "E-20260224-a1b2", "action": "epic_completed", "details": "EPIC 1/3 completed. 5 steps, 0 escalations.", "result": "pass"}
{"timestamp": "2026-02-24T17:30:05Z", "state": "QUEUE_PROCESSING", "epic_id": "E-20260224-c3d4", "action": "epic_start", "details": "Starting EPIC 2/3: E-20260224-c3d4 (medium)", "result": "pending"}
{"timestamp": "2026-02-24T19:00:00Z", "state": "FIRST_AID_COMPLETE", "epic_id": null, "action": "session_ended", "details": "3/3 EPICs completed. Duration: 3h. 1 escalation.", "result": "pass"}
```

Per-EPIC execution also logs to the EPIC-specific stage log at
`.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl` (handled by
`/aid-run-epic` logic).

---

## Reference Files

- **PERMISSION SANDWICH:** `skills/permission-sandwich.md` — backup, elevate, restore, crash recovery, permission learning
- **ESCALATION:** `skills/auto-escalation.md` — 16 triggers, pause/resume, PM notification format, escalation budget
- **ORCHESTRATION:** `skills/epic-orchestration.md` — 11-state machine (used inside each EPIC run)
- **QUEUE:** `skills/epic-queue.md` — queue format, operations, auto-pickup, safety guards
- **PM COMMS:** `skills/slack-mcp.md` — Slack MCP protocol, message types, fallback, timeouts
- **PERMISSIONS:** `defaults/policies/permissions-auto.yaml` — default auto-mode permission template
- **MODE FLAG:** `.aid-o/04-engine/auto-mode-state.yaml` — session state, mode, aggregate metrics

---

## Important

- **Read the four skills listed in Core Instruction BEFORE starting.** They are the
  authoritative sources. This command file is the execution protocol; the skills define
  the rules.
- **Permission sandwich is a SAFETY mechanism.** Its primary job is ensuring elevated
  permissions never persist beyond the auto-mode session. If in doubt, restore.
- **The mode flag is read from disk at every decision point, never cached.** This is how
  `/aid-stop` takes immediate effect.
- **Escalation is the ONLY mandatory PM touchpoint.** Everything else is automated.
  The 16 triggers in `skills/auto-escalation.md` are the exhaustive list.
- **Failed EPICs auto-pause the queue.** The PM must investigate and resume. The queue
  does not silently skip failures.
- **Evidence is mandatory.** Every transition logs to `stage_log.jsonl`. Every EPIC
  produces a `final_report.md`. The session produces a `summary-report.md`.
- **Permission learning is automatic.** If PM grants a permission during auto-mode,
  it is persisted for future sessions (unless it is on the hard-deny list).
- **The hard-deny list is non-negotiable.** It cannot be overridden by configuration,
  by PM grants, or by any other mechanism.
- If `$ARGUMENTS` is empty: start fresh auto-mode with current queue (equivalent to
  no flags).
