#!/usr/bin/env bats
# test-aid-audit-tests-cli.bats — P066 Step 8.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PARSER="$AID_PLUGIN_PATH/scripts/aid-audit-tests-cli-parse.sh"

  FIXTURE_PROJECT="$TEST_TMPDIR/fixture-project"
  mkdir -p "$FIXTURE_PROJECT/tests"
  local at='@test'
  printf '#!/usr/bin/env bats\n%s "case" {\n  [ 1 -eq 1 ]\n}\n' "$at" > "$FIXTURE_PROJECT/tests/suite.bats"
}

teardown() {
  teardown_test_evidence_dir
}

@test "defaults: scope=repo, mode=static when no arguments given" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scope == "repo" and .mode == "static"' >/dev/null
}

@test "unknown option fails loudly with exit code 2" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --bogus-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "nonexistent path: scope fails loudly with exit code 3" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:does/not/exist"
  [ "$status" -eq 3 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "a real, existing path: scope succeeds" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:tests"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scope == "path:tests"' >/dev/null
}

@test "--mode full without --budget-minutes is a hard error (exit code 4), never a default" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode full
  [ "$status" -eq 4 ]
  [[ "$output" == *"--budget-minutes"* ]]
}

@test "--mode full with --budget-minutes succeeds" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode full --budget-minutes 45
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "full" and .budget_minutes == 45' >/dev/null
}

@test "--max-agents 0 fails loudly with exit code 5" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --max-agents 0
  [ "$status" -eq 5 ]
}

@test "an unrecognized runner:<id> fails loudly (exit code 6) and lists the actually-discovered families" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "runner:nonexistent-runner"
  [ "$status" -eq 6 ]
  [[ "$output" == *"bats"* ]]
}

@test "a real, discovered runner:<id> succeeds" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "runner:bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.scope == "runner:bats"' >/dev/null
}

@test "an invalid --mode value fails loudly with exit code 9" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode bogus
  [ "$status" -eq 9 ]
}

@test "a non-numeric --budget-minutes fails loudly with exit code 7" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --budget-minutes not-a-number
  [ "$status" -eq 7 ]
}

@test "a non-numeric --repeat fails loudly with exit code 8" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --repeat not-a-number
  [ "$status" -eq 8 ]
}

@test "an option missing its value fails loudly instead of crashing bash's own arity check" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --mode
  [ "$status" -eq 2 ]
  [[ "$output" == *"--mode requires a value"* ]]

  run "$PARSER" --project-root "$FIXTURE_PROJECT" --max-agents
  [ "$status" -eq 2 ]
  [[ "$output" == *"--max-agents requires a value"* ]]
}

@test "path: scope rejects a sibling directory outside the project root (path traversal)" {
  mkdir -p "$TEST_TMPDIR/sibling-project"
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:../sibling-project"
  [ "$status" -eq 3 ]
  [[ "$output" == *"outside project root"* ]]
}

@test "path: scope rejects the project root itself (must be a real subdirectory)" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:."
  [ "$status" -eq 3 ]
}

@test "path: scope rejects a regular file (must be a directory)" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" "path:tests/suite.bats"
  [ "$status" -eq 3 ]
}

@test "--write-plan and --resume are parsed correctly" {
  run "$PARSER" --project-root "$FIXTURE_PROJECT" --write-plan --resume "audit-123"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.write_plan == true and .resume_id == "audit-123"' >/dev/null
}
