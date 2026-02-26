---
sidebar_position: 6
title: "/aid-first-aid"
description: "Launch FIRST AID autonomous orchestration mode — process the entire EPIC queue without PM interaction"
---

# /aid-first-aid

Launch **FIRST AID** (Fully Integrated Autonomous Development) mode. Once started, AID processes every queued EPIC end-to-end — plan, execute, gate, merge, pick up next — without requiring PM input, except for defined escalation triggers.

This is the top-level autonomous command. It wraps the entire EPIC lifecycle: permission backup and elevation, mode flag management, queue iteration, per-EPIC orchestration, and a cross-EPIC summary report at completion.

## Usage

```bash
/aid-first-aid                  # Start auto-mode with current queue
/aid-first-aid --resume         # Resume a paused or crashed session
/aid-first-aid --dry-run        # Validate queue and permissions without executing
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `--resume` | flag | No | Resume from a previously saved session (after `/aid-stop` or a crash) |
| `--dry-run` | flag | No | Validate queue and permissions and show what would happen, without executing |

## Prerequisites

- `.aid-o/` workspace must exist (run [`/aid-init`](./aid-init) first)
- EPIC queue must have at least one entry with status `queued` (use [`/aid-epic-queue add`](./aid-epic-queue))
- `.claude/settings.json` must exist and be valid JSON (or will be auto-created)
- `permissions-auto.yaml` must exist (resolved from project, plugin defaults, or auto-generated)

## Examples

```bash
# Process all queued EPICs autonomously
/aid-first-aid

# Preview the queue and permission state without executing
/aid-first-aid --dry-run

# Resume after stopping with /aid-stop or after a crash
/aid-first-aid --resume
```

## How It Works

FIRST AID has its own state machine that wraps the per-EPIC orchestration loop:

```text
FIRST_AID_INIT → QUEUE_PROCESSING → [per-EPIC: IDLE→...→DONE] → QUEUE_ADVANCE → FIRST_AID_COMPLETE
                                                                       ↑               |
                                                                       └── more EPICs ──┘
```

### Startup Sequence

On first invocation, FIRST AID:

1. Validates the workspace and EPIC queue
2. Checks for and cleans up any orphaned temp files
3. Backs up your current `~/.claude/settings.json` permissions
4. Elevates permissions to the auto-mode set (from `permissions-auto.yaml`)
5. Initializes session state in `.aid-o/04-engine/auto-mode-state.yaml`
6. Displays a startup banner with session ID, queue contents, and escalation budget
7. Begins processing EPICs from the queue in priority order

### Per-EPIC Execution (Auto-Mode Overrides)

Each EPIC runs through the full [`/aid-run-epic`](./aid-run-epic) state machine with these auto-mode differences:

| Decision Point | Manual Behavior | Auto-Mode Behavior |
|----------------|----------------|-------------------|
| PLAN_REVIEW | PM approves GO/REVISE/ABORT | Auto-approved if validation passes; escalates on failure |
| PHASE_CHECK | Auto-decide or code-reviewer | Same, plus one extra "fresh approach" retry cycle |
| GATES | Auto-retry up to configured maximum | Identical to manual |
| PM_APPROVAL | PM approves APPROVE/REJECT/REVISE | Auto-approved; guardrail check on last EPIC |
| DONE release | PM chooses release now or defer | Auto-defers for intermediate EPICs; mandatory bump on last |

### PM Interaction — Escalation Only

PM is only contacted for 16 defined escalation triggers, including:

- Agent output fails acceptance criteria after 3 cycles
- A gate fails after all retry attempts
- A scope violation is detected
- The escalation budget is reached

Use [`/aid-stop`](./aid-stop) at any time to disengage autonomous mode and return to manual control. Progress is saved and the session is resumable.

## Notes

- **Permissions are always restored** on completion or stop, even if earlier steps fail
- The **escalation budget** (default: 3) limits how many PM interventions are allowed before the session pauses for review
- Running agents are **not interrupted** by `/aid-stop` — the current step completes, but no new agents are dispatched
- The queue persists across sessions; remaining EPICs stay queued when you stop and resume

## Related

- [`/aid-stop`](./aid-stop) — emergency stop to disengage auto-mode immediately
- [`/aid-epic-queue`](./aid-epic-queue) — add, remove, and reorder EPICs in the queue
- [`/aid-run-epic`](./aid-run-epic) — run a single EPIC manually
- [`/aid-epic-status`](./aid-epic-status) — check status during autonomous execution
