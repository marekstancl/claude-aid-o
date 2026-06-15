---
status: active
plan_ref: plugins/aid-orchestrator/scripts/tests/fixtures/docs-writer-plan.md
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-004-1_1 --- Docs-Writer Role Regression

## Context

Regression fixture for the hyphenated `docs-writer` role. The role is valid per
the schema enum, but its hyphen must be sanitized to an underscore when building
the step ID (the step.id pattern `^step_[a-z0-9_]+$` forbids hyphens). Guards the
P041 docs -> docs-writer rename against the step-ID validation introduced later.

This EPIC covers Phase 1 of 1 from plan P-TEST-004.

## Goal

Validate that a docs-writer step converts cleanly to plan.json.

Phase 1/1 deliverables:
- Step 1: Implement the core module with basic data structures and helper utilities.
- Step 2: Document the module behavior and add ADR entries describing the design.

## Scope

### Allowed files/paths
- `src/core/module.py`
- `docs/adrs.md`

### Forbidden zones
- <!-- No forbidden zones specified in plan -->

## Artifacts

- Create: `src/core/module.py`
- Create: `docs/adrs.md`

## Constraints

- No external runtime dependencies

## DoD Gates

- docs_updated

## Acceptance Criteria

- [ ] [backend] Module loads without errors
- [ ] [docs-writer] ADR entries document the four new decisions with status markers

## Dependencies

### Internal (same plan)
<!-- First phase --- no internal dependencies -->

### External (other plans/EPICs)
<!-- No external dependencies -->

### Queue Implications
depends_on: []

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Implement the core module with basic data structures and helper utilities. | --- | --- |
| 2 | docs-writer | Document the module behavior and add ADR entries describing the design decisions. | 1 | --- |

## Run Breakdown

### Run 1: Phase 1
**Goal:** Validate that a docs-writer step converts cleanly to plan.json.
**Deliverables:** Phase 1 of 1 from plan P-TEST-004

## Hints

- expected_steps: 2
- complexity: medium
- parallelism_potential: low

## Notes

<!-- Auto-generated fixture for test-epic-to-json.sh -->
