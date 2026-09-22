#!/usr/bin/env bats
# aid-tier: t2
# P032 Step 7 — aid-fsm.sh PRE-FLIGHT branch enforcement (Step 2)
# + EXECUTE→GATES gates_report._generated_by precondition (Step 3) +
# grandfather behavior. P033 Step 9 adds CP2 verifier-output preconditions +
# force_override --reason enforcement. 14 assertions total.
# E-046-1_3 Step 6 adds: cross-plan E-→P gate (Step 1).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  # Force post-deploy mode for the gate-enforcement assertions.
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  # IMP-263 is strict-by-default in production (a new run with no binding is
  # rejected). Most increment-step tests here exercise OTHER preconditions
  # (SKIP/visual-anchoring/orphan/memory) and do not carry a binding, so this
  # file runs in observe to isolate the variable under test. The binding-specific
  # tests opt back into strict explicitly (AID_STEP_BINDING=strict) or prove the
  # default by unsetting it — see the "IMP-263 (fail-closed #1)" test.
  export AID_STEP_BINDING=observe
}

teardown() {
  unset GIT_DIR
  teardown_test_evidence_dir
}

# ─── Step 2: PRE-FLIGHT branch enforcement (6 assertions) ────────────────

@test "PRE-FLIGHT: HEAD=main → auto-create task/E-test/main" {
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$current_branch" == "task/E-test/main" ]
}

@test "PRE-FLIGHT: HEAD=task/E-test/main → resume case (no branch change)" {
  git checkout -b task/E-test/main -q
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$current_branch" == "task/E-test/main" ]
  [[ "$output" =~ "Resume case" ]]
}

@test "PRE-FLIGHT: HEAD=task/E-OTHER/main → mismatch hard fail with copy-paste fix" {
  git checkout -b task/E-OTHER/main -q
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -ne 0 ]
  [[ "$output" =~ "git checkout main && git branch -d task/E-OTHER/main" ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_branch_mismatch_detected"
}

@test "PRE-FLIGHT: HEAD=feat/foo → unusual warn + event, accept" {
  git checkout -b feat/foo -q
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unusual branch"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_branch_unusual_detected"
}

@test "PRE-FLIGHT: in worktree → skip enforcement, accept caller branch" {
  mock_git_worktree
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Worktree mode detected" ]]
}

@test "PRE-FLIGHT: uncommitted changes → reject with stash/commit suggestion" {
  echo "dirty modification" >> .gitkeep
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Uncommitted changes present" ]]
}

@test "PRE-FLIGHT: init --force self-writes tracked audit-log.jsonl → does NOT block itself (end-to-end repro)" {
  mkdir -p .aid-o/work
  echo '{"event":"seed"}' > .aid-o/work/audit-log.jsonl
  git add .aid-o/work/audit-log.jsonl
  git commit -q -m "track audit log"
  # Real repro: --force writes fsm_force_override to audit-log.jsonl (via
  # fsm_handle_force_override → fsm_emit_audit_log) DURING this same
  # invocation, before the clean-tree guard runs later in cmd_init.
  run "$FSM" init $(build_default_init_args E-test) --force --reason "reproducing audit-log.jsonl self-write dirty-tree bug end-to-end"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Uncommitted changes present" ]]
  # Confirm the self-write actually happened (guards against a no-op fixture).
  git diff --stat HEAD -- .aid-o/work/audit-log.jsonl | grep -q "audit-log.jsonl"
}

@test "PRE-FLIGHT: tracked .aid-o/config/queue.yaml dirty → does NOT block (existing exclusion, regression)" {
  mkdir -p .aid-o/config
  echo "queue: []" > .aid-o/config/queue.yaml
  git add .aid-o/config/queue.yaml
  git commit -q -m "track queue"
  echo "queue: [updated]" > .aid-o/config/queue.yaml
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Uncommitted changes present" ]]
}

@test "PRE-FLIGHT: dirty tree with an ordinary tracked file (not queue.yaml/audit-log.jsonl) → still blocked" {
  echo "some real code change" >> .gitkeep
  git add .gitkeep
  git commit -q -m "track gitkeep change baseline"
  echo "another change" >> .gitkeep
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Uncommitted changes present" ]]
}

# ─── P063 Step 2 (AC7): gate-runtime-baseline metrics file exclusions ────
# Defense-in-depth alongside the gitignore/.git-info-exclude backfill
# (gate_baseline_ensure_gitignored): even in a project where the baseline
# YAML (or its .lock sidecar) is UNUSUALLY git-tracked, `init` must not
# block on it — independent of whether that bootstrap succeeded in this
# clone. Same single-file, non-glob scoping as the queue.yaml/audit-log.jsonl
# exclusions above.

@test "PRE-FLIGHT (AC7a): tracked .aid-o/metrics/gate-runtime-baselines.yaml dirty → does NOT block" {
  mkdir -p .aid-o/metrics
  echo "gates: {}" > .aid-o/metrics/gate-runtime-baselines.yaml
  git add .aid-o/metrics/gate-runtime-baselines.yaml
  git commit -q -m "track baseline yaml (unusual, but must not block init)"
  echo "gates: {updated: true}" > .aid-o/metrics/gate-runtime-baselines.yaml
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Uncommitted changes present" ]]
}

@test "PRE-FLIGHT (AC7a2): tracked .aid-o/metrics/gate-runtime-baselines.yaml.lock dirty → does NOT block" {
  mkdir -p .aid-o/metrics
  touch .aid-o/metrics/gate-runtime-baselines.yaml.lock
  git add .aid-o/metrics/gate-runtime-baselines.yaml.lock
  git commit -q -m "track baseline lock sidecar (unusual, but must not block init)"
  echo "lock-noise" >> .aid-o/metrics/gate-runtime-baselines.yaml.lock
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Uncommitted changes present" ]]
}

@test "PRE-FLIGHT (AC7 regression): dirty tree under .aid-o/metrics/ but NOT the exact baseline filename → still blocked" {
  mkdir -p .aid-o/metrics
  echo "unrelated" > .aid-o/metrics/some-other-file.yaml
  git add .aid-o/metrics/some-other-file.yaml
  git commit -q -m "track unrelated metrics file baseline"
  echo "changed" >> .aid-o/metrics/some-other-file.yaml
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Uncommitted changes present" ]]
}

# ─── Step 3: EXECUTE→GATES precondition + grandfather (3 assertions) ─────

@test "EXECUTE→GATES: missing _generated_by (post-deploy) → hard fail" {
  # Post-deploy fsm-state.yaml + hand-written gates_report.json.
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{"overall":"pass","gates":{}}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing _generated_by" ]]
  [[ "$output" =~ "aid-run-gates.sh run-all" ]]
}

@test "EXECUTE→GATES: present _generated_by + CP3 outputs → accept" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  jq -n '{overall:"pass", gates:{}, _generated_by:"aid-run-gates.sh@v2.16.0", _generated_at:"2026-05-04T00:00:00Z", _command_log:[]}' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  # P094: a closed passing EPIC review round (cp3/rounds.json) is the precondition.
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp3 "" pass

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -eq 0 ]
}

@test "EXECUTE→GATES: pre-deploy grandfather (created_at < deploy_date) → accept regardless" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # Override created_at to BEFORE AID_DEPLOY_DATE
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^created_at: .*/created_at: 2026-03-01T00:00:00Z/' "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{"overall":"pass","gates":{}}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -eq 0 ]
}

# ─── P033 Step 9: CP2 verifier-output preconditions (3 assertions) ───────────

# Helper: write a fully-valid step-N-verify.md for a given step number.
write_valid_step_verify() {
  local file="$1" step="${2:-3}"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<VERIFY
# Step ${step} Verification

## Result: PASS

- [x] acceptance criterion met
- [x] output files match expected paths

Commit: abc1234def5678

## Memory Used
N/A — no prior memory applicable

## Memory Written
N/A — no new entries proposed
VERIFY
}

@test "increment-step: no cp2 round index for the step (post-deploy) → hard fail naming the step check" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # No cp2/step-3/rounds.json → CP2 precondition fails (P094)

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no review round index for cp2 step 3" ]]
  [[ "$output" =~ "aid-step-check.sh --checkpoint cp2 --step 3" ]]
}

@test "increment-step: cp2 round closed with verdict fail → hard fail; a bound skip → accept" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 3 fail
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verdict fail" ]]
  rm -rf "$TEST_EVIDENCE_DIR/cp2"
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 3 skip
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── AID-052: frontend Visual Anchoring precondition (E161) ──────────────────

write_plan_with_frontend_visual_step() {
  cat > "$TEST_EVIDENCE_DIR/plan.json" <<'PLAN'
{"epic_id":"E-test","version":"1.0","steps":[
  {"id":"step_0_architect","role":"architect","objective":"design contracts"},
  {"id":"step_1_domain","role":"domain","objective":"domain model"},
  {"id":"step_2_backend","role":"backend","objective":"implement api"},
  {"id":"step_3_frontend","role":"frontend","objective":"build ui","visual_refs":["mockups/x.tsx"]}
],"dependencies":[]}
PLAN
}

@test "increment-step: frontend step with visual_refs but no '## Visual Anchoring' → fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  write_plan_with_frontend_visual_step
  mkdir -p "$TEST_EVIDENCE_DIR/steps/step_3_frontend"
  printf '# Frontend output\nSome code, but no anchoring section.\n' \
    > "$TEST_EVIDENCE_DIR/steps/step_3_frontend/output.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Visual Anchoring" ]]
}

