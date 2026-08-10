#!/usr/bin/env bats
# test-nightly-reminder.bats — P081 Step 8: the second surface.
#
# WHAT THIS SUITE PROVES: the nightly result is stated where work starts, in
# exactly one line, in every state — and in NO line when there is nothing to
# state. The negative case carries real weight: a fresh project with no nightly
# is not in a red state, and a surface that shouted at it would be turned off
# within a week.
#
# The renderer under test is the one `/aid-status` actually uses: the recipes
# are extracted from `commands/aid-status.md`, exactly as
# test-status-two-streams.bats does, because in this plugin the command file IS
# the implementation.
#
# The last case is not a fixture: it runs the REAL aid-nightly-report.sh to
# produce the artifact and then renders THAT through the real recipe, so the
# producer and the consumer are proved to agree on a path and a schema rather
# than each being proved against a file this suite wrote itself.
#
# FD-3 HYGIENE: every `run bash -c` closes fd 3. Result count after any edit:
#   bats --tap test-nightly-reminder.bats | grep -cE '^(ok|not ok)'   # == 8

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DOC="$AID_PLUGIN_PATH/commands/aid-status.md"
  REPORT="$AID_PLUGIN_PATH/scripts/aid-nightly-report.sh"
  export DOC REPORT
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  NIGHTLY_DIR="$TEST_TMPDIR/nightly"
  export TEST_TMPDIR ROOT NIGHTLY_DIR
  export AID_NIGHTLY_DIR="$NIGHTLY_DIR"
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$NIGHTLY_DIR"
  cd "$ROOT"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _recipes — every `# recipe:` block body from the command file, in file order.
_recipes() {
  awk '
    /^# recipe: / { inblk = 1; print; next }
    inblk && /^```$/ { inblk = 0; next }
    inblk { print }
  ' "$DOC"
}

# _line — the nightly line the shipped recipe renders here, if any.
_line() {
  local body; body="$(_recipes)"
  run bash -c "cd '$ROOT' && $body
declare -F nightly_line >/dev/null || { echo 'MISSING: nightly_line is not defined by aid-status.md' >&2; exit 1; }
nightly_line" 3>&-
}

# _artifact <date> <failed json> [quarantined json] — a nightly result.
_artifact() {
  jq -n --arg d "$1" --argjson f "$2" --argjson q "${3:-[]}" \
    '{date:$d, suites_run:10, passed:10, failed:$f, flaky:[], quarantined:$q,
      duration_ms:1, exit_code:0, censored:false, log_url:"", notified:false}' \
    > "$NIGHTLY_DIR/latest.json"
}

_today() { date -u +%Y-%m-%d; }

@test "1: no artifact renders nothing at all — a fresh project is not red" {
  _line
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "2: a green night renders one line with its date" {
  _artifact "$(_today)" '[]'
  _line
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 1 ]
  [[ "$output" == "Nightly: green ($(_today))" ]]
}

@test "3: a red night names the count and the worst streak" {
  _artifact "$(_today)" '[{"suite":"test-a","streak":4},{"suite":"test-b","streak":1}]'
  _line
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 1 ]
  [[ "$output" == *"RED ($(_today))"* ]]
  [[ "$output" == *"2 suite(s) failing"* ]]
  [[ "$output" == *"worst streak 4"* ]]
  [[ "$output" == *"$NIGHTLY_DIR/$(_today).json"* ]]
}

@test "4: a non-empty quarantine record shows its count" {
  _artifact "$(_today)" '[]' '[{"suite":"test-wobbly","owner":"","age_days":3}]'
  _line
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 quarantined"* ]]
}

@test "5: a nightly that stopped running is itself the finding" {
  _artifact "2026-01-01" '[]'
  _line
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 1 ]
  [[ "$output" == *"NOT RUN since 2026-01-01"* ]]
  [[ "$output" == *"days"* ]]
}

@test "6: an unreadable artifact says so and names the path — never a verdict" {
  printf 'not json\n' > "$NIGHTLY_DIR/latest.json"
  _line
  [ "$status" -eq 0 ]
  [[ "$output" == *"unreadable"* ]]
  [[ "$output" == *"$NIGHTLY_DIR/latest.json"* ]]
  [[ "$output" != *"green"* ]]
  [[ "$output" != *"RED"* ]]
}

@test "7: the line leaves every other overview row untouched" {
  local body; body="$(_recipes)"
  run bash -c "cd '$ROOT' && $body && render_overview" 3>&-
  [ "$status" -eq 0 ]
  before="$output"
  _artifact "$(_today)" '[]'
  run bash -c "cd '$ROOT' && $body && render_overview" 3>&-
  [ "$status" -eq 0 ]
  # Exactly one line added, and it is the nightly line.
  [ "$(( $(grep -c '' <<<"$output") - $(grep -c '' <<<"$before") ))" -eq 2 ]
  diff <(grep -v '^Nightly:' <<<"$output" | grep -v '^$') \
       <(grep -v '^$' <<<"$before")
}

@test "8: END TO END — the real reporter's artifact is what the real status reads" {
  printf '  Summary\n\n  Suites:  3/3 passed, 0 failed\n' > "$TEST_TMPDIR/run.log"
  run bash "$REPORT" --runner-log "$TEST_TMPDIR/run.log" --exit-code 0 \
    --dir "$NIGHTLY_DIR" --tests-dir "$AID_PLUGIN_PATH/scripts/tests" --no-notify 3>&-
  [ "$status" -eq 0 ]
  _line
  [ "$status" -eq 0 ]
  [[ "$output" == "Nightly: green ($(_today))" ]]
}
