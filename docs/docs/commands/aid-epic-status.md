---
sidebar_position: 5
title: "/aid-epic-status"
description: "Show pipeline status — steps, gates, budget, and recent activity"
---

# /aid-epic-status

Show the current status of an EPIC pipeline, including step progress, gate results, budget usage, and recent activity. This is a read-only command — it never modifies any files.

## Usage

```bash
/aid-epic-status [epic-id]
/aid-epic-status              # Show overview of all EPICs
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `epic-id` | string | No | EPIC ID to inspect. If omitted, shows an overview of all EPICs. |

## Examples

```bash
# Detailed status for a specific EPIC
/aid-epic-status E-005-1_1

# Overview of all active and recently completed EPICs
/aid-epic-status
```

## How It Works

### With an EPIC ID — Detailed Status

Reads the latest run evidence from `.aid-o/04-engine/evidence/{epic_id}/` and displays:

- **State** — current state machine state (EXECUTING, GATES, PM_APPROVAL, etc.)
- **Steps** — completion status for each step with visual indicators
- **Gates** — gate results and retry attempt counts
- **Escalations** — any PM decisions that were required
- **Budget** — estimated spend vs. configured maximum
- **Evidence path** — where all run artifacts are stored
- **Recent activity** — last 5 entries from the stage log

**Step status icons:**

| Icon | Meaning |
|------|---------|
| ✅ | Done / passed |
| 🔄 | Running / in progress |
| ⏳ | Pending / not yet run |
| ❌ | Failed |
| ⏭️ | Skipped |

### Without an EPIC ID — Overview

Lists all EPICs found in `.aid-o/02-epics/` along with their run status:

```
Active EPICs
====================================
1. E-005-1_1 — Add Health Check Endpoint    [EXECUTING] step 3/7
2. E-006-1_1 — User Authentication           [GATES] retry 2/3

Recently Completed:
3. E-004-1_1 — Fix login timeout              [DONE] 2026-02-14

No plan yet:
4. E-007-1_1 — Optimize queries              (run /aid-plan-epic to start)
```

## Edge Cases

**No EPICs found** — the command explains how to create and start an EPIC.

**EPIC exists but no plan** — prompts you to run `/aid-plan-epic {path}`.

**EPIC exists but no run started** — shows the plan summary and prompts you to run `/aid-run-epic {epic_id}`.

## Notes

- Budget estimates are approximate, based on prompt sizes and dispatch counts
- Recent activity is read from `stage_log.jsonl` — the last 5–10 entries are shown

## Related

- [`/aid-run-epic`](./aid-run-epic) — execute the EPIC orchestration pipeline
- [`/aid-plan-epic`](./aid-plan-epic) — generate Plan JSON from an EPIC file
- [`/aid-epic-queue`](./aid-epic-queue) — manage the EPIC execution queue