@test "increment-step: frontend step with visual_refs AND '## Visual Anchoring' → accept" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  write_plan_with_frontend_visual_step
  mkdir -p "$TEST_EVIDENCE_DIR/steps/step_3_frontend"
  printf '## Visual Anchoring\nLayout: 12-col grid\nColors: #fff\n\n# code follows\n' \
    > "$TEST_EVIDENCE_DIR/steps/step_3_frontend/output.md"
  # satisfy CP2 verifier-output (SKIP classification, as for a trivial diff).
  # _generated_at required since E-046-1_3 Step 2.
  printf '_generated_by: aid-pre-filter.sh@v2.18.0\n_generated_at: 2026-06-18T10:00:00Z\nclassification: SKIP\nreason: trivial\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
    aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 3 pass   # P094: the round index is the cp2 evidence

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── P033 Step 9: force_override --reason enforcement (2 assertions) ─────────

@test "transition --force without --reason → die with examples" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"

  run "$FSM" transition EXECUTE GATES "$state_file" --force
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--reason" ]]
  [[ "$output" =~ "min 20 characters" ]]
}

@test "increment-step --force with short reason (< 20 chars) → die" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"

  run "$FSM" increment-step "$state_file" --force --reason "too short"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "min 20 characters" ]]
}

# ─── P035 Step 4: advance-to-gates atomicity (4 assertions) ──────────────

@test "advance-to-gates: success path EXECUTE→GATES via cmd_transition" {
  seed_test_state_files "EXECUTE" "5" "5"
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp3 "" pass
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_pre_gates"
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "gate_runner_complete"
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_transition"
}

@test "advance-to-gates: failure path leaves state at EXECUTE" {
  seed_test_state_files "EXECUTE" "5" "5"
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp3 "" pass
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_failing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "EXECUTE" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_pre_gates"
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_advance_to_gates_fail"
  # No fsm_transition event — gates failed before transition
  ! assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_transition"
}

@test "advance-to-gates: missing cp3 round index → cmd_transition fails after gates pass" {
  seed_test_state_files "EXECUTE" "5" "5"
  # NOTE: NO cp3/rounds.json (intentional — gates run, transition rejects)
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  # Gates ran independently of CP3 — runner exits 0
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "gate_runner_complete"
  # cmd_transition's check_preconditions sees no cp3 round index and rejects
  [[ "$output" == *"no review round index for cp3"* ]]
  # State stayed EXECUTE because cmd_transition didn't commit
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "EXECUTE" ]
}

# ─── P063 Step 3 (AC11): GATES:EXECUTE repeated-timeout policy block ────────
# Real 3-consecutive-timeout policy block via the actual aid-run-gates.sh
# code path (not hand-written JSON): seed 3 prior timeout samples in the
# gate-runtime-baseline file, then run one more attempt that also times out
# under the same currently-configured timeout, exactly like
# test-aid-run-gates.bats' AC6a fixture — this produces a REAL
# gates_report.json with runtime_baseline.retryable:false.

@test "AC11: GATES:EXECUTE refused when a gate is retryable:false (real timeout_policy_block); GATES:ESCALATION and --force still work" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1

  local exec_yaml="$TEST_TMPDIR/exec.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  flaky_gate:
    command: "sleep 2"
    required: true
    timeout_seconds: 1
    max_retries: 2
YAML
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  "$RUN_GATES" run-all "$exec_yaml" E-test R-test \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" >/dev/null 2>&1 || true

  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "false" ]
  run jq -re '.gates.flaky_gate.runtime_baseline.operator_action' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "increase_timeout_or_background" ]

  # Fixture A: GATES:EXECUTE is REFUSED, message names gate + operator_action.
  local state_a="$TEST_TMPDIR/state-a.yaml"
  write_post_deploy_state_yaml "$state_a"
  sed -i 's/^state: .*/state: GATES/' "$state_a"
  run "$FSM" transition GATES EXECUTE "$state_a"
  [ "$status" -ne 0 ]
  [[ "$output" == *"flaky_gate"* ]]
  [[ "$output" == *"increase_timeout_or_background"* ]]
  [ "$(grep '^state:' "$state_a" | awk '{print $2}')" = "GATES" ]

  # Fixture B: GATES:ESCALATION for the SAME evidence dir still succeeds
  # normally — this precondition only ever guards GATES:EXECUTE.
  local state_b="$TEST_TMPDIR/state-b.yaml"
  write_post_deploy_state_yaml "$state_b"
  sed -i 's/^state: .*/state: GATES/' "$state_b"
  run "$FSM" transition GATES ESCALATION "$state_b"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$state_b" | awk '{print $2}')" = "ESCALATION" ]

  # Fixture C: --force --reason overrides the refusal, same as every sibling
  # precondition.
  local state_c="$TEST_TMPDIR/state-c.yaml"
  write_post_deploy_state_yaml "$state_c"
  sed -i 's/^state: .*/state: GATES/' "$state_c"
  run "$FSM" transition GATES EXECUTE "$state_c" --force --reason "PM-authorized override — manually verified flaky_gate timeout is safe to retry"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$state_c" | awk '{print $2}')" = "EXECUTE" ]
}

# ─── E-063-1_1 REOPEN (PM finding, HIGH) ────────────────────────────────────
# AC11 above proves the block CORRECTLY refuses GATES:EXECUTE while it is
# still active. This test proves the other half the PM's manual review found
# missing: once that SAME gate later recovers, the block must be gone — and
# a DIFFERENT gate's own real, current failure must still be visible and
# actionable via a normal GATES:EXECUTE retry, never masked by the first
# gate's already-resolved history. Under the pre-fix code this transition
# was refused forever (flaky_gate's retryable:false never cleared), even
# though the actual remaining problem — other_gate — has nothing to do with
# the old timeout streak and gate-fixer could otherwise address it directly.
@test "E-063-1_1 reopen: GATES:EXECUTE proceeds once a previously-blocked gate recovers, even while a DIFFERENT gate currently fails" {
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-gate-runtime-baseline.sh"
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" update flaky_gate "sleep 2" "sleep 2" 124 1000 1
  bash "$LIB" mark-policy-block flaky_gate "increase_timeout_or_background"

  # Confirm the block is REAL (established via mark-policy-block, not just
  # raw seeded samples) before proceeding.
  run bash "$LIB" report-json flaky_gate
  [ "$(echo "$output" | jq -r '.retryable')" == "false" ]

  # A LATER gates run: flaky_gate now passes; other_gate fails for a reason
  # completely unrelated to flaky_gate's old timeout streak.
  local exec_yaml="$TEST_TMPDIR/exec-reopen.yaml"
  cat > "$exec_yaml" <<'YAML'
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
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  "$RUN_GATES" run-all "$exec_yaml" E-test R-test \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" >/dev/null 2>&1 || true

  run jq -re '.gates.flaky_gate.runtime_baseline.retryable' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "true" ]
  run jq -re '.gates.other_gate.result' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "fail" ]

  # The actual proof: GATES:EXECUTE must proceed WITHOUT --force. gate-fixer
  # needs to retry EXECUTE to address other_gate's real, current failure —
  # flaky_gate's already-resolved history must not stand in the way.
  local state="$TEST_TMPDIR/state-reopen.yaml"
  write_post_deploy_state_yaml "$state"
  sed -i 's/^state: .*/state: GATES/' "$state"
  run "$FSM" transition GATES EXECUTE "$state"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$state" | awk '{print $2}')" = "EXECUTE" ]
}

# ─── P040 Step 2: orphan dispatch reconciliation backstop (4 assertions) ─────

# Helper: seed the increment-step happy-path preconditions for step 3
# (valid step-3-verify.md + valid non-pending verifier-output-step-3.md).
_p040_seed_increment_preconditions() {
  local state_file="$1"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # _generated_at required since E-046-1_3 Step 2.
  printf '_generated_by: aid-orchestrator:verifier@abc123\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
    aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 3 pass   # P094: the round index is the cp2 evidence
}

@test "increment-step: clean/empty pending-dispatches → step advances" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  # Empty (size 0) pending file = all dispatches completed cleanly → skip.
  : > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
}

@test "increment-step: orphan start (no complete, past max) → step blocked + audit" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  # Start far in the past, expected_duration_max:60 → orphan.
  printf '%s\n' '{"ts":"2026-05-31T00:00:00Z","event":"start","focus":"cp2-step-1","agent_id":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"x","expected_duration_max":60}' \
    > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ORPHAN DISPATCH: focus=cp2-step-1" ]]
  # current_step NOT incremented (still 3)
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
  grep -q 'fsm_orphan_dispatch_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "increment-step: --force --blocked-checks bypass → advances with waiver audit" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  printf '%s\n' '{"ts":"2026-05-31T00:00:00Z","event":"start","focus":"cp2-step-1","agent_id":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"x","expected_duration_max":60}' \
    > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file" --force \
    --reason "PM-authorized override for known stale dispatch — emit script crashed mid-run; verified manually" \
    --blocked-checks "dispatch_orphan_complete"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
  grep -q 'fsm_orphan_dispatch_waived' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  # No NEW fail event was emitted for this waived invocation.
  ! grep -q 'fsm_orphan_dispatch_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

