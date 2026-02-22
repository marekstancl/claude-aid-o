---
name: aid-epic-queue
description: EPIC queue management (add, remove, pause)
user_invocable: true
---

Manage the EPIC execution queue — add, remove, reorder, pause, and monitor EPICs for autonomous pipeline execution.

The queue enables the Orchestrator to process multiple EPICs in sequence without manual intervention. After each EPIC completes (including Curator + Auditor post-processing), the Orchestrator automatically picks up the next EPIC from the queue.

## Usage

```
/aid-epic-queue                                           # Show queue (= list)
/aid-epic-queue list                                      # Show queue with status
/aid-epic-queue add <epic-path> [--priority <level>]      # Add EPIC to queue
/aid-epic-queue remove <epic-id>                          # Remove from queue
/aid-epic-queue next                                      # Show next EPIC in line
/aid-epic-queue pause                                     # Pause auto-pickup
/aid-epic-queue resume                                    # Resume auto-pickup
/aid-epic-queue reorder <epic-id> --priority <level>      # Change priority
```

**Priority levels:** `critical` | `high` | `medium` (default) | `low`

## Prerequisites

- `.aid-o/` workspace must exist
- Queue file: `.aid-o/04-engine/aid-epic-queue.yaml`
- If queue file doesn't exist, create it with empty queue on first use

## Core Instruction

**Read `skills/aid-epic-queue.md` FIRST.** It is the authoritative source for queue operations, priority rules, auto-pickup protocol, and safety guards.

## Commands

---

### `/aid-epic-queue` or `/aid-epic-queue list`

Display the full queue with status, priority, and timing.

**Actions:**
1. Read `.aid-o/04-engine/aid-epic-queue.yaml`
2. If file doesn't exist → print "No queue configured. Use `/aid-epic-queue add` to start."
3. Display queue:

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

If queue is paused:
```
Auto-pickup: PAUSED (2 EPICs queued, waiting for /aid-epic-queue resume)
```

---

### `/aid-epic-queue add <epic-path> [--priority <level>]`

Add an EPIC to the queue.

**Actions:**
1. Parse `$ARGUMENTS` — extract epic path and optional `--priority` flag
2. If no path → list EPICs in `.aid-o/02-epics/` and ask which to add
3. Validate EPIC file exists and has required sections (Goal, Scope, Constraints)
4. Call `add(epic_path, priority)` from `skills/aid-epic-queue.md`:
   - Default priority: `medium`
   - Reject if duplicate (already queued or running)
5. Confirm:
   ```
   Added to queue: E-20260217-c3d4-api-v2 (priority: medium)
   Position: 3 of 3 queued EPICs
   ```

---

### `/aid-epic-queue remove <epic-id>`

Remove an EPIC from the queue.

**Actions:**
1. Parse `$ARGUMENTS` — extract epic_id
2. Call `remove(epic_id)` from `skills/aid-epic-queue.md`
3. If running → reject: "Cannot remove a running EPIC. Pause the queue first."
4. Confirm:
   ```
   Removed from queue: E-20260217-c3d4-api-v2
   ```

---

### `/aid-epic-queue next`

Show the next EPIC that will be picked up.

**Actions:**
1. Call `next()` from `skills/aid-epic-queue.md`
2. Display:
   ```
   Next EPIC: E-20260217-c3d4-api-v2 (priority: medium)
   Path: .aid-o/02-epics/E-20260217-c3d4-api-v2.md
   Added: 1h ago
   ```
   Or: "Queue is empty. Add EPICs with `/aid-epic-queue add`."

---

### `/aid-epic-queue pause`

Pause auto-pickup. The currently running EPIC continues, but no new EPIC starts.

**Actions:**
1. Call `pause_queue()` from `skills/aid-epic-queue.md`
2. Confirm:
   ```
   Queue paused. Auto-pickup disabled.
   Currently running EPIC (if any) will continue to completion.
   Use /aid-epic-queue resume to re-enable auto-pickup.
   ```

---

### `/aid-epic-queue resume`

Resume auto-pickup.

**Actions:**
1. Call `resume_queue()` from `skills/aid-epic-queue.md`
2. If an EPIC just completed while paused, check if next should start:
   - If queue has next EPIC → inform PM: "Queue resumed. Next EPIC will start after current run (or immediately if idle)."
3. Confirm:
   ```
   Queue resumed. Auto-pickup enabled.
   Next in line: E-20260217-c3d4-api-v2 (medium)
   ```

---

### `/aid-epic-queue reorder <epic-id> --priority <level>`

Change the priority of a queued EPIC.

**Actions:**
1. Parse `$ARGUMENTS` — extract epic_id and new priority
2. Call `reorder(epic_id, new_priority)` from `skills/aid-epic-queue.md`
3. If not queued → reject: "Can only reorder EPICs with status 'queued'."
4. Confirm with new queue order:
   ```
   Updated: E-20260217-c3d4-api-v2 → priority: high
   New queue order:
    1. E-20260217-c3d4-api-v2 (high)
    2. E-20260218-e5f6-dashboard (low)
   ```

---

## Reference Files

- **PRIMARY:** `skills/aid-epic-queue.md` — queue format, operations, auto-pickup protocol, safety guards
- `skills/epic-orchestration.md` — DONE state auto-pickup trigger
- `skills/slack-mcp.md` — Status updates for queue events
- `commands/aid-run-epic.md` — Consumes next EPIC from queue in DONE state

## Important

- Queue file is created automatically on first `/aid-epic-queue add` if it doesn't exist
- The queue persists across sessions (YAML file on disk)
- Auto-pickup only happens in the Orchestrator's DONE state — not triggered by this command
- `/aid-epic-queue pause` does NOT abort a running EPIC — it prevents the next one from starting
- If the queue file doesn't exist when the Orchestrator checks (DONE state), it simply skips auto-pickup
- If `$ARGUMENTS` is empty → default to `list` behavior
