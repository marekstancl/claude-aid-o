---
name: aid-stop
description: Emergency stop — disengage FIRST AID auto-mode immediately
user_invocable: true
---

Immediately disengage FIRST AID autonomous orchestration mode. This is the emergency stop for auto-mode — it halts autonomous execution, saves progress for later resume, and returns control to the PM.

This command is designed to be **fast and non-blocking**. Every step is resilient to partial failures — the goal is always to return to manual mode, even if some cleanup steps encounter errors.

## Usage

```
/aid-stop
```

No arguments. No confirmation prompt. Immediate execution.

## Prerequisites

- FIRST AID auto-mode must be active (or at least partially active)
- State file: `.aid-o/work/auto-mode-state.yaml`

If auto-mode is not active, inform PM and exit gracefully (see Edge Cases).

## Core Instruction

**Read this stop sequence carefully.** Each step is independent — if one fails, log the failure and continue to the next.

## Stop Sequence

Execute these steps in order. Each step is independent — if one fails, log the failure and continue to the next. The sequence must always complete.

---

### Step 1: Verify Auto-Mode is Active

1. Read `.aid-o/work/auto-mode-state.yaml`
2. Check `mode` field:
   - If `mode: auto` → proceed with stop sequence
   - If `mode: paused` → already partially stopped; proceed with full stop
   - If `mode: manual` or file does not exist → auto-mode is not active. Display:
     ```
     FIRST AID is not active. Nothing to stop.
     Current mode: manual
     ```
     Exit command. Do not modify any files.

---

### Step 2: Set Mode to Paused (Immediate)

**This is the FIRST write operation — it prevents the Controller from dispatching new agents.**

1. Read current `.aid-o/work/auto-mode-state.yaml`
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
   - Continue to Step 3 (do NOT abort — progress save is critical)

---

### Step 3: Save Final Progress State

1. Update `.aid-o/work/auto-mode-state.yaml` to final stopped state:
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
   ```
2. If write fails → Log ERROR but continue to Step 4

---

### Step 4: Log Stop Event

Append to the active EPIC's `timeline.jsonl`:

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
  }
}
```

Stage log location: `.aid-o/work/evidence/{epic_id}/{run_id}/timeline.jsonl`

If stage log write fails → continue (non-blocking).

---

### Step 5: Display Status Message

After all steps complete, display the following status message to PM:

```
FIRST AID disengaged.
━━━━━━━━━━━━━━━━━━━━

Mode:        manual
Progress:    saved

  EPIC:  {epic_id}
  Step:  {step_id} ({state})
  Done:  {epics_completed} EPICs, {steps_executed} steps

Resume options:
  /aid-run               Resume autonomous mode from saved progress
  /aid-run {id}          Continue this EPIC manually (step by step)
  /aid-status {id}       Check current EPIC status
```

---

## Edge Cases

### Auto-mode not active

If `.aid-o/work/auto-mode-state.yaml` does not exist or `mode` is already `manual`:

```
FIRST AID is not active. Nothing to stop.
Current mode: manual
```

Exit without modifying any files.

### State file exists but is corrupted

If `auto-mode-state.yaml` exists but cannot be parsed:

1. Log ERROR about corrupted state file
2. Create a fresh state file with `mode: manual`
3. Display status with "unknown" for progress fields

### Currently executing agent step

The `/aid-stop` command does NOT attempt to interrupt a running agent. The agent will complete its current step, but:
- The Controller will not dispatch the next agent (mode is no longer `auto`)
- The completed step output is preserved in evidence

This is by design — killing an agent mid-execution could leave files in an inconsistent state.

### Queue has remaining EPICs

Remaining EPICs in `.aid-o/config/queue.yaml` are untouched. They remain queued. When PM resumes with `/aid-run`, the queue continues from where it stopped.

---

## Reference Files

- `skills/pipeline.md` — Controller state machine, evidence store structure
- `commands/aid-run.md` — The inverse command (start auto-mode / resume)
- `commands/aid-status.md` — Check EPIC progress after stopping

## Important

- This command is an **emergency stop**. It prioritizes speed and reliability over thoroughness. Every operation is designed to be non-blocking.
- Progress saving is the most critical step. Even if everything else fails, the PM should never lose track of where auto-mode left off.
- Running agents are NOT interrupted. The stop prevents *future* dispatches, not current execution. This is intentional — mid-execution interruption risks leaving the codebase in a broken state.
- The stop sequence NEVER prompts for confirmation. When PM says stop, it stops. Immediately.


**Last Updated:** 2026-03-19
