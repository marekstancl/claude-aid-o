#!/usr/bin/env bats
# P032 Step 7 — aid-fsm.sh PRE-FLIGHT branch enforcement (Step 2)
# + EXECUTE→GATES gates_report._generated_by precondition (Step 3) +
# grandfather behavior. P033 Step 9 adds CP2 verifier-output preconditions +
# force_override --reason enforcement. 14 assertions total.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  # Force post-deploy mode for the gate-enforcement assertions.
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
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

# ─── Step 3: EXECUTE→GATES precondition + grandfather (3 assertions) ─────

@test "EXECUTE→GATES: missing _generated_by (post-deploy) → hard fail" {
  # Post-deploy state.yaml + hand-written gates_report.json.
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{"overall":"pass","gates":{}}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing _generated_by" ]]
  [[ "$output" =~ "aid-run-gates.sh run-all" ]]
}

@test "EXECUTE→GATES: present _generated_by + CP3 outputs → accept" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  jq -n '{overall:"pass", gates:{}, _generated_by:"aid-run-gates.sh@v2.16.0", _generated_at:"2026-05-04T00:00:00Z", _command_log:[]}' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  # Session B CP3: both verifier-output-cp3-*.md required (file presence check)
  printf '_generated_by: aid-orchestrator:verifier@abc123\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  printf '_generated_by: aid-orchestrator:verifier@def456\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -eq 0 ]
}

@test "EXECUTE→GATES: pre-deploy grandfather (created_at < deploy_date) → accept regardless" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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

@test "increment-step: missing verifier-output-step-N.md (post-deploy) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # No verifier-output-step-3.md → CP2 precondition fails

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with verdict:pending (verifier not dispatched) → fail" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # Pre-filter wrote pending; verifier was NOT dispatched
  printf '_generated_by: aid-pre-filter.sh@v2.18.0\nclassification: RUN\nverdict: pending\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with classification:SKIP (docs diff) → accept" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # SKIP classification is valid without verdict (pre-filter wrote reason field instead)
  printf '_generated_by: aid-pre-filter.sh@v2.18.0\nclassification: SKIP\nreason: docs_only\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── P033 Step 9: force_override --reason enforcement (2 assertions) ─────────

@test "transition --force without --reason → die with examples" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"

  run "$FSM" transition EXECUTE GATES "$state_file" --force
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--reason" ]]
  [[ "$output" =~ "min 20 characters" ]]
}

@test "increment-step --force with short reason (< 20 chars) → die" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"

  run "$FSM" increment-step "$state_file" --force --reason "too short"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "min 20 characters" ]]
}

# ─── P035 Step 4: advance-to-gates atomicity (4 assertions) ──────────────

@test "advance-to-gates: success path EXECUTE→GATES via cmd_transition" {
  seed_test_state_files "EXECUTE" "5" "5"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
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
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
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

@test "advance-to-gates: missing CP3 outputs → cmd_transition fails after gates pass" {
  seed_test_state_files "EXECUTE" "5" "5"
  # NOTE: NO CP3 output files (intentional — gates run, transition rejects)
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  setup_passing_execution_yaml "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" advance-to-gates "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  [ "$status" -ne 0 ]
  # Gates ran independently of CP3 — runner exits 0
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "gate_runner_complete"
  # cmd_transition's check_preconditions sees missing CP3 outputs and rejects
  [[ "$output" == *"verifier-output-cp3-code-review.md missing"* ]]
  # State stayed EXECUTE because cmd_transition didn't commit
  [ "$(grep '^state:' "$TEST_EVIDENCE_DIR/fsm-state.yaml" | awk '{print $2}')" = "EXECUTE" ]
}

# ─── P040 Step 2: orphan dispatch reconciliation backstop (4 assertions) ─────

# Helper: seed the increment-step happy-path preconditions for step 3
# (valid step-3-verify.md + valid non-pending verifier-output-step-3.md).
_p040_seed_increment_preconditions() {
  local state_file="$1"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  printf '_generated_by: aid-orchestrator:verifier@abc123\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
}

@test "increment-step: clean/empty pending-dispatches → step advances" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  # Empty (size 0) pending file = all dispatches completed cleanly → skip.
  : > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
}

