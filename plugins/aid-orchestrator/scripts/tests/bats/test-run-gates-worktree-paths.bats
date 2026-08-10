#!/usr/bin/env bats
# test-run-gates-worktree-paths.bats — P079 Step 2 (IMP-479): the gate runner
# resolves its own STATE paths through the state root.
#
# THE LIVE FAILURE MODE UNDER TEST: `.aid-o` exists only in the primary
# checkout. Every state path the runner built was cwd-relative, so a run
# driven from a linked worktree looked for evidence directories that were not
# there — and because the ledger, the row checkpoints and the ladder are all
# guarded by `[[ -d ... ]]`, they did not fail, they went QUIET. The run still
# reported a confident green.
#
# The split this suite pins: gate COMMANDS run in the invoking tree (the
# candidate), the runner's own STATE writes land at the state root. Both
# halves are asserted in the same scenario, because either one alone can be
# satisfied by a fix that breaks the other.
#
# FD-3 HYGIENE: every runner invocation runs with `3>&-` so no child can hold
# bats' report fd. After any edit verify the result count:
#   bats --tap test-run-gates-worktree-paths.bats | grep -cE '^(ok|not ok)'   # == 6

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUNNER="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  export RUNNER
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  PRIMARY="$TEST_TMPDIR/primary"
  WT="$TEST_TMPDIR/primary/.aid-worktrees/plan-P900"
  export PRIMARY WT
  unset AID_PROJECT_ROOT AID_EXECUTION_LEDGER
  # The baseline library's own isolation seam — without it the runner writes
  # gate runtime metrics into the fixture and the gitignore bootstrap touches
  # the fixture's git config. Both are out of scope here.
  export AID_GATE_BASELINE_FILE="$TEST_TMPDIR/baseline.json"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_phys() { (cd "$1" && pwd -P); }

# _mk_primary — committed checkout with the .aid-o skeleton, .aid-o gitignored
# exactly as a real AID project has it.
_mk_primary() {
  mkdir -p "$PRIMARY/.aid-o/config" "$PRIMARY/.aid-o/work/evidence"
  printf '.aid-o/\n.aid-worktrees/\n' > "$PRIMARY/.gitignore"
  printf 'seed\n' > "$PRIMARY/README.md"
  (
    cd "$PRIMARY"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed primary"
  )
}

# _mk_worktree — a linked worktree carrying a commit the primary does NOT have,
# so "which tree did the gate see" has an unambiguous answer.
_mk_worktree() {
  git -C "$PRIMARY" worktree add -q "$WT" -b plan/P900
  printf 'candidate work\n' > "$WT/candidate.txt"
  git -C "$WT" add candidate.txt
  git -C "$WT" commit -q -m "candidate commit only on the worktree branch"
}

# _mk_run <epic> <run> <gate_command> — evidence dir + execution.yaml, both at
# the PRIMARY root. Echoes the evidence dir.
_mk_run() {
  local epic="$1" run="$2" cmd="$3" ev="$PRIMARY/.aid-o/work/evidence/$1/$2"
  mkdir -p "$ev/gates"
  printf '{"ts":"2026-08-10T00:00:00Z","event":"run_started"}\n' > "$ev/timeline.jsonl"
  cat > "$PRIMARY/.aid-o/config/execution.yaml" <<EOF
version: '1.0'
gates:
  probe:
    command: "${cmd}"
    required: true
    timeout_seconds: 30
    max_retries: 0
EOF
  printf '%s' "$ev"
}

# _run_gates <cwd> <epic> <run> — run-all from <cwd>.
_run_gates() {
  bash -c "cd '$1' && exec bash '$RUNNER' run-all '$PRIMARY/.aid-o/config/execution.yaml' '$2' '$3'" 3>&-
}

# ─── the split: commands in the tree, state at the root ────────────────────

@test "P079 Step 2: a worktree-driven run writes its timeline, ledger and report path under the STATE root — none of them in the worktree" {
  _mk_primary
  _mk_worktree
  local ev
  ev="$(_mk_run E-900-1_1 R-1 "pwd -P > '$PRIMARY/gate-cwd.txt'")"

  run _run_gates "$WT" E-900-1_1 R-1
  [ "$status" -eq 0 ]

  # State artifacts: all at the primary root.
  [ -f "$ev/execution-ledger.json" ]
  grep -q 'gate_runner_start' "$ev/timeline.jsonl"
  grep -q 'gates_complete' "$ev/timeline.jsonl"
  # The default report path the runner announced is the state root's, not a
  # path relative to the worktree it was invoked from.
  [ "$(jq -r 'select(.event=="gate_runner_start") | .report_path' "$ev/timeline.jsonl")" \
    = "$ev/gates/gates_report.json" ]

  # And nowhere else: the worktree grew no second workspace.
  [ ! -e "$WT/.aid-o" ]

  # The command, by contrast, ran in the WORKTREE.
  [ "$(cat "$PRIMARY/gate-cwd.txt")" = "$(_phys "$WT")" ]
}

