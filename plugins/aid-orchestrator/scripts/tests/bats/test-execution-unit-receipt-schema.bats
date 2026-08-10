#!/usr/bin/env bats
# test-execution-unit-receipt-schema.bats — P069 Step 4.
#
# Validates execution-unit-receipt.schema.json: minimal-valid + invalid
# fixtures, and proves the canonical ordering claim — two batch documents
# built from the SAME units in a DIFFERENT arrival order serialize to
# byte-identical output once sorted by unit_id (the one thing every
# producer/consumer of this shape must agree on, per this step's own
# Implementation Detail).
#
# JSON-Schema tests use python3 + jsonschema (Draft 2020-12) — same idiom as
# test-aid-test-catalog-schema.bats; skip cleanly when jsonschema is
# unavailable rather than false-failing.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/execution-unit-receipt.schema.json"
  WORK="$(mktemp -d)"
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

_schema_validate() {
  python3 - "$1" "$2" <<'PY'
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
sys.exit(1 if list(validator.iter_errors(inst)) else 0)
PY
}

# _is_units_sorted <file> — exit 0 iff units[] is already ascending by
# unit_id (a real, standalone check of the ordering CLAIM — not just a
# demonstration that `jq sort_by` can produce sorted output).
_is_units_sorted() {
  jq -e '.units == (.units | sort_by(.unit_id))' "$1" >/dev/null
}

# _is_strict_rfc3339_utc <ts> — same idiom as aid-plan-fsm.sh's own
# _pfsm_rfc3339_epoch (Codex review: this environment's python3+jsonschema
# has no "date-time" format checker registered at all — FORMAT_CHECKER
# silently treats an unrecognized format as valid, so the schema's
# `format:"date-time"` is NOT actually enforced by this test harness here;
# this gives the malformed-timestamp test a real, independent check).
_is_strict_rfc3339_utc() {
  local ts="$1"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] || return 1
  date -u -d "$ts" +%s >/dev/null 2>&1
}

_minimal_receipt() {
  local unit_id="$1"
  jq -nc --arg u "$unit_id" '{
    unit_id: $u, job_id: ($u + "-job"), state: "terminal_pass",
    duration_ms: 1200, concurrency_context: "sequential",
    co_scheduled_with: [], stdout_path: ("/tmp/" + $u + "/stdout.log"),
    exit_code: 0
  }'
}

@test "a minimal-valid batch document passes schema validation" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc --argjson u1 "$(_minimal_receipt "bats:a")" --argjson u2 "$(_minimal_receipt "bats:b")" \
    '{batch_id:"batch-1", units:[$u1,$u2], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:01:00Z"}' \
    > "$WORK/valid.json"
  run _schema_validate "$SCHEMA" "$WORK/valid.json"
  [ "$status" -eq 0 ]
}

@test "a non-terminal receipt with null duration_ms/exit_code passes schema validation" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{
    unit_id:"bats:running", job_id:"job-1", state:"running", duration_ms:null,
    concurrency_context:"sequential", co_scheduled_with:[],
    stdout_path:"/tmp/x/stdout.log", exit_code:null
  }' > "$WORK/receipt.json"
  jq -n --argjson r "$(cat "$WORK/receipt.json")" \
    '{batch_id:"batch-2", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/valid2.json"
  run _schema_validate "$SCHEMA" "$WORK/valid2.json"
  [ "$status" -eq 0 ]
}

@test "a receipt missing a required field is rejected" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{unit_id:"bats:a", job_id:"job-1", state:"terminal_pass"}' > "$WORK/incomplete_receipt.json"
  jq -n --argjson r "$(cat "$WORK/incomplete_receipt.json")" \
    '{batch_id:"batch-3", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/invalid.json"
  run _schema_validate "$SCHEMA" "$WORK/invalid.json"
  [ "$status" -eq 1 ]
}

@test "an unrecognized state value is rejected" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{
    unit_id:"bats:a", job_id:"job-1", state:"bogus_state", duration_ms:null,
    concurrency_context:"sequential", co_scheduled_with:[], stdout_path:null, exit_code:null
  }' > "$WORK/bad_receipt.json"
  jq -n --argjson r "$(cat "$WORK/bad_receipt.json")" \
    '{batch_id:"batch-4", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/invalid2.json"
  run _schema_validate "$SCHEMA" "$WORK/invalid2.json"
  [ "$status" -eq 1 ]
}

@test "a malformed started_at timestamp fails an independent strict RFC3339 check (Codex regression)" {
  # This environment's python3+jsonschema has no "date-time" FormatChecker
  # registered (no rfc3339-validator installed) — FORMAT_CHECKER silently
  # treats an unrecognized format as valid, so jsonschema alone would NOT
  # catch this here. Assert the real, independent check instead of a
  # library call this environment cannot actually enforce.
  ! _is_strict_rfc3339_utc "not-a-timestamp"
  _is_strict_rfc3339_utc "2026-08-02T00:01:00Z"
}

