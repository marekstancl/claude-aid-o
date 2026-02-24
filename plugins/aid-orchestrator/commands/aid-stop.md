---
name: aid-stop
description: Emergency stop — disengage FIRST AID auto-mode immediately
user_invocable: true
---

Immediately disengage FIRST AID autonomous orchestration mode. This is the emergency stop for auto-mode — it halts autonomous execution, restores original permissions, saves progress for later resume, and returns control to the PM.

This command is designed to be **fast and non-blocking**. Every step is resilient to partial failures — the goal is always to return to manual mode, even if some cleanup steps encounter errors.

## Usage

```
/aid-stop
```

No arguments. No confirmation prompt. Immediate execution.

## Prerequisites

- FIRST AID auto-mode must be active (or at least partially active)
- State file: `.aid-o/04-engine/auto-mode-state.yaml`
- Permission backup: `.aid-o/03-config/permissions-backup.json`

If auto-mode is not active, inform PM and exit gracefully (see Edge Cases).

## Core Instruction

**Read `skills/permission-sandwich.md` Section 4 (Restore Procedure).** It is the authoritative source for the permission restore protocol. This command invokes that procedure as part of its stop sequence.

## Stop Sequence

Execute these steps in order. Each step is independent — if one fails, log the failure and continue to the next. The sequence must always complete.

---

### Step 1: Verify Auto-Mode is Active

1. Read `.aid-o/04-engine/auto-mode-state.yaml`
2. Check `mode` field:
   - If `mode: auto` → proceed with stop sequence
   - If `mode: paused` → already partially stopped; proceed with full stop (ensure permissions are restored)
   - If `mode: manual` or file does not exist → auto-mode is not active. Display:
     ```
     FIRST AID is not active. Nothing to stop.
     Current mode: manual
     ```
     Exit command. Do not modify any files.

---

### Step 2: Set Mode to Paused (Immediate)

**This is the FIRST write operation — it prevents the Controller from dispatching new agents.**

1. Read current `.aid-o/04-engine/auto-mode-state.yaml`
2. Capture current progress before modifying:
   - `current_epic` from `session.current_epic_id`
   - `current_step` from `session.current_step_id`
   - `current_state` from `session.current_state`
   - `epics_completed` from `session.epics_completed` (default: 0)
   - `steps_executed` from `session.steps_executed` (default: 0)
3. Update the file:
   ```yaml
   mode: paused
   paused_at: "{now ISO 8601}"
   stopped_by: "pm"
   stop_reason: "/aid-stop command"
   progress:
     current_epic: "{epic_id}"
     current_step: "{step_id}"
     current_state: "{state machine state}"
     epics_completed: {N}
     steps_executed: {N}
   session:
     # ... preserve existing session data ...
   ```
4. If write fails:
   - Log ERROR: "Failed to update auto-mode-state.yaml: {error}"
   - Continue to Step 3 (do NOT abort — permission restore is more important)

---

### Step 3: Restore Permissions

Execute the RESTORE_PERMISSIONS procedure from `skills/permission-sandwich.md` Section 4.

**Summary of restore (see skill for full protocol):**

1. Check `.aid-o/03-config/permissions-backup.json` exists:
   - If missing → Log ERROR, warn PM: "No permission backup found. Review .claude/settings.json manually."
   - If corrupted (invalid JSON) → Log ERROR, warn PM: "Permission backup is corrupted. Review .claude/settings.json manually."
   - In both error cases: continue to Step 4 (non-blocking)
2. Atomic write restore:
   a. Write backup content to `.claude/settings.json.tmp`
   b. Validate temp file is valid JSON
   c. Rename `.claude/settings.json.tmp` to `.claude/settings.json`
3. Delete backup file:
   a. Remove `.aid-o/03-config/permissions-backup.json`
   b. If delete fails → Log WARNING (non-blocking)
4. Log to `stage_log.jsonl`:
   ```json
   {"state": "AID_STOP", "action": "permissions_restored", "entries_restored": "{count}"}
   ```

**Principle:** Restore is NEVER blocking. If it fails, warn PM and continue. PM can always fix `.claude/settings.json` manually.

---

### Step 4: Save Final Progress State

