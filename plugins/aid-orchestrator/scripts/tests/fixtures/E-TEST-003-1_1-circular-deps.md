---
status: active
plan_ref: null
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-003-1_1 --- Circular Dependency Test

## Context

This EPIC fixture is intentionally malformed to test cycle detection in
the aid-epic-to-json.sh script. Steps 1 and 2 declare mutual dependencies,
which Kahn's algorithm must detect and report as a circular dependency error.

## Goal

Intentionally trigger circular dependency detection in aid-epic-to-json.sh
to verify the script exits with code 1 and emits a JSON error on stderr.

## Scope

### Allowed files/paths
- `src/test/`

### Forbidden zones
- <!-- No forbidden zones -->

## Artifacts

- `src/test/placeholder.py`

## Constraints

- This fixture must NOT be used as a real EPIC input

## DoD Gates

- docs_updated

## Acceptance Criteria

- [ ] [qa] Cycle detection test passes

## Dependencies

### Internal (same plan)
<!-- No internal dependencies -->

### External (other plans/EPICs)
<!-- No external dependencies -->

### Queue Implications
depends_on: []

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Implement the first module that depends on the second module output. | 2 | --- |
| 2 | qa | Write tests for the first module that themselves depend on first module. | 1 | --- |

## Run Breakdown

### Run 1: Cycle Test
**Goal:** Trigger cycle detection.
**Deliverables:** None — this fixture should cause an error exit.

## Hints

- expected_steps: 2
- complexity: low
- parallelism_potential: low

## Notes

<!-- Intentionally circular fixture for cycle detection tests -->
