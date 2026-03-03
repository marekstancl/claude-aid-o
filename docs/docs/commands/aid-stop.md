---
sidebar_position: 7
title: "/aid-stop"
description: "Emergency stop — halt execution, save progress, restore state"
---

# /aid-stop

Emergency stop for running tasks. Halts autonomous execution, saves progress for later resume, and returns control to the PM. Designed to be **fast and non-blocking** -- every step is resilient to partial failures.

## Usage

```bash
/aid-stop
```

No arguments. No confirmation prompt. Immediate execution.

## What It Does

### Stop Sequence

Each step is independent -- if one fails, the error is logged and the sequence continues. The goal is always to return to manual mode.

1. **Verify active execution** -- reads `.aid-o/work/evidence/{task_id}/{run_id}/state.yaml`. If no task is running, reports "Nothing to stop" and exits without modifying files
2. **Set mode to paused** -- prevents the controller from dispatching new agents (first write operation)
3. **Save progress state** -- updates `state.yaml` to `state: ESCALATION` with current step, gate retries, and `resumable: true`
4. **Log stop event** -- appends to `timeline.jsonl`:
   ```json
   {
     "timestamp": "2026-03-03T10:15:00Z",
     "state": "AID_STOP",
     "action": "execution_halted",
     "trigger": "/aid-stop",
     "progress": {
       "current_task": "E-003-1_2",
       "current_step": "step_3_backend",
       "steps_executed": 2
     }
   }
   ```
5. **Display status** -- shows progress summary and resume options

## Output

```text
AID stopped.
====================================

Mode:        manual
Progress:    saved

  Task:  E-003-1_2 — Add Auth System
  Step:  step_3_backend (EXECUTE)
  Done:  2/7 steps

Resume options:
  /aid-run --resume         Resume from saved progress
  /aid-run E-003-1_2        Continue this task manually
  /aid-status E-003-1_2     Check current task status
```

## Important Behaviors

**Running agents are not interrupted.** `/aid-stop` prevents the controller from dispatching the *next* agent. The currently executing agent completes its step normally -- interrupting mid-execution could leave files in an inconsistent state. This is by design.

**Progress is always saved.** The session is fully resumable with `/aid-run --resume`.

**Queued tasks are untouched.** Remaining tasks stay in `.aid-o/config/queue.yaml` and are picked up when you resume.

**Progress saving is the most critical step.** Even if everything else fails, the PM should never lose track of where execution left off.

## Edge Cases

| Situation | Behavior |
|-----------|----------|
| No task running | Reports "Nothing to stop", exits without modifying files |
| State file corrupted | Creates a fresh state file with `state: ERROR`, preserves evidence |
| Currently executing agent | Agent completes normally; no new agents dispatched after stop |
| Queue has remaining tasks | Tasks remain queued; resumed on `/aid-run --resume` |

## Related Commands

- [`/aid-run --resume`](./aid-run) -- resume from saved progress after stopping
- [`/aid-run`](./aid-run) -- continue a specific task manually after stopping
- [`/aid-status`](./aid-status) -- check task progress after stopping
