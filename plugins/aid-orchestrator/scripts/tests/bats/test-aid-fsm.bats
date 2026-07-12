#!/usr/bin/env bats
# P032 Step 7 — aid-fsm.sh PRE-FLIGHT branch enforcement (Step 2)
# + EXECUTE→GATES gates_report._generated_by precondition (Step 3) +
# grandfather behavior. P033 Step 9 adds CP2 verifier-output preconditions +
# force_override --reason enforcement. 14 assertions total.
# E-046-1_3 Step 6 adds: cross-plan E-→P gate (Step 1), _generated_at CP2/CP4
# enforcement (Step 2), CP5 blocking_findings four-case matrix (Step 3).

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
  unset C3_AUDIT_POLICY
  teardown_test_evidence_dir
}

# _pin_c3_blocking
#   E-059-1_2 Step 1: the C3 independent-audit hook is enforcement-gated —
#   c3-audit-policy.yaml ships `enforcement: observe` (staged wake), so by
#   default the hook emits c3_gate_would_block telemetry and lets the transition
#   through. Tests that assert the hook BLOCKS pin enforcement to `blocking` via
#   the C3_AUDIT_POLICY seam (mirrors DELIVERY_GATE_POLICY). The per-profile
#   c3_required risk-gate still reads the installed default policy.
_pin_c3_blocking() {
  local policy_file="$TEST_TMPDIR/c3-audit-policy-blocking.yaml"
  cat > "$policy_file" <<'YAML'
version: 1
enforcement: blocking
risk_profiles:
  high:
    c3_required: true
    required_independence_level: cross_model
  unverifiable:
    c3_required: true
    required_independence_level: cross_provider
YAML
  export C3_AUDIT_POLICY="$policy_file"
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
  # Session B CP3: both verifier-output-cp3-*.md required (file presence check).
  # _generated_at required since E-046-1_3 Step 2.
  printf '_generated_by: aid-orchestrator:verifier@abc123\n_generated_at: 2026-06-18T10:00:00Z\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  printf '_generated_by: aid-orchestrator:verifier@def456\n_generated_at: 2026-06-18T10:01:00Z\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"

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

@test "increment-step: missing verifier-output-step-N.md (post-deploy) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # No verifier-output-step-3.md → CP2 precondition fails

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with verdict:pending (verifier not dispatched) → fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
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
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # SKIP classification is valid without verdict (pre-filter wrote reason field instead).
  # _generated_at required since E-046-1_3 Step 2.
  printf '_generated_by: aid-pre-filter.sh@v2.18.0\n_generated_at: 2026-06-18T10:00:00Z\nclassification: SKIP\nreason: docs_only\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── AID-052: frontend Visual Anchoring precondition (E161) ──────────────────

# Helper: 4-step plan.json where steps[3] is a frontend step carrying visual_refs.
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
  # _generated_at required since E-046-1_3 Step 2.
  printf '_generated_by: aid-orchestrator:verifier@abc123\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"
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

@test "CP4: malformed glob ERE (curator + prod touch + bad glob) → fail-closed with audit" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Malformed ERE glob: unmatched paren
  mkdir -p .aid-o/config
  printf 'cp4_production_paths: "plugins/|scripts/(foo"\n' > .aid-o/config/execution.yaml
  # Commit a production-path file so the range would match if the glob were valid
  mkdir -p plugins/aid-orchestrator/skills
  echo "prod change" > plugins/aid-orchestrator/skills/pipeline.md
  git add plugins/aid-orchestrator/skills/pipeline.md
  git commit -q -m "prod change"
  _cp4_seed_state "$base"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cp4_production_paths is not a valid ERE"* ]]
  [[ "$output" == *"Glob: plugins/|scripts/(foo"* ]]
  grep -q 'cp4_glob_invalid' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  grep -q 'cp4_production_paths_invalid_ere' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
}

