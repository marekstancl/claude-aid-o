#!/usr/bin/env bats
# aid-tier: t0
# test-gate-config-branch.bats — a gate's script is the BRANCH's script, and
# a branch that lacks one is told so by name (P087 Step 6, narrowed).
#
# What is NOT here, on purpose: gate CONFIGURATION from the branch. `.aid-o/`
# is gitignored, so execution.yaml never reaches a linked worktree, and
# reading executable configuration out of a working tree is what
# /ecosystem/specs/agent-hooks/ rule 3 forbids. Configuration stays at the
# state root (IMP-497's fix), and the registry row `gate_config_from_branch`
# records that half as not delivered. What IS delivered: the runner resolves
# every repo-relative script a gate command names in the tree it runs in, and
# a script missing there fails the gate with its name — never a quiet skip,
# never a fallback to the primary checkout's copy.
#
# FD-3 HYGIENE: every runner invocation runs with `3>&-`.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUNNER="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  TEST_TMPDIR="$(mktemp -d)"
  PRIMARY="$TEST_TMPDIR/primary"
  WT="$PRIMARY/.aid-worktrees/plan-P902"
  unset AID_PROJECT_ROOT AID_EXECUTION_LEDGER
  export AID_GATE_BASELINE_FILE="$TEST_TMPDIR/baseline.json"
  aid_test_mk_repo "$PRIMARY"
  mkdir -p "$PRIMARY/scripts"
  printf '#!/usr/bin/env bash\necho primary-copy\n' > "$PRIMARY/scripts/probe.sh"
  git -C "$PRIMARY" add -A; git -C "$PRIMARY" commit -q -m "probe on main"
  git -C "$PRIMARY" worktree add -q "$WT" -b plan/P902
  EV="$PRIMARY/.aid-o/work/evidence/E-902/R-1"
  mkdir -p "$EV/gates"
  printf '{"ts":"2026-08-25T00:00:00Z","event":"run_started"}\n' > "$EV/timeline.jsonl"
}
teardown() { cd /; rm -rf "$TEST_TMPDIR"; }

_config() {  # _config <command>
  cat > "$PRIMARY/.aid-o/config/execution.yaml" <<EOF
version: '1.0'
gates:
  probe:
    command: "$1"
    required: true
    timeout_seconds: 30
    max_retries: 0
EOF
}
_run() { bash -c "cd '$1' && exec bash '$RUNNER' run-all '$PRIMARY/.aid-o/config/execution.yaml' E-902 R-1" 3>&-; }

@test "gate-branch: AC16 (delivered half) — the script the gate runs is the branch's copy; configuration still comes from the state root" {
  printf '#!/usr/bin/env bash\necho branch-copy\n' > "$WT/scripts/probe.sh"
  git -C "$WT" commit -q -am "probe differs on the branch"
  _config "bash scripts/probe.sh | grep -q branch-copy"
  run _run "$WT"
  [ "$status" -eq 0 ]
  [ ! -e "$WT/.aid-o" ]
}

@test "gate-branch: AC17 — a script the configuration names but the branch lacks fails the gate BY NAME" {
  git -C "$WT" rm -q scripts/probe.sh; git -C "$WT" commit -q -m "branch dropped the probe"
  _config "bash scripts/probe.sh"
  run _run "$WT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"probe"* && "$output" == *"scripts/probe.sh"* && "$output" == *"not in the tree"* ]]
  grep -q 'gate_script_missing_in_tree' "$EV/timeline.jsonl"
}

@test "gate-branch: AC18 — there is no fallback to the primary checkout: its copy is not run when the branch has none" {
  git -C "$WT" rm -q scripts/probe.sh; git -C "$WT" commit -q -m "branch dropped the probe"
  _config "bash scripts/probe.sh > '$PRIMARY/ran.txt'"
  run _run "$WT"
  [ "$status" -ne 0 ]
  [ ! -e "$PRIMARY/ran.txt" ]
}

@test "gate-branch: a script that is only NAMED, not run, is not the branch's business — and one run after && is" {
  git -C "$WT" rm -q scripts/probe.sh; git -C "$WT" commit -q -m "branch dropped the probe"
  _config "echo scripts/probe.sh scripts/other.py"
  run _run "$WT"
  [ "$status" -eq 0 ]
  _config "true && scripts/probe.sh"
  run _run "$WT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/probe.sh"* ]]
}

@test "gate-branch: a run from the primary checkout behaves as before, and an absolute or {plugin_path} script is not the branch's business" {
  _config "bash scripts/probe.sh | grep -q primary-copy"
  run _run "$PRIMARY"
  [ "$status" -eq 0 ]
  _config "bash '$PRIMARY/scripts/probe.sh' >/dev/null"
  git -C "$WT" rm -q scripts/probe.sh; git -C "$WT" commit -q -m "branch dropped the probe"
  run _run "$WT"
  [ "$status" -eq 0 ]
}
