#!/usr/bin/env bats
# test-alloc-lock.bats — P074 Step 3: locked plan-ID/EPIC-ID allocation
# (`aid-fsm.sh alloc plan-id` / `alloc epic-id`).
#
# THE GROUNDED FAILURE MODE UNDER TEST: counter.yaml was the last unprotected
# shared file in the state layer — no script wrote it; the agent was told to
# read-increment-write it with no lock, so two concurrent sessions could mint
# the same ID. The allocator serializes allocation through the
# `counter.yaml.lock` sidecar (lib/aid-lock.sh, 5s timeout, fail closed) and
# rewrites ONLY the digits on the matching counter line (mktemp + mv), so
# every comment byte survives.
#
# FD-3 HYGIENE: bats reports test results over fd 3; a spawned child that
# inherits and holds that fd open silently truncates the suite's TAP output.
# Every heavyweight invocation below runs with `3>&-`. After any edit to this
# file, verify the full result count:
#   bats --tap test-alloc-lock.bats | grep -cE '^(ok|not ok)'   # == plan count (currently 11)

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPTS="$AID_PLUGIN_PATH/scripts"
  FSM="$SCRIPTS/aid-fsm.sh"
  LOCKLIB="$SCRIPTS/lib/aid-lock.sh"
  export SCRIPTS FSM LOCKLIB
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  unset AID_PROJECT_ROOT
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# _mk_repo <dir> — a committed git repo with a realistic counter.yaml carrying
# a header comment block, a long trailing annotation on the plan: line, and a
# continuation comment line under epic: (the live repo's exact shape).
_mk_repo() {
  local d="$1"
  mkdir -p "$d/.aid-o/config"
  cat > "$d/.aid-o/config/counter.yaml" <<'EOF'
# AID Orchestrator — Autoincrement ID Counters
# This file tracks the last-assigned sequential ID for each entity type.

plan: 74      # Last assigned plan number. Next: P075 (long historical annotation stays untouched)
epic: 0       # Last assigned ad-hoc EPIC number. Next: E-001
                # Note: continuation comment line survives byte-identically
EOF
  printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed"
  )
}

# _norm_counter <file> — the counter file with ONLY the counter digits blanked;
# everything else (all comment bytes, spacing) must compare byte-identical.
_norm_counter() {
  sed -E 's/^(plan:[[:space:]]*)[0-9]+/\1N/; s/^(epic:[[:space:]]*)[0-9]+/\1N/' "$1"
}

@test "alloc plan-id: increments the plan counter and prints ONLY the new ID on stdout" {
  _mk_repo "$TEST_TMPDIR/repo"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "P075" ]
  grep -q '^plan: 75' "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
}

@test "alloc epic-id: increments the epic counter and prints E-<NNN>" {
  _mk_repo "$TEST_TMPDIR/repo"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc epic-id" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "E-001" ]
  grep -q '^epic: 1' "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
}

@test "20 PARALLEL alloc plan-id invocations yield 20 distinct sequential IDs (no duplicates, no gaps)" {
  _mk_repo "$TEST_TMPDIR/repo"
  cd "$TEST_TMPDIR/repo"
  local i
  for i in $(seq 1 20); do
    bash "$FSM" alloc plan-id > "$TEST_TMPDIR/out.$i" 2>"$TEST_TMPDIR/err.$i" 3>&- &
  done
  wait
  # 20 unique IDs...
  [ "$(cat "$TEST_TMPDIR"/out.* | sort -u | wc -l)" -eq 20 ]
  # ...that are exactly the sequential run P075..P094 (no gaps, no repeats).
  local expected
  expected="$(for i in $(seq 75 94); do printf 'P%03d\n' "$i"; done)"
  [ "$(cat "$TEST_TMPDIR"/out.* | sort)" = "$expected" ]
  # The counter landed on exactly start+20.
  grep -q '^plan: 94' .aid-o/config/counter.yaml
  # And no allocation failed silently.
  [ "$(cat "$TEST_TMPDIR"/out.* | grep -c '^P')" -eq 20 ]
}

@test "comment lines in counter.yaml survive 20 allocations byte-identically (only the digits changed)" {
  _mk_repo "$TEST_TMPDIR/repo"
  cd "$TEST_TMPDIR/repo"
  _norm_counter .aid-o/config/counter.yaml > "$TEST_TMPDIR/before.norm"
  local i out
  for i in $(seq 1 20); do
    # Every allocation must SUCCEED and print an ID — otherwise the
    # before/after comparison would pass vacuously on 20 silent failures.
    out="$(bash "$FSM" alloc plan-id 2>/dev/null 3>&-)"
    [ "${out:0:1}" = "P" ]
  done
  _norm_counter .aid-o/config/counter.yaml > "$TEST_TMPDIR/after.norm"
  diff -u "$TEST_TMPDIR/before.norm" "$TEST_TMPDIR/after.norm"
}

