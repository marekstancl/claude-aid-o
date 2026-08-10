#!/usr/bin/env bats
# test-aid-obligations.bats — P079 Step 6 (IMP-476): a deferral that survives.
#
# THE LIVE FAILURE MODE UNDER TEST: the first P076 run deferred a
# release-blocking item into a `carried-obligations.md` the controller invented
# inside the plan WORKTREE's gitignored `.aid-o`. The worktree was torn down at
# close and the obligation went with it — and nothing would have read it
# anyway, because that file had no writer and no reader in the codebase.
#
# So both halves are asserted here: the record lands in the STATE root even
# when written from a worktree, and plan-close REFUSES while it is open.
#
# FD-3 HYGIENE: every plan-close-check invocation runs with `3>&-`. After any
# edit verify the result count:
#   bats --tap test-aid-obligations.bats | grep -cE '^(ok|not ok)'   # == 10

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-obligations.sh"
  CLOSE_CHECK="$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh"
  export LIB CLOSE_CHECK
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export TEST_TMPDIR ROOT
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT" "$ROOT/.aid-o/work/plan-state"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_journal() { printf '%s/.aid-o/work/plan-state/%s/carried-obligations.jsonl' "$ROOT" "$1"; }

# _lib <cwd> <shell code> — run library calls with a given working directory.
_lib() {
  local cwd="$1"; shift
  bash -c "cd '$cwd' && source '$LIB' && $*" 3>&-
}

# ─── the record survives the worktree ──────────────────────────────────────

@test "P079 Step 6: an obligation added FROM a worktree lands in the STATE root, not the worktree" {
  git -C "$ROOT" worktree add -q "$ROOT/.aid-worktrees/plan-P900" -b plan/P900

  run _lib "$ROOT/.aid-worktrees/plan-P900" \
    "aid_obligation_add P900 release_blocker 'IMP-999 must land before release' CP3"
  [ "$status" -eq 0 ]
  [ -f "$(_journal P900)" ]
  [ ! -e "$ROOT/.aid-worktrees/plan-P900/.aid-o" ]

  # And it survives the worktree being torn down — the P076 failure exactly.
  git -C "$ROOT" worktree remove --force "$ROOT/.aid-worktrees/plan-P900"
  run _lib "$ROOT" "aid_obligation_open P900"
  [ "$status" -eq 0 ]
  [[ "$output" == *"IMP-999 must land before release"* ]]
}

@test "P079 Step 6: with no resolvable state root the write is REFUSED, never redirected somewhere lossy" {
  run bash -c "cd '$TEST_TMPDIR' && source '$LIB' && aid_obligation_add P900 release_blocker 'x' ''" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"no durable place"* ]]
}

@test "P079 Step 6: an unknown severity and an empty text are refused" {
  run _lib "$ROOT" "aid_obligation_add P900 urgent 'x' ''"
  [ "$status" -ne 0 ]
  run _lib "$ROOT" "aid_obligation_add P900 release_blocker '   ' ''"
  [ "$status" -ne 0 ]
  [ ! -f "$(_journal P900)" ]
}

# ─── the journal folds correctly ───────────────────────────────────────────

@test "P079 Step 6: resolve closes exactly the obligation at its fold-time index" {
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'first' ''"
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'second' ''"
  run _lib "$ROOT" "aid_obligation_resolve P900 1 'fixed in step 4'"
  [ "$status" -eq 0 ]

  run _lib "$ROOT" "aid_obligation_open P900"
  [ "$status" -eq 0 ]
  [[ "$output" != *"first"* ]]
  [[ "$output" == *"second"* ]]
}

@test "P079 Step 6: a corrupt journal line fails CLOSED — never reported as 'nothing open'" {
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'real obligation' ''"
  printf 'this is not json\n' >> "$(_journal P900)"

  run _lib "$ROOT" "aid_obligation_open P900"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unreadable line"* ]]
}

@test "P079 Step 6: concurrent adds from two sessions both survive (append-only)" {
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'from session A' ''" &
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'from session B' ''" &
  wait

  run _lib "$ROOT" "aid_obligation_open P900"
  [ "$status" -eq 0 ]
  [[ "$output" == *"from session A"* ]]
  [[ "$output" == *"from session B"* ]]
}

# ─── the consumer refuses ──────────────────────────────────────────────────

@test "P079 Step 6: plan-close-check REFUSES while a release_blocker is open, naming it and both exits" {
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'the scheduler cap was never measured' CP3"

  run bash -c "cd '$ROOT' && exec bash '$CLOSE_CHECK' P900" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"the scheduler cap was never measured"* ]]
  [[ "$output" == *"obligation"* ]]
}

@test "P079 Step 6: resolving with a backlog IMP number unblocks the close check" {
  _lib "$ROOT" "aid_obligation_add P900 release_blocker 'the scheduler cap was never measured' CP3"
  _lib "$ROOT" "aid_obligation_resolve P900 1 'registered as IMP-500'"

  run bash -c "cd '$ROOT' && exec bash '$CLOSE_CHECK' P900" 3>&-
  [[ "$output" != *"the scheduler cap was never measured"* ]]
  [[ "$output" == *"PASS  [obligations]"* ]]
}

@test "P079 Step 6: a followup severity is recorded and never blocks the close check" {
  _lib "$ROOT" "aid_obligation_add P900 followup 'consider a nicer message' ''"

  run bash -c "cd '$ROOT' && exec bash '$CLOSE_CHECK' P900" 3>&-
  [[ "$output" == *"PASS  [obligations]"* ]]
  [[ "$output" != *"FAIL  [obligations]"* ]]
}

@test "P079 Step 6: an EMPTY journal file reads as 'nothing owed', not as 'unreadable'" {
  mkdir -p "$(dirname "$(_journal P900)")"
  : > "$(_journal P900)"

  run _lib "$ROOT" "aid_obligation_open P900"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c "cd '$ROOT' && exec bash '$CLOSE_CHECK' P900" 3>&-
  [[ "$output" == *"PASS  [obligations]"* ]]
}
