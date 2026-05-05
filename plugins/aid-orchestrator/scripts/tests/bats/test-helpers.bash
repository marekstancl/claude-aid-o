#!/usr/bin/env bash
# Shared bats helpers for the P032 Session A test suite.
# Loaded via `load test-helpers.bash` from each .bats file.

# setup_test_evidence_dir [epic_id] [run_id]
#   Creates a fresh TEST_TMPDIR with:
#     - $TEST_PROJECT_ROOT  (cd-ed into)
#     - git init + initial commit on main (so PRE-FLIGHT git checks succeed)
#     - $TEST_EVIDENCE_DIR  = .aid-o/work/evidence/<epic_id>/<run_id>/
#   Defaults: epic_id=E-test, run_id=R-test.
setup_test_evidence_dir() {
  local epic_id="${1:-E-test}"
  local run_id="${2:-R-test}"
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  export TEST_PROJECT_ROOT="$TEST_TMPDIR/project"
  export TEST_EVIDENCE_DIR="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}"
  mkdir -p "$TEST_EVIDENCE_DIR"
  cd "$TEST_PROJECT_ROOT"
  git init -q -b main 2>/dev/null || git init -q
  git config user.email "test@test.local"
  git config user.name "Test"
  echo "init" > .gitkeep
  git add .gitkeep
  git commit -q -m "initial"
}

# teardown_test_evidence_dir
#   Cleans up TEST_TMPDIR after each test. Safe to call when setup wasn't run.
teardown_test_evidence_dir() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# build_default_init_args [epic_id]
#   PM-authorized C1 helper. Echoes the 7 positional args for cmd_init so
#   tests use the real signature instead of a parallel "test mode" code
#   path. Real signature in tests = no drift between test contract and
#   production caller contract (orchestrator, queue, /aid-run scripts).
#
#   run_id derived from $TEST_EVIDENCE_DIR's basename so the FSM's internally-
#   computed evidence path (.aid-o/work/evidence/<epic>/<run>) matches the
#   directory the test setup actually created.
build_default_init_args() {
  local epic_id="${1:-E-test}"
  local run_id state_file
  if [[ "$epic_id" == "E-test" ]]; then
    run_id=$(basename "$TEST_EVIDENCE_DIR")
    state_file="$TEST_EVIDENCE_DIR/state.yaml"
  else
    run_id="R-${epic_id#E-}-test"
    state_file="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}/state.yaml"
    mkdir -p "$(dirname "$state_file")"
  fi
  echo "$epic_id $run_id 3 manual main HEAD $state_file"
}

# mock_git_worktree
#   Creates a REAL git worktree (not just env mocking) so all git commands
#   inside it behave as in production. cd's into the worktree and updates
#   TEST_EVIDENCE_DIR to live there. is_worktree() then returns true because
#   git_dir genuinely points under .git/worktrees/.
mock_git_worktree() {
  local wt_dir="$TEST_TMPDIR/wt"
  git worktree add -q "$wt_dir" -b wt-test-branch
  cd "$wt_dir"
  export TEST_EVIDENCE_DIR="$wt_dir/.aid-o/work/evidence/E-test/R-test"
  mkdir -p "$TEST_EVIDENCE_DIR"
}

# assert_timeline_event <timeline_file> <event_name>
#   Returns 0 if at least one line in the JSONL timeline has .event == event_name.
#   Uses `-se any(...)` instead of `select(...)` because jq 1.6's multi-input
#   exit code is inconsistent (returns 4 even when select matched).
assert_timeline_event() {
  local timeline=$1 expected_event=$2
  jq -se --arg ev "$expected_event" 'any(.[]; .event == $ev)' "$timeline" \
    | grep -q '^true$'
}

# write_post_deploy_state_yaml <state_file> [epic_id] [run_id] [branch]
#   Convenience: writes a complete READY/EXECUTE-state state.yaml suitable
#   for transition tests. branch defaults to task/<epic_id>/main.
write_post_deploy_state_yaml() {
  local state_file=$1
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
total_steps: 3
mode: manual
branch: $branch
base_commit: HEAD
gate_retries: 0
escalation_count: 0
started_at: "$now"
created_at: $now
EOF
}
