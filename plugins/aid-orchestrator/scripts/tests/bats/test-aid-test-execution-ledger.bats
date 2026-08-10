#!/usr/bin/env bats
# test-aid-test-execution-ledger.bats — P072 Step 26.
#
# The ledger answers one question: did anything run twice? Its value is
# entirely in not answering "no" when the answer is yes — and the first
# implementation did exactly that, so most of these cases pin the ways it can
# be silenced.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LEDGER="$PLUGIN_DIR/scripts/aid-test-execution-ledger.sh"
  SCHEMA="$PLUGIN_DIR/defaults/schemas/test-execution-ledger.schema.json"
  L="$TEST_TMPDIR/ledger.json"
}

teardown() { teardown_test_evidence_dir; }

_open() { bash "$LEDGER" open --path "$L" --run-id "${1:-r1}" --candidate-sha "${2:-sha1}" >/dev/null; }
_append() {  # <unit> <gate> [point] [fingerprint]
  bash "$LEDGER" append --path "$L" --run-unit-id "$1" --gate-id "$2" \
    --dispatch-point "${3:-aggregate_runner}" --fingerprint "${4:-fp}"
}
_close() { bash "$LEDGER" close --path "$L" "$@"; }

_validate() {
  python3 - "$SCHEMA" "$L" <<'PY'
import json,sys
from jsonschema.validators import Draft202012Validator
schema=json.load(open(sys.argv[1])); inst=json.load(open(sys.argv[2]))
errs=list(Draft202012Validator(schema).iter_errors(inst))
for e in errs: print("/".join(str(x) for x in e.path) or "(root)", e.message)
sys.exit(1 if errs else 0)
PY
}

# ─── The defect this exists to catch ───────────────────────────────────────

@test "the same unit under TWO gates is a double execution" {
  # This repository's real shape: gate:bats_fsm runs a file directly while
  # gate:bats_all runs it in the pool, and the full profile includes both.
  _open
  _append "bats:test-aid-fsm" "gate:bats_fsm" gate_runner_direct
  _append "bats:test-aid-fsm" "gate:bats_all" aggregate_runner
  run _close
  [ "$status" -eq 7 ]
  [[ "$output" == *"DOUBLE EXECUTION"* ]]
  [[ "$output" == *"gate:bats_fsm"* ]]
  [[ "$output" == *"gate:bats_all"* ]]
}

@test "a CONTAINS relation does not silence a real double execution" {
  # The obvious exemption — "the pool gate contains it" — was built and
  # immediately certified this exact defect as clean. It is gone, and this is
  # what stops it coming back.
  local c="$TEST_TMPDIR/contains.json"
  cat > "$c" <<'JSON'
[{"gate":"gate:bats_all","kind":"bats_tree_runner","partition":"pool",
  "membership":"runtime_partitioned","run_unit_ids":["bats:test-aid-fsm"]}]
JSON
  _open
  _append "bats:test-aid-fsm" "gate:bats_fsm" gate_runner_direct
  _append "bats:test-aid-fsm" "gate:bats_all" aggregate_runner
  run _close --contains "$c"
  [ "$status" -eq 7 ]
  [[ "$output" == *"DOUBLE EXECUTION"* ]]
}

@test "a duplicate is NAMED, with both gates — never merely counted" {
  # "2 duplicates" sends nobody anywhere.
  _open
  _append "bats:a" "gate:one"
  _append "bats:a" "gate:two"
  run _close
  [[ "$output" == *"bats:a ran under"* ]]
}

# ─── What is not a duplicate ───────────────────────────────────────────────

@test "the same unit twice under the SAME gate is that gate's own business" {
  # A retry, or a gate that repeats a unit deliberately. It is one gate's
  # decision, not two gates unaware of each other.
  _open
  _append "bats:a" "gate:one"
  _append "bats:a" "gate:one"
  run _close
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.duplicates | length' "$L")" = "0" ]
}

@test "different units under different gates are not duplicates" {
  _open
  _append "bats:a" "gate:one"
  _append "bats:b" "gate:two"
  run _close
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.dispatched' "$L")" = "2" ]
  [ "$(jq -r '.summary.distinct_units' "$L")" = "2" ]
}

# ─── Gaps are worse than failures ──────────────────────────────────────────

@test "a dispatch point OUTSIDE a gate run appends nothing, and that is not an error" {
  # A developer running a suite by hand has no run to account for. Failing
  # here would make the instrumentation something people remove.
  run bash "$LEDGER" append --run-unit-id "bats:a" --gate-id "gate:x" --dispatch-point aggregate_runner
  [ "$status" -eq 0 ]
}

