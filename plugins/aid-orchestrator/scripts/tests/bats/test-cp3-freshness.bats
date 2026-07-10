#!/usr/bin/env bats
# P060 Step 4 — CP3 review freshness (OBS-20260702-03, head-side twin of B-008).
# A STALE CP3 review must not pass as DONE evidence: fsm_check_cp3_freshness reads
# `Reviewed-Head:` from the CP3 verifier-output files and, when HEAD has moved
# past it, enforces the D4 narrow exception (test/fixture/evidence-only churn WITH
# a CP3-Freshness-Exception trailer; verdict-bearing files never qualify).
#
# 8 F4 scenarios (a–h) + 1 explicit grandfather-key control (AC: grandfather key =
# fsm_check_grandfather). Scenario (a) is an END-TO-END FSM transition test
# (drives `aid-fsm.sh transition GATES DONE`), the rest call the function directly.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  # Post-deploy so the freshness gate is live (not grandfathered) by default.
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
}

teardown() {
  unset CP3_FRESHNESS_POLICY || true
  teardown_test_evidence_dir
}

# ─── fixtures ────────────────────────────────────────────────────────────

# _write_cp3 <file> <reviewed_head|""> [generated_at]
#   Writes a CP3 verifier-output. Reviewed-Head line omitted when $2 is empty.
_write_cp3() {
  local file="$1" rh="$2" gen_at="${3:-2026-06-18T00:00:00Z}"
  {
    echo "_generated_by: aid-orchestrator:verifier@test"
    echo "_generated_at: $gen_at"
    echo "classification: FULL_REVIEW"
    echo "verdict: pass"
    [[ -n "$rh" ]] && echo "Reviewed-Head: $rh"
    echo ""
    echo "Synthetic CP3 output (bats fixture)."
  } > "$file"
}

# _seed_gates_state <reviewed_head|""> [created_at] [cp3_generated_at]
#   Writes fsm-state.yaml (state GATES, post-deploy), a passing gates_report,
#   and both CP3 outputs carrying Reviewed-Head. Echoes the state_file path.
_seed_gates_state() {
  local rh="$1" created_at="${2:-2026-06-18T00:00:00Z}" gen_at="${3:-2026-06-18T00:00:00Z}"
  local sf="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  cat > "$sf" <<EOF
epic_id: E-test
run_id: R-test
state: GATES
current_step: 1
total_steps: 1
branch: task/E-test/main
created_at: $created_at
gate_retries: 0
escalation_count: 0
EOF
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test"}\n' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  _write_cp3 "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md" "$rh" "$gen_at"
  _write_cp3 "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md" "$rh" "$gen_at"
  echo "$sf"
}

# _run_fresh <state_file>
#   Calls fsm_check_cp3_freshness in a condition context (mirrors production,
#   set -e disabled inside the function). status 0 → FRESH_OK, else FRESH_FAIL.
_run_fresh() {
  local sf="$1"
  run bash -c "source '$FSM'; if fsm_check_cp3_freshness '.aid-o/work/evidence/E-test/R-test' '$sf' '$TEST_PROJECT_ROOT'; then echo FRESH_OK; else echo FRESH_FAIL; exit 1; fi"
}

# ─── (a) end-to-end: stale review + production commit past head → blocked ─
@test "(a) stale review + production commit past head blocks GATES->DONE end-to-end" {
  local base; base=$(git rev-parse HEAD)
  local sf; sf=$(_seed_gates_state "$base")
  # Production commit PAST the reviewed head (no exception trailer).
  mkdir -p src && echo "prod change" > src/app.py
  git add src/app.py && git commit -q -m "production change after CP3 review"

  run "$FSM" transition GATES DONE "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CP3"* ]]
  [[ "$output" == *"src/app.py"* ]]
  # State must NOT have advanced to DONE.
  [ "$(grep '^state:' "$sf" | awk '{print $2}')" = "GATES" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "cp3_freshness_would_block"
}

# ─── (b) both D4 conditions met → pass + exception event with file-list ───
@test "(b) test churn + trailer meets D4 -> passes with cp3_freshness_exception event" {
  local base; base=$(git rev-parse HEAD)
  local sf; sf=$(_seed_gates_state "$base")
  mkdir -p pkg/tests
  echo "adjusted" > pkg/tests/foo_test.txt
  git add pkg/tests/foo_test.txt
  git commit -q -m "adjust test fixture

CP3-Freshness-Exception: widened flaky test tolerance"

  _run_fresh "$sf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FRESH_OK"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "cp3_freshness_exception"
  # Disclosure event carries the changed-file list (E10 abuse measurement).
  run jq -r 'select(.event=="cp3_freshness_exception") | .changed_files' \
    "$TEST_EVIDENCE_DIR/timeline.jsonl"
  [[ "$output" == *"pkg/tests/foo_test.txt"* ]]
}