1. Update `.aid-o/04-engine/auto-mode-state.yaml` to final stopped state:
   ```yaml
   mode: manual
   stopped_at: "{now ISO 8601}"
   stopped_by: "pm"
   stop_reason: "/aid-stop command"
   progress:
     current_epic: "{epic_id}"
     current_step: "{step_id}"
     current_state: "{state machine state}"
     epics_completed: {N}
     steps_executed: {N}
     resumable: true
   session:
     # ... preserve existing session data ...
     permissions:
       restored: true|false
       restore_error: "{error message if restore failed, null otherwise}"
   ```
2. If write fails → Log ERROR but continue to Step 5

---

### Step 5: Log Stop Event

Append to the active EPIC's `stage_log.jsonl`:

```json
{
  "timestamp": "{now ISO 8601}",
  "state": "AID_STOP",
  "action": "auto_mode_disengaged",
  "trigger": "/aid-stop",
  "progress": {
    "current_epic": "{epic_id}",
    "current_step": "{step_id}",
    "epics_completed": "{N}",
    "steps_executed": "{N}"
  },
  "permissions_restored": true|false
}
```

Stage log location: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`

If stage log write fails → continue (non-blocking).

---

### Step 6: Display Status Message

After all steps complete, display the following status message to PM:

```
FIRST AID disengaged.
━━━━━━━━━━━━━━━━━━━━

Mode:        manual
Permissions: restored (or: "REVIEW NEEDED — see warnings above")
Progress:    saved

  EPIC:  {epic_id}
  Step:  {step_id} ({state})
  Done:  {epics_completed} EPICs, {steps_executed} steps

Resume options:
  /aid-first-aid         Resume autonomous mode from saved progress
  /aid-run-epic {id}     Continue this EPIC manually (step by step)
  /aid-epic-status {id}  Check current EPIC status
```

If permissions restore had errors, replace the "restored" line with:
```
Permissions: REVIEW NEEDED
  ⚠ Could not restore original permissions automatically.
  ⚠ Review .claude/settings.json and fix manually if needed.
```

---

## Edge Cases

### Auto-mode not active

If `.aid-o/04-engine/auto-mode-state.yaml` does not exist or `mode` is already `manual`:

```
FIRST AID is not active. Nothing to stop.
Current mode: manual
```

Exit without modifying any files.

### State file exists but is corrupted

If `auto-mode-state.yaml` exists but cannot be parsed:

1. Attempt permission restore anyway (Step 3) — the backup file is the source of truth for whether permissions need restoring, not the state file
2. Log ERROR about corrupted state file
3. Create a fresh state file with `mode: manual`
4. Display status with "unknown" for progress fields

### Permission backup missing

This can happen if:
- Auto-mode was started without the permission sandwich (bug)
- Backup was already restored by crash recovery
- File was manually deleted

Action: Log warning, continue. Display "Permissions: unchanged (no backup found)" in status.

### Currently executing agent step

The `/aid-stop` command does NOT attempt to interrupt a running agent. The agent will complete its current step, but:
- The Controller will not dispatch the next agent (mode is no longer `auto`)
- The completed step output is preserved in evidence

This is by design — killing an agent mid-execution could leave files in an inconsistent state.

### Queue has remaining EPICs

Remaining EPICs in `.aid-o/04-engine/epic-queue.yaml` are untouched. They remain queued. When PM resumes with `/aid-first-aid`, the queue continues from where it stopped.

---

## Reference Files

- **PRIMARY:** `skills/permission-sandwich.md` Section 4 — Restore Procedure
- `skills/epic-orchestration.md` — Controller state machine, evidence store structure
- `skills/epic-queue.md` — Queue state, auto-pickup
- `commands/aid-first-aid.md` — The inverse command (start auto-mode / resume)
- `commands/aid-run-epic.md` — Manual EPIC execution (alternative to auto-mode)
- `commands/aid-epic-status.md` — Check EPIC progress after stopping

## Important

- This command is an **emergency stop**. It prioritizes speed and reliability over thoroughness. Every operation is designed to be non-blocking.
- The permission restore is the most critical step. Even if everything else fails, restoring permissions should succeed (or at minimum, warn PM clearly).
- Progress is always saved to enable clean resume. The PM should never lose track of where auto-mode left off.
- Running agents are NOT interrupted. The stop prevents *future* dispatches, not current execution. This is intentional — mid-execution interruption risks leaving the codebase in a broken state.
- The stop sequence NEVER prompts for confirmation. When PM says stop, it stops. Immediately.
