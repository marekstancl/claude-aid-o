# Epic Queue — Autonomous EPIC Pipeline

**Skill:** epic-queue
**Dependencies:** epic-orchestration, slack-mcp

---

## TL;DR

This skill defines the Epic Queue — a persistent YAML-based queue that enables
autonomous EPIC execution. The Orchestrator processes EPICs one at a time, picking
up the next one automatically after the current EPIC completes. PM can manage the
queue via `/epic-queue` command.

---

## Queue Format

The queue is stored in `.aid-o/04-engine/epic-queue.yaml`:

```yaml
# Epic Queue — managed by Orchestrator + /epic-queue command
# Do not edit manually while an EPIC is running.

paused: false                              # Global pause flag

queue:
  - epic_id: "E-20260217-a1b2-user-auth"
    path: ".aid-o/02-epics/E-20260217-a1b2-user-auth.md"
    priority: high
    status: completed                      # queued | running | completed | failed | paused
    added_at: "2026-02-17T10:00:00Z"
    started_at: "2026-02-17T10:05:00Z"
    completed_at: "2026-02-17T14:30:00Z"

  - epic_id: "E-20260217-c3d4-api-v2"
    path: ".aid-o/02-epics/E-20260217-c3d4-api-v2.md"
    priority: medium
    status: queued
    added_at: "2026-02-17T10:01:00Z"
    started_at: null
    completed_at: null
```

### Status Values

| Status | Meaning |
|--------|---------|
| `queued` | Waiting in queue, ready to be picked up |
| `running` | Currently being executed by Orchestrator |
| `completed` | Finished successfully (DONE state, approved) |
| `failed` | Finished with failure (aborted or unrecoverable) |
| `paused` | Individually paused by PM (skipped in pickup) |

---

## Queue Operations

### `add(epic_path, priority)`

Add an EPIC to the queue.

```
1. Validate EPIC file exists at epic_path
2. Extract epic_id from file
3. Check for duplicates (same epic_id already in queue with status queued|running)
   - If duplicate → reject with error: "EPIC already in queue"
4. Append to queue:
   epic_id: <extracted>
   path: <epic_path>
   priority: <priority — default: medium>
   status: queued
   added_at: <now ISO 8601>
   started_at: null
   completed_at: null
5. Save epic-queue.yaml
```

### `remove(epic_id)`

Remove an EPIC from the queue (only if not running).

```
1. Find entry by epic_id
2. IF status = "running" → reject: "Cannot remove running EPIC. Use /epic-queue pause."
3. Remove entry from queue list
4. Save epic-queue.yaml
```

### `next()`

Get the next EPIC to execute (highest priority, oldest within same priority).

```
1. Filter entries where status = "queued"
2. Sort by:
   a. Priority: critical > high > medium > low
   b. Within same priority: added_at ascending (FIFO)
3. Return first entry, or null if empty
```

### `start(epic_id)`

Mark an EPIC as running.

```
1. Find entry by epic_id
2. Set status = "running"
3. Set started_at = <now ISO 8601>
4. Save epic-queue.yaml
```

### `complete(epic_id, result_status)`

Mark an EPIC as completed or failed.

```
1. Find entry by epic_id
2. Set status = result_status (completed | failed)
3. Set completed_at = <now ISO 8601>
4. Save epic-queue.yaml
```

### `pause_queue()`

Pause auto-pickup globally.

```
1. Set paused = true at top level
2. Save epic-queue.yaml
3. Send Status Update (Slack Type G): ":double_vertical_bar: Queue paused by PM"
```

### `resume_queue()`

Resume auto-pickup.

```
1. Set paused = false at top level
2. Save epic-queue.yaml
3. Send Status Update (Slack Type G): ":arrow_forward: Queue resumed"
```

### `list()`

Return full queue with status, priority, and timing info.

### `reorder(epic_id, new_priority)`

Change priority of a queued EPIC.

```
1. Find entry by epic_id
2. IF status != "queued" → reject: "Can only reorder queued EPICs"
3. Set priority = new_priority
4. Save epic-queue.yaml
```

---

## Priority Rules

| Level | Value | Use case |
|-------|-------|----------|
| `critical` | Highest | Hotfix, security patch |
| `high` | High | Core feature, blocking work |
| `medium` | Default | Standard feature work |
| `low` | Lowest | Nice-to-have, refactoring |

Within the same priority level, EPICs are processed in FIFO order (oldest `added_at` first).

A running EPIC cannot be preempted. Priority only affects pickup order, not interruption.

---

## Auto-Pickup Protocol

Triggered from `skills/epic-orchestration.md` DONE state, after POST-PROCESSING completes.

```
1. Read .aid-o/04-engine/epic-queue.yaml
2. Mark current EPIC as "completed" (or "failed" if aborted)
3. IF paused = true:
     → Log: "Queue paused, skipping auto-pickup"
     → Send Status Update: ":double_vertical_bar: Queue paused. {N} EPICs waiting."
     → STOP (remain idle)
4. IF previous EPIC status = "failed":
     → Pause queue automatically (safety guard)
     → Send Escalation (Slack Type A): "Previous EPIC failed. Queue auto-paused."
     → PM must resume queue manually after investigating
     → STOP
5. next_epic = next()
6. IF next_epic is not null:
     → start(next_epic.epic_id)
     → Send Status Update: ":arrows_counterclockwise: Auto-starting: {next_epic.epic_id}"
     → Begin new run-epic loop with next_epic.path
7. ELSE:
     → Send Status Update: ":white_check_mark: Queue empty. Orchestrator idle."
     → STOP
```

---

## Safety Guards

| Guard | Behavior |
|-------|----------|
| **Max 1 concurrent EPIC** | Queue only picks up next after current finishes. No parallel EPIC execution. |
| **Failed EPIC → auto-pause** | If an EPIC fails (aborted/unrecoverable), the queue pauses automatically. PM must investigate and resume. |
| **Manual pause** | `/epic-queue pause` stops auto-pickup immediately. Does not abort the running EPIC. |
| **Duplicate prevention** | Cannot add the same EPIC twice (by epic_id) if it's already queued or running. |
| **Persistence** | Queue state lives in YAML file — survives run restarts and context window resets. |
| **Running protection** | Cannot remove or reorder a running EPIC. |

---

## Reference Files

- `skills/epic-orchestration.md` — DONE state triggers auto-pickup
- `skills/slack-mcp.md` — Status updates and escalations
- `commands/aid-run-epic.md` — Consumes next EPIC from queue
- `commands/aid-epic-queue.md` — CLI interface for queue management

---

## Important

- The queue is YAML-based and simple by design. It handles tens of EPICs, not thousands.
- Auto-pickup happens in the DONE state — the Orchestrator checks the queue after
  POST-PROCESSING (Curator + Auditor) completes.
- A failed EPIC always pauses the queue. This is a safety measure — the PM must
  investigate before more EPICs run. The queue does not silently skip failures.
- Queue state is read from disk each time (not cached). This ensures consistency
  even if the PM modifies the queue via `/epic-queue` while an EPIC is running.
- Parallelism is within EPICs (parallel_groups, analysis_groups), not between EPICs.
