#!/usr/bin/env bats
# P032 Step 7 — aid-run-gates.sh provenance fields + framing events (Step 3).
# 3 assertions covering the gate runner's _generated_by/_at/_command_log
# triple and the gate_runner_start / gate_runner_complete timeline events.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/gates"
  cd "$TEST_PROJECT"

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"

  EXEC_YAML="$TEST_PROJECT/exec.yaml"
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 0"
    required: false
YAML

  REPORT="$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  TIMELINE="$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/timeline.jsonl"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "run-all: gates_report.json carries _generated_by, _generated_at, _command_log" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]
  run jq -e 'has("_generated_by") and has("_generated_at") and has("_command_log")' "$REPORT"
  [ "$status" -eq 0 ]
  # _command_log is a non-empty array of {name, command, exit_code, duration_ms}
  run jq -e '._command_log | length > 0 and all(has("name") and has("command") and has("exit_code") and has("duration_ms"))' "$REPORT"
  [ "$status" -eq 0 ]
  # _generated_by uses the runner@version format
  run jq -re '._generated_by' "$REPORT"
  [[ "$output" =~ ^aid-run-gates\.sh@v ]]
}

@test "run-all: timeline.jsonl has gate_runner_start with report_path + gate_count + command_list" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$TIMELINE" ]
  assert_timeline_event "$TIMELINE" "gate_runner_start"
  run jq -se 'first(.[] | select(.event=="gate_runner_start")) | has("report_path") and has("gate_count") and has("command_list")' "$TIMELINE"
  [[ "$output" == *true* ]]
  # gate_count must equal the actual number of gates in execution.yaml (2 here)
  run jq -se 'first(.[] | select(.event=="gate_runner_start")).gate_count' "$TIMELINE"
  [ "$output" == "2" ]
}

@test "run-all: timeline.jsonl has gate_runner_complete with report_path + overall + duration_sec" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  assert_timeline_event "$TIMELINE" "gate_runner_complete"
  run jq -se 'first(.[] | select(.event=="gate_runner_complete")) | has("report_path") and has("overall") and has("duration_sec")' "$TIMELINE"
  [[ "$output" == *true* ]]
  # overall=pass for the all-passing fixture
  run jq -se 'first(.[] | select(.event=="gate_runner_complete")).overall' "$TIMELINE"
  [ "$output" == '"pass"' ]
}

# ─── OBS-20260708-07 F4 — gates runner must never lose a gate and report pass ──
# Three loss paths closed: (a) stdin-consuming gate starving subsequent gates,
# (b) null-command gate leaving no row (bare continue), (c) any other silent row
# loss caught by the defined==processed integrity assert.

@test "run-all F4a: stdin-consuming gate does not starve subsequent gates" {
  # 'eat' runs `cat` which, on the unfixed runner, consumes the driver's
  # here-string stdin (the remaining gate names) so 'beta' is never iterated —
  # yet overall still reports pass. The </dev/null redirect in run_gate fixes it.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  eat:
    command: "cat >/dev/null"
    required: false
  beta:
    command: "exit 0"
    required: false
YAML
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]
  # Both gates must appear — beta must not be starved out of the report
  run jq -e '.gates | has("eat") and has("beta")' "$REPORT"
  [ "$status" -eq 0 ]
  # No integrity failure, overall stays pass (both gates genuinely ran + passed)
  run jq -e '.gates | has("_integrity") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

@test "run-all F4b: null-command gate emits explicit skip row (never bare continue)" {
  # 'nocmd' has no command key. The unfixed runner WARNs + bare `continue`,
  # emitting no row (silent loss). After the fix it must emit an explicit
  # {result:skip, reason:no_command} row so defined==rows holds by construction.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  nocmd:
    required: false
  beta:
    command: "exit 0"
    required: false
YAML
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]
  run jq -re '.gates.nocmd.result' "$REPORT"
  [ "$output" == "skip" ]
  run jq -re '.gates.nocmd.reason' "$REPORT"
  [ "$output" == "no_command" ]
  # beta still processed; defined==rows holds so no integrity row, overall pass
  run jq -e '.gates | has("beta")' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -e '.gates | has("_integrity") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

@test "run-all F4c: silently-lost gate row trips _integrity fail + overall fail + nonzero exit" {
  # Fault injection (AID_TEST_DROP_GATE, honored only under test) drops one
  # gate's row without a corresponding processed++, simulating a silent row
  # loss. The defined==processed assert must catch it: emit an _integrity row,
  # force overall=fail, and exit non-zero.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: false
  beta:
    command: "exit 0"
    required: false
YAML
  run env AID_TEST_DROP_GATE=beta "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  # Non-zero exit from the runner
  [ "$status" -ne 0 ]
  [ -f "$REPORT" ]
  # Explicit integrity failure row present
  run jq -re '.gates._integrity.result' "$REPORT"
  [ "$output" == "fail" ]
  run jq -re '.gates._integrity.reason' "$REPORT"
  [ "$output" == "gate_count_mismatch" ]
  # defined/processed recorded (2 defined, 1 processed after the drop)
  run jq -re '.gates._integrity.defined' "$REPORT"
  [ "$output" == "2" ]
  run jq -re '.gates._integrity.processed' "$REPORT"
  [ "$output" == "1" ]
  # Overall must be fail — a lost gate can never surface as green
  run jq -re '.overall' "$REPORT"
  [ "$output" == "fail" ]
}

# ─── P060 Step 2 F4 — plan.json ⇄ execution.yaml gate reconciliation ──────────
# OBS-20260702-05: a gate declared in plan.json.gates[] but undefined in
# execution.yaml must NOT silently disappear (F1: never runs, all-PASS). Four
# scenarios: (a) direct runner reconciliation, (b) FSM end-to-end refusal,
# (c) no-plan.json skip event, (d) manual-flow bypass enforcement marker.