@test "CP4: malformed glob ERE + streamlined mode (advisory) → streamlined skip happens first" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Malformed ERE glob: unmatched paren
  mkdir -p .aid-o/config
  printf 'cp4_production_paths: "plugins/|scripts/(bad"\n' > .aid-o/config/execution.yaml
  # Commit a production-path file
  mkdir -p plugins/aid-orchestrator/skills
  echo "prod change" > plugins/aid-orchestrator/skills/pipeline.md
  git add plugins/aid-orchestrator/skills/pipeline.md
  git commit -q -m "prod change"
  # Streamlined mode: CP4 is advisory, should skip before glob check
  _streamlined_seed_state "true" "$base"
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"

  run bash -c '
    set -euo pipefail
    source "'"$FSM"'"
    epic_id=E-test run_id=R-test project_root="'"$TEST_PROJECT_ROOT"'"
    fsm_check_cp4_curator_validation "'"$TEST_EVIDENCE_DIR"'" "'"$TEST_PROJECT_ROOT"'" "'"$state_file"'"
  '
  [ "$status" -eq 0 ]
  grep -q 'cp4_skipped_streamlined_advisory' "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
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

# ─── E-046-1_3 Step 1: Cross-plan E-→P gate (4 assertions) ──────────────────
# Regression for the `grep -oP '^P\d+'` dead pattern that never matched E-NNN
# IDs → cross-plan gate silently skipped. Fixed by BASH_REMATCH[1] pattern.

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

@test "cross-plan gate: E-045 done+audit → blocks E-046 init without ca-review-complete" {
  _seed_done_epic "E-045-1_3" "R-E045-1"
  # No ca-review-complete → gate must block
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -ne 0 ]
  [[ "$output" == *"P045 has unreviewed"* ]]
}

@test "cross-plan gate: E-045 done+audit+ca-review-complete → E-046 init succeeds" {
  _seed_done_epic "E-045-1_3" "R-E045-1"
  touch "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-045-1_3/R-E045-1/ca-review-complete"
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -eq 0 ]
}

@test "cross-plan gate: same-plan E-046 sibling done+audit → no cross-plan block" {
  # E-046-1_2 done (same P046) → init E-046-1_3 must succeed without ca-review-complete
  _seed_done_epic "E-046-1_2" "R-E046-2"
  run "$FSM" init $(build_default_init_args "E-046-1_3")
  [ "$status" -eq 0 ]
}

@test "cross-plan gate: done EPIC without audit-report → gate skips (no block)" {
  # done_phase: review but no audit-report.md → gate condition not triggered
  _seed_done_epic "E-045-1_3" "R-E045-1" "false"
  run "$FSM" init $(build_default_init_args "E-046-1_1")
  [ "$status" -eq 0 ]
}

# ─── E-046-1_3 Step 2: _generated_at required in CP2 verifier output ─────────
# Regression for the missing check: empty/absent _generated_at was accepted before.

@test "increment-step: verifier-output missing _generated_at → hard fail (post-deploy)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # Valid except no _generated_at line
  printf '_generated_by: aid-orchestrator:verifier@CP2-step3-epic1\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with empty _generated_at: (blank value) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # _generated_at key present but value is empty string (yaml_field returns "")
  printf '_generated_by: aid-orchestrator:verifier@CP2-step3-epic1\n_generated_at: \nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with valid _generated_at timestamp → accept" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  printf '_generated_by: aid-orchestrator:verifier@CP2-step3-epic1\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── E-046-1_3 Step 2: CP4 content-validation (2 assertions) ────────────────
# Regression for content-blind CP4 route: file existed but was not content-validated.

@test "CP4: curator-validation file present but missing _generated_at → hard fail (content-validation)" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  # Commit a production-path file
  mkdir -p plugins/aid-orchestrator/skills
  echo "change" > plugins/aid-orchestrator/skills/pipeline.md
  git add plugins/aid-orchestrator/skills/pipeline.md
  git commit -q -m "prod change"
  _cp4_seed_state "$base"
  # CP4 file present but missing _generated_at (would have passed before Step 2)
  printf '_generated_by: aid-orchestrator:verifier@CP4-curator-epic1\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp4-curator-validation.md"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "CP4: curator-validation file with empty _generated_by → hard fail (content-validation)" {
  local base; base=$(git rev-parse HEAD)
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"
  mkdir -p plugins/aid-orchestrator/skills
  echo "change" > plugins/aid-orchestrator/skills/pipeline.md
  git add plugins/aid-orchestrator/skills/pipeline.md
  git commit -q -m "prod change"
  _cp4_seed_state "$base"
  # _generated_by present but empty value
  printf '_generated_by: \n_generated_at: 2026-06-18T10:00:00Z\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp4-curator-validation.md"

  _run_cp4_check "$TEST_EVIDENCE_DIR" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

