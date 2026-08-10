#!/usr/bin/env bats
# test-aid-nightly-report.bats — P081 Step 7: the nightly result is durable
# and the message is rare.
#
# WHAT THIS SUITE PROVES, in the order it matters:
#   * the artifact is written on every night, green or red, and it lands on the
#     SHARED host path — not under `.aid-o/`, which no CI job could ever write
#     somewhere the PM's checkout can read;
#   * a green night is silent;
#   * a red night sends exactly one message, and the SAME failure the next
#     night counts a streak instead of sending again;
#   * a suite that passes on its single retry is flaky and quarantined — a
#     third state, neither a failure nor a green run;
#   * a quarantine entry that ages past its deadline with no owner escalates
#     even on an otherwise quiet night;
#   * a missing Telegram helper degrades to a warning; the job still passes and
#     the artifact still says the message was missed.
#
# Fixture suites are written with printf, never a heredoc (IMP-494).
#
# Result count after any edit:
#   bats --tap test-aid-nightly-report.bats | grep -cE '^(ok|not ok)'   # == 11

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REPORT="$AID_PLUGIN_PATH/scripts/aid-nightly-report.sh"
  QUARANTINE="$AID_PLUGIN_PATH/scripts/aid-test-quarantine.sh"
  export AID_PLUGIN_PATH REPORT QUARANTINE
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  NIGHTLY_DIR="$TEST_TMPDIR/nightly"
  FIXTURE_TESTS="$TEST_TMPDIR/suites"
  SENT="$TEST_TMPDIR/sent.txt"
  export TEST_TMPDIR ROOT NIGHTLY_DIR FIXTURE_TESTS SENT
  export AID_NIGHTLY_DIR="$NIGHTLY_DIR"
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$FIXTURE_TESTS/bats" "$NIGHTLY_DIR"
  cd "$ROOT"

  # A stub for the shared ecosystem helper — this suite must never reach a real
  # Telegram API, and it must be able to see whether a message was attempted.
  STUB_TG="$TEST_TMPDIR/telegram-notify.sh"
  printf 'send_telegram_alert() { printf "%%s\\n" "$1" >> "$SENT"; return 0; }\n' > "$STUB_TG"
  export AID_TELEGRAM_LIB="$STUB_TG"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _log <passed> <run> <failed suite name…> — a runner log of that shape.
