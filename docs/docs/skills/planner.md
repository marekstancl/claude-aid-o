---
sidebar_position: 6
title: "Planner"
description: "Script contract for aid-epic-to-json.sh: EPIC to plan.json conversion, dependency graph, wave assembly, and run splitting."
---

# Planner

The planner skill documents the contract for `aid-epic-to-json.sh` -- the bash script that converts an EPIC specification into a `plan.json` execution artifact. All deterministic computation (dependency graph, wave assignment, parallel groups) is performed by the script. The LLM's role is limited to two decisions: validating the dependency graph and deciding whether to split runs.

## Purpose

The planner converts EPIC intent into an executable plan: a JSON structure with validated dependencies, wave-based execution groups, quality gate settings, and file manifests per step.

## When Used

- Invoked from [Pipeline](./pipeline) PRE-FLIGHT state
- Script output reviewed by PM at READY state
- Referenced by the pipeline throughout EXECUTE state

## Script Contract

```bash
aid-epic-to-json.sh <epic_file> <output_dir>
```

**Writes:**
- `plan.json` -- step list with waves, dependencies, parallel groups
- `plan_progress.json` -- execution state tracker (all steps pending)
- `execution.yaml` -- gates configuration derived from `gates.yaml`

**Exits non-zero on:** circular dependencies, unknown step IDs, no steps found, missing required EPIC sections.

The LLM does NOT generate plan.json inline. It invokes the script and reviews output.

## Dependency Graph

The script builds a DAG from EPIC step `depends_on` fields:

1. Parse EPIC steps into `(step_id, role, objective, depends_on[])` tuples
2. Build adjacency list
3. Validate: no cycles (Kahn's sort), all references exist, no self-dependencies
4. Assign levels: `level(S) = max(level(dep)+1)` for each dependency
5. Assemble waves: group same-level steps, split waves with 5+ into sub-waves of 4

**Example:**

```
Level 0: [step_1_architect]                         -> wave 0
Level 1: [step_2_domain, step_4_frontend]           -> wave 1 (parallel)
Level 2: [step_3_backend]                           -> wave 2
Level 3: [step_5_qa, step_6_security, step_7_docs]  -> wave 3 (parallel)
```

## Parallel Group Detection

Steps at the same dependency level run in parallel. If two same-level steps have overlapping `allowed_paths`, the script places them in sequential sub-waves.

## Run Split Decision (LLM)

The script does not split runs -- this is an LLM judgment call:

- **More than 7 steps:** propose split (Run 1: waves 0-1 foundation, Run 2: waves 2+ implementation)
- **7 or fewer steps:** single run
- **Rule:** never split inside a wave

Present split proposal to PM before PRE-FLIGHT.

## Output: plan.json

```json
{
  "epic_id": "EPIC-001",
  "steps": [
    { "id": "step_1_architect", "role": "architect", "objective": "...", "depends_on": [], "model": "opus" }
  ],
  "waves": [["step_1_architect"], ["step_2_domain", "step_4_frontend"]],
  "parallel_groups": [["step_2_domain", "step_4_frontend"]],
  "gates": ["tests_pass", "lint_pass", "security_scan_pass", "docs_updated"]
}
```

Model field is assigned from role card tiers, not dispatch config.

## Related

- [Pipeline](./pipeline) -- PRE-FLIGHT invokes this skill
- [Brainstorming](./brainstorming) -- produces the plan that becomes an EPIC
- [Role Cards](./role-cards) -- model tier per role
