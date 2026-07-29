#!/usr/bin/env bats
# test-aid-test-adapter-package-script.bats — P066 Step 3.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-adapter-package-script.sh"
  FIXTURE_DIR="$TEST_TMPDIR/pkgscript-fixture"
  mkdir -p "$FIXTURE_DIR"
}

teardown() {
  teardown_test_evidence_dir
}

@test "package_script_adapter_discover: a package.json-only fixture (no Bats) produces a non-empty, schema-valid run_units array" {
  cat > "$FIXTURE_DIR/package.json" <<'JSON'
{
  "name": "fixture",
  "scripts": {
    "test": "vitest run",
    "test:e2e": "playwright test",
    "build": "tsc -b"
  }
}
JSON
  run package_script_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq 'length')"
  [ "$count" -eq 2 ]
  echo "$output" | jq -e 'any(.[]; .run_unit_id == "npm:test")' >/dev/null
  echo "$output" | jq -e 'any(.[]; .run_unit_id == "npm:test:e2e")' >/dev/null
  echo "$output" | jq -e 'all(.[]; .command.type == "argv")' >/dev/null
}

@test "package_script_adapter_discover: a project with no test-shaped script and no CI job reports empty inventory" {
  cat > "$FIXTURE_DIR/package.json" <<'JSON'
{"name": "fixture", "scripts": {"build": "tsc -b"}}
JSON
  run package_script_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 0 ]
}

@test "package_script_adapter_discover: a CI run: line matching multiple runner keywords splits into multiple entries" {
  mkdir -p "$FIXTURE_DIR/.github/workflows"
  cat > "$FIXTURE_DIR/.github/workflows/ci.yml" <<'YML'
name: CI
jobs:
  test:
    steps:
      - run: pytest tests/ && go test ./...
YML
  run package_script_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  local count
  count="$(echo "$output" | jq '[.[] | select(.runner == "ci")] | length')"
  [ "$count" -eq 2 ]
}

@test "package_script_adapter_discover: a block-style (run: |) CI step still discovers the runner keyword" {
  mkdir -p "$FIXTURE_DIR/.github/workflows"
  cat > "$FIXTURE_DIR/.github/workflows/ci.yml" <<'YML'
name: CI
jobs:
  test:
    steps:
      - name: Run tests
        run: |
          cd project
          pytest tests/ -v
YML
  run package_script_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[] | select(.runner == "ci")] | length')" -eq 1 ]
  echo "$output" | jq -e '.[] | select(.runner == "ci") | .command.shell | contains("pytest tests/")' >/dev/null
}

@test "package_script_adapter_discover: a single-runner CI run: line produces exactly one entry" {
  mkdir -p "$FIXTURE_DIR/.github/workflows"
  cat > "$FIXTURE_DIR/.github/workflows/ci.yml" <<'YML'
name: CI
jobs:
  test:
    steps:
      - run: jest --ci
YML
  run package_script_adapter_discover "$FIXTURE_DIR"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[] | select(.runner == "ci")] | length')" -eq 1 ]
}