@test "a non-terminal receipt with a non-null duration_ms/exit_code is rejected (Codex regression)" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{
    unit_id:"bats:running", job_id:"job-1", state:"running", duration_ms:1000,
    concurrency_context:"sequential", co_scheduled_with:[], stdout_path:null, exit_code:0
  }' > "$WORK/bad_nonterminal.json"
  jq -n --argjson r "$(cat "$WORK/bad_nonterminal.json")" \
    '{batch_id:"batch-x1", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/invalid3.json"
  run _schema_validate "$SCHEMA" "$WORK/invalid3.json"
  [ "$status" -eq 1 ]
}

@test "a terminal_pass receipt with null duration_ms/exit_code is rejected (Codex regression)" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{
    unit_id:"bats:a", job_id:"job-1", state:"terminal_pass", duration_ms:null,
    concurrency_context:"sequential", co_scheduled_with:[], stdout_path:null, exit_code:null
  }' > "$WORK/bad_terminal.json"
  jq -n --argjson r "$(cat "$WORK/bad_terminal.json")" \
    '{batch_id:"batch-x2", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/invalid4.json"
  run _schema_validate "$SCHEMA" "$WORK/invalid4.json"
  [ "$status" -eq 1 ]
}

@test "a cancelled receipt with null duration_ms but a real exit_code is accepted (pre-exec handshake case)" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{
    unit_id:"bats:a", job_id:"job-1", state:"cancelled", duration_ms:null,
    concurrency_context:"sequential", co_scheduled_with:[], stdout_path:null, exit_code:143
  }' > "$WORK/preexec_cancel.json"
  jq -n --argjson r "$(cat "$WORK/preexec_cancel.json")" \
    '{batch_id:"batch-x3", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/valid3.json"
  run _schema_validate "$SCHEMA" "$WORK/valid3.json"
  [ "$status" -eq 0 ]
}

@test "a cancelled receipt with a null exit_code is rejected (aid-job.sh always sets 143)" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc '{
    unit_id:"bats:a", job_id:"job-1", state:"cancelled", duration_ms:null,
    concurrency_context:"sequential", co_scheduled_with:[], stdout_path:null, exit_code:null
  }' > "$WORK/bad_cancel.json"
  jq -n --argjson r "$(cat "$WORK/bad_cancel.json")" \
    '{batch_id:"batch-x4", units:[$r], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:00:00Z"}' \
    > "$WORK/invalid5.json"
  run _schema_validate "$SCHEMA" "$WORK/invalid5.json"
  [ "$status" -eq 1 ]
}

@test "a batch document missing batch_id is rejected" {
  _have_jsonschema || skip "python3+jsonschema unavailable"
  jq -nc --argjson u1 "$(_minimal_receipt "bats:a")" \
    '{units:[$u1], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:01:00Z"}' \
    > "$WORK/no_batch_id.json"
  run _schema_validate "$SCHEMA" "$WORK/no_batch_id.json"
  [ "$status" -eq 1 ]
}

# -- canonical ordering: sort-by-unit_id is the shared contract -------------
@test "two batches built from reordered input serialize to byte-identical output when sorted by unit_id" {
  local r_a r_b r_c
  r_a="$(_minimal_receipt "bats:aaa")"
  r_b="$(_minimal_receipt "bats:bbb")"
  r_c="$(_minimal_receipt "bats:ccc")"

  # Batch 1: units arrive in order c, a, b (e.g. completion order).
  jq -nc --argjson c "$r_c" --argjson a "$r_a" --argjson b "$r_b" \
    '{batch_id:"batch-x", units:[$c,$a,$b], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:01:00Z"}' \
    > "$WORK/batch1_raw.json"

  # Batch 2: same three units, arrival order b, c, a.
  jq -nc --argjson b "$r_b" --argjson c "$r_c" --argjson a "$r_a" \
    '{batch_id:"batch-x", units:[$b,$c,$a], started_at:"2026-08-02T00:00:00Z", ended_at:"2026-08-02T00:01:00Z"}' \
    > "$WORK/batch2_raw.json"

  # The raw, as-arrived fixtures are a MEANINGFUL reordering test — neither
  # is already sorted (Codex review: prove the fixture actually exercises
  # the claim, not just that jq's own sort_by works).
  ! _is_units_sorted "$WORK/batch1_raw.json"
  ! _is_units_sorted "$WORK/batch2_raw.json"

  # The canonicalization every producer/consumer agrees on: sort units[] by unit_id.
  _canonicalize() { jq -Sc '.units |= sort_by(.unit_id)' "$1"; }

  _canonicalize "$WORK/batch1_raw.json" > "$WORK/batch1_canonical.json"
  _canonicalize "$WORK/batch2_raw.json" > "$WORK/batch2_canonical.json"
  _is_units_sorted "$WORK/batch1_canonical.json"
  _is_units_sorted "$WORK/batch2_canonical.json"

  diff "$WORK/batch1_canonical.json" "$WORK/batch2_canonical.json"

  if _have_jsonschema; then
    run _schema_validate "$SCHEMA" "$WORK/batch1_canonical.json"
    [ "$status" -eq 0 ]
  fi
}
