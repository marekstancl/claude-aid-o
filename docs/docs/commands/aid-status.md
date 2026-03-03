---
sidebar_position: 5
title: "/aid-status"
description: "Show task status, queue, and pipeline overview"
---

# /aid-status

Show pipeline status, task details, and queue management -- unified view of everything running, queued, or completed. Replaces the v1 `/aid-epic-status` and `/aid-epic-queue` commands.

## Usage

```bash
/aid-status                                  # Overview: active tasks + queue summary
/aid-status <task-id>                        # Detailed task status
/aid-status queue                            # Queue management view
/aid-status queue add <path> [--priority]    # Add task to queue
/aid-status queue pause                      # Pause auto-pickup
/aid-status queue resume                     # Resume auto-pickup
/aid-status queue reorder <id> --priority <level>  # Change priority
```

### Examples

```bash
# Show everything at a glance
/aid-status

# Detailed FSM state for a specific task
/aid-status E-003-1_2

# View the task queue
/aid-status queue

# Add a task with high priority
/aid-status queue add .aid-o/tasks/E-015.md --priority high

# Pause auto-pickup (running task continues)
/aid-status queue pause
```

**Priority levels:** `critical` | `high` | `medium` (default) | `low`

## What It Does

### Overview (default)

```text
AID Status
====================================

Active Tasks:
  E-003-1_2 — Add Auth System           [EXECUTE] step 3/7
  E-003-2_2 — Auth Frontend             [queued]  waiting on E-003-1_2

Recent Quick Tasks:
  Q-007 — Add login button              (2 min ago, 3 files)
  Q-006 — Fix README typo               (1h ago, 1 file)

Queue: 2 queued, 1 running | Auto-pickup: active
Use /aid-status <id> for details, /aid-status queue for queue management.
```

Scans:
1. **Active tasks** -- lists files in `.aid-o/tasks/` (not `archive/`), checks evidence directories
2. **Quick logs** -- counts `.aid-o/work/quick/Q-*.md`, shows last 3 by date
3. **Queue** -- reads `.aid-o/config/queue.yaml`, shows summary

### Detailed Task Status (`/aid-status <task-id>`)

```text
TASK Status: E-003-1_2 — Add Auth System
====================================
State: EXECUTE          ← from state.yaml .state
Step: 3/7               ← current_step / total_steps
Mode: manual            ← from state.yaml .mode
Branch: task/E-003-1_2  ← from state.yaml .branch
Gate retries: 0/2       ← gate_retries
Escalations: 1          ← escalation_count
Started: 2026-03-03T10:00Z

Recent events (last 5 from timeline.jsonl):
  10:05 step_complete step_2_backend — pass
  10:03 step_dispatch step_2_backend — dispatched
  10:01 step_complete step_1_architect — pass
  09:58 step_dispatch step_1_architect — dispatched
  09:55 fsm_init — READY

Evidence: .aid-o/work/evidence/E-003-1_2/{run_id}/
```

Reads from `.aid-o/work/evidence/{task_id}/` -- loads `state.yaml` and last 10 entries from `timeline.jsonl`.

### Queue Management (`/aid-status queue`)

```text
Task Queue
====================================
  [READY]    E-015-1_2  (high)   — no dependencies
  [RUN]      E-014-1_2  (high)   — started 2h ago
  [WAITING]  E-015-2_2  (medium) — waiting on: E-015-1_2
  [BLOCKED]  E-013-1_1  (medium) — blocked by failed: E-012-1_1
  [DONE]     E-014-1_2  (high)   — completed 3h ago

Auto-pickup: Active (1 READY, 1 WAITING, 1 BLOCKED)
```

**Queue tags:**

| Tag | Meaning |
|-----|---------|
| `[READY]` | Eligible for pickup (no deps or all deps completed) |
| `[WAITING]` | Dependencies in progress |
| `[BLOCKED]` | Dependencies failed or missing |
| `[RUN]` | Currently running |
| `[DONE]` | Completed |
| `[FAIL]` | Failed |

### Queue Subcommands

| Subcommand | What It Does |
|------------|-------------|
| `queue add <path> [--priority <level>]` | Validate task file, reject duplicates, add to `.aid-o/config/queue.yaml` |
| `queue pause` | Pause auto-pickup. Running task continues, no new task starts |
| `queue resume` | Resume auto-pickup. Next task starts after current completes |
| `queue reorder <id> --priority <level>` | Change priority of a queued task, show new order |

## Edge Cases

**No tasks found:**
```text
No tasks found.

Get started:
  /aid-do "quick task"     — implement something small
  /aid-plan                — plan something bigger
```

**Task exists but no evidence:**
```text
TASK: E-003-1_2 — Add Auth System
Status: Not started (no evidence directory)

Run /aid-run E-003-1_2 to start execution.
```

## Evidence Paths (v2)

| v2 Path | Purpose |
|---------|---------|
| `.aid-o/work/evidence/{task_id}/{run_id}/` | Run evidence root |
| `state.yaml` | FSM state (replaces v1 `plan_progress.json`) |
| `timeline.jsonl` | Event log (replaces v1 `stage_log.jsonl`) |
| `.aid-o/tasks/` | Task files (replaces v1 `02-epics/`) |
| `.aid-o/config/queue.yaml` | Queue (replaces v1 `04-engine/epic-queue.yaml`) |

## Key Behaviors

- **Read-only by default** -- `/aid-status` and `/aid-status <id>` never modify files
- **Queue subcommands modify** -- `add`, `pause`, `resume`, `reorder` write to `queue.yaml`
- **Lazy queue creation** -- `.aid-o/config/queue.yaml` created on first `queue add`
- **v2 paths only** -- reads `state.yaml` (not `plan_progress.json`), `timeline.jsonl` (not `stage_log.jsonl`)

## Related Commands

- [`/aid-run`](./aid-run) -- start or resume task execution
- [`/aid-plan`](./aid-plan) -- create plans and EPICs to queue
- [`/aid-do`](./aid-do) -- quick tasks (shown in overview)
- [`/aid-stop`](./aid-stop) -- emergency stop for running tasks
