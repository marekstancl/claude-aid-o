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

EPIC IDs follow the canonical format defined in `skills/epic-state-machine.md` > ID Format: `E-{plan_id}-{phase}_{total}`

```yaml
# Epic Queue — managed by Orchestrator + /epic-queue command
# Do not edit manually while an EPIC is running.

paused: false                              # Global pause flag
last_modified: "2026-02-17T14:30:00Z"      # Updated on every queue mutation (ISO 8601)

queue:
  - epic_id: "E-003-1_2"
    path: ".aid-o/02-epics/E-003-1_2.md"
    priority: high
    status: completed                      # queued | running | completed | failed | paused | removed
    depends_on: []                         # list of epic_ids that must complete before this starts
    added_at: "2026-02-17T10:00:00Z"
    started_at: "2026-02-17T10:05:00Z"
    completed_at: "2026-02-17T14:30:00Z"

  - epic_id: "E-003-2_2"
    path: ".aid-o/02-epics/E-003-2_2.md"
    priority: medium
    status: queued
    depends_on: ["E-003-1_2"]              # waits for E-003-1_2 to complete first
    added_at: "2026-02-17T10:01:00Z"
    started_at: null
    completed_at: null
```

**Backward compatibility:** Existing entries without `depends_on` are treated as having
`depends_on: []` (no dependencies, always eligible for pickup).

### Status Values

| Status | Meaning |
|--------|---------|
| `queued` | Waiting in queue, ready to be picked up |
| `running` | Currently being executed by Orchestrator |
| `completed` | Finished successfully (DONE state, approved) |
| `failed` | Finished with failure (aborted or unrecoverable) |
| `paused` | Individually paused by PM (skipped in pickup) |
| `removed` | Removed from queue by PM (/epic-queue remove) |

---

## Queue Operations

### `add(epic_path, priority, depends_on)`

Add an EPIC to the queue.

```
0. CONFLICT_CHECK (see Conflict Detection Protocol below)
1. Validate EPIC file exists at epic_path
2. Extract epic_id from file
3. Check for duplicates (same epic_id already in queue with status queued|running)
   - If duplicate → reject with error: "EPIC already in queue"
4. DEPENDENCY VALIDATION (see below)
5. Append to queue:
   epic_id: <extracted>
   path: <epic_path>
   priority: <priority — default: medium>
   status: queued
   depends_on: <depends_on — default: []>
   added_at: <now ISO 8601>
   started_at: null
   completed_at: null
6. Update last_modified to current timestamp
7. Save epic-queue.yaml
```

#### Step 4: DEPENDENCY VALIDATION

```
IF depends_on is empty → skip validation, proceed to step 5

4a. REFERENCE CHECK — verify all referenced IDs exist:
  For each dep_id in depends_on:
    - IF dep_id == this epic's own epic_id → REJECT:
      "Self-dependency rejected: {epic_id} cannot depend on itself."
    - Search queue for entry with epic_id == dep_id
    - Also check completed entries (dependency is pre-satisfied)
    - IF dep_id not found anywhere:
      → REJECT: "Dependency '{dep_id}' not found in queue. Add it first
                 or remove the dependency."
    - IF dep_id found with status == "failed":
      → WARN: "Dependency '{dep_id}' has status 'failed'. EPIC will be
               BLOCKED until resolved."
      → Continue (allow add, but EPIC will not be eligible for pickup)

4b. CYCLE DETECTION — Kahn's Algorithm:
  Build the dependency graph from ALL queue entries + the new entry being added:
    Nodes = all entries in queue (any status except "removed") + the new entry
    Edges = for each entry, draw directed edge from dep_id → entry
            for each dep_id in that entry's depends_on list
            (edge means: dep_id must complete BEFORE entry can start)

  Run Kahn's Algorithm:
    1. Compute in_degree[node] for every node
       (in_degree = count of incoming edges = number of dependencies)
    2. Initialize processing_queue with all nodes where in_degree == 0
       (these are EPICs with no dependencies)
    3. sorted_count = 0
    4. WHILE processing_queue is not empty:
       a. Remove node from processing_queue
       b. sorted_count += 1
       c. For each dependent of node (entries whose depends_on contains node):
          - Decrement in_degree[dependent] by 1
          - IF in_degree[dependent] == 0: add dependent to processing_queue
    5. IF sorted_count < total_node_count:
       → CYCLE DETECTED
       → Cycle members = all nodes where in_degree > 0 after algorithm completes
       → Build cycle path: pick any cycle member, follow its dependencies through
         other cycle members until returning to start node
         Example: A → B → C → A
       → REJECT: "Circular dependency detected: {cycle_path joined with ' -> '}"
       → Do NOT add the entry to the queue

  IF no cycle detected → proceed to step 5
```

