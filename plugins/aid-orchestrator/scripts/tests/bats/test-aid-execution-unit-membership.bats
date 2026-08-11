#!/usr/bin/env bats
# aid-tier: t0
# test-aid-execution-unit-membership.bats — P069 Step 2.
#
# Proves execution_unit_membership_verify:
#   - a clean 1:1 resolution produces membership_verified:true with a
#     matching membership_binding (catalog_fingerprint == the resolved
#     run_unit's runtime.fingerprint)
#   - a zero-resolution run_unit_id fails, naming the id and candidate count
#   - a many-resolution run_unit_id (catalog integrity bug) fails likewise
#   - two distinct unit_ids resolving to a byte-identical command fail
#     without both carrying dedup:true, and pass when both do

setup() {
  LIB="${BATS_TEST_DIRNAME}/../../lib/aid-execution-unit-membership.sh"
  # shellcheck source=/dev/null
  source "$LIB"

  CATALOG_JSON='{
    "schema_version": "1.0.0",
    "run_units": [
      {"run_unit_id": "bats:a.bats", "runtime": {"fingerprint": "fp-a"}, "command": {"type":"argv","argv":["bats","a.bats"]}},
      {"run_unit_id": "bats:b.bats", "runtime": {"fingerprint": "fp-b"}, "command": {"type":"argv","argv":["bats","b.bats"]}},
      {"run_unit_id": "bats:dup1.bats", "runtime": {"fingerprint": "fp-dup1"}, "command": {"type":"argv","argv":["bats","same.bats"]}},
      {"run_unit_id": "bats:dup2.bats", "runtime": {"fingerprint": "fp-dup2"}, "command": {"type":"argv","argv":["bats","same.bats"]}},
      {"run_unit_id": "bats:ambiguous.bats", "runtime": {"fingerprint": "fp-x1"}, "command": {"type":"argv","argv":["bats","ambiguous.bats"]}},
      {"run_unit_id": "bats:ambiguous.bats", "runtime": {"fingerprint": "fp-x2"}, "command": {"type":"argv","argv":["bats","ambiguous-v2.bats"]}}
    ]
  }'
}

@test "a clean 1:1 resolution produces membership_verified:true with a matching membership_binding" {
  units='[{"unit_id":"bats:a.bats","dedup":false}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].membership_verified == true and .[0].membership_binding.catalog_fingerprint == "fp-a" and .[0].membership_binding.verifier_run_id == "verify-run-1" and (.[0].membership_binding.verified_at | length > 0)'
}

@test "a run_unit_id with zero catalog candidates fails loudly, naming it and the count" {
  units='[{"unit_id":"bats:does-not-exist.bats","dedup":false}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:does-not-exist.bats"* ]]
  [[ "$output" == *"0 candidates"* ]]
}

@test "a run_unit_id with multiple catalog candidates fails loudly, naming it and the count" {
  units='[{"unit_id":"bats:ambiguous.bats","dedup":false}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:ambiguous.bats"* ]]
  [[ "$output" == *"2 candidates"* ]]
}

@test "two distinct unit_ids resolving to a byte-identical command fail without dedup:true on both" {
  units='[{"unit_id":"bats:dup1.bats","dedup":false},{"unit_id":"bats:dup2.bats","dedup":false}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats:dup1.bats"* && "$output" == *"bats:dup2.bats"* ]]
}

@test "two distinct unit_ids resolving to a byte-identical command fail when only ONE carries dedup:true" {
  units='[{"unit_id":"bats:dup1.bats","dedup":true},{"unit_id":"bats:dup2.bats","dedup":false}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -ne 0 ]
}

@test "two distinct unit_ids resolving to a byte-identical command pass when BOTH carry dedup:true" {
  units='[{"unit_id":"bats:dup1.bats","dedup":true},{"unit_id":"bats:dup2.bats","dedup":true}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.[0].membership_verified == true) and (.[1].membership_verified == true) and (.[0].membership_binding.catalog_fingerprint == "fp-dup1") and (.[1].membership_binding.catalog_fingerprint == "fp-dup2")'
}

@test "a caller-supplied command mismatching the catalog is overwritten with the catalog's own command (Codex regression)" {
  units='[{"unit_id":"bats:a.bats","dedup":false,"command":{"type":"shell","shell":"arbitrary command"}}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].command == {"type":"argv","argv":["bats","a.bats"]}'
}

@test "a malformed (non-array) units_json is rejected rather than silently succeeding (Codex regression)" {
  units='{"x":{"unit_id":"bats:a.bats"}}'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-1"
  [ "$status" -ne 0 ]
  [ -z "$output" ] || [[ "$output" != *'"membership_verified"'* ]]
}

@test "multiple non-colliding units are all stamped independently in one pass" {
  units='[{"unit_id":"bats:a.bats","dedup":false},{"unit_id":"bats:b.bats","dedup":false}]'
  run execution_unit_membership_verify "$units" "$CATALOG_JSON" "verify-run-2"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.[0].membership_binding.catalog_fingerprint == "fp-a") and (.[1].membership_binding.catalog_fingerprint == "fp-b")'
}