# HIGH-2: --blocked-checks WITHOUT --force must NOT waive the orphan check.
# Before the fix, the waiver was honored independent of --force, so a bare
# `--blocked-checks dispatch_orphan_complete` bypassed the --reason ≥20 enforcement.
@test "increment-step: --blocked-checks WITHOUT --force → orphan still blocks (HIGH-2)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  printf '%s\n' '{"ts":"2026-05-31T00:00:00Z","event":"start","focus":"cp2-step-1","agent_id":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"x","expected_duration_max":60}' \
    > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  # No --force, no --reason — just the blocked-checks fence. Must STILL block.
  run "$FSM" increment-step "$state_file" --blocked-checks "dispatch_orphan_complete"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ORPHAN DISPATCH: focus=cp2-step-1" ]]
  # current_step NOT incremented (still 3)
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
  grep -q 'fsm_orphan_dispatch_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  # The waiver path was NOT taken.
  ! grep -q 'fsm_orphan_dispatch_waived' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

# HIGH-2 corollary: --force ALONE (no dispatch_orphan_complete in --blocked-checks)
# still runs the orphan check — force does not bypass by itself.
@test "increment-step: --force alone (no orphan waiver) → orphan still blocks" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  printf '%s\n' '{"ts":"2026-05-31T00:00:00Z","event":"start","focus":"cp2-step-1","agent_id":"aid-orchestrator:verifier","step_n":1,"evidence_dir":"x","expected_duration_max":60}' \
    > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file" --force \
    --reason "PM override of step verification only — orphan dispatch must remain enforced here"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ORPHAN DISPATCH: focus=cp2-step-1" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
}

@test "increment-step: malformed pending-dispatches → fail loud + audit reason" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  printf '%s\n' 'this is not json {{{' > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "pending-dispatches.jsonl is malformed" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
  grep -q '"reason":"pending_file_malformed"' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "increment-step: TZ=UTC orphan detection (tight 100s margin, past deadline) → blocked" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  # Compute timestamp 100 seconds ago in UTC. Start + 60s deadline = orphan now.
  # This tests that TZ=UTC jq parsing catches the orphan (without TZ=UTC,
  # a CEST+0200 host would understate by 7200s and miss the orphan).
  local ts_100s_ago
  ts_100s_ago=$(date -u -d '100 seconds ago' +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\n' "{\"ts\":\"$ts_100s_ago\",\"event\":\"start\",\"focus\":\"cp2-step-1\",\"agent_id\":\"aid-orchestrator:verifier\",\"step_n\":1,\"evidence_dir\":\"x\",\"expected_duration_max\":60}" \
    > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "ORPHAN DISPATCH: focus=cp2-step-1" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
  grep -q 'fsm_orphan_dispatch_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "aid-run-gates.sh: env-var bypass allows EXECUTE state when AID_GATES_TRIGGERED_BY_FSM=1" {
  seed_test_state_files "EXECUTE" "1" "1"
  local exec_yaml; exec_yaml="$TEST_EVIDENCE_DIR/execution.yaml"
  setup_passing_execution_yaml "$exec_yaml"
  local runner; runner="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"

  # With env var: runner accepts EXECUTE state, runs gates, exits 0
  AID_GATES_TRIGGERED_BY_FSM=1 run \
    "$runner" run-all "$exec_yaml" "E-test" "R-test" \
      --state-file "$TEST_EVIDENCE_DIR/fsm-state.yaml" \
      --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$status" -eq 0 ]

  # Without env var: runner rejects (state==EXECUTE, expected GATES)
  unset AID_GATES_TRIGGERED_BY_FSM
  run "$runner" run-all "$exec_yaml" "E-test" "R-test" \
      --state-file "$TEST_EVIDENCE_DIR/fsm-state.yaml" \
      --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FSM state must be GATES"* ]]
  [[ "$output" == *"advance-to-gates"* ]]
}

# ─── P040 Step 4: streamlined mode (Component D) — 7 assertions ──────────────

# Helper: seed an fsm-state.yaml with streamlined_mode under TEST_EVIDENCE_DIR.
# Args: <streamlined true|false> [base_commit]
_streamlined_seed_state() {
  local streamlined="$1"
  local base="${2:-HEAD}"
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<EOF
epic_id: E-test
run_id: R-test
state: DONE
base_commit: $base
streamlined_mode: $streamlined
EOF
}

# Helper: invoke a streamlined check function by sourcing aid-fsm.sh with
# epic_id/run_id/project_root in scope (needed by fsm_emit_audit_log).
# Args: <fn_name> <evidence_dir> <state_file> <project_root>.
_run_streamlined_check() {
  local fn="$1" ev_dir="$2" state_file="$3" proj_root="$4"
  run bash -c '
    set -euo pipefail
    source "'"$FSM"'"
    epic_id=E-test run_id=R-test project_root="'"$proj_root"'"
    '"$fn"' "'"$ev_dir"'" "'"$state_file"'"
  '
}

# Helper: write a 3-line timeline.jsonl (fsm_init + fsm_transition + one step).
_write_three_event_timeline() {
  cat > "$TEST_EVIDENCE_DIR/timeline.jsonl" <<'EOF'
{"event":"fsm_init","epic_id":"E-test"}
{"event":"fsm_transition","from":"READY","to":"EXECUTE"}
{"event":"fsm_step_complete","step":1}
EOF
}

@test "streamlined: init --streamlined writes streamlined_mode: true" {
  run "$FSM" init $(build_default_init_args E-test) --streamlined
  [ "$status" -eq 0 ]
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  grep -q '^streamlined_mode: true$' "$state_file"
  # Heredoc shape preserved: unquoted/unindented epic_id parseable by grep parser.
  [ "$(grep '^epic_id:' "$state_file" | awk '{print $2}')" = "E-test" ]
}

@test "streamlined: skips per-step CP2 (missing verifier-output) → increment-step exit 0" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3, post-deploy
  echo "streamlined_mode: true" >> "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # NO verifier-output-step-3.md (would fail CP2 in full mode); streamlined skips.

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
}

@test "streamlined: compliance.json emits coverage_mode + skipped_dimensions" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  echo "streamlined_mode: true" >> "$state_file"
  run bash -c '
    set -euo pipefail
    source "'"$FSM"'"
    project_root="'"$TEST_PROJECT_ROOT"'"
    write_compliance_json E-test R-test "'"$state_file"'" "'"$TEST_EVIDENCE_DIR"'" "'"$TEST_PROJECT_ROOT"'"
  '
  [ "$status" -eq 0 ]
  local cj="$TEST_EVIDENCE_DIR/compliance.json"
  [ -f "$cj" ]
  [ "$(jq -r '.coverage_mode' "$cj")" = "streamlined" ]
  jq -e '.skipped_dimensions == ["verifier_outputs.cp2_rounds"]' "$cj"
}

@test "streamlined: abandoned fires on <3 timeline events (NR 12 anchor)" {
  _streamlined_seed_state true
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"

  # 2-event timeline (fsm_init + fsm_transition only) → fires
  printf '{"event":"fsm_init"}\n{"event":"fsm_transition"}\n' > "$TEST_EVIDENCE_DIR/timeline.jsonl"
  _run_streamlined_check fsm_check_streamlined_abandoned "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"streamlined_abandoned"* ]]
  grep -q 'streamlined_abandoned_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"

  # 0-event timeline (missing file) → fires
  rm -f "$TEST_EVIDENCE_DIR/timeline.jsonl"
  _run_streamlined_check fsm_check_streamlined_abandoned "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"streamlined_abandoned"* ]]

  # 1-event timeline → fires
  printf '{"event":"fsm_init"}\n' > "$TEST_EVIDENCE_DIR/timeline.jsonl"
  _run_streamlined_check fsm_check_streamlined_abandoned "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]

  # 3-event timeline → does NOT fire
  _write_three_event_timeline
  _run_streamlined_check fsm_check_streamlined_abandoned "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "streamlined: integration-review without a passing cp3 round blocks" {
  _streamlined_seed_state true
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _write_three_event_timeline
  # gates_report present; the cp3 round closed with verdict fail.
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp3 "" fail
  echo '{}' > "$TEST_EVIDENCE_DIR/gates_report.json"

  _run_streamlined_check fsm_check_streamlined_integration_review "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cp3/rounds.json with verdict pass"* ]]
  grep -q 'streamlined_integration_review_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "streamlined: integration-review with a passing cp3 round and the gates report passes" {
  _streamlined_seed_state true
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _write_three_event_timeline
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp3 "" pass
  echo '{}'   > "$TEST_EVIDENCE_DIR/gates_report.json"

  _run_streamlined_check fsm_check_streamlined_integration_review "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  # No integration-review-fail audit recorded.
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl" ] || \
    ! grep -q 'streamlined_integration_review_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

# ─── P040 Component E: steps[] array absorption + read_steps_array ────────

@test "Component E: cmd_init writes steps[] array of length total_steps with id:1..N" {
  # build_default_init_args passes total_steps=3.
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # steps[] array present and correct length.
  [ "$(yq '.steps | length' "$state_file")" = "3" ]
  [ "$(yq '.steps[0].id' "$state_file")" = "1" ]
  [ "$(yq '.steps[2].id' "$state_file")" = "3" ]
  [ "$(yq '.steps[0].status' "$state_file")" = "pending" ]
  # Heredoc shape preserved: unquoted/unindented scalars still grep-parseable.
  [ "$(grep '^epic_id:' "$state_file" | awk '{print $2}')" = "E-test" ]
  [ "$(grep '^total_steps:' "$state_file" | awk '{print $2}')" = "3" ]
  # streamlined_mode scalar still present after steps[] append.
  [ "$(yq '.streamlined_mode' "$state_file")" = "false" ]
}