@test "P079 Step 2: the report's head_sha describes the WORKTREE HEAD (the candidate), not the state root's" {
  _mk_primary
  _mk_worktree
  local ev wt_head primary_head
  ev="$(_mk_run E-900-1_1 R-1 "true")"
  wt_head="$(git -C "$WT" rev-parse HEAD)"
  primary_head="$(git -C "$PRIMARY" rev-parse HEAD)"
  [ "$wt_head" != "$primary_head" ]

  run _run_gates "$WT" E-900-1_1 R-1
  [ "$status" -eq 0 ]
  # The report is this command's stdout contract.
  [ "$(jq -r '.revision.head_sha' <<<"$output")" = "$wt_head" ]
}

@test "P079 Step 2: a gate-scoped waiver is READ from the state root (a worktree run finds the file at all)" {
  _mk_primary
  _mk_worktree
  local ev
  ev="$(_mk_run E-900-1_1 R-1 "false")"
  # A waiver that will be REJECTED on validation is enough: the runner only
  # ever stamps `waiver_rejected` when it FOUND the file, so the key's presence
  # is proof of path resolution — and its absence is exactly the silent
  # behaviour this step fixes.
  mkdir -p "$ev/waivers"
  printf '{"gate":"probe","head":"deadbeef","command_sha":"deadbeef"}\n' \
    > "$ev/waivers/gate-waiver-probe.json"

  # A failing gate writes retry chatter to stderr, which bats merges into
  # `output` — so this one case reads the report from a file instead. The
  # waiver lookup this asserts resolves independently of the report path.
  run bash -c "cd '$WT' && exec bash '$RUNNER' run-all \
    '$PRIMARY/.aid-o/config/execution.yaml' E-900-1_1 R-1 \
    --report-file '$ev/gates/gates_report.json'" 3>&-
  [ "$status" -ne 0 ]                                   # required gate still fails
  [ -f "$ev/gates/gates_report.json" ]
  [ "$(jq -r '.gates.probe.result' "$ev/gates/gates_report.json")" = "fail" ]
  [ "$(jq -r '.gates.probe.waiver_rejected // "absent"' "$ev/gates/gates_report.json")" = "forged" ]
}

@test "P079 Step 2: gate-row checkpoints resolve too — the rows directory lands at the state root" {
  _mk_primary
  _mk_worktree
  local ev
  ev="$(_mk_run E-900-1_1 R-1 "true")"

  run _run_gates "$WT" E-900-1_1 R-1
  [ "$status" -eq 0 ]
  [ ! -e "$WT/.aid-o" ]
  # The row checkpoint actually persisted. Before this step the rows directory
  # resolved against the worktree, did not exist, and the `[[ -d ]]` guard
  # turned checkpointing into a silent no-op.
  [ -f "$ev/gates_rows/probe.json" ]
}

# ─── the fallback: fixtures outside any git repository ─────────────────────

@test "P079 Step 2: a bare fixture directory with no git repository still runs (historic cwd-relative fallback)" {
  local bare="$TEST_TMPDIR/bare"
  mkdir -p "$bare/.aid-o/config" "$bare/.aid-o/work/evidence/E-1/R-1/gates"
  cat > "$bare/.aid-o/config/execution.yaml" <<'EOF'
version: '1.0'
gates:
  probe:
    command: "true"
    required: true
    timeout_seconds: 30
    max_retries: 0
EOF
  run bash -c "cd '$bare' && exec bash '$RUNNER' run-all '.aid-o/config/execution.yaml' E-1 R-1" 3>&-
  [ "$status" -eq 0 ]
  [ "$(jq -r '.overall' <<<"$output")" = "pass" ]
  # The historic RELATIVE default is what a rootless fixture still gets.
  [ "$(jq -r 'select(.event=="gate_runner_start") | .report_path' \
       "$bare/.aid-o/work/evidence/E-1/R-1/timeline.jsonl")" \
    = ".aid-o/work/evidence/E-1/R-1/gates/gates_report.json" ]
}

# ─── guard grep: no unresolved state literal comes back ────────────────────

@test "P079 Step 2 guard grep: aid-run-gates.sh builds no unresolved .aid-o state path" {
  # Every `.aid-o/work` or `.aid-o/config` path construction must go through
  # the resolver helpers. Comments and operator-facing advice strings are not
  # path constructions.
  run bash -c "grep -n '\"\\.aid-o/\\(work\\|config\\)' '$AID_PLUGIN_PATH/scripts/aid-run-gates.sh' \
                 | grep -v '_gates_state_path'"
  if [ "$status" -eq 0 ]; then
    echo "unresolved state path(s):" >&2
    echo "$output" >&2
    false
  fi
}
