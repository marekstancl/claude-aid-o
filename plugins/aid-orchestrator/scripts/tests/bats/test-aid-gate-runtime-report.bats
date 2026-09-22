#!/usr/bin/env bats
# aid-tier: t0
# test-aid-gate-runtime-report.bats — P097 Step 5: aid-gate-runtime-report.sh
# prints the proposed `timeout_seconds` (from gates_rows history, through the
# library's `propose`) next to the configured one, per gate, and never writes.
# The CLI is driven as a real subprocess so the --project-root + cd contract
# is exercised, not assumed.

load test-helpers.bash

setup() {
  export TZ=UTC
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  CLI="$PLUGIN_ROOT/scripts/aid-gate-runtime-report.sh"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/.aid-o/config"
  cat > "$WORK/.aid-o/config/execution.yaml" <<'YAML'
gates:
  slow:
    command: "true"
    required: true
    timeout_seconds: 120
  quick:
    command: "true"
    required: false
YAML
  N=0
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# row <gate> <duration_ms> — one checkpointed pass row in its own run directory.
row() {
  N=$((N + 1))
  local dir="$WORK/.aid-o/work/evidence/E-1/R-$(printf '%03d' "$N")/gates_rows"
  mkdir -p "$dir"
  jq -nc --arg g "$1" --argjson ms "$2" \
    --arg at "$(date -u -d "@$((1756684800 + N))" +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:$g, row_version:2, status:"pass", reason:"exit_0", exit_code:0,
      duration_ms:$ms, completed_at:$at}' > "$dir/$1.json"
}

@test "edge case 1: --project-root with no .aid-o/ at all -> clear error, exit non-zero" {
  local empty_dir; empty_dir="$(mktemp -d)"
  run bash "$CLI" --project-root "$empty_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *".aid-o"* ]]
  rm -rf "$empty_dir"
}

@test "no history yet: every configured gate prints insufficient_history next to its configured value, exit 0" {
  run bash "$CLI" --project-root "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"quick insufficient_history (0 measured durations, 5 needed, 0 job_timeout rows excluded) configured_timeout_seconds=60"* ]]
  [[ "$output" == *"slow insufficient_history (0 measured durations, 5 needed, 0 job_timeout rows excluded) configured_timeout_seconds=120"* ]]
}

@test "proposed vs configured: 20 rows of 10 s..200 s -> proposed 390 next to configured 120; the unconfigured gate shows the default 60" {
  local i
  for i in $(seq 1 20); do row slow $((i * 10000)); done
  run bash "$CLI" --project-root "$WORK" slow
  [ "$status" -eq 0 ]
  [[ "$output" == "slow proposed_timeout_seconds=390 (p95 190000 ms over the last 20 measured durations, 0 job_timeout rows excluded) configured_timeout_seconds=120" ]]
  run bash "$CLI" --project-root "$WORK"
  [[ "$output" == *"proposed_timeout_seconds=390"*"configured_timeout_seconds=120"* ]]
  [[ "$output" == *"quick insufficient_history"*"configured_timeout_seconds=60"* ]]
}

@test "no writes: the project tree is byte-identical after a report" {
  local i before after
  for i in $(seq 1 20); do row slow $((i * 10000)); done
  before="$(cd "$WORK" && find . -type f -exec sha256sum {} + | sort)"
  bash "$CLI" --project-root "$WORK" >/dev/null
  after="$(cd "$WORK" && find . -type f -exec sha256sum {} + | sort)"
  [ "$before" = "$after" ]
}

@test "--project-root from an unrelated cwd matches running directly from that path" {
  local i unrelated_cwd
  for i in $(seq 1 20); do row slow $((i * 10000)); done
  unrelated_cwd="$(mktemp -d)"
  ( cd "$unrelated_cwd" && bash "$CLI" --project-root "$WORK" ) > "$WORK/via_flag.txt"
  ( cd "$WORK" && bash "$CLI" ) > "$WORK/direct.txt"
  diff "$WORK/via_flag.txt" "$WORK/direct.txt"
  rm -rf "$unrelated_cwd"
}

@test "usage: -h/--help, an unknown flag and a bare --project-root each exit non-zero" {
  run bash "$CLI" --help
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: aid-gate-runtime-report.sh"* ]]
  run bash "$CLI" --bogus-flag
  [ "$status" -ne 0 ]
  run bash "$CLI" --project-root
  [ "$status" -ne 0 ]
}