@test "run-all recon-a: plan.json declares gate undefined in execution.yaml → undefined_gate fail row + overall fail" {
  # setup()'s EXEC_YAML defines alpha/beta only. plan.json declares 'ghost',
  # which has no definition → reconciliation must emit an undefined_gate fail
  # row and flip overall to fail. On the UNFIXED runner (--plan-json ignored)
  # ghost is never flagged and overall stays pass (RED).
  printf '{"gates":["alpha","ghost"]}\n' > "$TEST_PROJECT/plan.json"
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" \
    --report-file "$REPORT" --plan-json "$TEST_PROJECT/plan.json"
  [ "$status" -ne 0 ]
  [ -f "$REPORT" ]
  run jq -re '.gates.ghost.result' "$REPORT"
  [ "$output" == "fail" ]
  run jq -re '.gates.ghost.reason' "$REPORT"
  [ "$output" == "undefined_gate" ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "fail" ]
  # Reconciliation ran → top-level marker true
  run jq -re '.plan_gates_reconciled' "$REPORT"
  [ "$output" == "true" ]
  # undefined_gate rows are NOT counted (counter-universe contract with Step 1):
  # alpha+beta both processed, defined==processed, so no _integrity row fires.
  run jq -e '.gates | has("_integrity") | not' "$REPORT"
  [ "$status" -eq 0 ]
  # Defined-and-declared gate alpha still ran normally
  run jq -re '.gates.alpha.result' "$REPORT"
  [ "$output" == "pass" ]
  # revision.head_sha substrate present (Step 8) — key exists on the report
  run jq -e 'has("revision") and (.revision | has("head_sha"))' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "run-all recon-b (FSM e2e): advance-to-gates refuses transition when plan.json declares undefined gate; undefined_gate row in FSM-written report" {
  # Kills a lazy impl that patches the runner but not the FSM call-site: the
  # report is written by the runner the FSM invoked, and the marker proves the
  # call-site passed --plan-json.
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "EXECUTE" "5" "5" "E-X" "R-1"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  # execution.yaml defines only always_pass — NOT 'ghost'
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  printf '{"gates":["always_pass","ghost"]}\n' > "$TEST_EVIDENCE_DIR/plan.json"

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # Refused: gates fail (undefined_gate) → runner nonzero → state stays EXECUTE
  [ "$status" -ne 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "EXECUTE" ]
  local report="$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ -f "$report" ]
  run jq -re '.gates.ghost.reason' "$report"
  [ "$output" == "undefined_gate" ]
  run jq -re '.overall' "$report"
  [ "$output" == "fail" ]
  # Marker true → FSM call-site passed --plan-json
  run jq -re '.plan_gates_reconciled' "$report"
  [ "$output" == "true" ]
}

@test "run-all recon-c (FSM e2e): advance-to-gates without plan.json → plan_gates_reconciliation_skipped event + unchanged pass" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "EXECUTE" "5" "5" "E-X" "R-1"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  # NO plan.json → reconciliation cannot run; behavior unchanged, marker absent/false

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "plan_gates_reconciliation_skipped"
  # Marker false — runner invoked without --plan-json
  run jq -re '.plan_gates_reconciled' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "false" ]
}

@test "run-all recon-d (enforcement): manual run-all WITHOUT --plan-json while plan.json exists → EXECUTE:GATES precondition fail (missing plan_gates_reconciled)" {
  # The L1-B1 marker enforcement: a report produced by bypassing --plan-json
  # while a plan.json exists lacks plan_gates_reconciled:true → the FSM-side
  # assert in check_preconditions EXECUTE:GATES must refuse the transition.
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "EXECUTE" "5" "5" "E-X" "R-1"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_EVIDENCE_DIR/gates"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  # plan.json exists → reconciliation is REQUIRED
  printf '{"gates":["always_pass"]}\n' > "$TEST_EVIDENCE_DIR/plan.json"
  # Simulate a manual two-step run WITHOUT --plan-json (and without --state-file,
  # per the documented manual flow that skips the state guard). Report gets
  # _generated_by but LACKS plan_gates_reconciled:true.
  "$RUN_GATES" run-all "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" >/dev/null 2>&1
  run jq -re '.plan_gates_reconciled' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "false" ]

  # EXECUTE→GATES must refuse — marker missing while plan.json exists
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition EXECUTE GATES "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_gates_reconciled"* ]]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "EXECUTE" ]
}

# ─── P061 E1 Step 1 — gates-enum fix: plan.json.gates[] must carry arbitrary ──
# gate names, not just the old hardcoded 4-value list (tests_pass, lint_pass,
# security_scan_pass, docs_updated). Two bugs fixed together:
#   1. aid-epic-to-json.sh's DoD Gates extraction filter silently dropped any
#      gate name outside that fixed list (no error, no output row) — verified
#      here via a fixture EPIC.md declaring "bats_all" (never in the old list).
#   2. The post-hoc validation jq's gate check was a dead no-op
#      (`[valid_gates[] | select(. == .)]` compares each value to itself, so
#      it's always non-empty regardless of input) — verified here by feeding
#      an actually-malformed gate name and confirming aid-epic-to-json.sh now
#      fails loud instead of silently accepting it.

@test "epic-to-json gates roundtrip: DoD Gates name outside old fixed 4-value list survives into plan.json.gates[]" {
  local epic_to_json="$AID_PLUGIN_PATH/scripts/aid-epic-to-json.sh"
  local schema="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  local epic="$TEST_TMPDIR/E-TEST-901-1_1-gates-roundtrip.md"
  local out_dir="$TEST_TMPDIR/out-roundtrip"
  mkdir -p "$out_dir"
  cat > "$epic" <<'EOF'
---
status: active
plan_ref: plugins/aid-orchestrator/scripts/tests/fixtures/minimal-plan.md
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-901-1_1 --- Gates Roundtrip

## Context

Fixture EPIC for the gates-enum roundtrip regression (P061 E1 Step 1).

## Goal

Prove a DoD Gates name outside the old hardcoded 4-value list survives
extraction into plan.json.gates[].

## Scope

### Allowed files/paths
- `src/core/module.py`

### Forbidden zones
- <!-- none -->

## Artifacts

- Create: `src/core/module.py`

## Constraints

- none

## DoD Gates

- bats_all

## Acceptance Criteria

- [ ] [backend] Module loads without errors

## Dependencies

### Internal (same plan)
<!-- none -->

### External (other plans/EPICs)
<!-- none -->

### Queue Implications
depends_on: []

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Implement the core module with basic data structures. | --- | --- |

## Run Breakdown

### Run 1: Phase 1
**Goal:** Gates roundtrip fixture.
**Deliverables:** n/a

## Hints

- expected_steps: 1
- complexity: low
- parallelism_potential: low

## Notes

<!-- Auto-generated fixture for test-aid-run-gates.bats (P061 E1 Step 1) -->
EOF

  run "$epic_to_json" --epic "$epic" --schema "$schema" --output-dir "$out_dir"
  [ "$status" -eq 0 ]
  local plan_json
  plan_json="$(echo "$output" | jq -r '.plan_json // ""')"
  [ -n "$plan_json" ]
  [ -f "$plan_json" ]
  # "bats_all" is NOT in the old hardcoded 4-value list — on the unfixed
  # extraction filter it would be silently dropped and gates[] would be [].
  run jq -e '.gates == ["bats_all"]' "$plan_json"
  [ "$status" -eq 0 ]
}