@test "Component E: cmd_init --streamlined keeps steps[] + streamlined_mode true" {
  run "$FSM" init $(build_default_init_args E-test) --streamlined
  [ "$status" -eq 0 ]
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$(yq '.steps | length' "$state_file")" = "3" ]
  [ "$(yq '.streamlined_mode' "$state_file")" = "true" ]
  [ "$(grep '^epic_id:' "$state_file" | awk '{print $2}')" = "E-test" ]
}

@test "Component E: read_steps_array prefers fsm-state.yaml over legacy state.yaml" {
  # fsm-state.yaml has 2 steps, legacy state.yaml has 5 — reader must pick fsm-state.
  local fsm_state="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  local legacy="$TEST_EVIDENCE_DIR/state.yaml"
  printf 'steps:\n  - id: 1\n    status: pending\n  - id: 2\n    status: pending\n' > "$fsm_state"
  printf 'steps:\n  - id: 1\n  - id: 2\n  - id: 3\n  - id: 4\n  - id: 5\n' > "$legacy"
  run bash -c 'source "'"$FSM"'"; read_steps_array "'"$fsm_state"'"'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "2" ]
}

@test "Component E: read_steps_array falls back to legacy state.yaml when fsm-state lacks steps" {
  local fsm_state="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  local legacy="$TEST_EVIDENCE_DIR/state.yaml"
  # fsm-state.yaml has scalars but NO steps[]; legacy has steps[].
  printf 'epic_id: E-test\nstate: READY\n' > "$fsm_state"
  printf 'steps:\n  - id: 1\n  - id: 2\n  - id: 3\n' > "$legacy"
  run bash -c 'source "'"$FSM"'"; read_steps_array "'"$fsm_state"'"'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "3" ]
}

@test "Component E: read_steps_array returns [] when neither file has steps" {
  local fsm_state="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  printf 'epic_id: E-test\nstate: READY\n' > "$fsm_state"
  run bash -c 'source "'"$FSM"'"; read_steps_array "'"$fsm_state"'"'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "0" ]
}

# ─── CP3 activation gap: --streamlined THROUGH aid-json-to-run.sh ─────────
# Guards the integration path the CP3 gap exposed: streamlined is activated
# via aid-json-to-run.sh (the sole auto-init entry point), NOT by calling
# aid-fsm.sh init --streamlined directly. setup_test_evidence_dir() already
# put us in a clean git repo on main, so Step 18 auto-init runs for real.

@test "CP3: aid-json-to-run.sh --streamlined → fsm-state.yaml streamlined_mode true" {
  local j2r="$AID_PLUGIN_PATH/scripts/aid-json-to-run.sh"
  local fixtures="$AID_PLUGIN_PATH/scripts/tests/fixtures"
  local plan_json="$fixtures/minimal-plan.json"
  local epic="$fixtures/E-TEST-001-1_1-minimal-test-plan.md"
  local tmpl="$AID_PLUGIN_PATH/defaults/templates/run-new-feature.md"
  local out_dir="$TEST_PROJECT_ROOT/.aid-o/work/runs/R-CP3-ON"
  mkdir -p "$out_dir"

  run "$j2r" --plan-json "$plan_json" --run-template "$tmpl" \
    --epic "$epic" --output-dir "$out_dir" --run-id "R-CP3-ON" --streamlined
  [ "$status" -eq 0 ]

  local state_file="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-TEST-001-1_1/R-CP3-ON/fsm-state.yaml"
  [ -f "$state_file" ]
  [ "$(yq -r '.streamlined_mode' "$state_file")" = "true" ]
}

@test "CP3: aid-json-to-run.sh WITHOUT --streamlined → streamlined_mode false" {
  local j2r="$AID_PLUGIN_PATH/scripts/aid-json-to-run.sh"
  local fixtures="$AID_PLUGIN_PATH/scripts/tests/fixtures"
  local plan_json="$fixtures/minimal-plan.json"
  local epic="$fixtures/E-TEST-001-1_1-minimal-test-plan.md"
  local tmpl="$AID_PLUGIN_PATH/defaults/templates/run-new-feature.md"
  local out_dir="$TEST_PROJECT_ROOT/.aid-o/work/runs/R-CP3-OFF"
  mkdir -p "$out_dir"

  run "$j2r" --plan-json "$plan_json" --run-template "$tmpl" \
    --epic "$epic" --output-dir "$out_dir" --run-id "R-CP3-OFF"
  [ "$status" -eq 0 ]

  local state_file="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-TEST-001-1_1/R-CP3-OFF/fsm-state.yaml"
  [ -f "$state_file" ]
  [ "$(yq -r '.streamlined_mode' "$state_file")" = "false" ]
}

# ─── D1 (IMP-232 v2.58.0): dependency-scoped init gate ──────────────────────
# The old global cross-plan ca-review-complete hard-block is REMOVED: an
# independent plan's state NEVER blocks another plan's init. A hard block occurs
# ONLY when THIS plan declares a STRUCTURED depends_on_plans target that is not
# closed (skippable via the sanctioned --force override). These replace the four
# old cross-plan-gate assertions.

# Helper: create a completed EPIC evidence dir with DONE+review state.
_seed_done_epic() {
  local epic_id="$1" run_id="$2" audit="${3:-true}"
  local ev_dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}"
  mkdir -p "$ev_dir"
  cat > "${ev_dir}/fsm-state.yaml" <<EOF
epic_id: ${epic_id}
run_id: ${run_id}
state: DONE
done_phase: review
base_commit: HEAD
branch: task/${epic_id}/main
EOF
  if [[ "$audit" == "true" ]]; then
    echo "blocking_findings: false" > "${ev_dir}/audit-report.md"
  fi
}

# Helper: structured lifecycle manifest declaring depends_on_plans.
# COMMITTED on the target branch (like plan-start writes it in production):
# IMP-273 routes cmd_init's mode decision through the committed-tree authority
# `_fsm_declared_plan_mode`, which treats an uncommitted (working-tree-only)
# manifest as `unresolved` and hard-blocks BEFORE the D1 dependency gate. A real
# plan's lifecycle manifest is always committed, so committing here keeps this a
# faithful legacy-plan fixture: the committed manifest carries no plan_branch
# mode, so the authority resolves legacy_epic_release_mode (a no-op) and control
# reaches the depends_on_plans gate these tests exercise.
_seed_manifest() {
  local plan_id="$1" deps_yaml="$2"   # deps_yaml e.g. "[P045]" or "[]"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests"
  cat > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${plan_id}.yaml" <<EOF
schema_version: aid-lifecycle-1.0
repo_id: test
plan_id: ${plan_id}
mode: legacy_epic_release_mode
declared_epics:
  - {id: E-${plan_id#P}-1_1, scope: required}
depends_on_plans: ${deps_yaml}
EOF
  git -C "$TEST_PROJECT_ROOT" add ".aid-lifecycle/manifests/${plan_id}.yaml" >/dev/null 2>&1
  git -C "$TEST_PROJECT_ROOT" commit -q -m "lifecycle manifest ${plan_id}"
}

# Helper: committed closed receipt (=> aid_plan_closure_state == closed).
_seed_closed_receipt() {
  local plan_id="$1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/receipts"
  cat > "$TEST_PROJECT_ROOT/.aid-lifecycle/receipts/${plan_id}.yaml" <<EOF
schema_version: aid-lifecycle-receipt-1.0
repo_id: test
plan_id: ${plan_id}
plan_manifest_sha: sha256:abc
state: closed
EOF
  git -C "$TEST_PROJECT_ROOT" add ".aid-lifecycle/receipts/${plan_id}.yaml" >/dev/null 2>&1
  git -C "$TEST_PROJECT_ROOT" commit -q -m "closed receipt ${plan_id}"
}

@test "D1: an independent plan is NOT blocked by another plan's done+audit (decoupled)" {
  # P045 EPIC done+audit, no ca-review-complete; P046 declares no deps -> must init.
  _seed_done_epic "E-045-1_3" "R-E045-1"
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -eq 0 ]
}

@test "D1: init BLOCKS when a structured depends_on_plans target is not closed" {
  _seed_manifest "P046" "[P045]"    # P045 has no receipt => not closed
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -ne 0 ]
  [[ "$output" == *"depends_on_plans: P045"* ]]
}

@test "D1: init SUCCEEDS when the depends_on_plans target is closed" {
  _seed_manifest "P046" "[P045]"
  _seed_closed_receipt "P045"
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -eq 0 ]
}

@test "D1: --force overrides the depends_on_plans block (audited)" {
  _seed_manifest "P046" "[P045]"    # P045 not closed
  run "$FSM" init $(build_default_init_args "E-046-1_1") --force --reason "P045 need not close first for this independent scaffolding step"
  [ "$status" -eq 0 ]
}

# v2.58.2 hotfix #3: a real dependency declared in the plan FRONTMATTER (not a
# hand-seeded manifest) must propagate into the tracked manifest via ensure_manifest
# and then actually block init end-to-end.
@test "D1: a frontmatter depends_on_plans is written into the manifest by ensure_manifest and blocks init end-to-end" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  cat > "$TEST_PROJECT_ROOT/.aid-o/plans/P046-x.md" <<'PLAN'
---
id: P046
type: regular
lifecycle_strict: true
depends_on_plans: [P045]
---
# Plan: P046
**EPIC 1: work (Steps 1-1)**
PLAN
  # scaffold path: ensure_manifest must carry the frontmatter dep into the manifest
  ( cd "$TEST_PROJECT_ROOT" && source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh" && aid_lifecycle_ensure_manifest P046 . )
  run yq -r '.depends_on_plans[]' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P046.yaml"
  [[ "$output" == *"P045"* ]]                       # dep reached the manifest via the NORMAL path
  # and init hard-blocks because P045 is not closed (D1 reads the tracked manifest)
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -ne 0 ]
  [[ "$output" == *"depends_on_plans: P045"* ]]
}