# ─── E-046-1_3 post-audit: yaml_field quote normalization + verdict whitelist ─
# Regression for auditor finding: _generated_by: "" passed as non-empty (quoted
# empty is non-empty string before quote-stripping fix), and verdict: banana
# passed because only "pending" and empty were rejected.

@test "verifier-output: _generated_by: \"\" (quoted empty) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  printf '_generated_by: ""\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
}

@test "verifier-output: _generated_at: '' (single-quoted empty) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  printf "_generated_by: aid-orchestrator:verifier@test\n_generated_at: ''\nclassification: RUN\nverdict: pass\n" \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
}

@test "verifier-output: verdict: banana (invalid scalar) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  write_post_deploy_state_yaml "$state_file"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  printf '_generated_by: aid-orchestrator:verifier@test\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: banana\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
}

# ─── E-046-1_3 post-audit: blocking_findings fail-closed on non-false values ──
# Auditor finding: only exact "true" was blocked; "maybe", "\"true\"", comments
# all passed silently as clean. Fix: accept ONLY scalar "false", block everything else.

# Helper: seed minimal DONE/review state for done-advance tests that need
# curator-report + audit-report to vary per test.
_seed_done_review_state() {
  local state_file="$1"
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
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/tasks" "$TEST_PROJECT_ROOT/.aid-o/work" \
           "$TEST_PROJECT_ROOT/.aid-o/config"
  touch "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-06-18T00:00:00Z","_command_log":[]}\n' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$AID_PLUGIN_PATH"
dispatch_mode: subagent
YAML
}

@test "CP5: blocking_findings: maybe → fail-closed (non-false treated as blocking)" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  printf 'blocking_findings: maybe\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings"* ]]
}

@test "CP5: blocking_findings: \"true\" (quoted) → fail-closed after yaml_field unquoting" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  printf 'blocking_findings: "true"\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings"* ]]
}

@test "D0 gate point: advance-to-gates logs d0_delivery_gate event (observe, non-blocking)" {
  local td; td="$(mktemp -d)"
  mkdir -p "$td/.aid-o/work/evidence/E-D0/R-D0T/gates"
  cat > "$td/.aid-o/work/evidence/E-D0/R-D0T/fsm-state.yaml" <<'EOF'
epic_id: E-D0
run_id: R-D0T
state: EXECUTE
current_step: 1
total_steps: 1
base_commit: HEAD
branch: integration/gui-control-v2
streamlined_mode: false
EOF
  cat > "$td/.aid-o/work/evidence/E-D0/R-D0T/timeline.jsonl" <<'EOF'
{"ts":"2026-06-23T00:00:00Z","event":"run_started"}
EOF
  mkdir -p "$td/.aid-o/config"
  cat > "$td/.aid-o/config/execution.yaml" <<'EOF'
version: '1.0'
gates:
  smoke:
    command: "echo 'smoke'"
    required: true
    timeout_seconds: 10
    max_retries: 0
EOF
  # Also need CP3 verifier outputs for EXECUTE→GATES precondition
  local ev="$td/.aid-o/work/evidence/E-D0/R-D0T"
  printf '_generated_by: aid-orchestrator:verifier\n_generated_at: 2026-01-01T00:00:00Z\nclassification: RUN\nverdict: pass\n' > "$ev/verifier-output-cp3-code-review.md"
  printf '_generated_by: aid-orchestrator:verifier\n_generated_at: 2026-01-01T00:00:00Z\nclassification: RUN\nverdict: pass\n' > "$ev/verifier-output-cp3-security.md"

  # cmd_transition reads evidence_dir as relative ".aid-o/..." so CWD must be $td
  AID_PROJECT_ROOT="$td" run bash -c "cd '$td' && bash '$FSM' advance-to-gates '$ev/fsm-state.yaml'"
  [ "$status" -eq 0 ]
  grep -q "d0_delivery_gate" "$ev/timeline.jsonl"
  rm -rf "$td"
}

# ─── E5 C2 Semantic Wiring-Gate (observe mode) ───────────────────────────────

@test "E5 wiring-gate observe: Critical finding logged but increment proceeds" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  # write_post_deploy_state_yaml creates state with current_step=3; total_steps=3
  write_post_deploy_state_yaml "$state_file"

  # CP2 preconditions: step-3-verify.md + verifier-output-step-3.md (valid, non-pending)
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  write_valid_verifier_output "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

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

