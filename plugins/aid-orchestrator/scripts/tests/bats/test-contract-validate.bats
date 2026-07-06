#!/usr/bin/env bats
# test-contract-validate.bats — P058 Step 4, D5 canonical behavioral test.
#
# Covers the contract-validation gate (aid-contract-validate.sh), its
# BLOCKING wiring into aid-auto-pipeline.sh, and the C0 review Check 6
# read-only wiring in aid-c0-contract.sh. One canonical bats file per this
# step's plan text ("jeden soubor, ne .sh+.bats dispatch").
#
# All fixtures are built inline (heredoc) in mktemp-isolated subprocess
# workspaces — no new files added to scripts/tests/fixtures/ (out of this
# step's allowed_paths).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  GATE="$AID_PLUGIN_PATH/scripts/gates/aid-contract-validate.sh"
  PIPELINE="$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  C0_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-c0-contract.sh"
  EPIC_TO_JSON="$AID_PLUGIN_PATH/scripts/aid-epic-to-json.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  FIXTURE_STEP_SCOPING="$AID_PLUGIN_PATH/scripts/tests/fixtures/E-TEST-005-1_1-step-scoping-repro.md"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── Gate unit tests: aid-contract-validate.sh in isolation ─────────────────

@test "aid-contract-validate.sh: exit 0 on a genuinely per-step-scoped clean plan.json" {
  local out_dir="$TEST_TMPDIR/clean-gen"
  mkdir -p "$out_dir"
  run bash "$EPIC_TO_JSON" --epic "$FIXTURE_STEP_SCOPING" --schema "$SCHEMA" --output-dir "$out_dir"
  [ "$status" -eq 0 ]
  local plan_json
  plan_json="$(echo "$output" | jq -r '.plan_json')"
  [ -f "$plan_json" ]

  run "$GATE" "$plan_json" "$FIXTURE_STEP_SCOPING"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
  echo "$output" | jq -e '[.checks[].status] == ["pass","pass","pass"]'
  echo "$output" | jq -e '.violations == []'
}

@test "aid-contract-validate.sh: exit non-zero with violations on a broadcast (per_step_scoping) plan.json" {
  local plan_json="$TEST_TMPDIR/broadcast-plan.json"
  cat > "$plan_json" <<'JSON'
{
  "epic_id": "E-BROADCAST-1_1",
  "version": 1,
  "steps": [
    {
      "id": "step_1_backend",
      "role": "backend",
      "outputs": ["Create: `a.py`", "Create: `b.py`"],
      "allowed_paths": ["a.py", "b.py"],
      "acceptance_criteria": ["a works", "b works"]
    },
    {
      "id": "step_2_qa",
      "role": "qa",
      "outputs": ["Create: `a.py`", "Create: `b.py`"],
      "allowed_paths": ["a.py", "b.py"],
      "acceptance_criteria": ["tests pass"]
    }
  ],
  "dependencies": []
}
JSON

  run "$GATE" "$plan_json"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '[.checks[] | select(.id == "per_step_scoping")][0].status == "fail"'
  echo "$output" | jq -e '[.violations[] | select(startswith("per_step_scoping"))] | length > 0'
}

@test "aid-contract-validate.sh: ac_no_fragments flags a bare '.enforcements' fragment-smell" {
  local plan_json="$TEST_TMPDIR/fragment-plan.json"
  cat > "$plan_json" <<'JSON'
{
  "epic_id": "E-FRAGMENT-1_1",
  "version": 1,
  "steps": [
    {
      "id": "step_1_backend",
      "role": "backend",
      "outputs": ["Create: `a.py`"],
      "allowed_paths": ["a.py"],
      "acceptance_criteria": [
        "registry `type: 4` řádek; `totals == .enforcements",
        "length`; TTL guard projde."
      ]
    }
  ],
  "dependencies": []
}
JSON

  run "$GATE" "$plan_json"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '[.checks[] | select(.id == "ac_no_fragments")][0].status == "fail"'
}

@test "aid-contract-validate.sh: ac_no_fragments does NOT false-positive on a legit AC with a balanced jq/backtick expression" {
  local plan_json="$TEST_TMPDIR/legit-plan.json"
  cat > "$plan_json" <<'JSON'
{
  "epic_id": "E-LEGIT-1_1",
  "version": 1,
  "steps": [
    {
      "id": "step_1_qa",
      "role": "qa",
      "outputs": ["Create: `test_a.py`"],
      "allowed_paths": ["test_a.py"],
      "acceptance_criteria": [
        "Regression assert confirms `jq '.steps[0].outputs | length == 3'` returns 3 for step 1's own outputs only"
      ]
    }
  ],
  "dependencies": []
}
JSON

  run "$GATE" "$plan_json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.checks[] | select(.id == "ac_no_fragments")][0].status == "pass"'
}