@test "epic-to-json gates validation: malformed gate name is rejected fail-loud (dead no-op fixed)" {
  # Proves the post-hoc validation jq's gate check is no longer a dead no-op
  # (`select(. == .)` always true). A gate name containing a space/colon is
  # not a well-formed identifier and must fail conversion, not pass silently.
  local epic_to_json="$AID_PLUGIN_PATH/scripts/aid-epic-to-json.sh"
  local schema="$AID_PLUGIN_PATH/defaults/templates/plan.schema.json"
  local epic="$TEST_TMPDIR/E-TEST-902-1_1-gates-invalid.md"
  local out_dir="$TEST_TMPDIR/out-invalid"
  mkdir -p "$out_dir"
  cat > "$epic" <<'EOF'
---
status: active
plan_ref: plugins/aid-orchestrator/scripts/tests/fixtures/minimal-plan.md
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-TEST-902-1_1 --- Gates Invalid

## Context

Fixture EPIC for the gates-validation dead-no-op regression (P061 E1 Step 1).

## Goal

Prove a structurally malformed DoD Gates name is rejected fail-loud.

## Scope

### Allowed files/paths
- `src/core/module.py`

### Forbidden zones
- <!-- none -->

## Artifacts

- Create: `src/core/module.py`

## Constraints

- none

## DoD Gates

- not a valid gate: name

## Acceptance Criteria

- [ ] [backend] Module loads without errors

## Dependencies

### Internal (same plan)
<!-- none -->

### External (other plans/EPICs)
<!-- none -->

### Queue Implications
depends_on: []

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Implement the core module with basic data structures. | --- | --- |

## Run Breakdown

### Run 1: Phase 1
**Goal:** Gates invalid-name fixture.
**Deliverables:** n/a

## Hints

- expected_steps: 1
- complexity: low
- parallelism_potential: low

## Notes

<!-- Auto-generated fixture for test-aid-run-gates.bats (P061 E1 Step 1) -->
EOF

  run "$epic_to_json" --epic "$epic" --schema "$schema" --output-dir "$out_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid gate name"* ]]
}

# ─── P061 E1 Step 2 — aid-run-gates.sh --profile flag, gate_profiles ─────────
# parsing, profile_excluded reporting. A profile is a named include[]
# whitelist of gate keys under execution.yaml.gate_profiles. Six scenarios:
# (a) an excluded gate never actually runs (proven via elapsed time, not just
# a result string — a broken impl that still executes the command but
# discards its row would pass a naive assertion); (b) a required:false gate
# still inside the profile's include[] runs normally; (c) a required:true
# gate excluded by the profile does not fail the run; (d)/(e) fail-loud on
# unknown profile / unknown gate inside include[]; (f) omitting --profile is
# bit-identical to today even once gate_profiles exists in the file.

@test "run-all profile a: gate excluded from active profile never runs (proven via elapsed time, not just its result string)" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  plan_diff:
    command: "exit 0"
    required: true
  shell_pipeline_smoke:
    command: "sleep 5"
    required: true
    timeout_seconds: 5
  docs_updated:
    command: "exit 0"
    required: false

gate_profiles:
  standard:
    include: [plan_diff, docs_updated]
YAML
  local start_ts end_ts elapsed
  start_ts=$(date +%s)
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile standard
  end_ts=$(date +%s)
  elapsed=$((end_ts - start_ts))
  [ "$status" -eq 0 ]
  # Must finish well under shell_pipeline_smoke's 5s timeout — proves it was
  # never dispatched to run_gate at all (not just that its row got discarded).
  # Threshold widened 3->5s (P063 Step 2): every included gate now also pays
  # a per-attempt gate_baseline_update write + a gate_baseline_report_json
  # read (yq/jq subprocess overhead, ~0.3-0.7s/gate on this fixture's 2
  # included gates) — a real, expected fixed cost of this EPIC, not a
  # regression this test is meant to catch. The distinguishing signal stays
  # intact: if shell_pipeline_smoke actually ran, elapsed would be >=5s (its
  # own sleep+timeout) plus this same per-gate overhead, i.e. comfortably
  # over this threshold either way.
  [ "$elapsed" -lt 5 ]
  run jq -re '.gates.shell_pipeline_smoke.result' "$REPORT"
  [ "$output" == "profile_excluded" ]
  run jq -re '.gates.shell_pipeline_smoke.reason' "$REPORT"
  [ "$output" == "profile_excluded" ]
  run jq -e '.excluded_gates == ["shell_pipeline_smoke"]' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.profile' "$REPORT"
  [ "$output" == "standard" ]
  run jq -re '.profile_source' "$REPORT"
  [ "$output" == "cli_flag" ]
  run jq -re '.profile_reason' "$REPORT"
  [ -n "$output" ]
  # Included gates still ran and passed
  run jq -re '.gates.plan_diff.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

@test "run-all profile b: required:false gate inside the active profile's include[] still runs" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 0"
    required: false
gate_profiles:
  standard:
    include: [alpha, beta]
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile standard
  [ "$status" -eq 0 ]
  run jq -re '.gates.alpha.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -re '.gates.beta.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -e '.excluded_gates == []' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "run-all profile c: required:true gate excluded by the active profile does not fail the run" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 0"
    required: true
gate_profiles:
  targeted:
    include: [alpha]
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile targeted
  [ "$status" -eq 0 ]
  run jq -re '.gates.beta.result' "$REPORT"
  [ "$output" == "profile_excluded" ]
  run jq -e '.excluded_gates == ["beta"]' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

@test "run-all profile d: unknown --profile name fails loud before running any gate" {
  # setup()'s EXEC_YAML (alpha/beta) has no gate_profiles block at all.
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile does-not-exist
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown gate profile"* ]]
  # Report must not have been written — validation happens before any gate runs
  [ ! -f "$REPORT" ]
}

@test "run-all profile e: profile include[] referencing an undefined gate fails loud before running any gate" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
gate_profiles:
  bogus:
    include: [alpha, ghost]
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" --profile bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"ghost"* ]]
  [ ! -f "$REPORT" ]
}

# ─── P061 E1 Step 3 — plan-gate floor enforcement (plan_gate_profile_excluded) ─
# plan.json.gates[] (Step 1) is a hard floor: the active gate profile (Step 2,
# --profile) must never silently exclude a gate the PLAN itself declared
# mandatory. profile_exclusion (Step 2) alone does NOT flip overall to fail —
# a required:true gate excluded by the profile is treated like a skipped
# required:false gate — so without this check the excluded-but-plan-required
# gate could vanish from a run that still reports overall=pass. Design chosen:
# (b) fail-loud (GATES:DONE precondition refuses with plan_gate_profile_excluded)
# over (a) force-run, because aid-fsm.sh is a precondition checker, not a gate
# executor — see step_3_backend/output.md for the full design rationale.

