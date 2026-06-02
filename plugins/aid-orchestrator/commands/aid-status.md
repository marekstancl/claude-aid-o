---
name: aid-status
description: Show EPIC status, queue, and pipeline overview
user_invocable: true
---

Show pipeline status, EPIC details, and queue management — unified view of everything running, queued, or completed.

## Usage

```
/aid-status                                  # overview: active EPICs + queue summary
/aid-status <epic-id>                        # detailed EPIC status (reads fsm-state.yaml)
/aid-status queue                            # queue management view
/aid-status queue add <path> [--priority]    # add EPIC to queue
```

**Priority levels:** `critical` | `high` | `medium` (default) | `low`

## Flow

### `/aid-status` — Overview (default)

1. **Scan active EPICs:**
   - List files in `.aid-o/tasks/` (not `archive/`)
   - For each, check `.aid-o/work/evidence/{epic_id}/` for run data
2. **Scan quick logs:**
   - Count files in `.aid-o/work/quick/Q-*.md`
   - Show last 3 by date
3. **Read queue:**
   - Read `.aid-o/config/queue.yaml` (if exists)
   - Show summary: N queued, N running, N done
4. **Display:**

```
AID Status
====================================

Active EPICs:
  E-003-1_2 — Add Auth System           [EXECUTE] step 3/7
  E-003-2_2 — Auth Frontend             [queued]  waiting on E-003-1_2

Recent Quick Tasks:
  Q-007 — Add login button              (2 min ago, 3 files)
  Q-006 — Fix README typo               (1h ago, 1 file)

Queue: 2 queued, 1 running | Auto-pickup: active
Use /aid-status <id> for details, /aid-status queue for queue management.
```

### `/aid-status <epic-id>` — Detailed EPIC Status

1. **Find evidence:**
   - Look in `.aid-o/work/evidence/{epic_id}/`
   - Find latest run_id (most recent subdirectory)
   - Load `fsm-state.yaml` (v2 state file)
   - Load `timeline.jsonl` (last 10 entries)

2. **Display:**

```
EPIC Status: E-003-1_2 — Add Auth System
====================================
State: EXECUTE          ← from fsm-state.yaml .state
Step: 3/7               ← current_step / total_steps
Mode: manual            ← from fsm-state.yaml .mode
Branch: task/E-003-1_2  ← from fsm-state.yaml .branch
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

**Status when no run started:**
```
EPIC: E-003-1_2 — Add Auth System
Status: Plan ready, not started

Run /aid-run E-003-1_2 to start execution.
```

### `/aid-status queue` — Queue Management View

1. Read `.aid-o/config/queue.yaml`
   - If not found: "No queue configured. Use `/aid-status queue add` to start."
2. Compute eligibility for each entry
3. Display:

```
EPIC Queue
====================================
  [READY]    E-015-1_2  (high)   — no dependencies
  [RUN]      E-014-1_2  (high)   — started 2h ago
  [WAITING]  E-015-2_2  (medium) — waiting on: E-015-1_2
  [BLOCKED]  E-013-1_1  (medium) — blocked by failed: E-012-1_1
  [DONE]     E-014-1_2  (high)   — completed 3h ago

Auto-pickup: Active (1 READY, 1 WAITING, 1 BLOCKED)
```

**Eligibility tags:**
- `[READY]` — eligible for pickup (no deps or all deps completed)
- `[WAITING]` — deps in progress
- `[BLOCKED]` — deps failed or missing
- `[RUN]` — currently running
- `[DONE]` — completed
- `[FAIL]` — failed

### `/aid-status queue add <path> [--priority <level>]`

1. Validate EPIC file exists and has required sections
2. Reject if duplicate (already queued or running)
3. Create `.aid-o/config/queue.yaml` if it doesn't exist (lazy-create)
4. Add entry with default priority `medium`
5. Confirm: `Added to queue: {epic_id} (priority: {level}), position {N}`

## Edge Cases

**No EPICs found:**
```
No EPICs found.

Get started:
  /aid-do "quick task"     — implement something small
  /aid-plan                — plan something bigger
```

**EPIC exists but no evidence:**
```
EPIC: {id} — {title}
Status: Not started (no evidence directory)

Run /aid-run {id} to start execution.
```

## Evidence Paths

```
.aid-o/work/evidence/{epic_id}/{run_id}/   — run evidence root
  fsm-state.yaml                                — FSM state (replaces plan_progress.json)
  timeline.jsonl                            — event log (replaces stage_log.jsonl)
.aid-o/tasks/                               — EPIC files (replaces 02-epics/)
.aid-o/config/queue.yaml                    — queue (replaces 04-engine/epic-queue.yaml)
```

## Reference Files

- `skills/pipeline.md` — FSM states, evidence structure
- `scripts/aid-fsm.sh` — fsm-state.yaml format and transitions
- `scripts/lib/aid-stage-log.sh` — timeline.jsonl format

## Important

- **Read-only by default** — `/aid-status` and `/aid-status <id>` never modify files
- **Queue subcommands modify** — `add` writes to queue.yaml
- **Lazy queue creation** — `.aid-o/config/queue.yaml` created on first `queue add`
- **v2 paths only** — reads `fsm-state.yaml` (not `plan_progress.json`), `timeline.jsonl` (not `stage_log.jsonl`)
- If `$ARGUMENTS` is empty → show overview (default)


**Last Updated:** 2026-06-01
