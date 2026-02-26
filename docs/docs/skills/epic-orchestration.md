---
sidebar_position: 9
title: "Epic Orchestration"
description: "The Controller state machine that drives an EPIC from planning through execution, gates, Curator resolution, PM approval, and completion — with optional FIRST AID autonomous mode."
---

# Epic Orchestration

The epic orchestration skill defines the Controller: the state machine that drives an EPIC through its complete lifecycle. Every state transition produces evidence. Failures trigger retries (maximum 3) and then escalate to the PM. The Controller supports both manual mode (PM approves at each decision point) and FIRST AID auto-mode (PM approves the queue once; the Controller runs end-to-end).

## Purpose

An EPIC is a complex deliverable broken into multiple agent steps with dependencies, parallel groups, quality gates, and optional multi-perspective analysis. Without a Controller to orchestrate this, each step would require manual coordination, evidence would be scattered, and failures would be opaque. The Controller makes EPIC execution reliable and auditable.

## When Used

- Invoked by `/aid-run-epic` for every EPIC execution
- The state machine drives all agent dispatches, gate runs, Curator resolution, and PM approvals
- In FIRST AID mode, invoked by `/aid-first-aid` to process an entire queue autonomously
- All other orchestration skills (gates-engine, retry-engine, parallel-dispatch, analysis-merge, planner) are called from within the Controller state machine

## Key Concepts

### State Machine

The Controller moves through these states for each EPIC:

| State | Description |
|---|---|
| IDLE | Loads the EPIC, validates it, creates the branch |
| PLANNING | Dispatches the Planner to generate plan JSON |
| PLAN_REVIEW | PM reviews and approves (or revises) the plan |
| EXECUTING | Dispatches the assigned role agent for the current step |
| PHASE_CHECK | Validates step output, collects improvement notes, checks for analysis groups |
| NEXT_PHASE | Advances to the next step or moves to GATES |
| GATES | Runs the gates engine against the completed steps |
| GATE_RETRY | Dispatches gate-fixer and retries failing gates (max 3 attempts) |
| CURATOR_RESOLVE | Dispatches Curator to evaluate improvement notes against the backlog |
| PM_APPROVAL | PM reviews and approves the completed EPIC before merge |
| DONE | Branch merge, archival, release sub-phase, Qdrant metrics, post-processing |
| ESCALATION | Pauses execution, notifies PM, waits for decision |

### FIRST AID Auto-Mode

Auto-mode is stored in `.aid-o/04-engine/auto-mode-state.yaml`. When `mode: auto`, PM decision points use autonomous rules instead of interactive approval. The Controller reads this file at every decision point:
- `manual` — standard behavior (default)
- `auto` — FIRST AID autonomous execution
- `paused` — auto-mode interrupted by an escalation

Auto-mode starts with `/aid-first-aid` and stops with `/aid-stop`. Escalation is the only mandatory PM touchpoint in auto-mode (see `auto-escalation` skill).

### Evidence Trail

Every state transition writes to the EPIC's evidence directory:
```text
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  stage_log.jsonl          — timestamped state transitions
  plan_progress.json       — step completion status
  gates_report.json        — gate results and retry history
  steps/                   — per-step agent outputs and analysis
  escalations/             — escalation evidence (auto-mode)
  final_report.md          — EPIC completion report
```

### Metrics Storage

At DONE state, the Controller stores metrics to Qdrant: per-step agent execution data (duration, complexity, bottleneck, errors), EPIC summary (total duration, step count, slowest step, gate retries), gate results, and token profile. These feed the `analytics` skill.

### DONE State and Release Sub-Phase

The DONE state performs: run file update, release sub-phase (version bump detection and execution), branch merge, EPIC archival, final report generation, Auditor dispatch, Qdrant metrics, and example EPIC extraction.

The release sub-phase checks for a CHANGELOG version header that does not match the version files. If a mismatch is found:
- In manual mode, PM is asked about intermediate EPICs
- In auto-mode, intermediate EPICs defer the bump and the last/standalone EPIC bumps mandatorily (see `auto-done-state` skill)

## How It Works

After loading the EPIC at IDLE, the Controller dispatches the Planner which builds a dependency graph, detects parallel groups, auto-generates analysis groups for sensitive steps, and validates the plan against the JSON schema. PM reviews the plan at PLAN_REVIEW.

During EXECUTING, the Controller dispatches one or more agents per step (sequential or parallel), collecting structured `step_output` YAML. PHASE_CHECK validates the output, collects improvement notes, and checks for configured analysis groups that need to run before advancing.

After all steps complete, GATES runs the gates engine. Failing required gates go through GATE_RETRY (dispatch gate-fixer, re-run, escalate at max attempts). CURATOR_RESOLVE collects all improvement notes, runs the Curator agent to evaluate proposals against `decision-policies.yaml` and Qdrant history, and routes high-priority proposals back to agents for auto-fix. PM_APPROVAL presents the completed EPIC for final review before merge.

## Configuration

Key configuration files read at IDLE and cached for the session:
- `.aid-o/03-config/policies/gates.yaml` — quality gate definitions
- `.aid-o/03-config/policies/decision-policies.yaml` — Curator auto-evaluation rules
- `.aid-o/04-engine/memory/project-profile.yaml` — project paths and tech stack
- `.aid-o/03-config/policies/memory-config.yaml` — Qdrant and knowledge settings
- `.aid-o/04-engine/auto-mode-state.yaml` — current execution mode

## Related

- [Planner](../skills/planner)
- [Gates Engine](../skills/gates-engine)
- [Retry Engine](../skills/retry-engine)
- [Parallel Dispatch](../skills/parallel-dispatch)
- [Analysis Merge](../skills/analysis-merge)
- [Auto Done State](../skills/auto-done-state)
- [Auto Escalation](../skills/auto-escalation)
- [Improvement Proposals](../skills/improvement-proposals)
