#!/usr/bin/env bats
# aid-tier: t2
# Tests for aid-stage-log.sh

setup() {
  TEST_DIR=$(mktemp -d)
  TIMELINE="$TEST_DIR/timeline.jsonl"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  source "$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-stage-log.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "creates valid JSONL entry with string value" {
  log_event "$TIMELINE" "step_dispatch" state=EXECUTE role=architect
  run jq -e '.event == "step_dispatch"' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "numeric values are not quoted in JSON" {
  log_event "$TIMELINE" "step_complete" duration_s=120
  run jq -e '.duration_s == 120' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "boolean values are not quoted in JSON" {
  log_event "$TIMELINE" "gate_run" required=true
  run jq -e '.required == true' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "never exits non-zero even with invalid timeline path" {
  run log_event "/nonexistent/dir/timeline.jsonl" "test_event"
  [ "$status" -eq 0 ]
}

@test "special characters in values are escaped" {
  log_event "$TIMELINE" "test" 'message=hello "world"'
  run jq -e '.message == "hello \"world\""' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "multiple events produce valid JSONL (one per line)" {
  log_event "$TIMELINE" "event_1" step=1
  log_event "$TIMELINE" "event_2" step=2
  run jq -s 'length == 2' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "entry has ts and event fields" {
  log_event "$TIMELINE" "my_event"
  run jq -e 'has("ts") and has("event")' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "null value is not quoted" {
  log_event "$TIMELINE" "test_null" result=null
  run jq -e '.result == null' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "value containing = sign uses everything after first =" {
  log_event "$TIMELINE" "test_eq" expr=a=b
  run jq -e '.expr == "a=b"' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "concurrent writes all produce valid JSON lines" {
  for i in $(seq 1 20); do
    log_event "$TIMELINE" "concurrent" idx=$i &
  done
  wait
  # Each line must be valid JSON
  run bash -c "while IFS= read -r line; do echo \"\$line\" | jq -e . > /dev/null || exit 1; done < '$TIMELINE'"
  [ "$status" -eq 0 ]
  # At least some events were written
  local count
  count=$(wc -l < "$TIMELINE")
  [ "$count" -gt 0 ]
}