# ─── (c) test-only commit WITHOUT trailer → fail ──────────────────────────
@test "(c) test-only commit without CP3-Freshness-Exception trailer fails" {
  local base; base=$(git rev-parse HEAD)
  local sf; sf=$(_seed_gates_state "$base")
  mkdir -p pkg/tests
  echo "adjusted" > pkg/tests/foo_test.txt
  git add pkg/tests/foo_test.txt
  git commit -q -m "adjust test fixture (no trailer)"

  _run_fresh "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FRESH_FAIL"* ]]
  [[ "$output" == *"trailer"* ]]
}

# ─── (d) trailer present but touches production path → fail ───────────────
@test "(d) trailer present but production path touched fails" {
  local base; base=$(git rev-parse HEAD)
  local sf; sf=$(_seed_gates_state "$base")
  mkdir -p src
  echo "prod" > src/handler.py
  git add src/handler.py
  git commit -q -m "production change with bogus trailer

CP3-Freshness-Exception: trying to sneak production past review"

  _run_fresh "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FRESH_FAIL"* ]]
  [[ "$output" == *"src/handler.py"* ]]
}

# ─── (e) post-review commit touching verifier-output-*.md → fail ──────────
@test "(e) commit touching verdict-bearing verifier-output file fails even under tests" {
  local base; base=$(git rev-parse HEAD)
  local sf; sf=$(_seed_gates_state "$base")
  # Verdict-bearing file placed under a tests/ dir AND with the trailer — must
  # still fail because verifier-output-*.md is never "bookkeeping".
  mkdir -p pkg/tests
  echo "verdict: pass" > pkg/tests/verifier-output-cp2-step-1.md
  git add pkg/tests/verifier-output-cp2-step-1.md
  git commit -q -m "touch a verdict-bearing file

CP3-Freshness-Exception: should not be allowed"

  _run_fresh "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FRESH_FAIL"* ]]
  [[ "$output" == *"verdict-bearing"* ]]
}

# ─── (f) observe mode → would_block event, does NOT block ─────────────────
@test "(f) observe mode logs cp3_freshness_would_block and does not block" {
  local base; base=$(git rev-parse HEAD)
  local sf; sf=$(_seed_gates_state "$base")
  mkdir -p src && echo "prod" > src/app.py
  git add src/app.py && git commit -q -m "production change past review"

  CP3_FRESHNESS_POLICY=observe _run_fresh "$sf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FRESH_OK"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "cp3_freshness_would_block"
}

# ─── (g) CP3 output without Reviewed-Head → fail ──────────────────────────
@test "(g) CP3 output without Reviewed-Head fails" {
  # Reviewed-Head omitted from both CP3 files; HEAD unchanged from base.
  local sf; sf=$(_seed_gates_state "")

  _run_fresh "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FRESH_FAIL"* ]]
  [[ "$output" == *"Reviewed-Head"* ]]
}

# ─── (h) grandfather keyed on created_at, NOT self-reported _generated_at ─
@test "(h) backdated _generated_at without Reviewed-Head on post-deploy run FAILS" {
  # created_at is POST-deploy (run is not grandfathered) but the CP3 file's
  # _generated_at is backdated before DEPLOY_DATE. Grandfather keys on the run's
  # created_at (fsm_check_grandfather), never the file — so this must FAIL.
  local sf; sf=$(_seed_gates_state "" "2026-06-18T00:00:00Z" "2026-01-01T00:00:00Z")

  _run_fresh "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FRESH_FAIL"* ]]
  [[ "$output" == *"Reviewed-Head"* ]]
}

# ─── grandfather-key control: pre-deploy run is skipped (fsm_check_grandfather) ─
@test "grandfather: pre-deploy created_at skips the freshness gate" {
  # created_at < DEPLOY_DATE → fsm_check_grandfather returns 0 → gate is skipped
  # even with no Reviewed-Head. Proves the key is created_at, not the file.
  local sf; sf=$(_seed_gates_state "" "2026-01-01T00:00:00Z")

  _run_fresh "$sf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FRESH_OK"* ]]
}
