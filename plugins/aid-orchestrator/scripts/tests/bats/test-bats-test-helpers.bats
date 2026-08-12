#!/usr/bin/env bats
# aid-tier: t0
# test-bats-test-helpers.bats — the shared bats helpers assert what they claim.
#
# WHY THIS SUITE EXISTS
#   `refute_grep` was introduced because ~90 `! grep` lines across the portfolio
#   asserted nothing (bash exempts a `!`-inverted command from `set -e` and from
#   bats' ERR trap). Its first cut then repeated the defect in a new shape: it
#   scored EVERY nonzero grep status as a refutation, so a missing file, an
#   unreadable file or a bad option — grep's status 2 — passed as "the pattern
#   is not there". A negative assertion nobody checks is exactly what the helper
#   exists to remove, so the helper itself gets checked here.
#
# Only status 1 (searched, no match) is a refutation. 0 is a match, anything
# else is an error, and both must fail the case.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
}

teardown() {
  teardown_test_evidence_dir
}

@test "refute_grep passes when the pattern is genuinely absent (grep status 1)" {
  printf 'hello world\n' > "$TEST_TMPDIR/f.txt"
  run refute_grep -qF 'secret' "$TEST_TMPDIR/f.txt"
  [ "$status" -eq 0 ]
}

@test "refute_grep called DIRECTLY (no run) does not fail the case on an absent pattern" {
  # How every real suite calls it. `run refute_grep …` shields the helper's
  # internals from bats' ERR trap, so a version whose capture was a bare
  # `out="$(grep …)"` passed under `run` and failed every direct caller the
  # moment the pattern was legitimately absent — grep's status 1 fired the trap
  # from inside the helper. This case is the direct-call shape.
  printf 'hello world\n' > "$TEST_TMPDIR/f.txt"
  refute_grep -qF 'secret' "$TEST_TMPDIR/f.txt"
  refute_grep -qF 'secret' "$TEST_TMPDIR/f.txt"
}

@test "refute_grep fails when the pattern MATCHES, and names what matched" {
  printf 'hello world\n' > "$TEST_TMPDIR/f.txt"
  run refute_grep -F 'hello' "$TEST_TMPDIR/f.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pattern MATCHED but must not"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "refute_grep FAILS on a missing file — grep status 2 refutes nothing" {
  # The regression: `if out="$(grep …)"` scored this 0, so every negative
  # assertion over a path that had moved, or was never written, passed silently.
  run refute_grep -q 'secret' "$TEST_TMPDIR/does-not-exist.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grep ERRORED (exit 2)"* ]]
  [[ "$output" == *"nothing was refuted"* ]]
}

@test "refute_grep FAILS on an unreadable file rather than reporting absence" {
  printf 'secret\n' > "$TEST_TMPDIR/locked.txt"
  chmod 000 "$TEST_TMPDIR/locked.txt"
  if [ -r "$TEST_TMPDIR/locked.txt" ]; then
    chmod 644 "$TEST_TMPDIR/locked.txt"
    skip "running as a user that ignores file permissions (root) — cannot make a file unreadable"
  fi
  run refute_grep -q 'secret' "$TEST_TMPDIR/locked.txt"
  chmod 644 "$TEST_TMPDIR/locked.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grep ERRORED"* ]]
}

@test "refute_grep FAILS on an invalid grep invocation rather than passing" {
  printf 'hello\n' > "$TEST_TMPDIR/f.txt"
  run refute_grep --no-such-option 'x' "$TEST_TMPDIR/f.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grep ERRORED"* ]]
}