@test "aid-contract-validate.sh: ac_no_fragments does NOT false-positive on a plural-possessive AC (CP2 regression)" {
  local plan_json="$TEST_TMPDIR/plural-possessive-plan.json"
  cat > "$plan_json" <<'JSON'
{
  "epic_id": "E-PLURAL-1_1",
  "version": 1,
  "steps": [
    {
      "id": "step_1_qa",
      "role": "qa",
      "outputs": ["Create: `test_a.py`"],
      "allowed_paths": ["test_a.py"],
      "acceptance_criteria": [
        "Users' permissions must not change when workers' shifts are updated"
      ]
    }
  ],
  "dependencies": []
}
JSON

  run "$GATE" "$plan_json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.checks[] | select(.id == "ac_no_fragments")][0].status == "pass"'
}

@test "aid-contract-validate.sh: ac_no_fragments STILL flags a generic (non-literal) truncated numeric fragment" {
  local plan_json="$TEST_TMPDIR/generic-truncation-plan.json"
  cat > "$plan_json" <<'JSON'
{
  "epic_id": "E-TRUNC-1_1",
  "version": 1,
  "steps": [
    {
      "id": "step_1_qa",
      "role": "qa",
      "outputs": ["Create: `test_a.py`"],
      "allowed_paths": ["test_a.py"],
      "acceptance_criteria": [
        "count == 3'"
      ]
    }
  ],
  "dependencies": []
}
JSON

  run "$GATE" "$plan_json"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.checks[] | select(.id == "ac_no_fragments")][0].status == "fail"'
}

@test "aid-contract-validate.sh: allowed_paths_shape flags prose/verb-prefix/parenthetical entries" {
  local plan_json="$TEST_TMPDIR/proseshape-plan.json"
  cat > "$plan_json" <<'JSON'
{
  "epic_id": "E-PROSE-1_1",
  "version": 1,
  "steps": [
    {
      "id": "step_1_backend",
      "role": "backend",
      "outputs": ["Create: `docs/x.md`"],
      "allowed_paths": ["Create/Modify: docs/x.md (nebo rozšířit stávající)"],
      "acceptance_criteria": ["docs updated"]
    }
  ],
  "dependencies": []
}
JSON

  run "$GATE" "$plan_json"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '.result == "fail"'
  echo "$output" | jq -e '[.checks[] | select(.id == "allowed_paths_shape")][0].status == "fail"'
}

@test "aid-contract-validate.sh: fatal input errors (missing file, invalid JSON) still emit JSON + exit 1" {
  run "$GATE" "$TEST_TMPDIR/does-not-exist.json"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.result == "fail"'

  local bad_json="$TEST_TMPDIR/bad.json"
  echo 'not json' > "$bad_json"
  run "$GATE" "$bad_json"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.result == "fail"'
}

# ─── Pipeline wiring: BLOCKING abort + persist-before-abort ─────────────────

@test "aid-auto-pipeline.sh: aborts non-zero on a broadcast-shaped EPIC (no per-step Files) — no run.md, no queue entry" {
  cat > "$TEST_PROJECT_ROOT/plan-nofiles.md" <<'PLANMD'
---
id: P900
type: plan
status: draft
created: 2026-07-05
author: PM + AI
---

# Plan: No-Files Broadcast Repro

## Context

Steps deliberately omit per-step **Files:** subsections, forcing
aid-epic-to-json.sh's no-block fallback (broadcast from flat EPIC-level
Scope/Artifacts) instead of per-step scoping.

## Goal

Reproduce a legacy-shaped (no per-step Files) EPIC to prove the D5
contract-validation gate blocks it.

## Scope

**In scope:**
- src/legacy/handler.py
- src/legacy/routes.py

**Out of scope:**
- src/new/

## Approach

### Option A: Single Phase (Recommended)
Single EPIC, two steps, no per-step Files.

### Decision

**Chosen:** Option A
**Rationale:** minimal repro

## Implementation Steps

**EPIC 1: Steps 1-2 — Legacy Touch**

### Step 1: Touch legacy handler

**Objective:** Modify the legacy handler to add a new code path.

**AID Role:** backend

**Acceptance Criteria:**
- [ ] Handler compiles
- [ ] No regression in existing handler tests

### Step 2: Touch legacy routes

**Objective:** Modify the legacy routes to wire the new code path.

**AID Role:** backend

**Acceptance Criteria:**
- [ ] Routes compile
- [ ] No regression in existing route tests

## Constraints

- No new runtime dependencies

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| none | low | low | n/a |

## Success Criteria

- Both steps land

## Next Steps

- [ ] Create Epic from this plan

---

