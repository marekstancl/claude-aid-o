---
sidebar_position: 15
title: "Parallel Dispatch"
description: "Branch management and concurrent agent execution protocol — defines how multiple agents work in parallel on separate branches and how their outputs are merged."
---

# Parallel Dispatch

The parallel dispatch skill defines how multiple agents are dispatched concurrently during EPIC execution. It covers branch creation strategy, the distinction between code-producing and analysis-only parallel groups, conflict detection (git, semantic, scope), and the extended PHASE_CHECK rules that apply when parallel groups complete.

## Purpose

Some EPIC steps are independent of each other and can run concurrently: a frontend agent and a backend agent implementing their respective layers based on the same architect step, or three analysis agents reviewing the same step from different perspectives. Parallel dispatch cuts wall-clock time by running these simultaneously rather than sequentially. The challenge is merging the results without losing work or silently accepting conflicting changes.

## When Used

- Triggered by the Controller during EXECUTING state when the plan's `parallel_groups` entry lists multiple agents for the same step group
- Used for both code-producing groups (agents that write files) and analysis groups (agents that only review)
- The Planner generates `parallel_groups` automatically based on the dependency graph (steps with the same dependency level can run in parallel)
- Analysis groups are also defined by the Planner for multi-perspective review of sensitive steps

## Key Concepts

### Branch Strategy

Each EPIC creates a base branch `epic/{epic_id}` at IDLE. For parallel code-producing groups:

- All parallel step branches fork from `epic/{epic_id}/main` at the **same commit** — agents start from identical state
- Each agent works on `epic/{epic_id}/step_{N}_{role}`
- Merge order is deterministic: lower step number merges first
- After all merges, the step branches are deleted

For analysis groups: no branches are created. Analysis agents are read-only; their outputs go to the evidence directory only.

If git is unavailable, all branching is skipped and agents work on the filesystem directly. Branching is best-effort and never halts the pipeline.

### Conflict Detection

The Controller checks for three types of conflicts after parallel agents complete:

**Git conflicts** — detected before merging with a dry-run (`git merge --no-commit --no-ff`). Any conflict triggers escalation E6 in auto-mode; in manual mode, PM is asked to resolve before the merge proceeds.

**Semantic conflicts** — two agents produce contradictory decisions or interface definitions (e.g., different field names for the same API contract). Detected during PHASE_CHECK by comparing agent outputs. Triggers escalation E10 in auto-mode.

**Scope conflicts** — an agent modifies files outside its `allowed_paths`. The first violation triggers a warning and re-dispatch; the second triggers escalation E9.

### Merge Order

Merges are deterministic to avoid non-deterministic conflict patterns:
1. Sequential merges in step number order (step_3 merges before step_4)
2. Within the same step number, alphabetical by role name
3. Each merge is a clean commit — no squash, no rebase

### Analysis Groups vs. Code-Producing Groups

| Aspect | Code-Producing | Analysis |
|---|---|---|
| Branches | Yes — one per agent | No — read-only |
| Output goes to | Filesystem + evidence | Evidence only |
| Merge required | Yes | No |
| Conflict risk | Yes (git + semantic) | No (findings only) |
| PHASE_CHECK | Normal step validation | Findings routed to analysis-merge |

## How It Works

When the Controller encounters a parallel group in the plan:

1. **Branch preparation**: create all step branches from the same base commit (code-producing only)
2. **Parallel dispatch**: send all agents simultaneously (single message, multiple Task calls)
3. **Output collection**: wait for all agents to complete; validate each output's YAML structure
4. **Analysis merge** (if analysis group): run the configured merge strategy on all findings
5. **Conflict detection** (if code-producing): dry-run merge to detect git conflicts before committing
6. **Sequential merge**: merge step branches in deterministic order
7. **PHASE_CHECK**: validate all outputs together; check for semantic conflicts

Any agent that produces invalid output is logged as a warning. If minimum viable agents complete successfully, the group proceeds with available outputs. If a critical agent fails, escalation E5 fires.

## Configuration

Parallel groups are defined in the plan JSON, generated automatically by the Planner:

```json
{
  "parallel_groups": [
    {
      "group_id": "group_2",
      "steps": ["step_2_domain", "step_3_frontend"],
      "type": "code",
      "merge_strategy": "sequential"
    }
  ]
}
```

The `type` field is either `"code"` (file-producing) or `"analysis"` (review-only). The Planner selects type based on the agents' roles — analysis agents (security, code-reviewer, docs-reviewer) are always analysis-only.

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Analysis Merge](../skills/analysis-merge)
- [Planner](../skills/planner)
- [Auto Escalation](../skills/auto-escalation)
- [Cost Optimization](../skills/cost-optimization)
