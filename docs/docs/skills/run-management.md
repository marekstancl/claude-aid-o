---
sidebar_position: 20
title: "Run Management"
description: "Defines the document hierarchy (plan, epic, run), run file lifecycle protocols, ID system, and the mandatory transitions for brainstorming-end, phase-end, and run-end."
---

# Run Management

The run management skill defines how AID tracks work within a single run: what a run file is, when to create one, how it evolves with the code, and the mandatory lifecycle protocols at each transition point. It also defines the document hierarchy that distinguishes plans, epics, and runs, and the ID system that connects them.

## Purpose

Without a run file, work is unrecoverable after a context reset: there is no record of what was decided, what changed, where things were left off, or what to do next. The run file is the living document of a run — not a static template but an evolving record of decisions, phases, commits, and outcomes. It is what makes handoffs possible and continuations coherent.

## When Used

- Created at the start of every non-trivial run (multi-file, multi-phase work)
- Updated after every commit and at every phase-end
- Read at the start of every continuation run
- Archived at run completion
- Referenced by `agent-core` (Run Start Protocol reads active-work.md which links to the current run file)

## Key Concepts

### Document Hierarchy

Plans, EPICs, and runs serve distinct purposes. Using the wrong document type in the wrong location is a hard error:

| Document | Purpose | Location | Lifecycle |
|---|---|---|---|
| **Plan** | Forming ideas, rough approach | `.aid-o/01-plans/` | Static — written once, referenced |
| **Epic** | Complex task specification, breakdown into runs | `.aid-o/02-epics/` | Updated after each run (progress, decisions) |
| **Run** | Detailed work plan for a single run | `.aid-o/04-engine/runs/` | Actively evolves with the code |

Never store a run file in `.aid-o/`, never put an EPIC in plans/, never put a plan in epics/. The directory is the document type.

### Run File as a Living Document

The run file starts as a plan and ends as a record:
- **At start**: describes what will be done (based on EPIC or plan + previous run state)
- **During work**: gets updated as phases complete, decisions are made, commits are recorded
- **At end**: captures what actually happened (may differ from the plan) — this is its most important value
- **After archival**: serves as context for the next run in the same EPIC

### ID System

All IDs are sequential, derived from `.aid-o/03-config/counter.yaml`:

| Document | Format | Example |
|---|---|---|
| Plan | `P{NNN}` | `P005` |
| EPIC from plan | `E-{NNN}-{phase}_{total}` | `E-005-1_4` |
| Ad-hoc EPIC | `E-{NNN}` | `E-001` |
| Run | `R-{EPIC_ID}-{run_number}` | `R-005-1_4-1` |

Run file names encode their ID and topic: `R-005-1_4-1-gui-foundation.md`. Branch names match: `run/R-005-1_4-1-gui-foundation`.

### Lifecycle Protocols

**Brainstorming-End**: present a session summary and ask PM "Plan or Run?" — use the design as reference for a single run, or execute as an EPIC?

**Run-Start**: create run file using the appropriate template, describe the planned work, get PM approval, then create the branch. Never create a branch before PM approval.

**Phase-End** (hard stop): summarize what was accomplished in this phase, update the run file and active-work.md, check context window size, and wait for PM GO before proceeding. Never continue to the next phase without PM acknowledgment.

**Run-End**: run documentation impact analysis per the project's docs platform playbook, update workspace files (command-history.md, lessons-learned.md, backlog.md), make the final commit, get PM approval for PR/merge, and archive the run file to `runs/archive/`.

### Workspace Files

At run-end, the agent updates:
- `command-history.md` — new working commands discovered this run
- `lessons-learned.md` — new gotchas, debugging insights, best practices
- `active-work.md` — current focus, recent work, next steps (for the next run's context)
- `backlog.md` — any issues discovered but not fixed this run

## How It Works

Every run starts with reading active-work.md (the authoritative current state), command-history.md, and lessons-learned.md. If a current run file is referenced in active-work.md, load it — this is a continuation.

For a new run: determine complexity (trivial = TodoList only, standard = run file + branch, complex = suggest EPIC). Create the run file from a template in `.aid-o/03-config/templates/`. Get PM approval. Create the branch.

Work proceeds in phases. Each phase ends with the phase-end protocol. After the final phase, the run-end protocol runs. The run file is archived to `runs/archive/` after the PR is merged or the work is otherwise complete.

## Configuration

Run templates are in `.aid-o/03-config/templates/`. The project profile at `.aid-o/04-engine/memory/project-profile.yaml` provides:
- `project.paths.runs_completed` — archive destination
- `project.paths.run_log` — run log file to update at completion
- `project.docs.platform` — determines which docs playbook to load at run-end

## Related

- [Agent Core](../skills/agent-core)
- [Epic Orchestration](../skills/epic-orchestration)
- [Quality Gates](../skills/quality-gates)
- [Brainstorming](../skills/brainstorming)
