---
sidebar_position: 4
title: "Run Management"
description: "Run lifecycle, ID generation, document hierarchy (Plan/Task/Quick), evidence structure, and workspace file protocols."
---

# Run Management

The run management skill defines how AID tracks work: what a run file is, when to create one, how it evolves, and the mandatory lifecycle protocols at each transition point. It also defines the document hierarchy (Plan/Task/Quick) and the ID system.

## Document Hierarchy

Three levels, no overlap:

| Document | Purpose | Location |
|----------|---------|----------|
| **Plan** | Forming ideas, rough approach | `.aid-o/plans/` |
| **Task** | Complex work (3+ runs), breakdown | `.aid-o/tasks/` |
| **Quick** | Single-conversation fast work | Q-NNN.md (FAST MODE) |
| **Run** | Detailed work plan for one run | `.aid-o/work/tasks/` |

Never mix locations. The directory IS the document type.

## ID System

Sequential IDs from `.aid-o/config/counter.yaml`:

| Document | Format | Example |
|----------|--------|---------|
| Plan | `P{NNN}` | `P001` |
| EPIC from plan | `E-{NNN}-{phase}_{total}` | `E-005-1_4` |
| Ad-hoc EPIC | `E-{NNN}` | `E-001` |
| Run | `R-{EPIC_ID}-{run_number}` | `R-005-1_4-1` |

Run file names encode ID and topic: `R-005-1_4-1-gui-foundation.md`. Branch: `run/R-005-1_4-1-gui-foundation`.

## Run Lifecycle

### Phase 1: Initialization
1. Read `active.md`, `command-history.md`, `lessons-learned.md`
2. Read `project.yaml` (if missing or >7 days old, run `/aid-init`)
3. New run: assess complexity, generate ID, create run file from template, get PM approval, create branch
4. Continuation: load run file, review last phase, announce next steps

### Phase 2: Work Loop
```
Loop:
  1. Announce phase start
  2. Implement + self-test
  3. PHASE-END CHECKPOINT (HARD STOP)
  4. PM GO -> quality gates -> commit -> next phase
  5. PM STOP -> handoff
```

**PHASE-END is a HARD STOP.** Before continuing: update run file, update active.md, write summary, propose QA steps if testable, check context window, STOP and ask PM. Do NOT continue without PM GO.

### Phase 3: Run-End
1. Final quality gates
2. Update project documentation (mandatory impact analysis)
3. Update workspace files (command-history, lessons-learned, backlog)
4. Present completion options to PM
5. Archive run file to `runs/archive/`

### Phase 4: Handoff (Optional)
When work is paused mid-implementation. Handoff block includes: completed tasks with commits, current progress, next steps, decisions made, key locations, how to test, branch info.

## Run Closure (DONE State)

1. Write `state.yaml`: `state: DONE`
2. Append to `timeline.jsonl`
3. Run [Curator](../agents/curator) agent (post-gate hook)
4. Write lessons to `backlog.md`
5. Archive task file to `.aid-o/tasks/archive/`
6. Update `active.md`

## Workspace Files

Updated at run-end:
- `command-history.md` -- new working commands
- `lessons-learned.md` -- new insights
- `active.md` -- current focus, recent work, next steps
- `backlog.md` -- issues discovered but not fixed

## v2 Workspace Layout

```
.aid-o/
  plans/           # Plans (archive/)
  tasks/           # Task specs / EPICs (archive/)
  config/          # PM config: policies/, templates/, playbooks/
    project.yaml   # From /aid-init
    counter.yaml   # ID counters
  work/            # AI workspace
    tasks/         # Active run files (archive/)
    active.md
    backlog.md
    lessons-learned.md
    command-history.md
    evidence/      # EPIC execution evidence
    timeline.jsonl
    state.yaml
```

## Related

- [Agent Protocol](./agent-protocol) -- output format for evidence
- [Pipeline](./pipeline) -- FSM states and transitions
- [Quality Gates](./quality-gates) -- pre-commit checks
- [Memory](./memory) -- context loading