@test "increment-step: orphan start (no complete, past max) → step blocked + audit" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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

@test "increment-step: malformed pending-dispatches → fail loud + audit reason" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  _p040_seed_increment_preconditions "$state_file"
  printf '%s\n' 'this is not json {{{' > "$TEST_EVIDENCE_DIR/pending-dispatches.jsonl"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "pending-dispatches.jsonl is malformed" ]]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "3" ]
  grep -q '"reason":"pending_file_malformed"' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "increment-step: TZ=UTC orphan detection (tight 100s margin, past deadline) → blocked" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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

# ─── P040 Step 3: CP4 curator-validation enforcement (5 assertions) ──────────

# Helper: invoke fsm_check_cp4_curator_validation by sourcing aid-fsm.sh in a
# subshell with epic_id/run_id/project_root in scope (needed by
# fsm_emit_audit_log). Echoes exit code via `run`. Args: <evidence_dir> <project_root>.
_run_cp4_check() {
  local ev_dir="$1" proj_root="$2"
  run bash -c '
    set -euo pipefail
    source "'"$FSM"'"
    epic_id=E-test run_id=R-test project_root="'"$proj_root"'"
    fsm_check_cp4_curator_validation "'"$ev_dir"'" "'"$proj_root"'"
  '
}

# Helper: seed an fsm-state.yaml with a given base_commit under the evidence dir.
_cp4_seed_state() {
  local base="$1"
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<EOF
epic_id: E-test
run_id: R-test
state: DONE
base_commit: $base
EOF
}

@test "CP4: no curator-report → skip silently (no audit entry)" {
  # No curator-report.md present → function returns 0 without touching audit log.
  _cp4_seed_state "HEAD"
  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl" ] || \
    ! grep -q 'cp4_' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "CP4: curator + production touch + missing CP4 file → block + audit" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Commit a production-path file so base_commit..HEAD touches production.
  mkdir -p plugins/aid-orchestrator/skills
  echo "pipeline change" > plugins/aid-orchestrator/skills/pipeline.md
  git add plugins/aid-orchestrator/skills/pipeline.md
  git commit -q -m "prod change"
  _cp4_seed_state "$base"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CP4 (curator-validation) review missing"* ]]
  grep -q 'cp4_missing_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  grep -q '"base"' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  grep -q 'pipeline.md' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "CP4: curator + docs-only range → skip + non-blocking telemetry" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Only docs / CHANGELOG touched in range → no production match.
  mkdir -p docs
  echo "doc change" > docs/notes.md
  echo "changelog" > CHANGELOG.md
  git add docs/notes.md CHANGELOG.md
  git commit -q -m "docs only"
  _cp4_seed_state "$base"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  grep -q 'cp4_skip_no_prod_match' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "CP4: NR 10 §3B range-scan — production touch at HEAD~1, docs-only at HEAD → block" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # HEAD~1: production file (aid-fsm.sh under scripts/).
  mkdir -p plugins/aid-orchestrator/scripts
  echo "fsm change" > plugins/aid-orchestrator/scripts/aid-fsm.sh
  git add plugins/aid-orchestrator/scripts/aid-fsm.sh
  git commit -q -m "prod change at HEAD~1"
  # HEAD: docs-only commit (would pass a last-commit-only check).
  mkdir -p docs
  echo "changelog" > docs/CHANGELOG.md
  git add docs/CHANGELOG.md
  git commit -q -m "docs only at HEAD"
  _cp4_seed_state "$base"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CP4 (curator-validation) review missing"* ]]
  # Range scan caught the HEAD~1 production file despite docs-only last commit.
  grep -q 'aid-fsm.sh' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  grep -q 'cp4_missing_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "CP4: consumer layout (cp4_production_paths=apps/|services/|packages/) → block on apps/ touch" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Consumer-style execution.yaml overriding the production glob.
  mkdir -p .aid-o/config
  printf 'cp4_production_paths: "apps/|services/|packages/"\n' > .aid-o/config/execution.yaml
  mkdir -p apps
  echo "consumer prod" > apps/foo.ts
  git add apps/foo.ts
  git commit -q -m "consumer prod change"
  _cp4_seed_state "$base"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CP4 (curator-validation) review missing"* ]]
  grep -q 'apps/foo.ts' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "CP4 composer: apps/ monorepo layout → cp4_production_paths = apps/|services/|packages/|src/" {
  # Exercises resolve_cp4_production_paths via compose_execution_yaml.
  local composer="$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"
  local proj="$TEST_TMPDIR/consumer"
  mkdir -p "$proj/apps" "$proj/src"
  local out="$proj/.aid-o/config/execution.yaml"
  run bash -c '
    set -euo pipefail
    export AID_PLUGIN_PATH="'"$AID_PLUGIN_PATH"'"
    source "'"$composer"'"
    compose_execution_yaml "'"$proj"'" "'"$out"'" typescript
  '
  [ "$status" -eq 0 ]
  grep -q 'cp4_production_paths: "apps/|services/|packages/|src/"' "$out"
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
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  grep -q '^streamlined_mode: true$' "$state_file"
  # Heredoc shape preserved: unquoted/unindented epic_id parseable by grep parser.
  [ "$(grep '^epic_id:' "$state_file" | awk '{print $2}')" = "E-test" ]
}

@test "streamlined: skips per-step CP2 (missing verifier-output) → increment-step exit 0" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3, post-deploy
  echo "streamlined_mode: true" >> "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # NO verifier-output-step-3.md (would fail CP2 in full mode); streamlined skips.

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^current_step:' "$state_file" | awk '{print $2}')" = "4" ]
}

