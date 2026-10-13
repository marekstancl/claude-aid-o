#!/usr/bin/env bats
# aid-tier: t2
# test-contract-validate.bats — P058 Step 4, D5 canonical behavioral test.
#
# Covers the contract-validation gate (aid-contract-validate.sh) and its
# BLOCKING wiring into the former generation pipeline, in one canonical bats file.
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
  SCHEMA="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  FIXTURE_STEP_SCOPING="$AID_PLUGIN_PATH/scripts/tests/fixtures/E-TEST-005-1_1-step-scoping-repro.md"
  # IMP-503 (v2.85.1): DoD gate resolution refuses without a real execution.yaml
  # at the project's state root. An empty `gates:` mapping is a valid outcome;
  # this fixture only has to exist and parse.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'gates: {}\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── Gate unit tests: aid-contract-validate.sh in isolation ─────────────────


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




@test "per_step_scoping R1: same allowed_paths + distinct outputs + per-step blocks -> PASS" {
  local epic="$TEST_TMPDIR/r1.md" pj="$TEST_TMPDIR/r1.json"
  cat > "$epic" <<'MD'
<!-- step-1: files=["Modify: `shared.py`"]; ac=["feature A"] -->
<!-- step-2: files=["Modify: `shared.py`"]; ac=["feature B"] -->
MD
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R1-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Modify: `shared.py` -- feature A"],"allowed_paths":["shared.py"],"acceptance_criteria":["feature A"]},
  {"id":"step_2_backend","role":"backend","outputs":["Modify: `shared.py` -- feature B"],"allowed_paths":["shared.py"],"acceptance_criteria":["feature B"]}
]}
JSON
  run "$GATE" "$pj" "$epic"
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "pass"'
}

@test "per_step_scoping R2: 3 steps same allowed_paths, honored blocks, distinct outputs -> PASS" {
  local epic="$TEST_TMPDIR/r2.md" pj="$TEST_TMPDIR/r2.json"
  cat > "$epic" <<'MD'
<!-- step-1: files=["Modify: `svc.sh`"]; ac=["dispatch"] -->
<!-- step-2: files=["Modify: `svc.sh`"]; ac=["validate"] -->
<!-- step-3: files=["Modify: `svc.sh`"]; ac=["verify"] -->
MD
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R2-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Modify: `svc.sh` -- add dispatch"],"allowed_paths":["svc.sh"],"acceptance_criteria":["dispatch"]},
  {"id":"step_2_backend","role":"backend","outputs":["Modify: `svc.sh` -- add validate"],"allowed_paths":["svc.sh"],"acceptance_criteria":["validate"]},
  {"id":"step_3_backend","role":"backend","outputs":["Modify: `svc.sh` -- add verify"],"allowed_paths":["svc.sh"],"acceptance_criteria":["verify"]}
]}
JSON
  run "$GATE" "$pj" "$epic"
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "pass"'
}

@test "per_step_scoping R3: generated allowed_paths conflict with explicit block -> FAIL" {
  local epic="$TEST_TMPDIR/r3.md" pj="$TEST_TMPDIR/r3.json"
  cat > "$epic" <<'MD'
<!-- step-1: files=["Modify: `a.py`"]; ac=["a"] -->
<!-- step-2: files=["Modify: `b.py`"]; ac=["b"] -->
MD
  # generator "ignored" the blocks and broadcast both files to every step
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R3-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Modify: `a.py`"],"allowed_paths":["a.py","b.py"],"acceptance_criteria":["a"]},
  {"id":"step_2_backend","role":"backend","outputs":["Modify: `b.py`"],"allowed_paths":["a.py","b.py"],"acceptance_criteria":["b"]}
]}
JSON
  run "$GATE" "$pj" "$epic"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "fail"'
  echo "$output" | jq -e '[.violations[]|select(startswith("per_step_scoping"))]|length > 0'
}

