---
sidebar_position: 17
title: "Planner"
description: "Converts an EPIC specification into a validated Plan JSON by building a dependency graph, detecting parallel groups via topological sort, and auto-generating analysis groups for sensitive steps."
---

# Planner

The planner skill converts an EPIC specification into a validated Plan JSON that the Controller uses to drive execution. It builds a dependency graph from the EPIC's steps, runs a topological sort to detect which steps can run in parallel, applies default ordering rules when the EPIC is underspecified, and auto-generates `analysis_groups` for steps that are security-sensitive, high-complexity, or contract-changing.

## Purpose

EPIC files describe intent: what each step should do and what it depends on. The Planner converts this intent into an executable plan: a JSON structure with validated dependencies, wave-based execution groups (respecting parallelism and file conflicts), analysis configurations, quality gate settings, and a file manifest for each step. Without the Planner, the Controller would have no structured execution schedule.

## When Used

- Invoked by the Controller at PLANNING state after loading the EPIC
- Output reviewed by PM at PLAN_REVIEW — PM can revise the plan before execution begins
- Referenced by the Controller throughout EXECUTING state (which wave, which step, which files)
- The `analysis_groups` section drives analysis dispatch at PHASE_CHECK
- The `relevant_files` per step feeds the cost optimization strategy

## Key Concepts

### Dependency Graph Construction

The Planner parses each EPIC step's `depends_on` list and builds a directed acyclic graph (DAG). It validates three conditions:
1. No cycles (topological sort via Kahn's algorithm — if fewer nodes are sorted than total, a cycle exists)
2. All referenced steps exist (no dangling dependencies)
3. No self-dependencies

The output is a `dependencies[]` array with `before`, `after`, and `reason` fields for each edge.

### Wave Assembly

Steps are assigned to execution waves based on their dependency level:
- Level 0: no dependencies (can run immediately)
- Level N: max dependency level of all prerequisites + 1
- Steps at the same level can run in parallel within a wave

Waves are capped at 4 steps maximum. Larger levels are split into sub-waves, keeping same-domain steps together. Before finalizing a wave, the Planner checks for file path conflicts (two steps sharing `allowed_paths`) and splits conflicting steps into sequential sub-waves.

### Analysis Group Generation

The Planner automatically generates `analysis_groups` for steps that match any of these triggers:
- Security-sensitive: step role is `backend` or `frontend`, and the EPIC involves auth/payments/data
- High-complexity: step has 3+ dependencies
- Contract-changing: step modifies API contracts or database schema

The auto-selected merge strategy follows the decision flow: security review → union; large groups (3+) with no clear expert → consensus; architecture review → weighted. PM can override during PLAN_REVIEW.

### File Manifest (relevant_files)

For each step, the Planner generates a `relevant_files` list — the files from previous steps that this step needs to read. This feeds the cost optimization strategy, allowing agents to read the right files immediately rather than discovering them through Glob operations.

The Architect agent in step 1 generates the project file manifest. The Planner extracts the subset of files relevant to each downstream step based on declared dependencies.

## How It Works

1. Parse all EPIC steps into `(step_id, role, objective, depends_on[])` tuples
2. Build the dependency graph and validate it
3. Assign levels via topological sort
4. Detect file path conflicts within same-level groups
5. Assemble waves (maximum 4 steps, conflict-split as needed)
6. Auto-generate analysis groups for qualifying steps
7. Apply default quality gate configuration from `gates.yaml`
8. Validate the complete plan against `defaults/templates/plan.schema.json`
9. Output validated Plan JSON to the evidence directory

If the EPIC has underspecified dependencies (no `depends_on` fields), the Planner applies a default ordering: architect → domain → backend → frontend → qa → security → docs.

## Configuration

The plan schema is defined in `defaults/templates/plan.schema.json`. The Planner validates the generated plan against this schema before returning it. Schema validation failures cause the PLANNING state to fail and trigger ESCALATION.

Quality gate defaults come from `.aid-o/03-config/policies/gates.yaml`. Analysis group merge strategy defaults follow the decision flowchart in the `analysis-merge` skill.

## Related

- [Epic Orchestration](../skills/epic-orchestration)
- [Analysis Merge](../skills/analysis-merge)
- [Parallel Dispatch](../skills/parallel-dispatch)
- [Cost Optimization](../skills/cost-optimization)
