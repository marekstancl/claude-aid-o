---
status: active
plan_ref: null
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-004-1_1 --- UI Contract Round-Trip Test

## Context

Test EPIC for verifying that ui_change_contract envelope flows from EPIC to plan.json.

This EPIC covers Phase 1 of 1 from plan P-TEST-004.

## Goal

Verify round-trip: EPIC with ui_change_contract → plan.json steps[0].ui_change_contract non-null.

## Scope

### Allowed files/paths
- `src/ui/MyComponent.tsx`

### Forbidden zones
- <!-- No forbidden zones specified -->

## Artifacts

- Modify: `src/ui/MyComponent.tsx`

## Constraints

- Test only

## DoD Gates

- docs_updated

## Acceptance Criteria

- [ ] [frontend] ui_change_contract non-null in plan.json step 1

## Dependencies

### Internal (same plan)
<!-- None -->

### External (other plans/EPICs)
<!-- None -->

### Queue Implications
depends_on: []

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | frontend | Modify existing UI with typed delta contract. | --- | --- |

## Step UI Contracts

<!-- step-1: ui_change_mode=existing_ui | path=.aid-o/work/evidence/E-TEST-004/companion/delta-contract.json | sha256=abc123deadbeef | schema_version=1.0.0 -->

## Run Breakdown

### Run 1: Phase 1
**Goal:** Verify round-trip: EPIC with ui_change_contract → plan.json steps[0].ui_change_contract non-null.
**Deliverables:** Phase 1 of 1 from plan P-TEST-004

## Hints

- expected_steps: 1
- complexity: low
- parallelism_potential: low

## Notes

<!-- Test fixture for ui_change_contract round-trip -->