# v2.58.2 audit hardening: a stray leading blank line before the `---` fence must
# NOT silently drop the dependency (that would be a D1 gate fail-OPEN).
@test "D1: a leading blank line before the frontmatter fence still propagates depends_on_plans (no fail-open)" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '\n\n---\nid: P047\ntype: regular\ndepends_on_plans: [P045]\n---\n# Plan: P047\n**EPIC 1: work (Steps 1-1)**\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/plans/P047-x.md"
  ( cd "$TEST_PROJECT_ROOT" && source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh" && aid_lifecycle_ensure_manifest P047 . )
  run yq -r '.depends_on_plans[]' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P047.yaml"
  [[ "$output" == *"P045"* ]]                       # dependency survived the leading blank line
  run "$FSM" init $(build_default_init_args "E-047-1_1")
  [ "$status" -ne 0 ]
  [[ "$output" == *"depends_on_plans: P045"* ]]
}

# ─── E-046-1_3 Step 2: _generated_at required in CP2 verifier output ─────────
# Regression for the missing check: empty/absent _generated_at was accepted before.

# ─── E-046-1_3 post-audit: yaml_field quote normalization + verdict whitelist ─
# Regression for auditor finding: _generated_by: "" passed as non-empty (quoted
# empty is non-empty string before quote-stripping fix), and verdict: banana
# passed because only "pending" and empty were rejected.

@test "P079 Step 4: '## Result: pass' passes the increment anchor (canonical heading stays uppercase)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # Same file, only the heading's casing differs.
  local vf="$TEST_EVIDENCE_DIR/step-3-verify.md"
  sed -i 's|## Result: PASS|## Result: pass|' "$vf"
  grep -q '## Result: pass' "$vf"
  printf '_generated_by: aid-orchestrator:verifier@test\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
    aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 3 pass   # P094: the round index is the cp2 evidence

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── E5 C2 Semantic Wiring-Gate (observe mode) ───────────────────────────────

@test "E5 wiring-gate observe: Critical finding logged but increment proceeds" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # write_post_deploy_state_yaml creates state with current_step=3; total_steps=3
  write_post_deploy_state_yaml "$state_file"

  # CP2 preconditions: step-3-verify.md + verifier-output-step-3.md (valid, non-pending)
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 3 pass   # P094: the round index is the cp2 evidence

  # Timeline seed (log_event appends to this file)
  echo '{"ts":"2026-06-18T00:00:00Z","event":"run_started"}' > "$TEST_EVIDENCE_DIR/timeline.jsonl"

  # Wiring report with one Critical unresolved finding
  cat > "$TEST_EVIDENCE_DIR/semantic-review-wiring.json" <<'WIRING'
{
  "semantic_review": {
    "findings": [
      {
        "fingerprint": "sha256:aabb000000000000000000000000000000000000000000000000000000000001",
        "severity": "critical",
        "lens": "transaction_boundary",
        "check_id": "TXN-001",
        "target_path": "src/test.ts",
        "finding_class": "boundary_violation",
        "status": "open",
        "detail": "test finding for wiring gate"
      }
    ]
  }
}
WIRING

  # Run increment-step in observe mode (default)
  SEMANTIC_REVIEW_POLICY=observe run "$FSM" increment-step "$state_file"

  # observe mode: must not block (exit 0)
  [ "$status" -eq 0 ]

  # Timeline must contain semantic_wiring_would_block event
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "semantic_wiring_would_block"
}

# Helper: fsm-state.yaml with an explicit steps[] array (P040 Component E
# shape) sized so steps[3] exists — current_step: 3, total_steps: 4. steps[0-2]
# are pre-completed (prior steps already advanced); steps[3] is the pending
# step under test for this increment-step call.
write_state_with_steps_array() {
  local state_file="$1"
  local epic_id="${2:-E-test}"
  local run_id="${3:-R-test}"
  local branch="${4:-task/${epic_id}/main}"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" <<EOF
epic_id: $epic_id
run_id: $run_id
state: EXECUTE
current_step: 3
total_steps: 4
mode: manual
branch: $branch
base_commit: HEAD
gate_retries: 0
escalation_count: 0
started_at: "$now"
created_at: $now
steps:
  - id: 1
    name: ""
    status: completed
    started_at: "$now"
    completed_at: "$now"
  - id: 2
    name: ""
    status: completed
    started_at: "$now"
    completed_at: "$now"
  - id: 3
    name: ""
    status: completed
    started_at: "$now"
    completed_at: "$now"
  - id: 4
    name: ""
    status: pending
    started_at: null
    completed_at: null
EOF
}

# Helper: satisfy the increment-step CP2 preconditions for the given step N
# (valid step-N-verify.md + a closed passing cp2 round, P094).
_obs20260708_seed_cp2() {
  local step="$1"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-${step}-verify.md" "$step"
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 "$step" pass
}

@test "increment-step: pending steps[3] becomes completed with a valid ISO 8601 completed_at" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_state_with_steps_array "$state_file"
  _obs20260708_seed_cp2 3

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(yq '.steps[3].status' "$state_file")" = "completed" ]
  local completed_at
  completed_at=$(yq '.steps[3].completed_at' "$state_file")
  [[ "$completed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  # started_at was null pre-increment → backfilled to the same completed_at,
  # never left null on an otherwise-completed step.
  [ "$(yq '.steps[3].started_at' "$state_file")" = "$completed_at" ]
}

@test "increment-step: two-step run leaves no steps[] entry pending (DONE-epic regression guard)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$state_file" <<EOF
epic_id: E-test
run_id: R-test
state: EXECUTE
current_step: 0
total_steps: 2
mode: manual
branch: task/E-test/main
base_commit: HEAD
gate_retries: 0
escalation_count: 0
started_at: "$now"
created_at: $now
steps:
  - id: 1
    name: ""
    status: pending
    started_at: null
    completed_at: null
  - id: 2
    name: ""
    status: pending
    started_at: null
    completed_at: null
EOF
  _obs20260708_seed_cp2 0
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]

  _obs20260708_seed_cp2 1
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]

  [ "$(yq '.steps[0].status' "$state_file")" = "completed" ]
  [ "$(yq '.steps[1].status' "$state_file")" = "completed" ]
  # OBS-20260708-04's exact symptom: a DONE (fully-advanced) epic must not
  # show any steps[] entry stuck at status: pending.
  local pending_count
  pending_count=$(yq '[.steps[] | select(.status == "pending")] | length' "$state_file")
  [ "$pending_count" = "0" ]
}

@test "increment-step: emits step_status_synced timeline event" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_state_with_steps_array "$state_file"
  _obs20260708_seed_cp2 3

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "step_status_synced"
}

@test "increment-step: forged current_step (yq multi-index injection, e.g. '0,1') does NOT forge steps[] completion (CP3 security finding)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$state_file" <<EOF
epic_id: E-test
run_id: R-test
state: EXECUTE
current_step: "0,1"
total_steps: 2
mode: manual
branch: task/E-test/main
base_commit: HEAD
gate_retries: 0
escalation_count: 0
started_at: "$now"
created_at: $now
steps:
  - id: 1
    name: ""
    status: pending
    started_at: null
    completed_at: null
  - id: 2
    name: ""
    status: pending
    started_at: null
    completed_at: null
EOF
  # current_step is a forged multi-index string, not a plain integer — both
  # bash's $((step + 1)) arithmetic AND yq's ".steps[0,1]" would otherwise
  # accept it (comma is valid in both contexts). --force bypasses the
  # unrelated CP2 verifier-output precondition so this reaches the steps[]
  # sync block under test.
  run "$FSM" increment-step "$state_file" --force --reason "CP3 security regression: forged current_step must not sync steps[]"
  # steps[1] (id: 2) must NOT be forged to completed — the numeric guard
  # must skip the sync block entirely for a non-digit current_step.
  [ "$(yq '.steps[1].status' "$state_file")" = "pending" ]
  [ "$(yq '.steps[0].status' "$state_file")" = "pending" ]
  ! assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "step_status_synced"
}

@test "increment-step: steps[] absent (legacy fsm-state.yaml) → current_step still bumps, no crash" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _p040_seed_increment_preconditions "$state_file"   # write_post_deploy_state_yaml has NO steps[] block

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
  # steps[] sync guard skipped gracefully — no crash, no sync event emitted.
  ! assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "step_status_synced"
}

# ─── E-065-5_7 DONE-review C3 finding: done-advance had no phase-edge check ──
# Codex's real DONE-review audit of this EPIC found: cmd_done_advance only
# verified from_phase matched the CURRENT state and to_phase was a KNOWN
# phase name — neither enforced a directional edge, so `done-advance release
# review <state>` reached the final write, regressing done_phase backward
# with no negative test catching it. Fix: review -> release is the ONLY
# legal edge; everything else (including same-phase and reverse) is rejected.

@test "(E-065-5_7 C3 finding) done-advance release->review: illegal reverse edge is rejected, done_phase unchanged" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  cat > "$state_file" <<YAML
epic_id: E-test
run_id: R-test
branch: task/E-test/main
state: DONE
done_phase: release
created_at: 2026-06-18T00:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
YAML

  run "$FSM" done-advance release review "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"illegal done_phase transition"* ]]
  [[ "$output" == *"release -> review"* ]]
  # done_phase must be unchanged — the rejection must happen before any write.
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

