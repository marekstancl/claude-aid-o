---
status: active
plan_ref: null
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-006-1_1 --- Test/Rewrite Files Verbs (v2.57.2 parser fix)

## Context

Regression fixture for the `aid-epic-to-json.sh` Files-verb parser: before
v2.57.2 the label-strip step only removed `Create:` / `Modify:` prefixes, so a
Files entry using the plan-template-sanctioned `Test:` or `Rewrite:` verb kept
its label and produced a non-path-like allowed_paths entry
("Test: `path` — desc"), which broke the pipeline `allowed_paths_shape`
contract. This fixture carries one artifact per verb (Create, Modify, Test,
Rewrite) so the strip is observable for all four.

This EPIC covers Phase 1 of 1 from plan P-TEST-006 (standalone fixture, no real
plan backs it).

## Goal

Verify that Create/Modify/Test/Rewrite Files verbs are all stripped, leaving
bare path-like allowed_paths entries in the generated plan.json.

## Scope

### Allowed files/paths
- `src/core/module.py`
- `src/core/routes.py`
- `tests/test_module.py`
- `src/core/legacy.py`

### Forbidden zones
- <!-- No forbidden zones specified in plan -->

## Artifacts

- Create: `src/core/module.py`
- Modify: `src/core/routes.py`
- Test: `tests/test_module.py`
- Rewrite: `src/core/legacy.py`

## Constraints

- Fixture only — no real files exist under these paths
- No external runtime dependencies

## DoD Gates

- tests_pass

## Acceptance Criteria

- [ ] [backend] Module exposes the create/update API against the approved contract
- [ ] [backend] Routes wire the module into the request pipeline
- [ ] [qa] Regression test asserts the four verb-labelled Files entries strip to bare paths

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
| 1 | backend | Implement the core module and wire it into the routes. | --- | --- |
| 2 | qa | Add regression coverage for the Files-verb strip. | 1 | --- |

## Run Breakdown

### Run 1: Phase 1
**Goal:** Verify Create/Modify/Test/Rewrite verbs are stripped from allowed_paths.
**Deliverables:** Phase 1 of 1 from plan P-TEST-006

## Hints

- expected_steps: 2
- complexity: low
- parallelism_potential: low

## Notes

<!-- Auto-generated fixture for test-epic-to-json-regression.sh T6 (v2.57.2 Test:/Rewrite: verb strip) -->