### `remove(epic_id)`

Remove an EPIC from the queue (only if not running).

```
1. Find entry by epic_id
2. IF status == "running" → reject: "Cannot remove running EPIC. Use /epic-queue pause first."
3. Update entry (DO NOT delete — preserve audit trail):
   status: "removed"
   removed_at: "{ISO 8601}"
4. Update last_modified to current timestamp
5. Save epic-queue.yaml
6. Log: "EPIC {epic_id} removed from queue (was: {previous_status})"
```

### `next()`

Get the next EPIC to execute (highest priority, oldest within same priority, all dependencies satisfied).

```
1. Filter entries where status = "queued"
2. DEPENDENCY FILTER — for each candidate entry:
   a. Resolve depends_on (treat missing field as [])
   b. For each dep_id in depends_on:
      - Find the queue entry with epic_id == dep_id
      - IF entry not found OR entry.status != "completed":
        → This candidate is BLOCKED — remove from eligible set
   c. Only entries with ALL dependencies satisfied (completed) remain eligible
3. Sort eligible entries by:
   a. Priority: critical > high > medium > low
   b. Within same priority: added_at ascending (FIFO)
4. Return first entry, or null if no eligible entry exists
```

### `start(epic_id)`

Mark an EPIC as running.

```
0. CONFLICT_CHECK (see Conflict Detection Protocol below)
1. Find entry by epic_id
2. Set status = "running"
3. Set started_at = <now ISO 8601>
4. Update last_modified to current timestamp
5. Save epic-queue.yaml
```

### `complete(epic_id, result_status)`

Mark an EPIC as completed or failed.

```
0. CONFLICT_CHECK (see Conflict Detection Protocol below)
1. Find entry by epic_id
2. Set status = result_status (completed | failed)
3. Set completed_at = <now ISO 8601>
4. Update last_modified to current timestamp
5. Save epic-queue.yaml
```

### `pause_queue()`

Pause auto-pickup globally.

```
1. Set paused = true at top level
2. Update last_modified to current timestamp
3. Save epic-queue.yaml
4. Send Status Update (Slack Type G): ":double_vertical_bar: Queue paused by PM"
```

### `resume_queue()`

Resume auto-pickup.

```
1. Set paused = false at top level
2. Update last_modified to current timestamp
3. Save epic-queue.yaml
4. Send Status Update (Slack Type G): ":arrow_forward: Queue resumed"
```

### `list()`

Return full queue with status, priority, and timing info.

### `reorder(epic_id, new_priority)`

Change priority of a queued EPIC.

```
1. Find entry by epic_id
2. IF status != "queued" → reject: "Can only reorder queued EPICs"
3. Set priority = new_priority
4. Update last_modified to current timestamp
5. Save epic-queue.yaml
```

---

## Conflict Detection Protocol

Every queue mutation that modifies entry state (`add()`, `start()`, `complete()`) executes
CONFLICT_CHECK as Step 0 before any other logic. This prevents concurrent modification when
multiple sessions (e.g., PM running `/epic-queue` while Controller is auto-picking) write to
the same queue file.

### CONFLICT_CHECK Algorithm

```
CONFLICT_CHECK(expected_last_modified):
  1. Read epic-queue.yaml from disk (fresh read, NOT cached)
  2. Parse last_modified timestamp from file
  3. IF last_modified != expected_last_modified:
       → Abort operation
       → Log: "Conflict detected: queue modified since last read.
               Expected: {expected_last_modified}, Found: {last_modified}.
               Re-read queue and retry."
       → Return error to caller
  4. IF auto-mode flag file exists (see Auto-Mode Flag File section):
       → Read flag file contents
       → IF current operation is NOT from the Controller session identified in flag:
            → Log warning: "Queue mutation attempted while auto-mode is active.
                            Session {flag_session_id} is running. Concurrent modification risk."
            → Proceed (do not block) — warning is informational for audit trail
  5. PASSED — caller proceeds with mutation
```

### Caller Responsibility

Every caller that invokes a mutation operation MUST:
1. Read the queue file before calling the mutation
2. Extract `last_modified` from the read
3. Pass the extracted `last_modified` as `expected_last_modified` to the mutation
4. On conflict error: re-read the queue, re-evaluate conditions, and retry if still valid

### Which Operations Use CONFLICT_CHECK