@test "(E-065-5_7 C3 finding) done-advance release->release: same-phase no-op edge is also rejected" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  cat > "$state_file" <<YAML
epic_id: E-test
run_id: R-test
branch: task/E-test/main
state: DONE
done_phase: release
created_at: 2026-06-18T00:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
YAML

  run "$FSM" done-advance release release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"illegal done_phase transition"* ]]
}

@test "(E-065-5_7 C3 finding) done-advance review->review: same-phase no-op edge is rejected" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  cat > "$state_file" <<YAML
epic_id: E-test
run_id: R-test
branch: task/E-test/main
state: DONE
done_phase: review
created_at: 2026-06-18T00:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
YAML

  run "$FSM" done-advance review review "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"illegal done_phase transition"* ]]
}

# ─── IMP-263: idempotent increment-step + step-bound evidence binding ────────
# Repro: E-064-1_2 double-advance. The controller misread the old bare-numeric
# stdout as an error and re-invoked; a copied prior verify file (next numerical
# filename) was accepted as evidence for a step that never ran, so the FSM
# advanced twice. These tests pin: (1) machine-readable stdout, (2) copied-file
# rejection, (3) wrong-plan-hash / wrong-commit / wrong-step rejection,
# (4) replay → already_applied, (5) crash-recovery across each write boundary.

# Canonical plan-step hash — MUST match _increment_plan_step_hash in aid-fsm.sh
# (jq -S -c of steps[i], sha256 of the string with NO trailing newline).
_imp263_plan_step_hash() {
  local plan_json="$1" idx="$2"
  printf '%s' "$(jq -S -c --argjson i "$idx" '.steps[$i]' "$plan_json")" | sha256sum | awk '{print $1}'
}

# Seed a 2-step plan.json under the evidence dir.
_imp263_write_plan() {
  cat > "$TEST_EVIDENCE_DIR/plan.json" <<'PLAN'
{"epic_id":"E-test","version":"1.0","steps":[
  {"id":"step_0_backend","role":"backend","objective":"a"},
  {"id":"step_1_backend","role":"backend","objective":"b"}
],"dependencies":[]}
PLAN
}

# Write a fully-bound step-verify.md. Args: file step_index step_id plan_hash commit token
_imp263_write_bound_verify() {
  local file="$1" idx="$2" sid="$3" ph="$4" commit="$5" token="$6"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<VERIFY
# Step ${idx} Verification
## Result: PASS
- [x] acceptance criterion met
Commit: ${commit:0:12}
step_index: ${idx}
step_id: ${sid}
plan_step_hash: ${ph}
reviewed_commit: ${commit}
idempotency_token: ${token}
## Memory Used
N/A — none
## Memory Written
N/A — none
VERIFY
}

# A bound skip of the step's cp2 review (satisfies the CP2 precondition, P094).
_imp263_write_verifier_output() {
  local step="$1"
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp2 "$step" skip
}

# Common setup: post-deploy state at current_step=0 + valid step-0 binding.
_imp263_seed_step0() {
  local state_file="$1" token="${2:-TOK-0}"
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^current_step: .*/current_step: 0/; s/^total_steps: .*/total_steps: 2/' "$state_file"
  _imp263_write_plan
  local ph0 head0
  ph0=$(_imp263_plan_step_hash "$TEST_EVIDENCE_DIR/plan.json" 0)
  head0=$(git rev-parse HEAD)
  _imp263_write_bound_verify "$TEST_EVIDENCE_DIR/step-0-verify.md" 0 step_0_backend "$ph0" "$head0" "$token"
  _imp263_write_verifier_output 0
}

@test "IMP-263: valid step-0 binding advances + writes ledger + machine-readable stdout" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" == "status=advanced advanced_from=0 advanced_to=1" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "1" ]
  [ -f "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl" ]
  [ "$(jq -r '.token' "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl")" = "TOK-0" ]
  [ "$(jq -r '.to' "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl")" = "1" ]
}

@test "IMP-263: stdout is a status= line (exit 0), never a bare integer mistakable for an exit code" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  # Not a bare integer, and the exit code is decoupled from the displayed step.
  [[ ! "$output" =~ ^[0-9]+$ ]]
  [[ "$output" =~ ^status= ]]
  [[ "$output" =~ advanced_to=1 ]]
}

@test "IMP-263 (AC): real step-0 verification copied to step-1 filename cannot complete step 1" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  run "$FSM" increment-step "$state_file"          # step 0 → 1, records TOK-0
  [ "$status" -eq 0 ]
  # Attacker copies step-0 evidence to the next numerical filename.
  cp "$TEST_EVIDENCE_DIR/step-0-verify.md" "$TEST_EVIDENCE_DIR/step-1-verify.md"
  _imp263_write_verifier_output 1
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ already_applied ]]
  # DID NOT double-advance: current_step stays 1.
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "1" ]
}

@test "IMP-263: fresh token with wrong step_index (copied file rebranded) is rejected" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  run "$FSM" increment-step "$state_file"          # now at step 1
  [ "$status" -eq 0 ]
  local ph0 head; ph0=$(_imp263_plan_step_hash "$TEST_EVIDENCE_DIR/plan.json" 0); head=$(git rev-parse HEAD)
  # step_index still names 0 but placed at step-1 filename with a fresh token.
  _imp263_write_bound_verify "$TEST_EVIDENCE_DIR/step-1-verify.md" 0 step_0_backend "$ph0" "$head" TOK-1-new
  _imp263_write_verifier_output 1
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "step_index=0 != current_step=1" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "1" ]
}

@test "IMP-263: evidence bound to a different plan-step hash is rejected before mutation" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^current_step: .*/current_step: 0/; s/^total_steps: .*/total_steps: 2/' "$state_file"
  _imp263_write_plan
  local head0; head0=$(git rev-parse HEAD)
  # step_index/id correct for step 0, but plan_step_hash is wrong (tampered).
  _imp263_write_bound_verify "$TEST_EVIDENCE_DIR/step-0-verify.md" 0 step_0_backend "deadbeefdeadbeef" "$head0" TOK-0
  _imp263_write_verifier_output 0
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "plan_step_hash does not match" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "0" ]
}

@test "IMP-263: evidence bound to a stale reviewed_commit (not HEAD) is rejected" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^current_step: .*/current_step: 0/; s/^total_steps: .*/total_steps: 2/' "$state_file"
  _imp263_write_plan
  local ph0; ph0=$(_imp263_plan_step_hash "$TEST_EVIDENCE_DIR/plan.json" 0)
  _imp263_write_bound_verify "$TEST_EVIDENCE_DIR/step-0-verify.md" 0 step_0_backend "$ph0" "0000000000000000000000000000000000000000" TOK-0
  _imp263_write_verifier_output 0
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "is not current HEAD" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "0" ]
}

@test "IMP-263 (AC): two identical sequential requests → one transition + one already_applied" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  # Pre-stage the copied file at step-1 (the real incident: it already existed).
  cp "$TEST_EVIDENCE_DIR/step-0-verify.md" "$TEST_EVIDENCE_DIR/step-1-verify.md"
  _imp263_write_verifier_output 1
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]; [[ "$output" =~ ^status=advanced ]]
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]; [[ "$output" =~ already_applied ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "1" ]
  # Exactly one applied transition recorded.
  [ "$(wc -l < "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl")" = "1" ]
}

@test "IMP-263: crash after ledger append, before current_step bump → self-heals, no double advance" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  # Simulate the crash: ledger says 0→1 applied, but current_step is still 0.
  printf '%s\n' '{"token":"TOK-0","step_index":0,"step_id":"step_0_backend","from":0,"to":1,"applied_at":"2026-07-01T00:00:00Z"}' \
    > "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl"
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" =~ already_applied ]]
  # Self-healed to the recorded target, and did NOT append a duplicate entry.
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "1" ]
  [ "$(wc -l < "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl")" = "1" ]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "step_transition_recovered"
}

@test "IMP-263: crash before ledger append → single advance on re-invocation (old-valid → new-valid)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  # No ledger, current_step 0 = the old-valid state after a pre-write crash.
  [ ! -f "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl" ]
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]; [[ "$output" =~ ^status=advanced ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "1" ]
  [ "$(wc -l < "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl")" = "1" ]
}

@test "IMP-263: genuinely grandfathered evidence with NO binding still advances (legacy compat)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step 3
  # created_at BEFORE the deploy threshold → genuinely grandfathered, so it stays
  # lenient even under strict-by-default (no env dependence).
  sed -i 's/^created_at: .*/created_at: 2026-01-01T00:00:00Z/' "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  _imp263_write_verifier_output 3
  unset AID_STEP_BINDING
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" == "status=advanced advanced_from=3 advanced_to=4" ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "step_binding_absent"
}

@test "IMP-263: AID_STEP_BINDING=strict rejects unbound evidence on a non-grandfathered run" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # created_at now > deploy date → not grandfathered
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  _imp263_write_verifier_output 3
  AID_STEP_BINDING=strict run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no IMP-263 binding" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
}

@test "IMP-263 (review MEDIUM): a forged ledger row cannot self-heal current_step by more than one" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0
  # A hand-forged ledger row claims token TOK-0 jumped 0→99. step-0 carries a
  # valid binding, so the idempotency lookup hits — but self-heal requires
  # to == from+1, so it can NEVER jump to 99. The run instead advances exactly
  # one step through the normal verified path; current_step is 1, never 99.
  # (The legitimate crash self-heal from=0,to=1 is covered by the dedicated
  # "crash after ledger append" test above.)
  printf '{"token":"TOK-0","from":0,"to":99}\n' > "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl"
  run "$FSM" increment-step "$state_file"
  local cs; cs=$(grep '^current_step:' "$state_file" | awk '{print $2}')
  [ "$cs" != "99" ]
  [ "$cs" -le 1 ]
}

