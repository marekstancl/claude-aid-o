#!/usr/bin/env bats
# Tests for aid-token-count.sh

setup() {
  TEST_DIR=$(mktemp -d)
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  source "$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-token-count.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "outputs valid JSON with estimated_tokens > 0 for non-empty text" {
  run count_tokens "hello world this is a test sentence with some content"
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.estimated_tokens > 0'"
  [ "$status" -eq 0 ]
}

@test "code content type produces more tokens than prose for same input" {
  local text="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  prose_tokens=$(count_tokens "$text" prose | jq '.estimated_tokens')
  code_tokens=$(count_tokens "$text" code | jq '.estimated_tokens')
  # code ratio=3.0 gives more tokens than prose ratio=4.0
  [ "$code_tokens" -gt "$prose_tokens" ]
}

@test "works as sourced library with text argument" {
  run count_tokens "hello world" prose
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.content_type == \"prose\"'"
  [ "$status" -eq 0 ]
}

@test "works with file input" {
  echo "This is test file content for token counting." > "$TEST_DIR/test.txt"
  run count_tokens "$TEST_DIR/test.txt"
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.estimated_tokens > 0'"
  [ "$status" -eq 0 ]
}

@test "unknown content type defaults to mixed" {
  run count_tokens "some text" unknown_type
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.content_type == \"mixed\"'"
  [ "$status" -eq 0 ]
}

@test "ratio field matches content type" {
  run count_tokens "test" prose
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.ratio == 4.0'"
  [ "$status" -eq 0 ]
}

@test "ratio for code is 3.0" {
  run count_tokens "test" code
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.ratio == 3.0'"
  [ "$status" -eq 0 ]
}

@test "ratio for mixed is 3.5" {
  run count_tokens "test" mixed
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.ratio == 3.5'"
  [ "$status" -eq 0 ]
}

@test "char_count matches text length" {
  local text="12345"
  run count_tokens "$text"
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.char_count == 5'"
  [ "$status" -eq 0 ]
}

@test "direct invocation as script works" {
  run bash "$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-token-count.sh" "hello world" prose
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.estimated_tokens > 0'"
  [ "$status" -eq 0 ]
}
