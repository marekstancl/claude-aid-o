#!/usr/bin/env bats
# P032 Step 7 — execution.yaml composer + stack auto-detection (Step 1).
# 4 assertions covering the per-stack template fragment system.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  HELPER="$AID_PLUGIN_PATH/scripts/lib/aid-init-execution-yaml.sh"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "stack detection: pyproject.toml → python in detected stacks → execution.yaml has Python gates" {
  touch pyproject.toml
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " python " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"
  run yq '.gates | has("py_test")' .aid-o/config/execution.yaml
  [ "$output" == "true" ]
  run yq '.gates.py_test.command' .aid-o/config/execution.yaml
  [ "$output" == "pytest -q" ]
}

@test "stack detection: package.json → typescript in detected stacks → execution.yaml has TS gates" {
  touch package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"
  run yq '.gates | has("ts_test")' .aid-o/config/execution.yaml
  [ "$output" == "true" ]
  run yq '.gates.ts_lint.command' .aid-o/config/execution.yaml
  [[ "$output" =~ eslint ]]
}

@test "stack detection: bash threshold > 5 (6 *.sh files → bash detected, 5 → not detected)" {
  source "$HELPER"

  # 5 files: NOT detected
  for i in $(seq 1 5); do touch "s_${i}.sh"; done
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ ! " ${stacks[*]} " =~ " bash " ]]

  # 6th file: NOW detected
  touch s_6.sh
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " bash " ]]
}

@test "multi-stack: Python + TypeScript project → execution.yaml has both gate sections in correct order" {
  touch pyproject.toml package.json
  source "$HELPER"
  mapfile -t stacks < <(detect_stacks "$PWD")
  [[ " ${stacks[*]} " =~ " python " ]]
  [[ " ${stacks[*]} " =~ " typescript " ]]

  mkdir -p .aid-o/config
  compose_execution_yaml "$PWD" .aid-o/config/execution.yaml "${stacks[@]}"

  # Both stacks present
  run yq '.gates | keys | join(",")' .aid-o/config/execution.yaml
  [[ "$output" =~ py_test ]]
  [[ "$output" =~ ts_test ]]

  # Order: detect_stacks lists python BEFORE typescript (order: python, ts, go, rust, bash).
  # Section comments preserve detection order.
  python_line=$(grep -n '# === Python' .aid-o/config/execution.yaml | head -1 | cut -d: -f1)
  ts_line=$(grep -n '# === Typescript' .aid-o/config/execution.yaml | head -1 | cut -d: -f1)
  [ "$python_line" -lt "$ts_line" ]
}
