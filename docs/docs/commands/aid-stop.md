---
sidebar_position: 13
title: "/aid-stop"
description: "Emergency stop — disengage FIRST AID auto-mode immediately"
---

# /aid-stop

Immediately disengage FIRST AID autonomous orchestration mode. This is the emergency stop for auto-mode — it halts autonomous execution, restores original permissions, saves progress, and returns control to you.

The command is designed to be **fast and non-blocking**: every step is resilient to partial failures. The goal is always to return to manual mode, even if some cleanup steps encounter errors.

## Usage

```bash
/aid-stop
```

No arguments. No confirmation prompt. Immediate execution.

## Prerequisites

- FIRST AID auto-mode must be active (started with [`/aid-first-aid`](./aid-first-aid))
- State file: `.aid-o/04-engine/auto-mode-state.yaml`
- Permission backup: `.aid-o/03-config/permissions-backup.json`

If auto-mode is not active, the command reports the current mode and exits without modifying any files.

## Stop Sequence

The stop sequence always runs to completion, even if individual steps fail:

1. **Verify auto-mode is active** — reads `auto-mode-state.yaml`; exits cleanly if mode is already `manual`
2. **Set mode to `paused`** — prevents the Controller from dispatching new agents (first write operation)
3. **Restore permissions** — atomic write of the original `~/.claude/settings.json` from the backup
4. **Save final progress state** — updates `auto-mode-state.yaml` to `mode: manual` with current progress and `resumable: true`
5. **Log stop event** — appends to the active EPIC's `stage_log.jsonl`
6. **Display status message** — shows permissions status, progress summary, and resume options

## Output

```text
FIRST AID disengaged.
━━━━━━━━━━━━━━━━━━━━

Mode:        manual
Permissions: restored
Progress:    saved

  EPIC:  E-005-1_1
  Step:  step_3_backend (EXECUTING)
  Done:  1 EPICs, 6 steps

Resume options:
  /aid-first-aid         Resume autonomous mode from saved progress
  /aid-run-epic E-005-1_1     Continue this EPIC manually (step by step)
  /aid-epic-status E-005-1_1  Check current EPIC status
```

If permission restore failed, a clear warning is displayed with instructions to fix `~/.claude/settings.json` manually.

## Important Behaviors

**Running agents are not interrupted.** `/aid-stop` prevents the Controller from dispatching the *next* agent. The currently executing agent completes its step normally — interrupting mid-execution could leave files in an inconsistent state. This is by design.

**Progress is always saved.** The session is fully resumable with `/aid-first-aid --resume`.

**Queued EPICs are untouched.** Remaining EPICs stay queued and are picked up when you resume.

**Permission restore is the most critical step.** Even if every other step fails, the command attempts permission restore and warns you clearly if it cannot complete it.

## Edge Cases

| Situation | Behavior |
|-----------|----------|
| Auto-mode not active | Reports "nothing to stop", exits without modifying files |
| State file corrupted | Attempts permission restore anyway; creates a fresh `manual` state file |
| Permission backup missing | Logs a warning, displays "Permissions: unchanged (no backup found)" |
| Currently executing agent | Agent completes normally; no new agents are dispatched after stop |
| Queue has remaining EPICs | EPICs remain queued; resumed on `/aid-first-aid` |

## Related

- [`/aid-first-aid`](./aid-first-aid) — start or resume autonomous mode
- [`/aid-run-epic`](./aid-run-epic) — continue an EPIC manually after stopping
- [`/aid-epic-status`](./aid-epic-status) — check EPIC progress after stopping