_log() {
  local passed="$1" total="$2"; shift 2
  local f="$TEST_TMPDIR/run.log"
  printf '  Summary\n\n  Suites:  %s/%s passed, %s failed\n' "$passed" "$total" "$(( total - passed ))" > "$f"
  if [[ $# -gt 0 ]]; then
    printf '  Failed suites:\n' >> "$f"
    local s; for s in "$@"; do printf '    - %s\n' "$s" >> "$f"; done
    printf '\n' >> "$f"
  fi
  printf '%s\n' "$f"
}

_mk_bats() {
  local path="$1" body="$2"
  printf '#!/usr/bin/env bats\n' > "$path"
  printf '@test "case" { %s; }\n' "$body" >> "$path"
}

# _quarantine <suite> <days ago> — an ownerless open entry of that exact age.
_quarantine() {
  jq -nc --arg s "$1" --arg d "$(date -u -d "$2 days ago" +%Y-%m-%d)" \
    '{action:"add", suite:$s, owner:"", opened:$d, at:($d + "T00:00:00Z")}' \
    > "$NIGHTLY_DIR/quarantine.jsonl"
}

_report() {
  bash "$REPORT" --runner-log "$1" --tests-dir "$FIXTURE_TESTS" \
    --dir "$NIGHTLY_DIR" "${@:2}" 3>&-
}

@test "1: a green night writes the artifact on the shared path and sends nothing" {
  run _report "$(_log 3 3)" --exit-code 0
  [ "$status" -eq 0 ]
  [ -f "$NIGHTLY_DIR/latest.json" ]
  [ ! -e "$SENT" ]
  [ "$(jq -r '.failed | length' "$NIGHTLY_DIR/latest.json")" = "0" ]
  [ "$(jq -r '.notified' "$NIGHTLY_DIR/latest.json")" = "false" ]
  [ ! -e "$ROOT/.aid-o/work/nightly" ]
}

@test "2: a red night sends exactly one message and records the failure" {
  _mk_bats "$FIXTURE_TESTS/bats/test-red.bats" false
  run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.failed[0].suite' "$NIGHTLY_DIR/latest.json")" = "test-red" ]
  [ "$(jq -r '.failed[0].streak' "$NIGHTLY_DIR/latest.json")" = "1" ]
  [ "$(jq -r '.notified' "$NIGHTLY_DIR/latest.json")" = "true" ]
  [ "$(grep -c '' "$SENT")" -ge 1 ]
  [ "$(grep -c 'AID nightly' "$SENT")" -eq 1 ]
}

@test "3: the same failure the next night counts a streak instead of re-sending" {
  _mk_bats "$FIXTURE_TESTS/bats/test-red.bats" false
  _report "$(_log 2 3 test-red)" --exit-code 1
  rm -f "$SENT"
  run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.failed[0].streak' "$NIGHTLY_DIR/latest.json")" = "2" ]
  [ ! -e "$SENT" ]
  [ "$(jq -r '.notified' "$NIGHTLY_DIR/latest.json")" = "false" ]
}

@test "4: a suite that passes on its single retry is flaky and quarantined" {
  _mk_bats "$FIXTURE_TESTS/bats/test-wobbly.bats" true
  run _report "$(_log 2 3 test-wobbly)" --exit-code 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.failed | length' "$NIGHTLY_DIR/latest.json")" = "0" ]
  [ "$(jq -r '.flaky[0]' "$NIGHTLY_DIR/latest.json")" = "test-wobbly" ]
  [ "$(jq -r '.quarantined[0].suite' "$NIGHTLY_DIR/latest.json")" = "test-wobbly" ]
}

@test "5: the quarantine count appears in every report, green nights included" {
  bash "$QUARANTINE" add test-wobbly.bats someone
  run _report "$(_log 3 3)" --exit-code 0
  [ "$status" -eq 0 ]
  [ "$(jq -r '.quarantined | length' "$NIGHTLY_DIR/latest.json")" = "1" ]
  [ "$(jq -r '.quarantined[0].owner' "$NIGHTLY_DIR/latest.json")" = "someone" ]
  [ ! -e "$SENT" ]
}

@test "6: an ownerless quarantine escalates the night it crosses its deadline" {
  _quarantine test-old.bats 14
  run _report "$(_log 3 3)" --exit-code 0
  [ "$status" -eq 0 ]
  [ -e "$SENT" ]
  [[ "$(cat "$SENT")" == *"no owner"* ]]
  [[ "$(cat "$SENT")" == *"test-old.bats"* ]]
}

@test "6b: and then weekly, not every night — a daily repeat mutes the channel" {
  _quarantine test-old.bats 15          # one night past the crossing
  run _report "$(_log 3 3)" --exit-code 0
  [ "$status" -eq 0 ]
  [ ! -e "$SENT" ]

  _quarantine test-old.bats 21          # a week after the crossing
  run _report "$(_log 3 3)" --exit-code 0
  [ "$status" -eq 0 ]
  [ -e "$SENT" ]
}

@test "6c: a suite that keeps flaking does NOT reset its own age" {
  _quarantine test-old.bats 14
  bash "$QUARANTINE" add test-old.bats ""      # tonight it flaked again
  [ "$(bash "$QUARANTINE" list --json | jq -r '.[0].age_days')" -eq 14 ]
  [ "$(bash "$QUARANTINE" list --json | jq 'length')" -eq 1 ]
}

@test "7: a missing Telegram helper is a warning, not a failed job" {
  _mk_bats "$FIXTURE_TESTS/bats/test-red.bats" false
  AID_TELEGRAM_LIB="$TEST_TMPDIR/does-not-exist.sh" \
    run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$status" -eq 0 ]
  [ -f "$NIGHTLY_DIR/latest.json" ]
  [ "$(jq -r '.notified' "$NIGHTLY_DIR/latest.json")" = "false" ]
}

@test "7b: a failure whose message never got out is re-sent, not counted silent" {
  _mk_bats "$FIXTURE_TESTS/bats/test-red.bats" false
  # Night one: the helper is missing, so nothing is delivered.
  AID_TELEGRAM_LIB="$TEST_TMPDIR/does-not-exist.sh" \
    run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$(jq -r '.notified' "$NIGHTLY_DIR/latest.json")" = "false" ]
  [ ! -e "$SENT" ]

  # Night two: the helper is back. The failure is "known", but it was never
  # actually reported — silence here would make the outage permanent.
  run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$status" -eq 0 ]
  [ -e "$SENT" ]
  [ "$(jq -r '.notified' "$NIGHTLY_DIR/latest.json")" = "true" ]
}

@test "8: a run cut short is recorded censored, never as a green night" {
  f="$TEST_TMPDIR/partial.log"
  printf 'Suite 1/194: test-a\n  [PASS] 1/1 passed, 0 failed\n' > "$f"
  run _report "$f" --exit-code 137
  [ "$status" -eq 0 ]
  [ "$(jq -r '.censored' "$NIGHTLY_DIR/latest.json")" = "true" ]
  [ "$(jq -r '.exit_code' "$NIGHTLY_DIR/latest.json")" = "137" ]
  [ "$(jq -r '.failed[0].suite' "$NIGHTLY_DIR/latest.json")" = "(runner)" ]
}