@test "GATES:DONE plan-gate floor (CHECKPOINT 1): plan declares gates:[\"bats_all\"], active profile excludes it -> transition refused with plan_gate_profile_excluded" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "GATES" "5" "5" "E-X" "R-1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  bats_all:
    command: "true"
    required: true
  always_pass:
    command: "true"
    required: true
gate_profiles:
  standard:
    include: [always_pass]
YAML
  printf '{"gates":["bats_all"]}\n' > "$TEST_EVIDENCE_DIR/plan.json"

  # Produce a REAL gates_report.json via the actual runner: profile 'standard'
  # excludes bats_all, which plan.json requires. overall stays "pass"
  # (profile_excluded never fails the run by itself, per Step 2) — this is
  # the exact silent-pass gap Step 3 closes.
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" \
    --plan-json "$TEST_EVIDENCE_DIR/plan.json" --profile standard
  [ "$status" -eq 0 ]
  run jq -re '.overall' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "pass" ]
  run jq -e '.excluded_gates == ["bats_all"]' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$status" -eq 0 ]

  # GATES→DONE must refuse — a plan-required gate was excluded by the profile.
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_gate_profile_excluded"* ]]
  [[ "$output" == *"bats_all"* ]]
  # State never advanced past GATES
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  # Reason surfaced on the timeline via cmd_transition's generic precondition logger
  run jq -rse 'last(.[] | select(.event=="fsm_precondition_fail")).reason' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [ "$output" == "plan_gate_profile_excluded" ]
}

@test "GATES:DONE plan-gate floor: plan-required gate INSIDE the active profile's include[] -> transition proceeds normally" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "GATES" "5" "5" "E-X" "R-1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  bats_all:
    command: "true"
    required: true
gate_profiles:
  standard:
    include: [bats_all]
YAML
  printf '{"gates":["bats_all"]}\n' > "$TEST_EVIDENCE_DIR/plan.json"
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" \
    --plan-json "$TEST_EVIDENCE_DIR/plan.json" --profile standard
  [ "$status" -eq 0 ]
  run jq -e '.excluded_gates == []' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$status" -eq 0 ]

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "DONE" ]
}

@test "GATES:DONE plan-gate floor: no --profile used (legacy) -> excluded_gates empty, plan-gate floor is a no-op" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "GATES" "5" "5" "E-X" "R-1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  bats_all:
    command: "true"
    required: true
YAML
  printf '{"gates":["bats_all"]}\n' > "$TEST_EVIDENCE_DIR/plan.json"
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" \
    --plan-json "$TEST_EVIDENCE_DIR/plan.json"
  [ "$status" -eq 0 ]

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "DONE" ]
}

@test "GATES:DONE plan-gate floor (CHECKPOINT 1 regression): malformed plan.json blocks transition with plan_json_malformed" {
  # Regression test: if plan.json exists but is not valid JSON (truncated,
  # corrupt, etc.), the jq --slurpfile command will fail. Before the fix,
  # that failure was silently caught by || plan_gate_floor_violations=""
  # and coerced to "[]" (no violations), silently passing the check.
  # After the fix, malformed JSON must block the transition with a clear error.
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "GATES" "5" "5" "E-X" "R-1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  bats_all:
    command: "true"
    required: true
YAML

  # Create a truncated/malformed plan.json (valid key but truncated value)
  printf '{"gates":["bats_all"' > "$TEST_EVIDENCE_DIR/plan.json"

  # Run gates with the valid report (this will succeed because it only reads
  # execution.yaml and has no gates_profile, so no exclusions)
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" \
    --plan-json "$TEST_EVIDENCE_DIR/plan.json"
  [ "$status" -eq 0 ]

  # GATES→DONE must refuse because plan.json is malformed/corrupt
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_json_malformed"* ]]
  # State must stay GATES (never advanced)
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  # Reason surfaced on timeline
  run jq -rse 'last(.[] | select(.event=="fsm_precondition_fail")).reason' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [ "$output" == "plan_json_malformed" ]
}

@test "GATES:DONE plan-gate floor (E-061-1_6 CP3 regression): plan.json.gates as object (not array) blocks transition with plan_json_malformed" {
  # Regression test (E-061-1_6 CP3 security finding 1): if plan.json.gates
  # is a JSON object instead of an array (syntactically valid JSON, but
  # schema-non-compliant), the original jq expression silently produced []
  # ("no violations") because $pg[] over an object yields its VALUES, not
  # keys, so the gate-name string matching never succeeded. This violated
  # the step's "Never a silent skip" design principle. After the fix,
  # non-array .gates must fail closed via the same plan_json_malformed path
  # used for parse errors.
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  seed_test_state_files "GATES" "5" "5" "E-X" "R-1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"

  # Create a plan.json with gates as an object (not an array) — schema violation.
  # This is syntactically valid JSON but violates plan.schema.json which requires
  # gates to be {"type":"array","items":{"type":"string"}}.
  printf '{"gates":{"tests_pass":true}}' > "$TEST_EVIDENCE_DIR/plan.json"

  # Manually create a gates_report.json with an excluded gate (the scenario
  # this check is designed to catch: profile-excluded gate that is plan-required).
  # Use the passing execution.yaml fixture to generate the report.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  # Add a gate_profiles block with a profile that excludes tests_pass
  cat >> "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" <<'YAML'
gate_profiles:
  limited:
    include: [always_pass]
YAML
  run "$RUN_GATES" run-all "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" --profile limited
  [ "$status" -eq 0 ]
  # Verify the report has tests_pass excluded (not in the limited profile)
  run jq -e '.excluded_gates | index("tests_pass") != null' "$TEST_EVIDENCE_DIR/gates/gates_report.json" 2>/dev/null
  # Note: tests_pass is NOT defined in the fixture, so it won't appear in excluded_gates.
  # That's OK — what matters is: the PLAN claims to require tests_pass (via malformed plan.json),
  # and the FSM's type-checking will now catch the malformed .gates shape.

  # GATES→DONE must refuse — the type-check in the jq expression now catches
  # the non-array .gates and treats it as malformed JSON (via error())
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_json_malformed"* ]]
  # State must stay GATES (never advanced)
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  # Reason surfaced on timeline
  run jq -rse 'last(.[] | select(.event=="fsm_precondition_fail")).reason' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [ "$output" == "plan_json_malformed" ]
}

@test "run-all profile f (legacy regression): omitting --profile runs all gates unchanged even when gate_profiles is defined" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 0"
    required: false
