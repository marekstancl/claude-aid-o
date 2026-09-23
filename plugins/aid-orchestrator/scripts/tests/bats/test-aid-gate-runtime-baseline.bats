#!/usr/bin/env bats
# aid-tier: t1
# test-aid-gate-runtime-baseline.bats — P097 Step 5: `propose` arithmetic on a
# fixture history of gates_rows/<gate>.json files. The library never runs
# during a gate run and never writes; these cases prove the number it prints
# is the one the written rule gives by hand (2 × p95 of the last 20 measured
# durations, job_timeout rows excluded, rounded up to 30 s, 60–3 600 s), the
# bounds, the five-sample floor and the job_timeout exclusion.

setup() {
  export TZ=UTC
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LIB="$PLUGIN_ROOT/scripts/lib/aid-gate-runtime-baseline.sh"
  WORK="$(mktemp -d)"
  EVID="$WORK/.aid-o/work/evidence"
  N=0
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# row <gate> <duration_ms> [reason=exit_0] — one checkpointed row in its own
# run directory, newer than the previous one by `completed_at`.
row() {
  local gate="$1" ms="$2" reason="${3:-exit_0}"
  N=$((N + 1))
  local dir="$EVID/E-1/R-$(printf '%03d' "$N")/gates_rows"
  mkdir -p "$dir"
  local at; at="$(date -u -d "@$((1756684800 + N))" +%Y-%m-%dT%H:%M:%SZ)"
  jq -nc --arg g "$gate" --argjson ms "$ms" --arg r "$reason" --arg at "$at" \
    '{gate:$g, row_version:2, status:(if $r=="exit_0" then "pass" else "fail" end),
      reason:$r, exit_code:(if $r=="exit_0" then 0 elif $r=="job_timeout" then 124 else 1 end),
      duration_ms:$ms, started_at:null, completed_at:$at,
      evidence:null, required:true, waived:false, reused_from:null}' \
    > "$dir/${gate}.json"
}

@test "AC3: 20 durations 10 s..200 s -> p95 = 190 000 ms, 2 x p95 = 380 s, rounded up to 30 s = 390" {
  local i
  for i in $(seq 1 20); do row slow $((i * 10000)); done
  run bash "$LIB" propose "$EVID" slow
  [ "$status" -eq 0 ]
  [[ "$output" == "slow proposed_timeout_seconds=390 (p95 190000 ms over the last 20 measured durations, 0 job_timeout rows excluded)" ]]
}

@test "window: only the newest 20 measured durations count — 5 older huge rows are ignored" {
  local i
  for i in $(seq 1 5); do row slow 3000000; done
  for i in $(seq 1 20); do row slow $((i * 10000)); done
  run bash "$LIB" propose "$EVID" slow
  [ "$status" -eq 0 ]
  [[ "$output" == *"proposed_timeout_seconds=390 "* ]]
}

@test "bounds: 1 ms rows floor at 60 s; 50 min rows cap at 3600 s" {
  local i
  for i in $(seq 1 20); do row tiny 1; row huge 3000000; done
  run bash "$LIB" propose "$EVID" tiny
  [[ "$output" == *"proposed_timeout_seconds=60 "* ]]
  run bash "$LIB" propose "$EVID" huge
  [[ "$output" == *"proposed_timeout_seconds=3600 "* ]]
}

@test "fewer than five measured durations -> insufficient_history, exit 0, no number" {
  local i
  for i in $(seq 1 4); do row young 5000; done
  run bash "$LIB" propose "$EVID" young
  [ "$status" -eq 0 ]
  [[ "$output" == "young insufficient_history (4 measured durations, 5 needed, 0 job_timeout rows excluded)" ]]
  run bash "$LIB" propose "$EVID" never_ran
  [ "$status" -eq 0 ]
  [[ "$output" == "never_ran insufficient_history (0 measured durations, 5 needed, 0 job_timeout rows excluded)" ]]
}

@test "job_timeout rows are excluded from the measurement and counted: 3 timeouts among 8 rows -> 5 measured" {
  row flaky 20000
  row flaky 600000 job_timeout
  row flaky 20000
  row flaky 600000 job_timeout
  row flaky 20000
  row flaky 600000 job_timeout
  row flaky 20000
  row flaky 20000
  run bash "$LIB" propose "$EVID" flaky
  [ "$status" -eq 0 ]
  # p95 of five 20 000 ms rows = 20 000 -> 40 s -> rounded to 60 (the floor).
  [[ "$output" == "flaky proposed_timeout_seconds=60 (p95 20000 ms over the last 5 measured durations, 3 job_timeout rows excluded)" ]]
}

@test "propose never writes: the evidence tree is byte-identical before and after" {
  local i before after
  for i in $(seq 1 20); do row slow $((i * 10000)); done
  before="$(cd "$WORK" && find . -type f -exec sha256sum {} + | sort)"
  bash "$LIB" propose "$EVID" slow >/dev/null
  after="$(cd "$WORK" && find . -type f -exec sha256sum {} + | sort)"
  [ "$before" = "$after" ]
  [ ! -d "$WORK/.aid-o/metrics" ]
}

@test "usage: missing arguments exit 2; an unknown verb prints usage and exits 1" {
  run bash "$LIB" propose "$EVID"
  [ "$status" -eq 2 ]
  run bash "$LIB" update slow
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: aid-gate-runtime-baseline.sh propose"* ]]
}
