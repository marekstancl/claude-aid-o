#!/usr/bin/env bats
# test-aid-gate-runtime-report.bats — P063 Step 4: aid-gate-runtime-report.sh
# (Gate Runtime Baselines EPIC, final step).
#
# The CLI is a thin presentation layer over Step 1's library
# (aid-gate-runtime-baseline.sh) — it never re-derives percentile or
# formatting logic, only calls gate_baseline_show / gate_baseline_report_json
# and formats their output. These tests seed real baseline data through the
# real library (gate_baseline_update), then drive the CLI as a real
# subprocess (never sourced) so the --project-root + cd contract is actually
# exercised, not just assumed.
#
# Covers:
#   AC14 — --project-root + cd contract: running from an unrelated cwd with
#          --project-root produces the SAME output as running directly from
#          that project root.
#   Edge case 1 — --project-root points at a dir with no .aid-o/ at all ->
#                 clear error, exit non-zero.
#   Edge case 2 — no arguments, valid project root -> lists every gate with
#                 >=1 sample.
#   Edge case 3 — a gate with 0 non-censored samples (all timeouts) reports
#                 data-insufficient explicitly, never a value derived from
#                 the timeout samples (same rule as Step 1's AC4).
#   Error Handling — no baseline file yet / gate never run -> "no data yet"
#                    message, exit 0 (not an error).

load test-helpers.bash

setup() {
  export TZ=UTC
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT
  CLI="$PLUGIN_ROOT/scripts/aid-gate-runtime-report.sh"
  export CLI
  LIB="$PLUGIN_ROOT/scripts/lib/aid-gate-runtime-baseline.sh"
  export LIB
  WORK="$(mktemp -d)"
  export WORK
  mkdir -p "$WORK/.aid-o/metrics"
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# seed_gate <gate_name> <duration_ms> <exit_code> <timeout_seconds>
#   Writes one sample directly through the real library (never through the
#   CLI) at $WORK/.aid-o/metrics/gate-runtime-baselines.yaml — the exact path
#   the CLI resolves to after cd-ing into $WORK (library's own CWD-relative
#   default, no env override needed once the CLI has cd'd there).
seed_gate() {
  local gate_name="$1" duration_ms="$2" exit_code="${3:-0}" timeout_seconds="${4:-60}"
  (
    cd "$WORK" || exit 1
    # shellcheck disable=SC1090
    source "$LIB"
    gate_baseline_update "$gate_name" "tpl-${gate_name}" "resolved-${gate_name}" \
      "$exit_code" "$duration_ms" "$timeout_seconds"
  )
}

# ─── Edge case 1: no .aid-o/ at all -> clear error, exit non-zero ───────────

@test "edge case 1: --project-root with no .aid-o/ at all -> clear error, exit non-zero" {
  local empty_dir; empty_dir="$(mktemp -d)"
  run bash "$CLI" --project-root "$empty_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no .aid-o/ workspace"* ]] || [[ "$output" == *".aid-o"* ]]
  rm -rf "$empty_dir"
}

# ─── Error Handling: no baseline file yet -> "no data yet", exit 0 ──────────

@test "error handling: valid project root but no baseline file yet -> 'no data yet', exit 0" {
  run bash "$CLI" --project-root "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No gate runtime data yet"* ]]
}

@test "error handling: gate_name given but never run -> 'no data yet' style message, exit 0" {
  run bash "$CLI" --project-root "$WORK" nonexistent_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"nonexistent_gate"* ]]
  [[ "$output" == *"insufficient data"* ]]
}

# ─── Edge case 2: no args, valid project root -> lists every gate ───────────

@test "edge case 2: no arguments from a valid project root lists every gate with >=1 sample" {
  seed_gate "gate_one" 1000 0 60
  seed_gate "gate_two" 2000 0 60

  run bash "$CLI" --project-root "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate_one"* ]]
  [[ "$output" == *"gate_two"* ]]
}

# ─── Edge case 3: 0 non-censored samples (all censored) -> explicit insufficiency ──

@test "edge case 3: gate with only censored (timeout) samples reports data-insufficient, never derives a value from timeouts" {
  seed_gate "timeout_gate" 999999 124 60
  seed_gate "timeout_gate" 999999 124 60

  run bash "$CLI" --project-root "$WORK" timeout_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"timeout_gate"* ]]
  [[ "$output" == *"insufficient data"* ]]
  # Explicitly never a number derived from the 999999ms censored samples.
  [[ "$output" != *"999999"* ]]
  [[ "$output" == *"only 0 non-censored sample"* ]]
}

# ─── AC14: --project-root + cd contract ─────────────────────────────────────

@test "AC14: --project-root from an unrelated cwd matches running directly from that path" {
  seed_gate "bats_all" 2040000 0 2400
  seed_gate "bats_all" 2040000 0 2400
  seed_gate "bats_all" 2100000 0 2400

  local unrelated_cwd; unrelated_cwd="$(mktemp -d)"

  ( cd "$unrelated_cwd" && bash "$CLI" --project-root "$WORK" bats_all ) > "$WORK/out_via_flag.txt"
  ( cd "$WORK" && bash "$CLI" bats_all ) > "$WORK/out_direct.txt"

  diff "$WORK/out_via_flag.txt" "$WORK/out_direct.txt"
  rm -rf "$unrelated_cwd"
}

@test "AC14: --project-root from an unrelated cwd matches direct cd for the full gate list (no gate_name)" {
  seed_gate "gate_a" 1000 0 60
  seed_gate "gate_b" 2000 0 60

  local unrelated_cwd; unrelated_cwd="$(mktemp -d)"

  ( cd "$unrelated_cwd" && bash "$CLI" --project-root "$WORK" ) > "$WORK/list_via_flag.txt"
  ( cd "$WORK" && bash "$CLI" ) > "$WORK/list_direct.txt"

  diff "$WORK/list_via_flag.txt" "$WORK/list_direct.txt"
  rm -rf "$unrelated_cwd"
}

# ─── Data-sufficiency note (Implementation Detail) ──────────────────────────

@test "sufficient data: gate with >=3 non-censored samples reports recommendation available" {
  seed_gate "ready_gate" 1000 0 60
  seed_gate "ready_gate" 1000 0 60
  seed_gate "ready_gate" 1000 0 60

  run bash "$CLI" --project-root "$WORK" ready_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommendation available"* ]]
  [[ "$output" == *"3 non-censored samples"* ]]
}

@test "insufficient data: gate with only 2 non-censored samples reports recommendation not yet available with real count" {
  seed_gate "sparse_gate" 1000 0 60
  seed_gate "sparse_gate" 1000 0 60

  run bash "$CLI" --project-root "$WORK" sparse_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"only 2 non-censored sample"* ]]
  [[ "$output" == *"recommendation not yet available"* ]]
}

# ─── Usage / flag handling ───────────────────────────────────────────────────

@test "usage: -h/--help prints usage and exits non-zero" {
  run bash "$CLI" --help
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: aid-gate-runtime-report.sh"* ]]
}

@test "usage: unknown flag prints usage and exits non-zero" {
  run bash "$CLI" --bogus-flag
  [ "$status" -ne 0 ]
}

@test "usage: --project-root missing its argument prints usage and exits non-zero" {
  run bash "$CLI" --project-root
  [ "$status" -ne 0 ]
}