| Operation | CONFLICT_CHECK | Rationale |
|-----------|---------------|-----------|
| `add()` | Yes | Prevents duplicate adds from concurrent sessions |
| `start()` | Yes | Prevents two sessions from starting different EPICs |
| `complete()` | Yes | Prevents stale completion overwriting a re-queued EPIC |
| `remove()` | No | PM-only operation; low concurrency risk |
| `pause_queue()` | No | PM-only operation; idempotent |
| `resume_queue()` | No | PM-only operation; idempotent |
| `reorder()` | No | PM-only operation; low concurrency risk |
| `next()` | No | Read-only; no mutation |
| `list()` | No | Read-only; no mutation |

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
| **Dependency validation** | `add()` validates that all `depends_on` IDs exist in the queue, rejects self-dependencies, and runs Kahn's algorithm to detect circular dependency chains before accepting the entry. |
| **Dependency-aware pickup** | `next()` only returns EPICs whose dependencies have ALL completed. Blocked EPICs remain queued but are skipped until their dependencies are satisfied. |
| **Persistence** | Queue state lives in YAML file — survives run restarts and context window resets. |
| **Running protection** | Cannot remove or reorder a running EPIC. |
| **Conflict detection** | Mutation operations (`add`, `start`, `complete`) check `last_modified` timestamp before writing. Concurrent modification aborts the operation. |
| **Auto-mode flag** | `.aid-o/04-engine/auto-mode-active.flag` signals active Controller session. Queue operations warn on concurrent access from non-Controller callers. |

---

## Auto-Mode Flag File

The file `.aid-o/04-engine/auto-mode-active.flag` provides fast external detection of an
active auto-mode session without parsing the full queue YAML.

### Format

Plain text, single line:

```
FA-{session_id} {started_at}
```

Example:

```
FA-20260217-a1b2 2026-02-17T10:05:00Z
```

### Lifecycle

| Event | Action | Responsible |
|-------|--------|-------------|
| FIRST_AID session starts | Create flag file | Controller (`first-aid-controller.md`) |
| FIRST_AID session completes | Delete flag file | Controller (`first-aid-controller.md`) |
| `/aid-stop` command issued | Delete flag file | Command (`aid-stop`) |
| Session crash / ungraceful exit | Flag file remains (stale) | Detected by staleness check below |

### Creation

The Controller writes the flag file as the FIRST action after FIRST_AID_INIT, before any
queue operations:

```
1. Generate session_id (format: FA-{YYYYMMDD}-{4-hex})
2. Write to .aid-o/04-engine/auto-mode-active.flag:
   "{session_id} {current ISO 8601 timestamp}"
3. Proceed with queue operations
```

### Deletion

The flag file is deleted in two paths:

1. **Normal completion** (FIRST_AID_COMPLETE): Controller deletes the flag after the final
   queue update (marking current EPIC complete and before auto-pickup of next EPIC, or
   when entering idle state).
2. **Manual stop** (`/aid-stop`): Command deletes the flag file as part of graceful shutdown.

### Staleness Detection

If the flag file exists but the Controller session is not active (e.g., after a crash):

```
1. Read flag file → extract started_at timestamp
2. IF (now - started_at) > 4 hours:
     → Log warning: "Stale auto-mode flag detected. Session {session_id} started
                     {started_at} but no activity in 4+ hours."
     → Flag is NOT auto-deleted (PM must investigate and delete manually or via /aid-stop)
3. ELSE:
     → Treat as active session (Controller may be in a long-running step)
```

### Queue Operation Integration

Queue mutation operations reference the flag file in CONFLICT_CHECK Step 4:

- If the flag file exists and the current operation is NOT from the Controller session
  identified in the flag, a warning is logged about concurrent modification risk.
- The warning is informational — it does not block the operation. This preserves PM
  ability to manage the queue via `/epic-queue` while auto-mode is active, while
  creating an audit trail of concurrent access.

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
- Queue state is read from disk each time (not cached). Combined with the
  `last_modified` conflict detection protocol, this ensures consistency even if
  the PM modifies the queue via `/epic-queue` while an EPIC is running.
- The auto-mode flag file (`.aid-o/04-engine/auto-mode-active.flag`) enables fast
  detection of active auto-mode sessions. It is cheaper to check than parsing the
  full queue YAML. Queue operations log warnings on concurrent access but do not
  block PM operations — the PM always retains manual override capability.
- Parallelism is within EPICs (parallel_groups, analysis_groups), not between EPICs.
- Dependencies are validated at `add()` time (existence check + cycle detection) and
  enforced at `next()` time (only EPICs with all dependencies completed are eligible).
  An EPIC with a failed dependency will remain queued indefinitely until the dependency
  is resolved (re-run and completed) or the dependency is removed from `depends_on`.

---

**Last Updated:** 2026-02-27
