#!/usr/bin/env bats
# aid-tier: t2
# Tests for scope-check.sh

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  TEST_DIR=$(mktemp -d)
  # Store allowed file OUTSIDE the git repo so git diff doesn't include it
  ALLOWED_FILE=$(mktemp)
  echo "src/**" > "$ALLOWED_FILE"
  echo "tests/**" >> "$ALLOWED_FILE"
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -m "base"
  BASE_COMMIT=$(git rev-parse HEAD)
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -f "$ALLOWED_FILE"
}


@test "passes when no files changed" {
  run "$SCRIPT_DIR/gates/scope-check.sh" "$ALLOWED_FILE" "$BASE_COMMIT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result == "pass"'
}

@test "passes when all changes within allowed paths" {
  mkdir -p src; echo "code" > src/main.ts
  git add -A; git commit -m "change"
  run "$SCRIPT_DIR/gates/scope-check.sh" "$ALLOWED_FILE" "$BASE_COMMIT"
  [ "$status" -eq 0 ]
}

@test "fails when file outside allowed paths" {
  echo "change" > README.md
  git add -A; git commit -m "change"
  run "$SCRIPT_DIR/gates/scope-check.sh" "$ALLOWED_FILE" "$BASE_COMMIT"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "exits 1 with error JSON if allowed_paths_file missing" {
  run "$SCRIPT_DIR/gates/scope-check.sh" "/nonexistent/file" "$BASE_COMMIT"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.result == "fail"'
}

@test "exits non-zero without arguments" {
  run "$SCRIPT_DIR/gates/scope-check.sh"
  [ "$status" -ne 0 ]
}
