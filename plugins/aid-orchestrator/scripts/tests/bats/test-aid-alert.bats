#!/usr/bin/env bats
# aid-tier: t0
# test-aid-alert.bats — AID speaks with the ecosystem's mandatory fields, and
# says WHICH WORLD the message is about before it says anything else.
#
# The reader's first question, asked out loud after a real night (PM,
# 2026-08-26): "is this about the plan I have running, or about the nightly
# tests?" A free-text message could not answer it, and the ecosystem alert
# standard calls that a defect of the alert rather than of the reader. These
# cases hold the answer in place.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1
  LIB="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/lib/aid-alert.sh"
  export LIB
  TEST_TMPDIR="$(mktemp -d)"; export TEST_TMPDIR
  SENT="$TEST_TMPDIR/sent.txt"; export SENT
  STUB="$TEST_TMPDIR/telegram-notify.sh"
  cat > "$STUB" <<'STUB'
send_alert() {
  { printf 'severity=%s\nscope=%s\nid=%s\n' "$1" "$2" "$3"
    printf 'co=%s\nakce=%s\nkontext=%s\nrunbook=%s\nstate=%s\nsource=%s\n' \
      "$4" "$5" "${6:-}" "${7:-}" "${8:-}" "${9:-}"
  } >> "$SENT"
}
STUB
  export AID_TELEGRAM_LIB="$STUB"
}

teardown() { cd /; [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"; return 0; }

_f() { grep -m1 "^$1=" "$SENT" | cut -d= -f2-; }

@test "a running-plan alert says BĚŽÍCÍ PLÁN, names the EPIC, and is scoped aid-beh" {
  run bash -c 'source "$LIB"; aid_alert_run warning plan-precondition-fail E-089-1_2 \
      "tatáž precondition selhala třikrát." "Do konce dneška rozhodni." "epic=E-089-1_2"'
  [ "$status" -eq 0 ]
  [ "$(_f state)"    = "BĚŽÍCÍ PLÁN" ]
  [ "$(_f scope)"    = "aid-beh" ]
  [ "$(_f id)"       = "plan-precondition-fail" ]
  [ "$(_f severity)" = "warning" ]
  # The subject is prepended to Co, so the reader learns WHICH run immediately.
  [[ "$(_f co)" == E-089-1_2* ]]
}

@test "a nightly alert says NOČNÍ TESTY and is scoped aid-testy — never confusable with a run" {
  run bash -c 'source "$LIB"; aid_alert_nightly warning nightly-red \
      "3 sady spadly." "Do zítřejšího poledne přiděl vlastníka."'
  [ "$status" -eq 0 ]
  [ "$(_f state)" = "NOČNÍ TESTY" ]
  [ "$(_f scope)" = "aid-testy" ]
  [ "$(_f source)" = "noční běh" ]
}

@test "every mandatory field of the standard is filled — none is silently empty" {
  run bash -c 'source "$LIB"; aid_alert_nightly critical nightly-neuplny "Běh se nedokončil." "Zjisti proč."'
  [ "$status" -eq 0 ]
  for f in severity scope id co akce state source; do
    v="$(_f "$f")"
    [ -n "$v" ] || { echo "field '$f' is empty — the standard makes it mandatory"; false; }
  done
}

@test "the Akce of every shipped alert carries a DEADLINE, not just an instruction" {
  # The standard's project rule 1: at a project the action is a decision, and a
  # decision without a deadline leaves the reader unsure whether to get up.
  local fsm="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-fsm.sh"
  local rep="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-nightly-report.sh"
  local n_actions n_deadlines
  n_actions="$(grep -cE '^\s+"(Do |Nic hned)' "$fsm" || true)"
  [ "$n_actions" -ge 5 ]
  # every action line either names a deadline or explicitly says none is needed
  n_deadlines="$(grep -E '^\s+"(Do |Nic hned)' "$fsm" | grep -cE 'Do (konce|zítřejšího|dneška)|Nic hned' || true)"
  [ "$n_actions" -eq "$n_deadlines" ]
  grep -q 'local_action=.*Do zítřejšího poledne' "$rep"
}

@test "a missing shared library says NOT DELIVERED (rc 1) and never kills the caller" {
  # Two separate promises. The wrapper reports the truth — rc 1, so the nightly
  # reporter records notified:false and retries tomorrow — and the FSM discards
  # that status with `|| true` at every call site, so a transition cannot fail
  # because a message could not be sent. Both are asserted here.
  export AID_TELEGRAM_LIB="$TEST_TMPDIR/does-not-exist.sh"
  run bash -c 'source "$LIB"; aid_alert_run critical plan-compliance-blocked E-1_1 "x" "y"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not delivered"* ]]
  run bash -c 'set -euo pipefail; source "$LIB"
    aid_alert_run critical plan-compliance-blocked E-1_1 "x" "y" || true
    echo "survived"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"survived"* ]]
}