# ── IMP-263 fail-closed hardening (PM review 2026-07-24) ─────────────────────
# Three gaps the earlier IMP-263 pass left open:
#   #3 a hand-inserted single-step ledger row let unverified evidence masquerade
#      as crash recovery (self-heal advanced current_step with NO valid binding);
#   #2 a PARTIAL binding (token only) evaded the id/hash/commit checks (they were
#      guarded by `-n`), so token-only evidence advanced;
#   #1 strict was opt-in — a new run with no binding advanced by default.

@test "IMP-263 (fail-closed #3): forged ledger row cannot self-heal without a valid live binding" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^current_step: .*/current_step: 0/; s/^total_steps: .*/total_steps: 2/' "$state_file"
  _imp263_write_plan
  _imp263_write_verifier_output 0
  # Evidence that would FAIL preconditions (Result: FAIL, no binding) but carries
  # a token matching a hand-forged ledger row. Only the ledger self-heal bypass
  # could advance here.
  cat > "$TEST_EVIDENCE_DIR/step-0-verify.md" <<'VF'
# Step 0 Verification
## Result: FAIL
idempotency_token: FORGE-0
VF
  printf '{"token":"FORGE-0","from":0,"to":1}\n' > "$TEST_EVIDENCE_DIR/step-transition-ledger.jsonl"
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  # Must NOT have self-healed: current_step stays 0.
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "0" ]
}

@test "IMP-263 (fail-closed #2): a partial binding (token only) is rejected, not silently advanced" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^current_step: .*/current_step: 0/; s/^total_steps: .*/total_steps: 2/' "$state_file"
  _imp263_write_plan
  _imp263_write_verifier_output 0
  # Otherwise-valid evidence, but the binding carries ONLY a token — the id/hash/
  # commit checks must not be skippable.
  cat > "$TEST_EVIDENCE_DIR/step-0-verify.md" <<'VF'
# Step 0 Verification
## Result: PASS
- [x] acceptance criterion met
Commit: abc1234def5678
idempotency_token: TOK-PARTIAL
## Memory Used
N/A — none
## Memory Written
N/A — none
VF
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ binding ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "0" ]
}

@test "IMP-263 (fail-closed #1): strict is the DEFAULT for a new run — no binding is rejected without any env" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # created_at > deploy → new run
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  _imp263_write_verifier_output 3
  unset AID_STEP_BINDING
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ binding ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
}

@test "init with fewer than seven positional arguments is a usage error, not an unbound-variable crash (ACTA #16)" {
  run bash "$FSM" init E-1 R-1 5 full
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: aid-fsm.sh init"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

# ─── amend-scope (ACTA #17): one command moves all three scope readers ───────
@test "amend-scope widens the current step, re-stamps plan_json_hash, records the amendment and refuses the rest" {
  local td="$TEST_EVIDENCE_DIR"
  cat > "$td/plan.json" <<'PLAN'
{"steps":[{"id":"step_1_backend","allowed_paths":["src/a.py"]},{"id":"step_2_qa","allowed_paths":["tests/b.py"]}]}
PLAN
  cat > "$td/fsm-state.yaml" <<EOS
epic_id: E-AS
run_id: R-AS
state: EXECUTE
current_step: 0
total_steps: 2
plan_json_hash: $(sha256sum "$td/plan.json" | awk '{print $1}')
EOS
  : > "$td/timeline.jsonl"
  run bash "$FSM" amend-scope "$td/fsm-state.yaml" --add tests/test_a.py --reason "short"
  [ "$status" -ne 0 ]; [[ "$output" == *"20 characters"* ]]
  run bash "$FSM" amend-scope "$td/fsm-state.yaml" --add /etc/passwd --reason "AC3 demands a test the plan forgot"
  [ "$status" -ne 0 ]; [[ "$output" == *"relative path"* ]]
  run bash "$FSM" amend-scope "$td/fsm-state.yaml" --add src/ --reason "a whole directory is not a file"
  [ "$status" -ne 0 ]; [[ "$output" == *"FILES"* ]]
  mkdir -p "$td/lib"; ( cd "$td" && run bash "$FSM" amend-scope fsm-state.yaml --add lib --reason "an existing directory without a slash"; [ "$status" -ne 0 ] )
  printf 'src/a.py\n' > "$(dirname "$td")/allowed_paths.txt"
  jq '.steps[0].forbidden_paths = ["secrets/"]' "$td/plan.json" > "$td/p.tmp" && mv "$td/p.tmp" "$td/plan.json"
  run bash "$FSM" amend-scope "$td/fsm-state.yaml" --add secrets/key.pem --reason "trying to widen into a forbidden path"
  [ "$status" -ne 0 ]; [[ "$output" == *"forbidden_paths"* ]]
  run bash "$FSM" amend-scope "$td/fsm-state.yaml" --add tests/test_a.py --add src/a_helper.py --reason "AC3 demands a test the plan forgot"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.steps[0].allowed_paths' "$td/plan.json")" = '["src/a.py","src/a_helper.py","tests/test_a.py"]' ]
  [ "$(jq -c '.steps[1].allowed_paths' "$td/plan.json")" = '["tests/b.py"]' ]          # other step untouched
  [ "$(grep '^plan_json_hash:' "$td/fsm-state.yaml" | awk '{print $2}')" = "$(sha256sum "$td/plan.json" | awk '{print $1}')" ]
  [ "$(jq -r '.[0].reason' "$td/steps/step_1_backend/scope-amendment.json")" = "AC3 demands a test the plan forgot" ]
  grep -q '"event":"scope_amended"' "$td/timeline.jsonl"
  grep -qx 'tests/test_a.py' "$(dirname "$td")/allowed_paths.txt"   # the scope_check gate's file kept in step
  # In GATES the scope may still be widened, but never silently: the gate rows
  # judged against the old scope are retired (or their absence is said out
  # loud), because they were judged against a scope that no longer exists.
  # This assertion used to expect a refusal ("not EXECUTE"); the refusal moved
  # to rebase-plan, and the test kept asserting it long after amend-scope
  # stopped saying it.
  sed -i 's/^state: EXECUTE/state: GATES/' "$td/fsm-state.yaml"
  run bash "$FSM" amend-scope "$td/fsm-state.yaml" --add x.py --reason "widening after the gates have run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gates must still be re-run"* || "$output" == *"Re-run the gates"* ]]
  # rebase-plan is the one that still refuses outside EXECUTE
  run bash "$FSM" rebase-plan "$td/fsm-state.yaml" --reason "a rebase at a boundary is the refused one"
  [ "$status" -ne 0 ]; [[ "$output" == *"not EXECUTE"* ]]
}

# ─── rebase-plan (agents #2): a regenerated plan is accepted under three conditions ─
_rebase_fixture() {   # 3-step plan, run on step 1, init snapshot written by hand the way init does
  local td="$TEST_EVIDENCE_DIR"
  cat > "$td/plan.json" <<'PLAN'
{"steps":[{"id":"step_1","allowed_paths":["a.py"]},{"id":"step_2","allowed_paths":["b.py"]},{"id":"step_3","allowed_paths":["c.py"]}]}
PLAN
  cat > "$td/fsm-state.yaml" <<EOS
epic_id: E-RB
run_id: R-RB
state: EXECUTE
current_step: 1
total_steps: 3
base_commit: abc1234def5678
plan_json_hash: $(sha256sum "$td/plan.json" | awk '{print $1}')
EOS
  : > "$td/timeline.jsonl"
  ( source "$FSM" 2>/dev/null || true; _step_hashes_write "$td" "$(sha256sum "$td/plan.json" | awk '{print $1}')" )
  [ -f "$td/step-hashes.json" ]
}
_edit_step() { jq --argjson i "$1" --arg v "$2" '.steps[$i].objective = $v' "$TEST_EVIDENCE_DIR/plan.json" > "$TEST_EVIDENCE_DIR/p.tmp" && mv "$TEST_EVIDENCE_DIR/p.tmp" "$TEST_EVIDENCE_DIR/plan.json"; }

@test "rebase-plan: nothing to do when the hash still matches" {
  _rebase_fixture
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -eq 0 ]; [[ "$output" == *"nothing to rebase"* ]]
}

@test "rebase-plan: a change to a FUTURE step is accepted, recorded, and the hash re-stamped" {
  _rebase_fixture
  _edit_step 2 "renamed objective"
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -eq 0 ]; [[ "$output" == *"future step(s) changed: 2"* ]]
  [ "$(grep '^plan_json_hash:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "$(sha256sum "$TEST_EVIDENCE_DIR/plan.json" | awk '{print $1}')" ]
  [ "$(jq -r '.[0].reason' "$TEST_EVIDENCE_DIR/plan-rebase.json")" = "PM regenerated the plan after a rename" ]
  grep -q '"event":"plan_rebased"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q '^base_commit: abc1234def5678' "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  grep -q '^current_step: 1' "$TEST_EVIDENCE_DIR/fsm-state.yaml"
}