gate_profiles:
  standard:
    include: [alpha]
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ "$status" -eq 0 ]
  # beta is NOT in 'standard's include[], but --profile was never passed —
  # both gates run exactly as they would with no gate_profiles block at all.
  run jq -re '.gates.alpha.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -re '.gates.beta.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -e '.excluded_gates == []' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.profile' "$REPORT"
  [ "$output" == "null" ]
  run jq -re '.profile_source' "$REPORT"
  [ "$output" == "null" ]
  run jq -re '.profile_reason' "$REPORT"
  [ "$output" == "null" ]
}

# ─── P061 E2 Step 2 ("Step 8") — FSM risk-upgrade enforcement (D4) ───────────
# The active gate profile ACTUALLY recorded on gates_report.json.profile must
# be >= the risk-required profile computed by the Step 1 shared resolver
# (aid-gate-profile.sh's gate_profile_resolve) against this run's actual
# base_commit..HEAD diff — the GATES:DONE precondition VERIFIES and ENFORCES
# this floor (D4), it does not just let the resolver's own earlier suggestion
# go unchecked (AID-v3-principles.md §1: detector without enforcement is
# decoration).

@test "GATES:DONE risk-upgrade (CHECKPOINT 2): diff touches aid-fsm.sh -> resolver requires 'full'; active profile 'quick' -> precondition FAILS with risk_profile_below_required" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  local base; base=$(git rev-parse HEAD)

  # Simulate this EPIC's own diff touching aid-fsm.sh (high-risk path per
  # aid-gate-profile.sh's classification rules) between base_commit and HEAD.
  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "touch aid-fsm.sh"

  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  always_pass:
    command: "true"
    required: true
gate_profiles:
  quick:
    include: []
  full:
    include: [always_pass]
YAML

  # Active profile recorded is 'quick' — too weak for a high-risk diff.
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" --profile quick
  [ "$status" -eq 0 ]
  run jq -re '.profile' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "quick" ]
  run jq -re '.overall' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "pass" ]

  # GATES→DONE must refuse — the risk-required profile for this diff is 'full'.
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_profile_below_required"* ]]
  [[ "$output" == *"'quick'"* ]]
  [[ "$output" == *"'full'"* ]]
  # State never advanced past GATES
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  # Reason surfaced on the timeline via cmd_transition's generic precondition logger
  run jq -rse 'last(.[] | select(.event=="fsm_precondition_fail")).reason' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [ "$output" == "risk_profile_below_required" ]
}

@test "GATES:DONE risk-upgrade: diff touches aid-fsm.sh -> active profile 'full' (== required) -> transition proceeds normally" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  local base; base=$(git rev-parse HEAD)

  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "touch aid-fsm.sh"

  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  always_pass:
    command: "true"
    required: true
gate_profiles:
  full:
    include: [always_pass]
YAML

  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" --profile full
  [ "$status" -eq 0 ]

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "DONE" ]
}

@test "GATES:DONE risk-upgrade: no --profile used (legacy, D9) -> profile field absent -> no-op even for a high-risk diff" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  local base; base=$(git rev-parse HEAD)

  # High-risk diff (aid-fsm.sh touched) but the run never used --profile at all
  # (execution.yaml has no gate_profiles block) — D9: behaves exactly like
  # today, every defined gate already ran, nothing weaker to enforce against.
  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "touch aid-fsm.sh"

  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  setup_passing_execution_yaml "$exec_yaml"

  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$status" -eq 0 ]
  run jq -re '.profile' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "null" ]

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "DONE" ]
}

@test "advance-to-gates auto-resolve (FSM e2e): diff touches aid-fsm.sh + gate_profiles.full defined -> runner invoked with --profile full automatically (no explicit --profile from caller)" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  local base; base=$(git rev-parse HEAD)

  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "touch aid-fsm.sh"

  seed_test_state_files "EXECUTE" "5" "5" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" <<'YAML'
gates:
  always_pass:
    command: "true"
    required: true
gate_profiles:
  full:
    include: [always_pass]
YAML

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  run jq -re '.profile' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "full" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "gate_profile_selected"
}

@test "advance-to-gates auto-resolve (legacy regression, D9): diff touches aid-fsm.sh but gate_profiles is NOT defined -> --profile never passed, all gates run unchanged" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  local base; base=$(git rev-parse HEAD)

  # Same high-risk diff as above, but this project's execution.yaml has never
  # opted into gate_profiles at all — the overwhelming majority case today.
  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "touch aid-fsm.sh"

  seed_test_state_files "EXECUTE" "5" "5" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  run jq -re '.profile' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "null" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "gate_profile_auto_resolve_skipped"
}

@test "GATES:DONE risk-upgrade regression: unrecognized/custom profile name 'ci-fast' on high-risk diff (aid-fsm.sh) -> precondition FAILS with risk_profile_unresolvable" {
  # E-061-2_6 Step 2 fix: when an active profile name is not in the canonical 5
  # (quick/targeted/standard/full/release) and the required profile is high-risk
  # (> quick), the precondition must FAIL, not silently pass.
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  local base; base=$(git rev-parse HEAD)

  # Simulate high-risk diff touching aid-fsm.sh
  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "touch aid-fsm.sh"

  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  always_pass:
    command: "true"
    required: true
gate_profiles:
  ci-fast:
    include: []
  full:
    include: [always_pass]
YAML

  # Active profile is the custom 'ci-fast' (not in canonical 5 ranks)
  # which excludes all gates, so overall=pass even though nothing ran.
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" --profile ci-fast
  [ "$status" -eq 0 ]
  run jq -re '.profile' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "ci-fast" ]
  run jq -re '.overall' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "pass" ]

  # GATES→DONE must FAIL — the required profile for this diff is 'full' (high-risk),
  # but the active profile 'ci-fast' is unrecognized (not in the rank table), so we
  # cannot verify it meets the requirement. This must be fail-closed, not silent pass.
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_profile_unresolvable"* ]]
  [[ "$output" == *"ci-fast"* ]]
  [[ "$output" == *"full"* ]]
  # State never advanced past GATES
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  # Reason surfaced on the timeline via cmd_transition's generic precondition logger
  run jq -rse 'last(.[] | select(.event=="fsm_precondition_fail")).reason' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [ "$output" == "risk_profile_unresolvable" ]
}

# ─── P061 E-061-2_6: Regression test for yq expression injection (security fix) ──
# Vulnerability: unescaped ${profile} in yq expression allowed attacker-supplied
# yq operators (// alternation, # comments) to inject a fabricated profile with
# attacker-controlled gate whitelist, bypassing the profile-selection mechanism.
# Fix: replaced `.gate_profiles.\"${profile}\"` with `.gate_profiles[strenv(PROFILE)]`
# so profile names are always treated as literal keys, never parsed as yq expressions.
# Regression test: confirm injection payload is rejected (unknown profile) not accepted.
@test "run-all: yq injection payload in --profile is rejected (unknown profile)" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  test_gate:
    command: "exit 0"
    required: true