@test "lock timeout: allocation fails closed naming the .lock path and the recorded holder" {
  _mk_repo "$TEST_TMPDIR/repo"
  local lock="$TEST_TMPDIR/repo/.aid-o/config/counter.yaml.lock"
  # A REAL separate process holds the sidecar for longer than the 5s budget.
  bash "$LOCKLIB" hold "$lock" 12 > "$TEST_TMPDIR/holder.out" 2>&1 3>&- &
  local holder_pid=$!
  # Wait until the holder reports the lock is genuinely held.
  local tries=0
  while ! grep -q '^HELD' "$TEST_TMPDIR/holder.out" 2>/dev/null; do
    sleep 0.1; tries=$((tries + 1)); [ "$tries" -lt 50 ]
  done
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  kill "$holder_pid" 2>/dev/null || true
  wait "$holder_pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"counter.yaml.lock"* ]]          # names the .lock path
  [[ "$output" == *"pid recorded in lock file:"* ]]  # aid-lock.sh names the recorded holder pid
  [[ "$output" == *"concurrent allocation likely holds it"* ]]  # allocator names the likely holder class
  # Fail closed: the counter value is untouched.
  grep -q '^plan: 74' "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  # Nothing was printed on stdout that looks like a minted ID.
  [[ "$output" != *"P075"* ]]
}

@test "missing counter.yaml: refuses with 'run /aid-init first' and never invents a counter file" {
  _mk_repo "$TEST_TMPDIR/repo"
  rm "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"run /aid-init first"* ]]
  [ ! -f "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml" ]
}

@test "non-integer counter value: fails closed naming the malformed line" {
  _mk_repo "$TEST_TMPDIR/repo"
  printf 'plan: seventy-four  # broken by hand\nepic: 0\n' \
    > "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed counter line"* ]]
  [[ "$output" == *"plan: seventy-four"* ]]   # the malformed line is named
}

@test "digits-prefixed garbage value (74not-an-integer): fails closed, file untouched" {
  _mk_repo "$TEST_TMPDIR/repo"
  printf 'plan: 74not-an-integer\nepic: 0\n' \
    > "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed counter line"* ]]
  [[ "$output" == *"74not-an-integer"* ]]
  # The file was never rewritten (no truncated 75not-an-integer).
  grep -q '^plan: 74not-an-integer$' "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
}

@test "integer followed by a trailing comment still allocates (comment is valid trailing content)" {
  _mk_repo "$TEST_TMPDIR/repo"
  printf 'plan: 7  # historical annotation\nepic: 0\n' \
    > "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "P008" ]
  grep -q '^plan: 8  # historical annotation$' "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
}

@test "missing plan: line entirely: fails closed pointing at /aid-init" {
  _mk_repo "$TEST_TMPDIR/repo"
  printf '# comments only, no counters\n' > "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"run /aid-init first"* ]]
}

@test "allocation from inside a linked worktree routes to the PRIMARY counter (no worktree fork)" {
  _mk_repo "$TEST_TMPDIR/primary"
  git -C "$TEST_TMPDIR/primary" worktree add -q "$TEST_TMPDIR/wt" -b p074/alloc-wt
  # Tripwire: a regular FILE named .aid-o at the worktree top level — any
  # attempt to mkdir a worktree-local workspace would fail on it.
  printf 'P074 tripwire\n' > "$TEST_TMPDIR/wt/.aid-o"
  chmod 444 "$TEST_TMPDIR/wt/.aid-o"
  run bash -c "cd '$TEST_TMPDIR/wt' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "P075" ]
  # The PRIMARY counter moved; the worktree carries no forked workspace.
  grep -q '^plan: 75' "$TEST_TMPDIR/primary/.aid-o/config/counter.yaml"
  [ -f "$TEST_TMPDIR/wt/.aid-o" ]
  [ ! -d "$TEST_TMPDIR/wt/.aid-o" ]
}

@test "P999 rollover: the allocator emits P1000 naturally (no three-digit assumption)" {
  _mk_repo "$TEST_TMPDIR/repo"
  printf 'plan: 999  # at the rollover\nepic: 0\n' \
    > "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
  run bash -c "cd '$TEST_TMPDIR/repo' && '$FSM' alloc plan-id" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "P1000" ]
  grep -q '^plan: 1000' "$TEST_TMPDIR/repo/.aid-o/config/counter.yaml"
}

@test "dispatcher usage text carries the literal 'alloc plan-id' (plan-level AC7 grep)" {
  run bash -c "'$FSM' definitely-not-a-subcommand" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"alloc plan-id"* ]]
  [[ "$output" == *"alloc epic-id"* ]]
}
