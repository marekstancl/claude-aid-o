#!/usr/bin/env bats
# aid-tier: t2
#
# T2 SINCE P099 (docs/plans/P099-merge-path-2026-09.md): the reporter runs only
# in the nightly CI job, so its suite runs there too — a broken reporter shows
# the next morning in /aid-status (NOT RUN / unreadable), not on a merge.
#
# MEASURED 61 s over 12 cases = 5 s per case (nightly journal, 2026-08-15); T0
# is under 2 s per case. Each case drives the real reporter over a real runner
# log.
# test-aid-nightly-report.bats — P081 Step 7: the nightly result is durable;
# since P099 it sends no message at all.
#
# WHAT THIS SUITE PROVES, in the order it matters:
#   * the artifact is written on every night, green or red, and it lands on the
#     SHARED host path — not under `.aid-o/`, which no CI job could ever write
#     somewhere the PM's checkout can read;
#   * no night, green or red, reaches Telegram;
#   * the SAME failure the next night counts a streak;
#   * a suite that passes on its single retry is flaky and quarantined — a
#     third state, neither a failure nor a green run.
#
# Fixture suites are written with printf, never a heredoc (IMP-494).
#
# Result count after any edit:
#   bats --tap test-aid-nightly-report.bats | grep -cE '^(ok|not ok)'   # == 8

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

  # A stub for the shared ecosystem helper: any call it records is a message
  # the nightly must no longer send.
  STUB_TG="$TEST_TMPDIR/telegram-notify.sh"
  printf 'send_alert() { echo "$3" >> "$SENT"; }\n' > "$STUB_TG"
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
  [ ! -e "$ROOT/.aid-o/work/nightly" ]
}

@test "2: a red night records the failure and sends nothing" {
  _mk_bats "$FIXTURE_TESTS/bats/test-red.bats" false
  run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.failed[0].suite' "$NIGHTLY_DIR/latest.json")" = "test-red" ]
  [ "$(jq -r '.failed[0].streak' "$NIGHTLY_DIR/latest.json")" = "1" ]
  [ ! -e "$SENT" ]
}

@test "3: the same failure the next night counts a streak" {
  _mk_bats "$FIXTURE_TESTS/bats/test-red.bats" false
  _report "$(_log 2 3 test-red)" --exit-code 1
  run _report "$(_log 2 3 test-red)" --exit-code 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.failed[0].streak' "$NIGHTLY_DIR/latest.json")" = "2" ]
}

@test "4: a suite that passes on its single retry is flaky and quarantined" {
  # The retry goes through the RUNNER now, not a bare `bats` — a suite that
  # fails only under runner conditions must not be laundered into a silent
  # quarantine. The fixture supplies a stub runner so the flaky path is still
  # exercised; without a reachable runner the suite stays FAILED by design.
  cat > "$TEST_TMPDIR/stub-runner.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TEST_TMPDIR/stub-runner.sh"
  export AID_NIGHTLY_RUNNER="$TEST_TMPDIR/stub-runner.sh"
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

@test "6c: a suite that keeps flaking does NOT reset its own age" {
  _quarantine test-old.bats 14
  bash "$QUARANTINE" add test-old.bats ""      # tonight it flaked again
  [ "$(bash "$QUARANTINE" list --json | jq -r '.[0].age_days')" -eq 14 ]
  [ "$(bash "$QUARANTINE" list --json | jq 'length')" -eq 1 ]
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

@test "4b: with no reachable runner a retry does NOT launder a failure into flaky" {
  # The defect this closes: the retry used to re-run `bats "$path"` bare, so a
  # suite that fails only under the runner's own conditions passed standalone,
  # was filed flaky, dropped out of failed[] and the night reported GREEN.
  export AID_NIGHTLY_RUNNER="/nonexistent/runner.sh"
  _mk_bats "$FIXTURE_TESTS/bats/test-wobbly.bats" true
  run _report "$(_log 2 3 test-wobbly)" --exit-code 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.failed | length' "$NIGHTLY_DIR/latest.json")" -ge 1 ]
  [ "$(jq -r '.flaky | length' "$NIGHTLY_DIR/latest.json")" = "0" ]
}