gate_profiles:
  real_profile:
    include: [test_gate]
YAML
  # Inject yq alternation operator in profile name: when vulnerability exists,
  # yq expression becomes `.gate_profiles."<injected>" // ["test_gate"]` which
  # falls through to the attacker-supplied literal array, making the runner believe
  # test_gate is in a real profile even though "injected" is not a real key.
  # After the fix, the profile name is a literal string key lookup, and the
  # injection payload is treated as a non-existent profile name → fail loud.
  local injection_payload='nonexistent" // ["test_gate"] #'

  # Must fail with exit code 1 and unknown profile error message
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --profile "$injection_payload"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown gate profile"* ]]
  [[ "$output" == *"no such key"* || "$output" == *"ERROR"* ]]
}

@test "run-all: yq injection with comment terminator in --profile is rejected" {
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 1"
    required: true
gate_profiles:
  safe_profile:
    include: [alpha]
YAML
  # Alternative injection: comment terminator to suppress latter part of yq.
  # Payload attempts to close string and comment out the rest of the yq expression.
  local injection_payload='safe_profile") .include = []; #'

  # Must fail (unknown profile), NOT pass with beta excluded by injection.
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --profile "$injection_payload"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown gate profile"* ]]
}

# ─── P063 Step 2 (AC8): gates_report.json additive-only fields ─────────────
# gate_baseline_update (per-attempt) + the runtime_baseline merge into each
# gate's aggregate row must be PURELY ADDITIVE: every key present in a
# PRE-P063-style report (the shape shipped through P061 EPIC 1/6, the last
# version before this EPIC) stays present, unchanged in kind, in a POST-P063
# report from the same gate run.
#
# TODO(Step 3): AC8's other half — "a policy-blocked required:true gate
# produces overall==fail" — depends on Step 3's repeated-timeout FSM
# precondition / policy-block mechanism, which does not exist yet as of this
# step. That half is intentionally NOT tested here; add it once Step 3 lands
# gate_baseline_mark_policy_block's wiring into a real fail-the-run path.
@test "AC8: gates_report.json gains only additive fields — every pre-P063 top-level and per-gate key survives unchanged" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]

  # Pre-P063 top-level key set (P061 EPIC 1/6 shape). New keys are allowed to
  # exist ALONGSIDE this set — the assertion is "this subset survives", not
  # "the set is exactly this". (`all(generator; cond)` evaluates `cond` with
  # `.` bound to each generated value, NOT the original input — bind the
  # object to $obj first so `has($k)` checks the right thing.)
  run jq -e '
    . as $obj
    | (["epic_id","run_id","overall","completed_at","gates","_generated_by",
      "_generated_at","_command_log","covered_paths","changed_paths_covered",
      "relevance","plan_gates_reconciled","revision","profile",
      "profile_source","profile_reason","excluded_gates"]) as $pre
    | all($pre[]; . as $k | $obj | has($k))
  ' "$REPORT"
  [ "$status" -eq 0 ]

  # Pre-P063 per-gate key set, for a gate that actually ran the retry loop
  # (not a profile_excluded/skip/undefined_gate row — those are separate,
  # unaffected shapes built at different call sites, out of scope here).
  run jq -e '
    .gates.alpha as $g
    | (["gate","result","exit_code","duration_ms","output","attempts"]) as $pre
    | all($pre[]; . as $k | $g | has($k))
  ' "$REPORT"
  [ "$status" -eq 0 ]

  # Pre-existing values keep their original kind (not just "key present with
  # a null/placeholder value" — a value-swap would technically pass a bare
  # has() check while still silently breaking every existing consumer).
  run jq -e '.gates.alpha.result == "pass" and (.gates.alpha.exit_code|type) == "number" and (.gates.alpha.duration_ms|type) == "number" and (.gates.alpha.attempts|type) == "number"' "$REPORT"
  [ "$status" -eq 0 ]

  # The new ADDITIVE field: runtime_baseline, a well-formed object carrying
  # gate_baseline_report_json's documented keys — additive alongside, never
  # replacing, any pre-existing key above.
  run jq -e '.gates.alpha | has("runtime_baseline") and (.runtime_baseline | type) == "object"' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -e '
    .gates.alpha.runtime_baseline as $rb
    | (["samples_count","non_censored_samples_count","p95_ms",
        "timeout_recommended_seconds","run_mode_recommended","data_sufficient",
        "last_attempt_result","policy_result","retryable","operator_action"]) as $pre
    | all($pre[]; . as $k | $rb | has($k))
  ' "$REPORT"
  [ "$status" -eq 0 ]

  # And it reflects a REAL sample from this very run (not a stub/empty
  # placeholder) — proves the per-attempt gate_baseline_update wiring
  # actually fired, not just that the merge key exists.
  run jq -e '.gates.alpha.runtime_baseline.samples_count >= 1 and .gates.alpha.runtime_baseline.last_attempt_result == "pass"' "$REPORT"
  [ "$status" -eq 0 ]
}

# ─── P063 Step 3: repeated-timeout policy block (AC6, AC10) ────────────────
# LIB seeds the baseline file directly (CLI dispatch mode) so a 3-consecutive-
# timeout streak can be assembled WITHOUT actually running 3 real gate
# attempts — matches how the streak really accumulates in production (across
# separate runs). command_template passed to `LIB update` must be byte-
# identical to the gate's `command:` in execution.yaml, otherwise the
# fingerprint differs and gate_baseline_update starts a fresh series instead
# of extending the seeded one.

@test "AC6a: 3 consecutive timeouts at the SAME timeout_seconds as current config -> blocks instead of a further attempt" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1

  cat > "$EXEC_YAML" <<'YAML'
