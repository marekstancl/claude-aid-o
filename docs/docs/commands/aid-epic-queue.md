---
sidebar_position: 4
title: "/aid-epic-queue"
description: "Manage the EPIC execution queue — add, remove, reorder, pause, and monitor"
---

# /aid-epic-queue

Manage the EPIC execution queue. Add, remove, reorder, pause, and monitor EPICs for autonomous pipeline execution. When a queue is active, the Orchestrator picks up the next EPIC automatically after each EPIC completes.

## Usage

```bash
/aid-epic-queue                                           # Show queue (same as list)
/aid-epic-queue list                                      # Show queue with status
/aid-epic-queue add <epic-path> [--priority <level>]      # Add EPIC to queue
/aid-epic-queue remove <epic-id>                          # Remove from queue
/aid-epic-queue next                                      # Show next EPIC in line
/aid-epic-queue pause                                     # Pause auto-pickup
/aid-epic-queue resume                                    # Resume auto-pickup
/aid-epic-queue reorder <epic-id> --priority <level>      # Change priority
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `subcommand` | string | No | Action to perform. Defaults to `list`. |
| `epic-path` | string | Conditional | Path to the EPIC file (required for `add`) |
| `epic-id` | string | Conditional | EPIC ID (required for `remove` and `reorder`) |
| `--priority` | string | No | Priority level: `critical`, `high`, `medium` (default), or `low` |

## Prerequisites

- `.aid-o/` workspace must exist (run [`/aid-init`](./aid-init) first)
- Queue file: `.aid-o/04-engine/epic-queue.yaml` — created automatically on first `add`

## Examples

```bash
# View the current queue
/aid-epic-queue

# Add an EPIC with default (medium) priority
/aid-epic-queue add .aid-o/02-epics/E-005-1_1-user-auth.md

# Add with high priority
/aid-epic-queue add .aid-o/02-epics/E-006-1_1-hotfix.md --priority high

# Remove an EPIC from the queue
/aid-epic-queue remove E-005-1_1

# Promote an EPIC to high priority
/aid-epic-queue reorder E-005-1_1 --priority high

# Pause auto-pickup (current EPIC continues)
/aid-epic-queue pause

# Resume auto-pickup
/aid-epic-queue resume
```

## How It Works

### Queue Display

The `list` subcommand (default) shows all EPICs with their status and priority:

```
EPIC Queue
━━━━━━━━━━━━━
 RUNNING: E-20260217-a1b2-user-auth (high) — started 2h ago
 QUEUED:  E-20260217-c3d4-api-v2 (medium) — added 1h ago
 QUEUED:  E-20260218-e5f6-dashboard (low) — added 30m ago
 DONE:    E-20260216-g7h8-scaffold (high) — completed 3h ago
 FAILED:  E-20260215-i9j0-legacy (medium) — failed 5h ago

Auto-pickup: Active (2 EPICs queued)
```

### Priority Ordering

EPICs are picked up in priority order (`critical` > `high` > `medium` > `low`), then by the time they were added (FIFO within the same priority level).

### Pause Behavior

`/aid-epic-queue pause` does **not** abort the currently running EPIC. The running EPIC completes normally; only the automatic pickup of the next EPIC is suspended. Use [`/aid-stop`](./aid-stop) to disengage autonomous mode entirely.

## Notes

- The queue file is created automatically on the first `add` if it does not exist
- The queue persists across Claude Code sessions (stored as YAML on disk)
- Auto-pickup only triggers in the Orchestrator's DONE state — not by this command directly
- Running EPICs cannot be removed; pause the queue first if you need to restructure it
- For fully autonomous batch execution, see [`/aid-first-aid`](./aid-first-aid)

## Related

- [`/aid-first-aid`](./aid-first-aid) — autonomous mode that processes the full queue without PM interaction
- [`/aid-run-epic`](./aid-run-epic) — run a single EPIC manually
- [`/aid-epic-status`](./aid-epic-status) — check detailed status of a running EPIC
