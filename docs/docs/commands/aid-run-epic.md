---
sidebar_position: 11
title: "/aid-run-epic"
description: "Execute the full EPIC orchestration pipeline through the 11-state Controller"
---

# /aid-run-epic

Run the Controller state machine to orchestrate an EPIC through its full lifecycle: Plan Review → Execute Steps → Quality Gates → PM Approval → Done. This is the main orchestration command — once started, it runs autonomously, dispatching agents, checking outputs, retrying failures, and escalating to PM only when necessary.

## Usage

```bash
/aid-run-epic <epic-id-or-path>
/aid-run-epic                      # Auto-detects if only one active EPIC
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `epic-id-or-path` | string | No | EPIC ID or path to the EPIC file. Auto-detected if only one active EPIC exists. |

## Prerequisites

- `.aid-o/` workspace must exist
- EPIC file must exist in `.aid-o/02-epics/` or at the given path
- Plan JSON should exist (from [`/aid-plan-epic`](./aid-plan-epic)). If not, plan generation runs automatically.

## Examples

```bash
# Run by EPIC ID
/aid-run-epic E-005-1_1

# Run by file path
/aid-run-epic .aid-o/02-epics/E-005-1_1-user-auth.md

# Auto-detect the only active EPIC
/aid-run-epic
```

## State Machine

The Controller implements 11 states:

| State | Description |
|-------|-------------|
| **IDLE** | Resolve EPIC, load or generate Plan JSON, initialize evidence |
| **PLANNING** | Generate Plan JSON + run file if not already present |
| **PLAN_REVIEW** | Present step sequence and budget to PM for GO / REVISE / ABORT |
| **EXECUTING** | Dispatch the next agent (sequential or parallel group) |
| **PHASE_CHECK** | Verify outputs, scope, acceptance criteria; dispatch code-reviewer if needed |
| **NEXT_PHASE** | Mark step done, find next available step(s) |
| **GATES** | Run quality gates (tests, lint, security, docs) |
| **GATE_RETRY** | Dispatch fix agent, re-run failed gate; up to `max_retries_per_gate` attempts |
| **ESCALATION** | Send PM a structured decision request (fix / skip / abort) |
| **CURATOR_RESOLVE** | Auto-evaluate Curator proposals; dispatch fix agents for approved items |
| **PM_APPROVAL** | Send PM final merge approval request (APPROVE / REJECT / REVISE) |
| **DONE** | Merge branches, version bump, archive, audit, memory indexing |

## PM Checkpoints

AID contacts you at three mandatory checkpoints (via Slack if configured, otherwise in chat):

1. **PLAN_REVIEW** — approve the execution plan before any agents are dispatched
2. **ESCALATION** — handle a failure that the system could not resolve automatically
3. **PM_APPROVAL** — approve the final merge after all gates pass

Everything else is autonomous, driven by `decision-policies.yaml`.

## DONE State Actions

After PM approves the merge, the DONE state:

1. Updates the run file status to `completed`
2. Runs the release sub-phase (version bump, git tag, GitHub release) if CHANGELOG and version files are out of sync
3. Merges step branches into the EPIC base branch, then creates a PR to main
4. Archives the run file
5. Updates `active-work.md`
6. Dispatches the Curator agent (backlog proposals) and Lessons-Extractor agent in parallel
7. Dispatches the Auditor agent for a post-run health audit
8. Indexes EPIC summary, architectural decisions, and patterns into Qdrant
9. Presents a structured completion summary with next-step options
10. Checks the EPIC queue — if auto-pickup is active and a queued EPIC exists, starts the next one

## Branch Strategy

```
Base branch:     epic/{epic_id}/main    (created from main at EPIC start)
Per-step:        epic/{epic_id}/step_{N}_{role}
Parallel steps:  all fork from epic/{epic_id}/main (same base commit)
Merge order:     sequential by step number after all steps in the group pass PHASE_CHECK
Final:           epic/{epic_id}/main → PR to project main branch
```

## Evidence

Every state transition is logged to `stage_log.jsonl`. All artifacts are stored under:

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  plan.json                           # Execution plan
  plan_progress.json                  # Live progress tracker
  epic_input.md                       # Copy of the EPIC file
  stage_log.jsonl                     # State machine audit log
  gates_report.json                   # Gate results with retry history
  pm_plan_approval.json               # PM plan review decision
  pm_decision.json                    # PM escalation/merge decisions
  curator_resolve_report.json         # Curator proposal outcomes
  final_report.md                     # Post-run summary
  steps/step_{N}_{role}/
    prompt.md                         # Dispatch prompt
    output.md                         # Agent output
    diff.patch                        # File changes
    review.md                         # Code-reviewer feedback (if dispatched)
```

## Resuming an Interrupted Run

If a run was interrupted, re-run the same command. The Controller reads `plan_progress.json` to determine which steps are already done and continues from where it left off. If `plan_progress.json` is corrupted, it rebuilds state from `stage_log.jsonl`.

## Notes

- The EPIC file is **never modified** during execution — only the copy in the evidence directory
- Budget tracking is approximate; a warning is sent when 80% of the configured budget is consumed
- If git operations fail, orchestration continues without branching (a warning is logged)

## Related

- [`/aid-plan-epic`](./aid-plan-epic) — generate Plan JSON before running
- [`/aid-epic-status`](./aid-epic-status) — check status during execution
- [`/aid-first-aid`](./aid-first-aid) — autonomous mode for the full queue
- [`/aid-stop`](./aid-stop) — stop autonomous mode (for use with `/aid-first-aid`)