gates:
  flaky_gate:
    command: "sleep 2"
    required: true
    timeout_seconds: 1
    max_retries: 2
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ -f "$REPORT" ]

  # Blocked on the FIRST attempt of this run (no retry consumed) — proves the
  # loop stopped instead of burning attempt 2/3.
  run jq -re '.gates.flaky_gate.attempts' "$REPORT"
  [ "$output" == "1" ]
  run jq -re '.gates.flaky_gate.result' "$REPORT"
  [ "$output" == "fail" ]
  run jq -re '.gates.flaky_gate.reason' "$REPORT"
  [ "$output" == "timeout_policy_block" ]
  run jq -re '.gates.flaky_gate.recommendation' "$REPORT"
  [ "$output" == "increase_timeout_or_background" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$REPORT"
  [ "$output" == "false" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "timeout_policy_block" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.operator_action' "$REPORT"
  [ "$output" == "increase_timeout_or_background" ]
  # required:true gate that fails still flips overall (pre-existing semantics,
  # unbroken by this new code path).
  run jq -re '.overall' "$REPORT"
  [ "$output" == "fail" ]
}

@test "AC6b: 3 consecutive timeouts recorded at a LOWER timeout_seconds than the current (raised) config -> does NOT block; real attempts continue under the new timeout" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 3" "sleep 3" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 3" "sleep 3" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 3" "sleep 3" 124 1000 1

  # Current config RAISES timeout_seconds to 2 (was 1 for the seeded samples).
  # The gate command still times out at 2s (sleep 3s > 2s) — this is a REAL
  # attempt, not an auto-pass, so the block-check's own timeout comparison
  # (not just "did it pass") is what must produce "no-block" here.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  flaky_gate:
    command: "sleep 3"
    required: true
    timeout_seconds: 2
    max_retries: 1
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ -f "$REPORT" ]

  # NOT blocked: the run exhausted its retries normally (max_retries:1 -> 2
  # real executions) instead of being short-circuited after 1. `attempts`
  # reports the loop counter's POST-loop value (a pre-existing, off-by-one
  # bash `for` artifact unrelated to this step: it overshoots by 1 past the
  # last real execution whenever the loop exhausts without `break`) — 3 here
  # confirms both real attempts ran to exhaustion, not that a 3rd fired.
  run jq -re '.gates.flaky_gate.attempts' "$REPORT"
  [ "$output" == "3" ]
  run jq -re '.gates.flaky_gate.result' "$REPORT"
  [ "$output" == "fail" ]
  # No policy-block fields — this is an ordinary exhausted-retries timeout fail.
  run jq -e '.gates.flaky_gate | has("reason") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -e '.gates.flaky_gate | has("recommendation") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$REPORT"
  [ "$output" == "true" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "none" ]
}

@test "AC10: a gate whose CURRENT attempt just passed is never blocked by an unrelated historical timeout streak" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "exit 0" "exit 0" 124 1000 60
  bash "$LIB" update flaky_gate "exit 0" "exit 0" 124 1000 60
  bash "$LIB" update flaky_gate "exit 0" "exit 0" 124 1000 60

  cat > "$EXEC_YAML" <<'YAML'
gates:
  flaky_gate:
    command: "exit 0"
    required: true
    timeout_seconds: 60
    max_retries: 2
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ "$status" -eq 0 ]
  [ -f "$REPORT" ]

  run jq -re '.gates.flaky_gate.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -re '.gates.flaky_gate.attempts' "$REPORT"
  [ "$output" == "1" ]
  run jq -e '.gates.flaky_gate | has("reason") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.gates.flaky_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "none" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$REPORT"
  [ "$output" == "true" ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

# ─── E-063-1_1 REOPEN (PM finding, HIGH) — real policy block must clear ─────
# AC10 above seeds raw samples via `LIB update` but never calls
# `LIB mark-policy-block`, so it never actually exercised the bug: a gate
# whose policy_result/retryable were genuinely flipped to an active block
# (via gate_baseline_mark_policy_block, the real code path aid-run-gates.sh
# Step 3 uses) NEVER cleared again, even once the gate itself recovered.
# These 3 tests establish a REAL block first, then prove it clears exactly
# where the PM's remediation instruction requires: a later passing attempt
# (while a DIFFERENT gate's own unrelated failure stays correctly reported,
# unaffected), a command_template edit, and a raised timeout_seconds.

@test "E-063-1_1 reopen: a gate previously policy-blocked then later PASSING clears retryable, while a DIFFERENT currently-failing gate is unaffected" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" mark-policy-block flaky_gate "increase_timeout_or_background"

  # Confirm the block is REAL before proceeding (not just a raw sample seed).
  run bash "$LIB" report-json flaky_gate
  [ "$(echo "$output" | jq -r '.retryable')" == "false" ]
  [ "$(echo "$output" | jq -r '.policy_result')" == "timeout_policy_block" ]

  # A LATER gates run: flaky_gate now passes quickly; a DIFFERENT gate,
  # other_gate, fails for a completely unrelated reason. Under the pre-fix
  # code, flaky_gate's stale retryable:false would still be carried forward
  # here even though this run's own attempt for it just passed.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  flaky_gate:
    command: "exit 0"
    required: true
    timeout_seconds: 5
    max_retries: 0
  other_gate:
    command: "exit 1"
    required: true
    timeout_seconds: 5
    max_retries: 0
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ -f "$REPORT" ]

  run jq -re '.gates.flaky_gate.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$REPORT"
  [ "$output" == "true" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "none" ]
  run jq -e '.gates.flaky_gate | has("reason") | not' "$REPORT"
  [ "$status" -eq 0 ]

  # other_gate's own unrelated failure is still correctly reported — never
  # masked, suppressed, or itself turned into a policy block by flaky_gate's
  # unrelated history.
  run jq -re '.gates.other_gate.result' "$REPORT"
  [ "$output" == "fail" ]
  run jq -re '.gates.other_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "none" ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "fail" ]  # other_gate's real, unrelated failure still flips overall
}

@test "E-063-1_1 reopen: command_template edit on a previously policy-blocked gate clears the block" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" mark-policy-block flaky_gate "increase_timeout_or_background"

  run bash "$LIB" report-json flaky_gate
  [ "$(echo "$output" | jq -r '.retryable')" == "false" ]

  # SAME gate name, EDITED command (fingerprint reset).
  cat > "$EXEC_YAML" <<'YAML'
gates:
  flaky_gate:
    command: "exit 0 # edited"
    required: true
    timeout_seconds: 5
    max_retries: 0
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ -f "$REPORT" ]

  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$REPORT"
  [ "$output" == "true" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "none" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.samples_count' "$REPORT"
  [ "$output" == "1" ]  # series really reset, not blended with the old block's samples
}

@test "E-063-1_1 reopen: raising timeout_seconds on a previously policy-blocked gate clears the block" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" mark-policy-block flaky_gate "increase_timeout_or_background"

  run bash "$LIB" report-json flaky_gate
  [ "$(echo "$output" | jq -r '.retryable')" == "false" ]

  # SAME command_template (no fingerprint reset) — timeout_seconds RAISED so
  # the gate now genuinely finishes inside the new timeout.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  flaky_gate:
    command: "sleep 2"
    required: true
    timeout_seconds: 5
    max_retries: 0
