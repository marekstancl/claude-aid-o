#!/usr/bin/env bats
# aid-tier: t0
# test-aid-test-adapter-bats.bats — P066 Step 2.
#
# Discovery against a fixture dir produces exactly one run_unit_id per FILE
# (never per @test), with test_cases[] correctly populated, byte-identical
# run_unit_ids across two runs, and adapter_confidence: static_parse verified
# against this repo's real installed Bats version.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-adapter-bats.sh"

  FIXTURE_DIR="$TEST_TMPDIR/bats-fixture"
  mkdir -p "$FIXTURE_DIR/dir-a" "$FIXTURE_DIR/dir-b"

  # NOTE: fixture content below is built via _write_fixture_bats rather than
  # a heredoc with literal "@test" at line-start — Bats' own preprocessor is
  # a naive line scanner that would otherwise mistake these fixture lines
  # (embedded in THIS outer .bats file's setup()) for real test definitions
  # of the outer suite, corrupting this file's own test count.
  for n in 1 2 3; do
    _write_fixture_bats "$FIXTURE_DIR/dir-a/suite-$n.bats" "suite $n" 5
  done
}

# _write_fixture_bats <path> <name-prefix> <case-count>
_write_fixture_bats() {
  local path="$1" prefix="$2" count="$3" at='@test'
  {
    printf '#!/usr/bin/env bats\n'
    local words=(one two three four five six seven eight nine ten)
    for ((i = 0; i < count; i++)); do
      printf '%s "%s case %s" {\n  [ 1 -eq 1 ]\n}\n' "$at" "$prefix" "${words[$i]}"
    done
  } > "$path"
}

teardown() {
  teardown_test_evidence_dir
}

@test "bats_adapter_discover: a 3-file x ~5-@test fixture produces 3 run_units, never 15" {
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" -eq 3 ]
}

@test "bats_adapter_discover: one run_unit_id per FILE, test_cases[] populated at the correct count" {
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].run_unit_id == "bats:dir-a/suite-1"' >/dev/null
  echo "$output" | jq -e '(.[] | .test_cases | length) == 5' | grep -qv false
  local case_counts
  case_counts="$(echo "$output" | jq -c '[.[] | .test_cases | length] | unique')"
  [ "$case_counts" = "[5]" ]
}

@test "bats_adapter_discover: run_unit_id never carries a test-name suffix" {
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local out_file="$TEST_TMPDIR/discover-output.json"
  printf '%s' "$output" > "$out_file"
  run jq -e '[.[] | .run_unit_id] | map(test("case-")) | any' "$out_file"
  [ "$status" -eq 1 ]
}

@test "bats_adapter_discover: run_unit_ids are byte-identical across two runs" {
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local first="$output"
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "bats_adapter_discover: adapter_confidence static_parse on the real installed Bats version" {
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local confidences
  confidences="$(echo "$output" | jq -c '[.[].isolation.adapter_confidence] | unique')"
  [ "$confidences" = '["static_parse"]' ]
  run bats --help
  [[ "$output" != *"--list"* ]]
}

@test "bats_adapter_discover: a same-basename-different-directory collision is avoided by full relative path" {
  _write_fixture_bats "$FIXTURE_DIR/dir-b/suite-1.bats" "dir-b variant" 1
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local unique_ids total_ids
  unique_ids="$(echo "$output" | jq '[.[].run_unit_id] | unique | length')"
  total_ids="$(echo "$output" | jq '[.[].run_unit_id] | length')"
  [ "$unique_ids" -eq "$total_ids" ]
  [ "$total_ids" -eq 4 ]
}

@test "bats_adapter_discover: a filename containing a double quote does not abort discovery" {
  printf '#!/usr/bin/env bats\n' > "$FIXTURE_DIR/dir-a/a\"b.bats"
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'any(.[]; .run_unit_id | contains("a\"b"))' >/dev/null
}

@test "bats_adapter_discover: an all-punctuation @test title still gets a non-empty test_case_id" {
  printf '#!/usr/bin/env bats\n%s "!!!" {\n  [ 1 -eq 1 ]\n}\n' '@test' > "$FIXTURE_DIR/dir-a/punctuation-title.bats"
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.[] | select(.run_unit_id == "bats:dir-a/punctuation-title") | .test_cases[0].test_case_id | length > 0] | all' >/dev/null
}

@test "bats_adapter_discover: a .bats file with zero @test blocks is still one run_units entry" {
  printf '#!/usr/bin/env bats\n# no tests here yet\n' > "$FIXTURE_DIR/dir-a/empty.bats"
  run bats_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[] | select(.run_unit_id == "bats:dir-a/empty") | .test_cases == []' >/dev/null
}