@test "rebase-plan: a change to the CURRENT step or a DONE step is refused and nothing is written" {
  _rebase_fixture
  _edit_step 1 "the step in flight changed"
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -ne 0 ]; [[ "$output" == *"step 1"* && "$output" == *"being worked on"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/plan-rebase.json" ]
  _rebase_fixture
  _edit_step 0 "history rewritten"
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -ne 0 ]; [[ "$output" == *"done step(s) 0"* ]]
  [ ! -f "$TEST_EVIDENCE_DIR/plan-rebase.json" ]
}

@test "rebase-plan: a legacy run without step-hashes.json is refused fail-closed; a short reason is refused" {
  _rebase_fixture
  rm "$TEST_EVIDENCE_DIR/step-hashes.json"; _edit_step 2 "x"
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -ne 0 ]; [[ "$output" == *"step-hashes.json"* ]]
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "short"
  [ "$status" -ne 0 ]; [[ "$output" == *"20 characters"* ]]
}

@test "rebase-plan: amend-scope keeps the snapshot, so a later rebase does not refuse the widened current step" {
  _rebase_fixture
  run bash "$FSM" amend-scope "$TEST_EVIDENCE_DIR/fsm-state.yaml" --add tests/test_b.py --reason "AC demands a test the plan forgot"
  [ "$status" -eq 0 ]
  _edit_step 2 "future change after the amendment"
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -eq 0 ]
}

@test "rebase-plan: init writes the per-step snapshot; outside EXECUTE it refuses; after a rebase increment-step passes" {
  printf '{"steps":[{"id":"s1","allowed_paths":["a.py"]},{"id":"s2","allowed_paths":["b.py"]},{"id":"s3","allowed_paths":["c.py"]}]}\n' > "$TEST_EVIDENCE_DIR/plan.json"
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [ "$(jq '.steps | length' "$TEST_EVIDENCE_DIR/step-hashes.json")" = "3" ]
  # outside EXECUTE → refused
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  run "$FSM" rebase-plan "$state_file" --reason "PM regenerated the plan after a rename"
  [ "$status" -ne 0 ]; [[ "$output" == *"not EXECUTE"* ]]
  # a real increment after a rebase: seed the passing preconditions at step 3 of a 4-step plan
  _p040_seed_increment_preconditions "$state_file"
  # current_step is 3 (0-based) → index 3 is the step in flight; index 4 is a FUTURE step
  jq '.steps += [{"id":"s4","allowed_paths":["d.py"]},{"id":"s5","allowed_paths":["e.py"]}]' "$TEST_EVIDENCE_DIR/plan.json" > "$TEST_EVIDENCE_DIR/p.tmp" && mv "$TEST_EVIDENCE_DIR/p.tmp" "$TEST_EVIDENCE_DIR/plan.json"
  ( source "$FSM" 2>/dev/null || true; _step_hashes_write "$TEST_EVIDENCE_DIR" "$(sha256sum "$TEST_EVIDENCE_DIR/plan.json" | awk '{print $1}')" )
  "$FSM" set-field plan_json_hash "$(sha256sum "$TEST_EVIDENCE_DIR/plan.json" | awk '{print $1}')" "$state_file" --reason "fixture setup: stamp the hash of the plan this case writes"
  "$FSM" set-field total_steps 5 "$state_file" --reason "fixture setup: the plan this case writes has five steps"
  : > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"
  # the PM regenerates the FUTURE step (index 4)
  jq '.steps[4].objective = "regenerated"' "$TEST_EVIDENCE_DIR/plan.json" > "$TEST_EVIDENCE_DIR/p.tmp" && mv "$TEST_EVIDENCE_DIR/p.tmp" "$TEST_EVIDENCE_DIR/plan.json"
  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]; [[ "$output" == *"hash mismatch"* && "$output" == *"rebase-plan"* ]]
  run "$FSM" rebase-plan "$state_file" --reason "PM regenerated the plan after a rename"
  [ "$status" -eq 0 ]
  grep -q '"event":"plan_rebased"' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  grep -q '"epic_id":"E-test"' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
}

@test "rebase-plan: amend-scope moves only the current step's snapshot — a hand edit of a done step is still refused afterwards" {
  _rebase_fixture
  _edit_step 0 "history rewritten by hand"
  run bash "$FSM" amend-scope "$TEST_EVIDENCE_DIR/fsm-state.yaml" --add tests/test_b.py --reason "AC demands a test the plan forgot"
  [ "$status" -eq 0 ]
  _edit_step 2 "future change"
  run bash "$FSM" rebase-plan "$TEST_EVIDENCE_DIR/fsm-state.yaml" --reason "PM regenerated the plan after a rename"
  [ "$status" -ne 0 ]; [[ "$output" == *"done step(s) 0"* ]]
}

@test "rebase-plan/amend-scope: an amendment changes the current step, so its OLD IMP-263 binding no longer completes it — the step is re-verified" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _imp263_seed_step0 "$state_file" TOK-0                      # a valid, bound step-0 verification
  # the plan.json hash stamp + snapshot, as init would leave them
  "$FSM" set-field plan_json_hash "$(sha256sum "$TEST_EVIDENCE_DIR/plan.json" | awk '{print $1}')" "$state_file" --reason "fixture setup: stamp the hash of the plan this case writes"
  ( source "$FSM" 2>/dev/null || true; _step_hashes_write "$TEST_EVIDENCE_DIR" "$(sha256sum "$TEST_EVIDENCE_DIR/plan.json" | awk '{print $1}')" )
  run "$FSM" amend-scope "$state_file" --add src/extra.py --reason "PM approved one more file for step 0"
  [ "$status" -eq 0 ]
  AID_STEP_BINDING=strict run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "plan_step_hash does not match" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "0" ]
}

# ─── Test 1: behavior_trace_count=0 FAILS ────────────────────────────────

# ─── Test 2: behavior_trace_count=3 PASSES ───────────────────────────────

# ─── Test 3: behavior_trace_required=false PASSES regardless of count ────

# ─── Test 4: no behavior_trace_required field PASSES (default is no enforcement)

# ─── Test 5: missing behavior_trace_count when required FAILS ─────────────

# ─── Test 6: behavior_trace_count=1 with required=true PASSES (boundary) ──

@test "set-field: a transition precondition needs a reason and leaves a field_set line; an ordinary field needs none" {
  local td="$TEST_EVIDENCE_DIR" sf
  sf="$td/fsm-state.yaml"
  cat > "$sf" <<EOS
epic_id: E-test
run_id: R-test
state: EXECUTE
current_step: 0
total_steps: 4
EOS
  local tl="$td/timeline.jsonl"; : > "$tl"
  local before; before="$(cat "$sf")"
  run bash "$FSM" set-field total_steps 2 "$sf"
  [ "$status" -eq 1 ]; [[ "$output" == *"--reason"* ]]
  [ "$(cat "$sf")" = "$before" ]

  run bash "$FSM" set-field total_steps 2 "$sf" --reason "the plan lost two steps in review"
  echo "$output"; [ "$status" -eq 0 ]
  grep -q '^total_steps: 2' "$sf"
  [ "$(jq -r 'select(.event == "field_set") | "\(.field) \(.old) \(.new)"' "$tl" | tail -1)" = "total_steps 4 2" ]

  # an ordinary field needs no reason and is still traced
  run bash "$FSM" set-field pm_decision merge "$sf"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.event == "field_set") | .field' "$tl" | tail -1)" = pm_decision ]
}

@test "set-field: a precondition field on a state file with no timeline is refused, reason or not" {
  local sf="$TEST_EVIDENCE_DIR/orphan-state.yaml"
  printf 'state: EXECUTE
current_step: 0
total_steps: 4
' > "$sf"
  run bash "$FSM" set-field total_steps 2 "$sf" --reason "a reason with nowhere to be recorded"
  [ "$status" -eq 1 ]; [[ "$output" == *"names no epic_id/run_id"* ]]
  grep -q '^total_steps: 4' "$sf"
}

# ─── P097 Step 4: the GATES:DONE gate-profile floor, end to end (t2) ────────
# The merge-path proof of the same rule is in test-aid-gate-profile-select.bats
# (t0, the library verdict) and test-aid-run-gates.bats (t1); this is the
# FSM's own end-to-end case: a report that names no profile while the
# project's execution.yaml declares gate_profiles is refused with
# risk_profile_unresolvable, and the same run recorded under the resolved
# profile proceeds.
@test "P097 Step 4: GATES:DONE refuses a gates_report.json with no profile (risk_profile_unresolvable) and accepts the same run recorded under the resolved profile" {
  [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
  setup_test_evidence_dir E-X R-1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  local RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  local base; base=$(git rev-parse HEAD)
  echo "ordinary" > ordinary.txt; git add ordinary.txt; git commit -q -m "ordinary change"
  seed_test_state_files "GATES" "1" "1" "E-X" "R-1"
  echo "base_commit: $base" >> "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  local exec_yaml="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  cat > "$exec_yaml" <<'YAML'
gates:
  always_pass:
    command: "true"
    required: true
default_profile: standard
gate_profiles:
  standard:
    include: [always_pass]
  full:
    include: [always_pass]
    when_paths: ["*/aid-fsm.sh"]
YAML
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$status" -eq 0 ]
  run jq -r '.profile' "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  [ "$output" == "null" ]
  aid_fixture_seed_step_review "$TEST_EVIDENCE_DIR" cp3 "" pass
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_profile_unresolvable"* ]]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "GATES" ]

  # The same run, recorded under the resolved profile, passes the floor.
  run "$RUN_GATES" run-all "$exec_yaml" "E-X" "R-1" \
    --report-file "$TEST_EVIDENCE_DIR/gates/gates_report.json" --profile standard
  [ "$status" -eq 0 ]
  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "DONE" ]
}