@test "a library without send_alert() is refused loudly, not silently downgraded" {
  printf 'send_telegram_alert() { return 0; }\n' > "$TEST_TMPDIR/legacy.sh"
  export AID_TELEGRAM_LIB="$TEST_TMPDIR/legacy.sh"
  run bash -c 'source "$LIB"; aid_alert_nightly warning nightly-red "x" "y"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"defines no send_alert"* ]]
  [ ! -s "$SENT" ]
}

@test "under test mode the PRODUCTION library is refused — a fixture cannot reach the real channel" {
  # No stub: AID_TELEGRAM_LIB falls back to the production path, which test mode
  # refuses outright. This is what replaced an AID_ALERT_FORCE override that any
  # fixture could have inherited next to real credentials.
  unset AID_TELEGRAM_LIB
  run bash -c 'source "$LIB"; aid_alert_nightly critical nightly-red "x" "y"; echo "rc=$?"'
  [[ "$output" == *"rc=2"* ]]
  [ ! -s "$SENT" ]
}

@test "delivery status is REPORTED, not swallowed — a failed send must be retryable" {
  # The first version always returned 0, so the nightly reporter recorded a
  # failed alert as delivered and never retried it.
  printf 'send_alert() { return 7; }\n' > "$TEST_TMPDIR/broken.sh"
  export AID_TELEGRAM_LIB="$TEST_TMPDIR/broken.sh"
  run bash -c 'source "$LIB"; aid_alert_nightly warning nightly-red "x" "y"; echo "rc=$?"'
  [[ "$output" == *"rc=1"* ]]
  run bash -c 'source "$LIB"; aid_alert_nightly warning nightly-red "x" "y"'
  [ "$status" -eq 1 ]
}

@test "the sender runs in a SUBSHELL — a hostile library cannot change the caller's shell" {
  cat > "$TEST_TMPDIR/hostile.sh" <<'H'
set +e
trap 'echo trapped' EXIT
send_alert() { MARKER=leaked; return 0; }
H
  export AID_TELEGRAM_LIB="$TEST_TMPDIR/hostile.sh"
  run bash -c 'set -e; source "$LIB"; MARKER=clean; aid_alert_nightly info nightly-red "x" "y"; echo "marker=$MARKER"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"marker=clean"* ]]
}

@test "an inherited load flag does not leave the helpers undefined" {
  # `_AID_ALERT_SH_LOADED` can arrive through the environment; returning on the
  # flag alone left aid_alert_run undefined — "command not found" inside a state
  # machine under `set -euo pipefail`.
  run bash -c '_AID_ALERT_SH_LOADED=1 
    source "$LIB"
    declare -F aid_alert_run >/dev/null || { echo MISSING; exit 1; }
    echo defined'
  [ "$status" -eq 0 ]
  [[ "$output" == *"defined"* ]]
}

@test "aid-fsm.sh no longer carries its own transport" {
  local fsm="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-fsm.sh"
  # The retired shim may name the port in prose; no live call may POST to it.
  run grep -nE '^[^#]*curl .*localhost:8817' "$fsm"
  [ "$status" -ne 0 ]
}