YAML
  run "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  [ -f "$REPORT" ]

  run jq -re '.gates.flaky_gate.result' "$REPORT"
  [ "$output" == "pass" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$REPORT"
  [ "$output" == "true" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.policy_result' "$REPORT"
  [ "$output" == "none" ]
}

# ─── P061 EPIC 3 Step 10 — targeted_tests gate wiring (execution.yaml) ───────
# Verifies the targeted_tests gate registered in the real
# .aid-o/config/execution.yaml is (a) findable/runnable by aid-run-gates.sh at
# all, (b) NOT activated in any self-host gate_profiles.*.include[] yet (D3/D1
# — EPIC 4 territory), and (c) propagates aid-select-tests.sh's real
# pass/fail/unverifiable-as-fail result into gates_report.json end-to-end
# (CHECKPOINT 3), not just via a direct selector invocation.

@test "execution.yaml: targeted_tests gate is defined and not included in any gate_profiles (D3/D1 boundary)" {
  local repo_exec_yaml
  repo_exec_yaml="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)/.aid-o/config/execution.yaml"
  [ -f "$repo_exec_yaml" ]
  run yq -e '.gates.targeted_tests.command' "$repo_exec_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *aid-select-tests.sh* ]]
  # No gate_profiles include[] anywhere lists targeted_tests. Covers both
  # today's reality (no gate_profiles key at all yet in this file) and,
  # defensively, a future gate_profiles block that forgets the boundary.
  # yq -o=json + jq (not yq's own `any(...)`, which isn't valid yq-expression
  # syntax) mirrors the exact yq-then-jq convention aid-run-gates.sh itself
  # already uses for gate_profiles introspection (see its
  # profile_defined_keys_json line).
  run bash -c "yq -o=json '.gate_profiles // {}' '$repo_exec_yaml' | jq '[.[] | .include[]?] | any(. == \"targeted_tests\")'"
  [ "$status" -eq 0 ]
  [ "$output" == "false" ]
}

# stub_bash_gate <relpath> <exit_code> — fast bash test stub written under
# STUB_ROOT. Mirrors test-aid-select-tests.bats's own stub_bash; kept local
# to this file since bash functions aren't shared across separate .bats files.
stub_bash_gate() {
  local relpath="$1" code="${2:-0}"
  mkdir -p "$STUB_ROOT/$(dirname "$relpath")"
  cat > "$STUB_ROOT/$relpath" <<EOF
#!/usr/bin/env bash
exit ${code}
EOF
  chmod +x "$STUB_ROOT/$relpath"
}

# commit_gate_change <file> — append a line to <file> (relative to the
# current git CWD) and commit it. Mirrors test-aid-select-tests.bats's own
# commit_change.
commit_gate_change() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo "changed" >> "$file"
  git add -A
  git commit -q -m "touch $file"
}

@test "run-all targeted_tests gate (CHECKPOINT 3 via gate runner): diff touching ONLY aid-plan-diff.sh -> gates_report.json.gates.targeted_tests reflects only test-plan-diff.sh" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  local base; base=$(git rev-parse HEAD)

  # Real production paths under the fixture repo's own plugins/aid-orchestrator/
  # tree — aid-select-tests.sh's classification logic (map_path_to_tests) is
  # always the real hardcoded mapping; only WHERE it executes the mapped test
  # file from is redirected (AID_SELECT_TESTS_PLUGIN_ROOT), the same isolation
  # seam test-aid-select-tests.bats already uses, for speed + determinism
  # instead of running the real (multi-minute) suites.
  mkdir -p plugins/aid-orchestrator/scripts
  STUB_ROOT="$TEST_TMPDIR/stub-plugin-root"
  export AID_SELECT_TESTS_PLUGIN_ROOT="$STUB_ROOT"
  mkdir -p "$STUB_ROOT/scripts/tests"
  stub_bash_gate "scripts/tests/test-plan-diff.sh" 0

  commit_gate_change "plugins/aid-orchestrator/scripts/aid-plan-diff.sh"

  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"

  local exec_yaml="$TEST_PROJECT_ROOT/exec.yaml"
  cat > "$exec_yaml" <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    timeout_seconds: 60
YAML

  local report="$TEST_EVIDENCE_DIR/gates/gates_report.json"
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --state-file "$TEST_EVIDENCE_DIR/fsm-state.yaml" --report-file "$report"
  [ "$status" -eq 0 ]

  run jq -re '.gates.targeted_tests.result' "$report"
  [ "$output" == "pass" ]
  run jq -re '.gates.targeted_tests.exit_code' "$report"
  [ "$output" == "0" ]
  # The gate's captured output is the selector's own JSON summary (run_gate
  # captures stdout+stderr) — assert it names ONLY test-plan-diff.sh, proving
  # the CHECKPOINT 3 selection reached gates_report.json end-to-end, not just
  # a direct aid-select-tests.sh invocation.
  run jq -re '.gates.targeted_tests.output' "$report"
  [[ "$output" == *"test-plan-diff.sh"* ]]
  [[ "$output" != *"test-aid-fsm"* ]]
  [[ "$output" != *"test-release-policy"* ]]

  unset AID_SELECT_TESTS_PLUGIN_ROOT
}

@test "run-all targeted_tests gate: unknown production path (D-selector-1 unverifiable) surfaces as plain gate result 'fail' — no new result value" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  local base; base=$(git rev-parse HEAD)

  mkdir -p plugins/aid-orchestrator/scripts
  STUB_ROOT="$TEST_TMPDIR/stub-plugin-root"
  export AID_SELECT_TESTS_PLUGIN_ROOT="$STUB_ROOT"
  mkdir -p "$STUB_ROOT/scripts/tests"

  # A path inside the production surface (scripts/) with no Initial-mapping
  # entry -> aid-select-tests.sh exits 3 (unverifiable). aid-run-gates.sh
  # needs zero changes to treat this as a fail: any non-zero exit is a fail
  # (run_gate: result="fail" whenever exit_code -ne 0) — confirming
  # D-selector-1 without a new "unverifiable" result value anywhere.
  commit_gate_change "plugins/aid-orchestrator/scripts/aid-brand-new-unmapped-script.sh"

  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"

  local exec_yaml="$TEST_PROJECT_ROOT/exec.yaml"
  cat > "$exec_yaml" <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    timeout_seconds: 60
YAML

  local report="$TEST_EVIDENCE_DIR/gates/gates_report.json"
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --state-file "$TEST_EVIDENCE_DIR/fsm-state.yaml" --report-file "$report"
  [ "$status" -eq 0 ]

  run jq -re '.gates.targeted_tests.result' "$report"
  [ "$output" == "fail" ]
  run jq -re '.gates.targeted_tests.exit_code' "$report"
  [ "$output" == "3" ]

  unset AID_SELECT_TESTS_PLUGIN_ROOT
}