**Last Updated:** 2026-07-05
PLANMD

  cd "$TEST_PROJECT_ROOT"
  run "$PIPELINE" --plan plan-nofiles.md --queue-mode chain --plugin-dir "$AID_PLUGIN_PATH"
  [ "$status" -ne 0 ]

  # Contract-validate.json recorded a FAIL before the abort (persist-before-abort)
  local cv_file="$TEST_PROJECT_ROOT/.aid-o/work/evidence/plan-nofiles/c0/contract-validate.json"
  [ -f "$cv_file" ]
  run jq -e '.result == "fail"' "$cv_file"
  [ "$status" -eq 0 ]

  # No run.md and no queue entry were created for this phase
  local run_count
  run_count="$(find "$TEST_PROJECT_ROOT/.aid-o/work/runs" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$run_count" -eq 0 ]

  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml" ]
}

@test "aid-auto-pipeline.sh: clean multi-step, per-step-Files EPIC still passes the D5 gate and completes" {
  cat > "$TEST_PROJECT_ROOT/plan-clean.md" <<'PLANMD'
---
id: P902
type: plan
status: draft
created: 2026-07-05
author: PM + AI
---

# Plan: Clean Per-Step Files Repro

## Context

Minimal single-phase plan whose two steps each carry their own **Files:**
subsection, so aid-epic-to-json.sh derives genuinely per-step outputs and
allowed_paths (no broadcast).

## Goal

Confirm the D5 gate does not false-positive on a well-formed EPIC.

## Scope

**In scope:**
- src/core/

**Out of scope:**
- src/legacy/

## Approach

### Option A: Single Phase (Recommended)
One EPIC, two steps, each with its own Files.

### Decision

**Chosen:** Option A
**Rationale:** minimal repro

## Implementation Steps

**EPIC 1: Steps 1-2 — Core**

### Step 1: Write the initial module

**Objective:** Implement the core module with basic data structures.

**AID Role:** backend

**Files:**
- Create: `src/core/module.py`
- Create: `src/core/utils.py`

**Acceptance Criteria:**
- [ ] Module loads without errors
- [ ] Helper functions return expected types

### Step 2: Write unit tests for the module

**Objective:** Create a unit test suite covering all public functions.

**AID Role:** qa

**Files:**
- Create: `tests/test_module.py`

**Acceptance Criteria:**
- [ ] All public functions have at least one test
- [ ] Tests pass in CI

## Constraints

- No new runtime dependencies

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| none | low | low | n/a |

## Success Criteria

- Both steps land, per-step scoped

## Next Steps

- [ ] Create Epic from this plan

---

**Last Updated:** 2026-07-05
PLANMD

  cd "$TEST_PROJECT_ROOT"
  run "$PIPELINE" --plan plan-clean.md --queue-mode chain --plugin-dir "$AID_PLUGIN_PATH"
  [ "$status" -eq 0 ]

  local cv_file="$TEST_PROJECT_ROOT/.aid-o/work/evidence/plan-clean/c0/contract-validate.json"
  [ -f "$cv_file" ]
  run jq -e '.result == "pass"' "$cv_file"
  [ "$status" -eq 0 ]

  local run_count
  run_count="$(find "$TEST_PROJECT_ROOT/.aid-o/work/runs" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$run_count" -gt 0 ]
  [ -f "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml" ]
}