@test "streamlined: compliance.json emits coverage_mode + skipped_dimensions" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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
  jq -e '.skipped_dimensions == ["verifier_outputs.cp2_per_step","verifier_outputs.cp4_curator_validation"]' "$cj"
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

@test "streamlined: integration-review missing CP3 code-review blocks" {
  _streamlined_seed_state true
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _write_three_event_timeline
  # Only cp3-security + gates_report present; cp3-code-review absent.
  echo "sec" > "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  echo '{}' > "$TEST_EVIDENCE_DIR/gates_report.json"

  _run_streamlined_check fsm_check_streamlined_integration_review "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"verifier-output-cp3-code-review.md"* ]]
  grep -q 'streamlined_integration_review_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "streamlined: integration-review with all three files present passes" {
  _streamlined_seed_state true
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _write_three_event_timeline
  echo "code" > "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  echo "sec"  > "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  echo '{}'   > "$TEST_EVIDENCE_DIR/gates_report.json"

  _run_streamlined_check fsm_check_streamlined_integration_review "$TEST_EVIDENCE_DIR" "$state_file" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  # No integration-review-fail audit recorded.
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl" ] || \
    ! grep -q 'streamlined_integration_review_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "streamlined: CP4 mode-aware skip → advisory audit, no missing_cp4 fail" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Commit a production-path file so base..HEAD touches plugins/.
  mkdir -p plugins/aid-orchestrator/skills
  echo "pipeline change" > plugins/aid-orchestrator/skills/pipeline.md
  git add plugins/aid-orchestrator/skills/pipeline.md
  git commit -q -m "prod change"
  _streamlined_seed_state true "$base"
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # Integration-review files present (CP4 advisory short-circuit runs first anyway).
  echo "code" > "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  echo "sec"  > "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"
  echo '{}'   > "$TEST_EVIDENCE_DIR/gates_report.json"

  run bash -c '
    set -euo pipefail
    source "'"$FSM"'"
    epic_id=E-test run_id=R-test project_root="'"$TEST_PROJECT_ROOT"'"
    fsm_check_cp4_curator_validation "'"$TEST_EVIDENCE_DIR"'" "'"$TEST_PROJECT_ROOT"'" "'"$state_file"'"
  '
  [ "$status" -eq 0 ]
  grep -q 'cp4_skipped_streamlined_advisory' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  ! grep -q 'cp4_missing_fail' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

# ─── P040 Component E: steps[] array absorption + read_steps_array ────────

@test "Component E: cmd_init writes steps[] array of length total_steps with id:1..N" {
  # build_default_init_args passes total_steps=3.
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
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
