---
sidebar_position: 10
title: "Epic Queue"
description: "Persistent YAML-based queue that enables autonomous EPIC pipeline execution — the Controller picks up the next EPIC automatically after each completion."
---

# Epic Queue

The EPIC queue is a persistent YAML file that holds an ordered list of EPICs to be executed. The Controller processes EPICs one at a time, automatically picking up the next one after each completion. PM manages the queue via the `/aid-epic-queue` command.

## Purpose

Running multiple EPICs sequentially requires coordination: what runs next, what has completed, what failed, and whether to pause. The epic queue makes this coordination explicit and persistent. If the system restarts mid-queue, the queue state survives. If an EPIC fails, the queue pauses safely rather than starting the next EPIC with corrupted state.

## When Used

- Created and managed by the `/aid-epic-queue` command
- Read by the Controller at every DONE state to determine whether to auto-pickup the next EPIC
- Central to FIRST AID auto-mode (`/aid-first-aid`), which processes the entire queue autonomously
- Referenced by `auto-done-state` for queue transitions and `auto-escalation` for pausing on failure

## Key Concepts

### Queue File Structure

The queue is stored at `.aid-o/04-engine/epic-queue.yaml`:

```yaml
paused: false

queue:
  - epic_id: "E-20260217-user-auth"
    path: ".aid-o/02-epics/E-20260217-user-auth.md"
    priority: high
    status: completed
    added_at: "2026-02-17T10:00:00Z"
    started_at: "2026-02-17T10:05:00Z"
    completed_at: "2026-02-17T14:30:00Z"

  - epic_id: "E-20260217-api-v2"
    path: ".aid-o/02-epics/E-20260217-api-v2.md"
    priority: medium
    status: queued
    added_at: "2026-02-17T10:01:00Z"
    started_at: null
    completed_at: null
```

### EPIC Status Values

| Status | Meaning |
|---|---|
| `queued` | Waiting in queue, ready to be picked up |
| `running` | Currently being executed by the Controller |
| `completed` | Finished successfully (DONE state, approved) |
| `failed` | Finished with failure (aborted or unrecoverable error) |
| `paused` | Individually paused by PM; skipped during auto-pickup |

### Queue Operations

The Controller calls these operations internally:

- **`add(epic_path, priority)`** — adds an EPIC to the queue with status `queued`
- **`next()`** — returns the highest-priority queued EPIC, or null if none exist
- **`start(epic_id)`** — marks an EPIC as `running`
- **`complete(epic_id, status)`** — marks an EPIC as `completed` or `failed`
- **`pause(epic_id)`** — marks an individual EPIC as `paused`

The global `paused` flag pauses the entire queue. When `paused: true`, the Controller finishes the current EPIC but does not auto-pickup the next one.

### Safety Rules

- If an EPIC fails (status `"failed"`), the queue automatically sets `paused: true` — the next EPIC does not start until PM explicitly resumes
- The queue file must not be edited manually while an EPIC is running
- A `paused` EPIC is skipped during auto-pickup (it stays in the queue but is not selected by `next()`)

## How It Works

The Controller checks the queue at the end of every DONE state. If `paused: false` and a queued EPIC exists, the Controller calls `next()` to get it, marks it as `running`, sends a status notification, and begins the new orchestration loop at IDLE.

In FIRST AID auto-mode, `auto-done-state` extends this with guardrail checks (escalation budget), summary aggregation across EPICs, and session completion logic when the queue empties.

## Configuration

Queue file location: `.aid-o/04-engine/epic-queue.yaml`

Priority values: `critical`, `high`, `medium`, `low` — higher priority EPICs are selected first by `next()`.

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Auto Done State](../skills/auto-done-state)
- [Auto Escalation](../skills/auto-escalation)
- [Slack MCP](../skills/slack-mcp)