@test "aid-auto-pipeline.sh: multi-phase phase-2 failure overwrites phase-1 pass in contract-validate.json (no stale pass)" {
  cat > "$TEST_PROJECT_ROOT/plan-mixed.md" <<'PLANMD'
---
id: P901
type: plan
status: draft
created: 2026-07-05
author: PM + AI
---

# Plan: Mixed Clean/Broadcast Phases Repro

## Context

Two-phase fixture: Phase 1 has real per-step **Files:** subsections (clean).
Phase 2 omits them entirely, forcing the no-block broadcast fallback so its
contract-validate run fails. Proves contract-validate.json (shared per
plan_id, not per phase) reflects the LATEST phase's result, not a stale
earlier pass.

## Goal

Prove phase-2 failure overwrites a phase-1 pass in contract-validate.json.

## Scope

**In scope:**
- src/legacy/handler.py
- src/legacy/routes.py

**Out of scope:**
- src/new/

## Approach

### Option A: Two Phases (Recommended)
Phase 1 clean, Phase 2 broadcast-shaped.

### Decision

**Chosen:** Option A
**Rationale:** minimal repro of persist-before-abort across phases

## Implementation Steps

**EPIC 1: Steps 1-2 — Clean Phase**

### Step 1: Write the initial module

**Objective:** Implement the core module with basic data structures.

**AID Role:** backend

**Files:**
- Create: `src/core/module.py`
- Create: `src/core/utils.py`

**Acceptance Criteria:**
- [ ] Module loads without errors
- [ ] Helper functions return expected types

### Step 2: Write unit tests for the module

**Objective:** Create a unit test suite covering all public functions.

**AID Role:** qa

**Files:**
- Create: `tests/test_module.py`

**Acceptance Criteria:**
- [ ] All public functions have at least one test
- [ ] Tests pass in CI

**EPIC 2: Steps 3-4 — Broadcast (No-Files) Phase**

### Step 3: Touch legacy handler

**Objective:** Modify the legacy handler to add a new code path.

**AID Role:** backend

**Acceptance Criteria:**
- [ ] Handler compiles
- [ ] No regression in existing handler tests

### Step 4: Touch legacy routes

**Objective:** Modify the legacy routes to wire the new code path.

**AID Role:** backend

**Acceptance Criteria:**
- [ ] Routes compile
- [ ] No regression in existing route tests

## Constraints

- No new runtime dependencies

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| none | low | low | n/a |

## Success Criteria

- Phase 1 EPIC is per-step scoped
- Phase 2 EPIC is broadcast-shaped and blocked by the D5 gate

## Next Steps

- [ ] Create Epics from this plan

---

**Last Updated:** 2026-07-05
PLANMD

  cd "$TEST_PROJECT_ROOT"
  run "$PIPELINE" --plan plan-mixed.md --queue-mode chain --plugin-dir "$AID_PLUGIN_PATH"
  [ "$status" -ne 0 ]

  # Shared-per-plan-id contract-validate.json must show FAIL (phase 2's
  # result), not a stale PASS left over from phase 1.
  local cv_file="$TEST_PROJECT_ROOT/.aid-o/work/evidence/plan-mixed/c0/contract-validate.json"
  [ -f "$cv_file" ]
  run jq -e '.result == "fail"' "$cv_file"
  [ "$status" -eq 0 ]

  # Phase 1 (E-901-1_2) succeeded: queued + run.md exists.
  run grep -c "E-901-1_2" "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  local phase1_runs
  phase1_runs="$(find "$TEST_PROJECT_ROOT/.aid-o/work/runs" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$phase1_runs" -gt 0 ]

  # Phase 2 (E-901-2_2) did NOT reach queue/run stage.
  run grep -c "E-901-2_2" "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml"
  [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
}

# ─── C0 review Check 6: reads (never re-runs) contract-validate.json ───────

@test "aid-c0-contract.sh review: Check 6 reflects a persisted PASS result" {
  local c0_dir="$TEST_TMPDIR/c0-pass"
  mkdir -p "$c0_dir"
  echo '{"result":"pass","checks":[],"violations":[]}' > "$c0_dir/contract-validate.json"

  run bash "$C0_SCRIPT" review "$AID_PLUGIN_PATH/scripts/tests/fixtures/c0/clean-plan/plan.md" "$c0_dir"
  [ "$status" -eq 0 ]

  run jq -e '.plan_review.structural_checks[] | select(.id == "contract_validation") | .status == "pass"' "$c0_dir/plan-review.json"
  [ "$status" -eq 0 ]
}

@test "aid-c0-contract.sh review: Check 6 reflects a persisted FAIL result (does not re-run the gate)" {
  local c0_dir="$TEST_TMPDIR/c0-fail"
  mkdir -p "$c0_dir"
  echo '{"result":"fail","checks":[{"id":"per_step_scoping","status":"fail","detail":"broadcast"}],"violations":["per_step_scoping: broadcast"]}' > "$c0_dir/contract-validate.json"

  run bash "$C0_SCRIPT" review "$AID_PLUGIN_PATH/scripts/tests/fixtures/c0/clean-plan/plan.md" "$c0_dir"
  [ "$status" -eq 0 ]

  # review itself stays observe-only (exit 0) even though the underlying
  # contract-validate result is FAIL — blocking already happened upstream in
  # the pipeline hook, before review ever runs on a genuinely failing phase.
  run jq -e '.plan_review.structural_checks[] | select(.id == "contract_validation") | .status != "pass"' "$c0_dir/plan-review.json"
  [ "$status" -eq 0 ]
}

@test "aid-c0-contract.sh review: Check 6 is 'unverifiable' (never 'pass') when contract-validate.json is absent" {
  local c0_dir="$TEST_TMPDIR/c0-missing"
  mkdir -p "$c0_dir"

  run bash "$C0_SCRIPT" review "$AID_PLUGIN_PATH/scripts/tests/fixtures/c0/clean-plan/plan.md" "$c0_dir"
  [ "$status" -eq 0 ]

  run jq -e '.plan_review.structural_checks[] | select(.id == "contract_validation") | .status == "unverifiable"' "$c0_dir/plan-review.json"
  [ "$status" -eq 0 ]
}