@test "an append naming a ledger that does not exist FAILS — a named ledger is an accounted run" {
  # This used to return 0, which made "the ledger vanished mid-run" and
  # "nothing ran twice" produce the same observable outcome. A path was
  # supplied, so a run IS being accounted for; the file's absence is the
  # accounting failing, not an absence of accounting.
  run bash "$LEDGER" append --path "$TEST_TMPDIR/never-opened.json" \
    --run-unit-id "bats:a" --gate-id "gate:x" --dispatch-point aggregate_runner
  [ "$status" -eq 3 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "an append MISSING its required fields is a usage error, not a silent skip" {
  # A silently dropped append is a gap, and a gap is indistinguishable from
  # "nothing ran twice".
  _open
  run bash "$LEDGER" append --path "$L" --run-unit-id "bats:a"
  [ "$status" -eq 2 ]
}

@test "closing a ledger that was never opened fails rather than reporting clean" {
  run bash "$LEDGER" close --path "$TEST_TMPDIR/absent.json"
  [ "$status" -eq 3 ]
}

# ─── The record itself ─────────────────────────────────────────────────────

@test "the ledger validates against its schema, open and closed" {
  _open
  run _validate
  [ "$status" -eq 0 ]
  _append "bats:a" "gate:one" aggregate_runner
  _close
  run _validate
  [ "$status" -eq 0 ]
}

@test "every entry records WHICH dispatch point appended it" {
  # The paths are not interchangeable: `gate_runner_direct` is the one
  # that makes a directly-invoked gate visible at all (P078: two live paths).
  _open
  _append "bats:a" "gate:one" gate_runner_direct
  _append "bats:b" "gate:two" aggregate_runner
  _close
  [ "$(jq -r '[.entries[].dispatch_point] | sort | join(",")' "$L")" = "aggregate_runner,gate_runner_direct" ]
}

@test "an unrecognised dispatch point is rejected by the schema" {
  _open
  _append "bats:a" "gate:one" aggregate_runner
  jq '.entries[0].dispatch_point = "somewhere_else"' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  run _validate
  [ "$status" -ne 0 ]
}

@test "the candidate SHA is recorded, so two commits are two runs" {
  # A unit run against two different revisions is two legitimate executions,
  # not a duplicate — the ledger is per-run for exactly that reason.
  _open r9 deadbeef
  [ "$(jq -r '.candidate_sha' "$L")" = "deadbeef" ]
  [ "$(jq -r '.run_id' "$L")" = "r9" ]
}

@test "the summary reports dispatched, distinct and duplicates" {
  _open
  _append "bats:a" "gate:one"
  _append "bats:a" "gate:two"
  _append "bats:b" "gate:one"
  run _close
  [ "$(jq -r '.summary.dispatched' "$L")" = "3" ]
  [ "$(jq -r '.summary.distinct_units' "$L")" = "2" ]
  [ "$(jq -r '.summary.duplicates | length' "$L")" = "1" ]
}

# ─── Concurrency ───────────────────────────────────────────────────────────

@test "concurrent appends do not lose entries" {
  # Appends can race (backgrounded gates, concurrent shells); a lost append
  # is a gap, and a gap reads as an absence of duplication.
  _open
  local i
  for i in $(seq 1 12); do
    ( _append "bats:u$i" "gate:many" aggregate_runner ) &
  done
  wait
  _close
  [ "$(jq -r '.summary.dispatched' "$L")" = "12" ]
}

# ─── Deliberate repeats are declared, never inferred ────────────────────────

@test "a repeat DECLARED as escalation is a deliberate repeat, not a duplicate" {
  # P069's escalation reruns the same units under the full profile with the
  # parent's ledger inherited. Without a way to say so, correct behaviour
  # would fail the run.
  _open
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:one" --dispatch-point aggregate_runner
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:two" \
    --dispatch-point gate_runner_direct --execution-kind escalation
  run bash "$LEDGER" close --path "$L"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.duplicates | length' "$L")" = "0" ]
  [ "$(jq -r '.summary.deliberate_repeats | length' "$L")" = "1" ]
}

@test "a deliberate repeat is REPORTED, never silent — it still costs wall clock" {
  _open
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:one" --dispatch-point aggregate_runner
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:two" \
    --dispatch-point gate_runner_direct --execution-kind escalation
  run bash "$LEDGER" close --path "$L"
  [[ "$output" == *"deliberate repeat"* ]]
  [[ "$output" == *"bats:a"* ]]
}

@test "AID_EXECUTION_KIND declares a whole subprocess — that is how escalation marks itself" {
  _open
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:one" --dispatch-point aggregate_runner
  AID_EXECUTION_KIND=escalation bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" \
    --gate-id "gate:two" --dispatch-point aggregate_runner
  run bash "$LEDGER" close --path "$L"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary.deliberate_repeats | length' "$L")" = "1" ]
}

@test "an UNDECLARED repeat is still a double execution — silence is not a declaration" {
  # The whole exemption is worth nothing if forgetting to mark something is
  # the same as marking it.
  _open
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:one" --dispatch-point aggregate_runner
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:two" --dispatch-point gate_runner_direct
  run bash "$LEDGER" close --path "$L"
  [ "$status" -eq 7 ]
  [ "$(jq -r '.summary.deliberate_repeats | length' "$L")" = "0" ]
}

@test "an unrecognised --execution-kind is rejected — a typo must not become a free pass" {
  _open
  run bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:one" \
    --dispatch-point aggregate_runner --execution-kind "escalation!"
  [ "$status" -eq 2 ]
}

@test "every entry records its execution kind, and the default is normal" {
  _open
  bash "$LEDGER" append --path "$L" --run-unit-id "bats:a" --gate-id "gate:one" --dispatch-point aggregate_runner
  [ "$(jq -r '.entries[0].execution_kind' "$L")" = "normal" ]
}
