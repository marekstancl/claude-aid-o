---
status: active
plan_ref: null
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-005-1_1 --- Step Scoping Repro (P057)

## Context

Regression fixture for the P057/P058 per-step scoping bug: `aid-epic-to-json.sh`
currently BROADCASTS the flat `## Artifacts` list and the flat
`## Scope > Allowed files/paths` list to EVERY step, instead of assigning each
step only its own outputs/allowed_paths. It also splits Acceptance Criteria on
a delimiter (`IFS='|||'`) that collides with a literal `|` inside AC text,
silently fragmenting AC items that legitimately contain a pipe (e.g. jq
expressions). This fixture carries two steps (backend, qa) with genuinely
distinct files and acceptance criteria so the bug is observable, plus a
multi-path Files entry and a literal `|`/`-->` in AC text to exercise those two
adjacent defects at the same time.

This EPIC covers Phase 1 of 1 from plan P-TEST-005 (standalone fixture, no
real plan backs it).

## Goal

Verify that per-step outputs, allowed_paths, and acceptance_criteria in the
generated plan.json are scoped to each step individually — not broadcast from
the EPIC-level flat sections.

## Scope

### Allowed files/paths
Tento seznam dnes generátor broadcastuje na OBA kroky (backend i qa) — to je
právě reprodukovaná vada; po fixu (Step 3) budou allowed_paths odvozené
per-step z Implementation Steps `**Files:**`, ne z tohoto seznamu.
- `scripts/tests/fixtures/e_test_005_fake/backend_service.py`
- `scripts/tests/fixtures/e_test_005_fake/backend_routes.py`
- `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (both changelogs must stay in sync)
- `scripts/tests/fixtures/e_test_005_fake/test_backend_service.py`
- `scripts/tests/fixtures/e_test_005_fake/test_backend_routes.py`

### Forbidden zones
- <!-- No forbidden zones specified in plan -->

## Artifacts

- Create: `scripts/tests/fixtures/e_test_005_fake/backend_service.py`
- Modify: `scripts/tests/fixtures/e_test_005_fake/backend_routes.py`
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (both changelogs must stay in sync)
- Create: `scripts/tests/fixtures/e_test_005_fake/test_backend_service.py`
- Create: `scripts/tests/fixtures/e_test_005_fake/test_backend_routes.py`

## Implementation Steps

<!--
  NOT parsed by today's aid-epic-to-json.sh (no code path reads this H2 —
  confirmed via grep, only aid-plan-to-epic.sh reads "**Files:**" and it reads
  it from plan.md, not from EPIC.md). Kept here as the per-step ground truth
  that P058 Steps 2-3 will wire into the real per-step HTML-comment block
  (see plan Step 2) without needing to touch this fixture. Distinct Files
  per step is the (a) requirement from P058 Step 1.
-->

### Step 1: backend — Implement widget service backend layer

**Files:**
- Create: `scripts/tests/fixtures/e_test_005_fake/backend_service.py`
- Modify: `scripts/tests/fixtures/e_test_005_fake/backend_routes.py`
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (both changelogs must stay in sync)

### Step 2: qa — Regression tests for the widget backend

**Files:**
- Create: `scripts/tests/fixtures/e_test_005_fake/test_backend_service.py`
- Create: `scripts/tests/fixtures/e_test_005_fake/test_backend_routes.py`

## Constraints

- Fixture only — no real service exists under `scripts/tests/fixtures/e_test_005_fake/`
- No external runtime dependencies

## DoD Gates

- tests_pass

## Acceptance Criteria

- [ ] [backend] Widget service `create()` and `update()` return validated DTOs backed by the new persistence layer
- [ ] [backend] Contract chain resolves start --> middle --> end without truncation when the widget route follows nested references
- [ ] [qa] Regression assert confirms `jq '.steps[0].outputs | length == 3'` returns 3 for step 1's own outputs only, not the EPIC-wide artifact union
- [ ] [qa] Multi-path artifact `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` both appear as separate allowed_paths entries for step 1, not one merged/truncated entry

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
| 1 | backend | Implement the widget service backend layer with create/update persistence against the approved contract. | --- | --- |
| 2 | qa | Write regression tests validating per-step scoping of outputs, allowed_paths, and acceptance criteria for the widget backend. | 1 | --- |

## Step UI Contracts

<!-- Per-step files/ac ground truth for the P058 Step 3 fix (Data Model D2 —
     per-step scoping blok v EPIC.md, placed after the Steps table, reusing
     this section's HTML-comment-block pattern the same way the existing
     ui_change_mode= line does). Today's aid-epic-to-json.sh only reads
     "ui_change_mode=" out of a matched "<!-- step-N:" line (see
     parse_step_ui_contracts() + the grep in Step 9 of that script) — it
     greps the whole line, then seds for ui_change_mode=, finds none in the
     two lines below, so ui_change_mode/ui_change_contract stay null for
     both steps (verified against the current generator). Zero effect on T5
     today; this is the block Step 3 will parse instead of falling back to
     broadcast. The step-1 ac[] value below intentionally embeds a raw
     comment-closer sequence mid-string, untouched, no sentinel-encoding
     applied yet — that reproduces the exact comment-carrier truncation risk
     the P058 Step 2 Files bullet calls out as needing an encode/decode
     sentinel. Do not "fix" the embedded sequence here; it is the fixture. -->
<!-- step-1: files=["Create: `scripts/tests/fixtures/e_test_005_fake/backend_service.py`","Modify: `scripts/tests/fixtures/e_test_005_fake/backend_routes.py`","Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (both changelogs must stay in sync)"]; ac=["Widget service `create()` and `update()` return validated DTOs backed by the new persistence layer","Contract chain resolves start --> middle --> end without truncation when the widget route follows nested references"] -->
<!-- step-2: files=["Create: `scripts/tests/fixtures/e_test_005_fake/test_backend_service.py`","Create: `scripts/tests/fixtures/e_test_005_fake/test_backend_routes.py`"]; ac=["Regression assert confirms `jq '.steps[0].outputs | length == 3'` returns 3 for step 1's own outputs only, not the EPIC-wide artifact union","Multi-path artifact `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` both appear as separate allowed_paths entries for step 1, not one merged/truncated entry"] -->

## Run Breakdown

### Run 1: Phase 1
**Goal:** Verify per-step outputs/allowed_paths/acceptance_criteria are scoped per step, not broadcast.
**Deliverables:** Phase 1 of 1 from plan P-TEST-005

## Hints

- expected_steps: 2
- complexity: medium
- parallelism_potential: low

## Notes

<!-- Auto-generated fixture for test-epic-to-json-regression.sh T5 (P058 Step 1, red test) -->