# ─── E-057-1_2 Finding 3: C3 risk-profile-resolution hook regression suite ───
# Tests for done-advance review→release C3 precondition gate. Three scenarios:
# 1. risk_profile=high + AID_PLUGIN_PATH set + blocking audit → hook fires, blocks
# 2. risk_profile=high + policy missing high key + blocking audit → hook fires, blocks (Finding 1 fix: yq has() catches absence)
# 3. risk_profile=medium (non-C3) + no audit-report → hook no-op, passes (true-negative control)

@test "E-057-1_2 C3 hook: risk_profile=high + blocking audit-report → precondition fails" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  _pin_c3_blocking   # E-059-1_2: hook is observe-by-default; pin blocking to assert the block

  # Create review-profile.json with high-risk profile
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{
  "review_profile": {
    "risk_profile": "high"
  }
}
JSON

  # Create audit-report.json with blocking finding (matches c3_hook_fired=true condition)
  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<'JSON'
{
  "audit_report": {
    "blocking_findings": true,
    "input_manifest_hash": "sha256:abc123"
  },
  "status": "pass",
  "revision": {
    "head_sha": "deadbeef"
  }
}
JSON

  # Set AID_PLUGIN_PATH so the hook can locate c3-audit-policy.yaml
  export AID_PLUGIN_PATH

  # Mock current HEAD to match the audit's head_sha (otherwise stale-check fails first)
  GIT_AUTHOR_DATE='2026-06-18 00:00:00' git commit --allow-empty --amend -m "test" >/dev/null 2>&1 || true

  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"blocking_findings == true"* ]]
}

@test "E-057-1_2 C3 hook: has() presence-check prevents false-pass on absent profile key" {
  # Finding 1 fix: yq has() confirms both .risk_profiles[profile] AND .c3_required exist
  # before treating policy read as succeeded. If either is absent, fail-closed (hook fires).
  # This test verifies the has() logic via direct yq call (unit-level verification).
  local test_policy_good="$TEST_EVIDENCE_DIR/policy-good.yaml"
  local test_policy_missing_high="$TEST_EVIDENCE_DIR/policy-no-high.yaml"

  # Policy file WITH "high" key (normal case)
  cat > "$test_policy_good" <<'YAML'
version: 1
risk_profiles:
  high:
    c3_required: true
    required_independence_level: cross_model
  medium:
    c3_required: false
YAML

  # Policy file WITHOUT "high" key (corruption scenario)
  cat > "$test_policy_missing_high" <<'YAML'
version: 1
risk_profiles:
  medium:
    c3_required: false
YAML

  # Verify: has() works on good policy
  local has_high_good
  has_high_good=$(yq -r '(.risk_profiles | has("high")) and (.risk_profiles["high"] | has("c3_required"))' "$test_policy_good" 2>/dev/null)
  [ "$has_high_good" == "true" ]

  # Verify: has() returns false on corrupted policy (key absent)
  local has_high_bad
  has_high_bad=$(yq -r '(.risk_profiles | has("high")) and (.risk_profiles["high"] | has("c3_required"))' "$test_policy_missing_high" 2>/dev/null)
  [ "$has_high_bad" == "false" ]

  rm -f "$test_policy_good" "$test_policy_missing_high"
}

@test "E-057-1_2 C3 hook: risk_profile=medium (non-C3) + no audit-report → hook no-op, precondition passes" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"

  # Create review-profile.json with medium profile (NOT a C3-required profile)
  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{
  "review_profile": {
    "risk_profile": "medium"
  }
}
JSON

  # Do NOT create audit-report.json (medium profile doesn't require C3 audit)
  # This tests that the hook is a no-op for non-C3 profiles

  # Create a legacy audit-report.md (empty blocking_findings) to fall through to legacy path
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"
  echo "curator report" > "$TEST_EVIDENCE_DIR/curator-report.md"

  export AID_PLUGIN_PATH
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  # Should NOT see C3 block reason in output
  [[ "$output" != *"C3 independent audit block"* ]]
}