@test "per_step_scoping R4: legacy (no blocks), identical outputs AND allowed_paths -> FAIL" {
  local pj="$TEST_TMPDIR/r4.json"
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R4-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Create: `a.py`"],"allowed_paths":["a.py"],"acceptance_criteria":["a"]},
  {"id":"step_2_qa","role":"qa","outputs":["Create: `a.py`"],"allowed_paths":["a.py"],"acceptance_criteria":["a"]}
]}
JSON
  run "$GATE" "$pj"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "fail"'
}

@test "per_step_scoping R5: legacy (no blocks), same allowed_paths but DISTINCT outputs -> PASS (the P065-class fix)" {
  local pj="$TEST_TMPDIR/r5.json"
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R5-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Modify: `svc.sh` -- dispatch"],"allowed_paths":["svc.sh"],"acceptance_criteria":["dispatch"]},
  {"id":"step_2_backend","role":"backend","outputs":["Modify: `svc.sh` -- verify"],"allowed_paths":["svc.sh"],"acceptance_criteria":["verify"]}
]}
JSON
  run "$GATE" "$pj"
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "pass"'
}

@test "per_step_scoping R6: P057/P058 broadcast reproduction stays FAIL" {
  local pj="$TEST_TMPDIR/r6.json"
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R6-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Create: `x.py`","Create: `y.py`"],"allowed_paths":["x.py","y.py"],"acceptance_criteria":["x"]},
  {"id":"step_2_backend","role":"backend","outputs":["Create: `x.py`","Create: `y.py`"],"allowed_paths":["x.py","y.py"],"acceptance_criteria":["y"]},
  {"id":"step_3_backend","role":"backend","outputs":["Create: `x.py`","Create: `y.py`"],"allowed_paths":["x.py","y.py"],"acceptance_criteria":["z"]}
]}
JSON
  run "$GATE" "$pj"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "fail"'
}

@test "per_step_scoping R7: explicit per-step blocks themselves degenerately broadcast -> FAIL" {
  local epic="$TEST_TMPDIR/r7.md" pj="$TEST_TMPDIR/r7.json"
  cat > "$epic" <<'MD'
<!-- step-1: files=["Modify: `shared.py`"]; ac=["same"] -->
<!-- step-2: files=["Modify: `shared.py`"]; ac=["same"] -->
MD
  # blocks honored (gen == block) BUT identical files AND identical outputs
  cat > "$pj" <<'JSON'
{ "epic_id":"E-R7-1_1","version":1,"dependencies":[],"steps":[
  {"id":"step_1_backend","role":"backend","outputs":["Modify: `shared.py`"],"allowed_paths":["shared.py"],"acceptance_criteria":["same"]},
  {"id":"step_2_backend","role":"backend","outputs":["Modify: `shared.py`"],"allowed_paths":["shared.py"],"acceptance_criteria":["same"]}
]}
JSON
  run "$GATE" "$pj" "$epic"
  [ "$status" -ne 0 ]
  echo "$output" | jq -e '[.checks[]|select(.id=="per_step_scoping")][0].status == "fail"'
}

@test "aid-contract-validate.sh: ac_no_fragments accepts an AC quoting a finding in single quotes (P103), still flags an unbalanced one" {
  local plan_json="$TEST_TMPDIR/quoted-finding-plan.json"
  jq -n '{epic_id: "E-QUOTE-1_1", version: 1, dependencies: [], steps: [{id: "step_1_qa", role: "qa", outputs: ["Create: `test_a.py`"], allowed_paths: ["test_a.py"],
    acceptance_criteria: ["Still open in part: '"'"'current build id'"'"' and the page reload are covered by one test"]}]}' > "$plan_json"
  run "$GATE" "$plan_json"
  echo "$output" | jq -e '[.checks[] | select(.id == "ac_no_fragments")][0].status == "pass"'
  jq '.steps[0].acceptance_criteria = ["the check reads '"'"'.foo and stops"]' "$plan_json" > "$plan_json.2"
  run "$GATE" "$plan_json.2"
  echo "$output" | jq -e '[.checks[] | select(.id == "ac_no_fragments")][0].status != "pass"'
}
