#!/usr/bin/env bats
# aid-tier: t0
# test-aid-alert.bats — AID sends two messages and only two: the agent is
# waiting for the PM, and the plan is delivered (P099 Step 3). Both carry the
# ecosystem standard's mandatory fields; a waiting message goes out once per
# stop whichever session ends its turn, and again only after the PM answered.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1
  LIB="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/lib/aid-alert.sh"
  TEST_TMPDIR="$(mktemp -d)"
  SENT="$TEST_TMPDIR/sent.txt"
  export LIB TEST_TMPDIR SENT AID_SESSION_STORE="$TEST_TMPDIR/store"
  cat > "$TEST_TMPDIR/telegram-notify.sh" <<'STUB'
send_alert() {
  { printf 'severity=%s\nscope=%s\nid=%s\n' "$1" "$2" "$3"
    printf 'co=%s\nakce=%s\nstate=%s\nsource=%s\n' "$4" "$5" "${8:-}" "${9:-}"
  } >> "$SENT"
}
STUB
  export AID_TELEGRAM_LIB="$TEST_TMPDIR/telegram-notify.sh"
  mkdir -p "$TEST_TMPDIR/wan"; cd "$TEST_TMPDIR/wan"; git init -q
}

teardown() { cd /; [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"; return 0; }

_f() { grep -m1 "^$1=" "$SENT" | cut -d= -f2-; }
_sent() { grep -c '^id=' "$SENT" 2>/dev/null || echo 0; }

@test "the waiting message carries every mandatory field, names the plan and the next action" {
  run bash -c 'source "$LIB"; aid_alert_waiting P900 "rozhodnutí o kroku 3" "odpověz v session"'
  [ "$status" -eq 0 ]
  [ "$(_f id)" = agent-waiting ]; [ "$(_f severity)" = warning ]; [ "$(_f state)" = "ČEKÁ NA TEBE" ]
  [ "$(_f scope)" = wan-aid ]; [ "$(_f source)" = "AID · wan" ]
  [[ "$(_f co)" == "P900: agent stojí — rozhodnutí o kroku 3" ]]; [ "$(_f akce)" = "odpověz v session" ]
}

@test "the project is the main checkout, also from a linked worktree" {
  git commit -q --allow-empty -m init; git worktree add -q "$TEST_TMPDIR/plan-P900" 2>/dev/null
  run bash -c 'cd "$TEST_TMPDIR/plan-P900"; source "$LIB"; aid_alert_waiting P900 x y'
  [ "$(_f scope)" = wan-aid ]
}

@test "one waiting message per stop across sessions; the PM's answer re-arms it" {
  bash -c 'source "$LIB"; aid_alert_waiting P900 a b'
  bash -c 'source "$LIB"; aid_alert_waiting P900 a b'          # another session, same stop
  [ "$(_sent)" -eq 1 ]
  bash -c 'source "$LIB"; aid_alert_waiting P901 a b'          # another plan
  [ "$(_sent)" -eq 2 ]
  bash -c 'source "$LIB"; aid_alert_waiting_clear P900; aid_alert_waiting P900 a b'
  [ "$(_sent)" -eq 3 ]
}

@test "delivered is sent once per plan and says when the close was forced" {
  bash -c 'source "$LIB"; aid_alert_delivered P900 /ev/P900; aid_alert_delivered P900 /ev/P900'
  [ "$(_sent)" -eq 1 ]; [ "$(_f id)" = plan-delivered ]; [ "$(_f severity)" = info ]
  [ "$(_f co)" = "P900 dodán" ]; [ "$(_f akce)" = "stránka dodávky: /ev/P900" ]
  bash -c 'source "$LIB"; aid_alert_delivered P901 /ev/P901 forced'
  grep -q '^co=P901 dodán (uzavřen vynuceně)$' "$SENT"
}

@test "a failed send returns 1, is recorded, keeps the record closed, and never kills the caller" {
  printf 'send_alert() { return 7; }\n' > "$TEST_TMPDIR/broken.sh"
  AID_TELEGRAM_LIB="$TEST_TMPDIR/broken.sh" run bash -c 'set -euo pipefail; source "$LIB"; aid_alert_waiting P900 a b || echo "rc=$?"; echo survived'
  [[ "$output" == *"rc=1"*"survived"* ]]
  jq -e '.plan == "P900" and .id == "agent-waiting"' "$AID_SESSION_STORE/alerts/failures.jsonl"
  bash -c 'source "$LIB"; aid_alert_waiting P900 a b'
  [ "$(_sent)" -eq 1 ]
}

@test "a missing library or one without send_alert() is not delivered, said on stderr" {
  AID_TELEGRAM_LIB="$TEST_TMPDIR/none.sh" run bash -c 'source "$LIB"; aid_alert_waiting P900 a b'
  [ "$status" -eq 1 ]; [[ "$output" == *"not delivered"* ]]
  printf 'send_telegram_alert() { return 0; }\n' > "$TEST_TMPDIR/legacy.sh"
  AID_TELEGRAM_LIB="$TEST_TMPDIR/legacy.sh" run bash -c 'source "$LIB"; aid_alert_waiting P901 a b'
  [ "$status" -eq 1 ]; [[ "$output" == *"defines no send_alert"* ]]
}

@test "under test mode the production library is refused (rc 2)" {
  unset AID_TELEGRAM_LIB
  run bash -c 'source "$LIB"; aid_alert_delivered P900 x; echo "rc=$?"'
  [[ "$output" == *"rc=2"* ]]; [ ! -s "$SENT" ]
}

@test "the sender runs in a subshell, and an inherited load flag does not hide the helpers" {
  printf 'send_alert() { MARKER=leaked; }\n' > "$TEST_TMPDIR/hostile.sh"
  AID_TELEGRAM_LIB="$TEST_TMPDIR/hostile.sh" run bash -c 'source "$LIB"; MARKER=clean; aid_alert_waiting P900 a b; echo "marker=$MARKER"'
  [[ "$output" == *"marker=clean"* ]]
  run bash -c '_AID_ALERT_SH_LOADED=1; source "$LIB"; declare -F aid_alert_waiting aid_alert_delivered'
  [ "$status" -eq 0 ]
}

@test "the library sends exactly two kinds of message, and no AID script sends another" {
  [ "$(grep -c '^  _aid_alert_once ' "$LIB")" -eq 2 ]
  local scripts; scripts="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  run grep -rnE 'aid_alert_(run|nightly)|try_telegram_alert|send_alert ' "$scripts" --include=*.sh
  [ -z "$(echo "$output" | grep -v '/tests/\|lib/aid-alert.sh')" ]
}