@test "E-057-1_2 C3 hook: malformed policy YAML fails closed (no script crash) instead of bypassing" {
  # CP4 round 2 regression: bare `var=$(yq ...)` under set -e aborted the WHOLE script
  # when c3-audit-policy.yaml was unparseable, skipping the structured PRECONDITION FAIL
  # message and the ERROR summary entirely (though the script's own nonzero exit still
  # prevented the transition from completing — not a bypass, but an unhandled crash
  # instead of a clean, audited fail-closed message). This test locks the fix: a
  # malformed policy file for a high-risk profile must still emit the C3 block message.
  # E-059-1_2: the malformed policy exercises the RISK-GATE (fail-closed → hook fires);
  # the enforcement toggle is pinned blocking via C3_AUDIT_POLICY so the block asserts.
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  _pin_c3_blocking

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{
  "review_profile": {
    "risk_profile": "high"
  }
}
JSON

  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<'JSON'
{
  "audit_report": {
    "blocking_findings": true,
    "input_manifest_hash": "sha256:abc123"
  },
  "status": "pass",
  "revision": {
    "head_sha": "deadbeef"
  }
}
JSON

  GIT_AUTHOR_DATE='2026-06-18 00:00:00' git commit --allow-empty --amend -m "test" >/dev/null 2>&1 || true

  # Point AID_PLUGIN_PATH at a fake plugin root whose c3-audit-policy.yaml is syntactically
  # broken (missing colon after the risk-profile key) — yq must fail to parse it, and the
  # done-advance call must NOT crash the whole script as a result.
  local fake_plugin_root="$TEST_EVIDENCE_DIR/fake-plugin-root"
  mkdir -p "$fake_plugin_root/defaults/policies"
  printf 'risk_profiles:\n  high\n    c3_required: true\n' > "$fake_plugin_root/defaults/policies/c3-audit-policy.yaml"

  AID_PLUGIN_PATH="$fake_plugin_root"
  export AID_PLUGIN_PATH
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"blocking_findings == true"* ]]
  [[ "$output" == *"precondition(s) failed"* ]]
}

@test "E-057-1_2 C3 hook: non-object .audit_report in valid JSON fails closed (no script crash)" {
  # CP4 round 3 finding: audit-report.json can be well-formed JSON at the top level while
  # .audit_report itself is a scalar/string instead of an object — jq errors trying to index
  # into it (.audit_report.blocking_findings), which under set -e aborted the whole script
  # before any of the 4 field-extraction jq calls' fail-closed logic could run. This test
  # locks the guard added to all 4 reads (c3_blocking/c3_status/c3_manifest_hash/c3_head_sha).
  # E-059-1_2: pin enforcement blocking so the fail-closed reason actually blocks.
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_done_review_state "$state_file"
  _pin_c3_blocking

  cat > "$TEST_EVIDENCE_DIR/review-profile.json" <<'JSON'
{
  "review_profile": {
    "risk_profile": "high"
  }
}
JSON

  # .audit_report is a STRING, not an object — jq's `.audit_report.blocking_findings`
  # errors ("Cannot index string with string") when read directly.
  cat > "$TEST_EVIDENCE_DIR/audit-report.json" <<'JSON'
{
  "audit_report": "oops-not-an-object",
  "status": "pass",
  "revision": {
    "head_sha": "deadbeef"
  }
}
JSON

  GIT_AUTHOR_DATE='2026-06-18 00:00:00' git commit --allow-empty --amend -m "test" >/dev/null 2>&1 || true

  export AID_PLUGIN_PATH
  run "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"C3 independent audit block"* ]]
  [[ "$output" == *"precondition(s) failed"* ]]
}

# ─── OBS-20260708-04: increment-step syncs steps[] array (4 assertions) ──────
# fsm_init's header comment declares steps[] "single source of truth", but
# cmd_increment_step historically only ever bumped the current_step scalar —
# steps[] entries stayed status: pending forever, even on fully DONE runs
# (VULCAN B-142 ×2, AID's own E-059-2_2 self-dogfood run; live-repro anchor:
# E-061-2_6/R-E061-2/fsm-state.yaml, both steps pending post-merge).

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
# (valid step-N-verify.md + valid non-pending verifier-output-step-N.md).
_obs20260708_seed_cp2() {
  local step="$1"
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-${step}-verify.md" "$step"
  printf '_generated_by: aid-orchestrator:verifier@abc123\n_generated_at: 2026-06-18T10:00:00Z\nclassification: RUN\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-${step}.md"
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
