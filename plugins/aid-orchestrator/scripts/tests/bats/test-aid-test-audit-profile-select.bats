#!/usr/bin/env bats
# test-aid-test-audit-profile-select.bats — P072 Step 13 (production wiring).
#
# The selector exists so that "was that slow suite ever diagnosed?" is a
# question about artifacts rather than about what the controller remembered to
# do. Every case here pins either a refusal, or the honesty rule that a unit
# which did not fit under the ceiling is REPORTED rather than dropped.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SELECT="$PLUGIN_DIR/scripts/aid-test-audit-profile-select.sh"
  PROJ="$TEST_TMPDIR/proj"; mkdir -p "$PROJ/.aid-o/config"
  M="$TEST_TMPDIR/measurements.jsonl"
  OUT="$TEST_TMPDIR/selection.json"
}

teardown() { teardown_test_evidence_dir; }

_m() {
  # <run_unit_id> <duration_ms> [state]
  jq -nc --arg id "$1" --argjson d "$2" --arg s "${3:-terminal_pass}" \
    '{run_unit_id:$id, job_id:"j", state:$s, exit_code:0,
      started_at:"t", ended_at:"t", duration_ms:$d, stdout_path:"/dev/null"}' >> "$M"
}

_run() {
  bash "$SELECT" --measurements "$M" --project-root "$PROJ" \
    --audit-id "AUD-1" --output "$OUT" "$@"
}

@test "REFUSAL: an absent measurements file is an error, never an empty selection" {
  # "nothing was slow enough" and "I could not read the measurements" must not
  # look alike — one is a finding, the other is a broken audit.
  run bash "$SELECT" --measurements "$TEST_TMPDIR/nope.jsonl" --project-root "$PROJ" \
    --audit-id "AUD-1" --output "$OUT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"not an empty selection"* ]]
  [ ! -f "$OUT" ]
}

@test "REFUSAL: one unparseable line stops the selection" {
  # Skipping it would remove a candidate from consideration, and nobody would
  # learn that a slow unit was never even weighed.
  _m "bats:a" 500000
  printf 'this is not json\n' >> "$M"
  run _run
  [ "$status" -eq 3 ]
  [[ "$output" == *"hole in it"* ]]
  [ ! -f "$OUT" ]
}

@test "REFUSAL: --audit-id is required — a selection with no audit binds to nothing" {
  _m "bats:a" 500000
  run bash "$SELECT" --measurements "$M" --project-root "$PROJ" --output "$OUT"
  [ "$status" -eq 2 ]
}

@test "a unit at or above the trigger is selected; one below it is not" {
  _m "bats:slow" 200000
  _m "bats:fast" 4000
  _run --trigger-ms 120000 --max-units 3
  [ "$(jq -r '.selected | length' "$OUT")" = "1" ]
  [ "$(jq -r '.selected[0].run_unit_id' "$OUT")" = "bats:slow" ]
  [ "$(jq -r '.selected[0].measured_ms' "$OUT")" = "200000" ]
  [ "$(jq -r '.deferred | length' "$OUT")" = "0" ]
}

@test "the boundary is inclusive: exactly at the trigger owes a profile" {
  _m "bats:exact" 120000
  _run --trigger-ms 120000 --max-units 3
  [ "$(jq -r '.selected | length' "$OUT")" = "1" ]
}

@test "over the trigger but past the ceiling is DEFERRED with its cost, not dropped" {
  # A quantified gap that is left out of the artifact is a gap nobody sees.
  _m "bats:a" 500000
  _m "bats:b" 400000
  _m "bats:c" 300000
  _run --trigger-ms 120000 --max-units 2
  [ "$(jq -r '.selected | length' "$OUT")" = "2" ]
  [ "$(jq -r '.deferred | length' "$OUT")" = "1" ]
  [ "$(jq -r '.deferred[0].run_unit_id' "$OUT")" = "bats:c" ]
  [ "$(jq -r '.deferred[0].measured_ms' "$OUT")" = "300000" ]
  [[ "$(jq -r '.deferred[0].reason' "$OUT")" == *"not diagnosed, and not dismissed"* ]]
}

@test "selection is by descending cost — the most expensive units get the budget" {
  _m "bats:mid" 300000
  _m "bats:worst" 900000
  _m "bats:least" 130000
  _run --trigger-ms 120000 --max-units 1
  [ "$(jq -r '.selected[0].run_unit_id' "$OUT")" = "bats:worst" ]
}

@test "a NON-TERMINAL measurement is not a candidate" {
  # A job that never reached a terminal state has no duration worth ranking;
  # profiling it would be measuring a measurement that failed.
  _m "bats:lost" 900000 "lost"
  _m "bats:real" 200000
  _run --trigger-ms 120000 --max-units 3
  [ "$(jq -r '[.selected[].run_unit_id] | index("bats:lost")' "$OUT")" = "null" ]
  [ "$(jq -r '.measured_units' "$OUT")" = "1" ]
}

@test "nothing over the trigger yields an EMPTY selection, and that is a success" {
  _m "bats:a" 1000
  run _run --trigger-ms 120000 --max-units 3
  [ "$status" -eq 0 ]
  [ "$(jq -r '.selected | length' "$OUT")" = "0" ]
  [ "$(jq -r '.deferred | length' "$OUT")" = "0" ]
}

@test "the policy actually used is recorded in the artifact" {
  # A reader must be able to tell whether a unit was skipped because it was
  # cheap or because the ceiling was low.
  _m "bats:a" 500000
  _run --trigger-ms 250000 --max-units 7
  [ "$(jq -r '.policy.profile_trigger_ms' "$OUT")" = "250000" ]
  [ "$(jq -r '.policy.profile_max_units' "$OUT")" = "7" ]
  [ "$(jq -r '.audit_id' "$OUT")" = "AUD-1" ]
  [ "$(jq -r '.schema_version' "$OUT")" = "aid-test-profile-selection-v1" ]
}

@test "with no flags the thresholds come from the project's test-audit.yaml" {
  cat > "$PROJ/.aid-o/config/test-audit.yaml" <<'YAML'
budget_minutes_default: 30
max_read_only_audit_agents: 4
allowed_runners: [bats, sh]
decision:
  profile_trigger_ms: 50000
  profile_max_units: 1
YAML
  _m "bats:a" 60000
  _m "bats:b" 55000
  _run
  [ "$(jq -r '.policy.profile_trigger_ms' "$OUT")" = "50000" ]
  [ "$(jq -r '.selected | length' "$OUT")" = "1" ]
  [ "$(jq -r '.deferred | length' "$OUT")" = "1" ]
}
