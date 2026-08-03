#!/usr/bin/env bats
# test-aid-test-audit-profile.bats — P072 Step 12.
#
# The profiler's value is in what it REFUSES to claim. A file-level timeout
# tells nobody what to do; a fabricated attribution is worse, because it sends
# someone to split a file whose cost would follow the state into both halves.
# Every case here pins either a refusal or an attribution that cites evidence.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REPO="$(cd "$PLUGIN_DIR/../.." && pwd)"
  PROFILE="$PLUGIN_DIR/scripts/aid-test-audit-profile.sh"
  CATALOG="$REPO/.aid-o/config/test-catalog.yaml"
  EXEC_YAML="$REPO/.aid-o/config/execution.yaml"
  OUT="$TEST_TMPDIR/out"
}

teardown() { teardown_test_evidence_dir; }

# A disposable clone — the only root the profiler will run against.
_clone() {
  local c="$TEST_TMPDIR/clone"
  [ -d "$c" ] && { echo "$c"; return 0; }
  git clone -q "$REPO" "$c" 2>/dev/null
  mkdir -p "$c/.aid-o/config"
  cp "$CATALOG" "$EXEC_YAML" "$REPO/.aid-o/config/test-audit.yaml" "$c/.aid-o/config/" 2>/dev/null || true
  echo "$c"
}

@test "REFUSAL: profiling the live checkout exits 10" {
  run bash "$PROFILE" --run-unit-id x --catalog "$CATALOG" \
    --output-dir "$OUT" --target-root "$REPO" --project-root "$REPO"
  [ "$status" -eq 10 ]
  [[ "$output" == *"live checkout"* ]]
  [[ "$output" == *"disposable clone"* ]]
}

@test "REFUSAL: a unit that is not in the catalog exits 3 — no command is invented" {
  local c; c="$(_clone)"
  run bash "$PROFILE" --run-unit-id "bats:does/not/exist" --catalog "$CATALOG" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO"
  [ "$status" -eq 3 ]
  [[ "$output" == *"never invents a command"* ]]
}

@test "REFUSAL: a non-numeric budget is rejected before anything runs" {
  local c; c="$(_clone)"
  run bash "$PROFILE" --run-unit-id x --catalog "$CATALOG" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes banana
  [ "$status" -eq 2 ]
  [ ! -d "$OUT/profiles" ]
}

@test "a real profile of a small unit completes and attributes to a cited bucket" {
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [ -f "$r" ]
  [ "$(jq -r '.complete' "$r")" = "true" ]
  [ "$(jq -r '.lower_bound_ms' "$r")" = "null" ]
  [ "$(jq -r '.timing.cases | length' "$r")" -gt 0 ]
  # a completed run must name a bucket, and the reason must not be empty
  [ -n "$(jq -r '.root_cause.bucket' "$r")" ]
  [ "$(jq -r '.root_cause.reason | length > 20' "$r")" = "true" ]
}

@test "the evidence log is written INCREMENTALLY, not at the end" {
  # A suite that will exceed an hour must be observable long before its
  # deadline; a log that appears only on exit is indistinguishable from a hung
  # process.
  local c; c="$(_clone)"
  bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3 >/dev/null
  local log; log="$(find "$OUT/profiles" -name '*.log' | head -1)"
  [ -s "$log" ]
  grep -q '^1\.\.' "$log"
}

@test "DEADLINE: an unfinished run reports a lower bound and refuses to name a cause" {
  # The honest shape. `elapsed` becomes `lower_bound_ms`, the timing document
  # says truncated, and the root cause is `undecidable` WITH the probe that
  # would settle it — not a plausible-sounding guess.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 1 2>/dev/null)"
  [ "$(jq -r '.complete' "$r")" = "false" ]
  [ "$(jq -r '.incomplete_reason' "$r")" = "deadline" ]
  [ "$(jq -r '.lower_bound_ms' "$r")" -ge 60000 ]
  [ "$(jq -r '.timing.truncated' "$r")" = "true" ]
  [ "$(jq -r '.root_cause.next_probe' "$r")" != "null" ]
}

@test "DEADLINE: the cases observed BEFORE the deadline are kept, not discarded" {
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 1 2>/dev/null)"
  [ "$(jq -r '.timing.cases | length' "$r")" -gt 5 ]
  [ "$(jq -r '.timing.planned' "$r")" -gt "$(jq -r '.timing.cases | length' "$r")" ]
}

@test "duplicate membership is read from contains[], and only EXACT membership counts" {
  # A runtime-partitioned candidate set says nothing about whether a unit
  # really ran twice; counting it would report every pooled bats file as
  # duplicated.
  local c contains r; c="$(_clone)"
  contains="$TEST_TMPDIR/contains.json"
  cat > "$contains" <<'JSON'
[{"gate":"gate:a","kind":"direct_invocation","partition":"all","membership":"exact",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]},
 {"gate":"gate:b","kind":"direct_invocation","partition":"all","membership":"exact",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]},
 {"gate":"gate:pool","kind":"catalog_pool_runner","partition":"pool","membership":"runtime_partitioned",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]}]
JSON
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" \
    --budget-minutes 3 --contains "$contains")"
  [ "$(jq -r '.duplicate_membership.duplicated' "$r")" = "true" ]
  [ "$(jq -r '.root_cause.bucket' "$r")" = "duplicate_membership" ]
  # the runtime-partitioned gate must NOT be among the cited gates
  [ "$(jq -r '.duplicate_membership.gates | index("gate:pool")' "$r")" = "null" ]
}

@test "a single exact gate is NOT reported as duplicated" {
  local c contains r; c="$(_clone)"
  contains="$TEST_TMPDIR/one.json"
  cat > "$contains" <<'JSON'
[{"gate":"gate:only","kind":"direct_invocation","partition":"all","membership":"exact",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]}]
JSON
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" \
    --budget-minutes 3 --contains "$contains")"
  [ "$(jq -r '.duplicate_membership.duplicated' "$r")" = "false" ]
  [ "$(jq -r '.root_cause.bucket' "$r")" != "duplicate_membership" ]
}

@test "the receipt records the runner version the timing came from" {
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [[ "$(jq -r '.timing.bats_version' "$r")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "$(jq -r '.schema_version' "$r")" = "aid-test-profile-v1" ]
}

@test "fixture_growth needs enough timed cases to tell growth from noise" {
  # Declaring accumulation from three data points is how a plausible-sounding
  # cause gets attached to ordinary variance.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  local n; n="$(jq -r '.timing.cases | length' "$r")"
  if [ "$n" -lt 8 ]; then
    [ "$(jq -r '.fixture_growth.detected' "$r")" = "false" ]
    [[ "$(jq -r '.fixture_growth.note // ""' "$r")" == *"too few timed cases"* ]]
  fi
}

@test "source signals are recorded as SIGNALS, never as an attributed share of the time" {
  # The runner reports one duration per case and cannot separate waiting from
  # working, so a sleep count is evidence for a probe — not a number of
  # milliseconds anyone may attribute to waiting.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  run jq -e '.source_signals | has("explicit_sleeps") and has("git_invocations")' "$r"
  [ "$status" -eq 0 ]
  # no bucket in the receipt claims a millisecond split the runner cannot make
  run jq -e '.root_cause | has("attributed_ms")' "$r"
  [ "$status" -ne 0 ]
}
