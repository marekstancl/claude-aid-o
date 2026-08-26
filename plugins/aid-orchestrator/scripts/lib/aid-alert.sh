#!/usr/bin/env bash
# =============================================================================
# lib/aid-alert.sh — THE one way AID speaks to a human outside the terminal
#
# WHY THIS FILE EXISTS. Until 2026-08-26 AID had two senders and neither obeyed
# the ecosystem alert standard:
#   * aid-nightly-report.sh sourced the shared telegram library but called the
#     LEGACY `send_telegram_alert "<free text>"`, so its message carried no
#     severity, host, scope, ID, "Co" or "Akce";
#   * aid-fsm.sh had its own `try_telegram_alert`, POSTing straight to the MCP
#     bot on localhost:8817 — a second transport as well as a second format.
# The result is documented in the standard itself: a reader had to ask "is this
# from the tests, or from something else?", which the standard calls a defect of
# the alert, not of the reader.
#
# THE STANDARD: /ecosystem/operations/alerting-and-automation §2. Mandatory
# fields are severity+emoji, state, source, host, scope, ID, Co, Akce. The
# shared `send_alert()` in /opt/eco/services/scripts/lib/telegram-notify.sh
# assembles them; nothing here formats a message by hand, because a sender that
# concatenates its own text is a sender that can get the format wrong.
#
# WHAT THIS ADDS ON TOP, and why it is not just a call to send_alert:
#
#   1. THE FIRST LINE SAYS WHICH WORLD THIS IS ABOUT (PM, 2026-08-26). The
#      standard's `state` field is free, so AID spends it on the one question
#      its reader actually has: is this my RUNNING PLAN, or last night's TESTS?
#      `aid_alert_run` renders "BĚŽÍCÍ PLÁN", `aid_alert_nightly` renders
#      "NOČNÍ TESTY" — before host, before scope, before a word of prose.
#   2. IT DEGRADES, NEVER FAILS. AID ships as a plugin into projects that have
#      no /opt/eco/services at all. A missing library is a skipped alert and a
#      note on stderr — never a non-zero return into a state machine that is
#      mid-transition. This is the contract `try_telegram_alert` already had and
#      the one thing about it worth keeping.
#   3. AID_TEST_MODE=1 SUPPRESSES THE PRODUCTION PATH so fixtures never reach the
#      real channel. A fixture that points AID_TELEGRAM_LIB at its own stub gets
#      genuine (stubbed) delivery and an honest return code.
#      AID_ALERT_SINK=<file> records what WOULD have been sent, so a test can
#      assert on the composed message instead of on the fact that nothing blew
#      up.
#
# SCOPES — the PROJECT and the part, never one without the other:
#   <projekt>-aid-beh     a plan/EPIC that is running RIGHT NOW
#   <projekt>-aid-testy   the nightly test portfolio
#
# The project half was added on 2026-08-26, when the PM asked the obvious next
# question: this plugin is installed per project, so the day AID also runs over
# WAN or Sousto, two identically-shaped messages arrive and nothing in either
# says which repository they came from. `Host` is the machine, not the project.
# The standard's own project rule is the same point one level down — `wan` is
# too coarse when it covers the nightly, the dependency check and an account
# lock at once — so `wan-aid-beh` says both halves: whose, and which part.
#
# The name is the git top-level directory, which needs no configuration and is
# what a human calls the project. The `source` field carries it too, so the
# FIRST line already reads "AID · wan".

# _aid_alert_project — the project this AID is running over. Never fails: an
# unnamed project is still an alert worth sending, it just says "projekt".
_aid_alert_project() {
  local top name
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  [[ -n "$top" ]] || top="$PWD"
  name="$(basename "$top")"
  # Scope is read by humans and grouped by machines; keep it to the characters
  # both handle without quoting.
  name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')"
  printf '%s' "${name:-projekt}"
}
#
# Sourced, never executed. Re-source safe.
# =============================================================================
# The guard checks for the FUNCTIONS, not just the flag: `_AID_ALERT_SH_LOADED`
# can arrive through an inherited environment, and returning on the flag alone
# would leave aid_alert_run undefined — "command not found" inside a state
# machine running under `set -euo pipefail`, mid-transition. (Cross-model
# review, 2026-08-26.)
if [[ -n "${_AID_ALERT_SH_LOADED:-}" ]] && declare -F aid_alert_run >/dev/null 2>&1; then
  return 0
fi
_AID_ALERT_SH_LOADED=1

_AID_ALERT_PRODUCTION_LIB="/opt/eco/services/scripts/lib/telegram-notify.sh"
AID_ALERT_TELEGRAM_LIB="${AID_TELEGRAM_LIB:-$_AID_ALERT_PRODUCTION_LIB}"

# _aid_alert_send <severity> <scope> <id> <what> <action> <context> <runbook> <state> <source>
#
# RETURNS THE TRUTH ABOUT DELIVERY: 0 delivered, 1 not delivered, 2 suppressed.
# The first version always returned 0 — "the alert path did not damage the FSM"
# — and the nightly reporter read that as "the message went out", so a night
# whose alert failed was recorded `notified: true` and NEVER RETRIED. That is
# the opposite of the mechanism it was built for. Callers that genuinely do not
# care (the FSM, mid-transition) discard it explicitly with `|| true`.
_aid_alert_send() {
  local severity="$1" scope="$2" id="$3" what="$4" action="$5"
  local context="${6:-}" runbook="${7:-}" state="${8:-}" source="${9:-aid}"

  # A sink records the composed call even when delivery is suppressed, so a
  # fixture can assert the FIELDS rather than merely that nothing crashed.
  if [[ -n "${AID_ALERT_SINK:-}" ]]; then
    {
      printf 'severity=%s\nscope=%s\nid=%s\nstate=%s\nsource=%s\n' \
        "$severity" "$scope" "$id" "$state" "$source"
      printf 'co=%s\nakce=%s\n' "$what" "$action"
      [[ -n "$context" ]] && printf 'kontext=%s\n' "$context"
      [[ -n "$runbook" ]] && printf 'runbook=%s\n' "$runbook"
      printf -- '---\n'
    } >> "$AID_ALERT_SINK" 2>/dev/null || true
  fi

  # TEST MODE SUPPRESSES THE PRODUCTION PATH, NOT A STUB.
  #
  # The first version had an AID_ALERT_FORCE escape hatch so the suites testing
  # this file could reach a sender — which meant any fixture with that variable,
  # real credentials and the default library could have sent a REAL Telegram.
  # The hatch is gone. What decides now is WHICH library is configured: a
  # fixture pointing at its own stub gets genuine (stubbed) delivery and an
  # honest return code, while a fixture that forgot to stub cannot reach the
  # real channel at all, because the production path is refused under test mode.
  if [[ "${AID_TEST_MODE:-0}" == "1" && "$AID_ALERT_TELEGRAM_LIB" == "$_AID_ALERT_PRODUCTION_LIB" ]]; then
    return 2
  fi

  if [[ ! -f "$AID_ALERT_TELEGRAM_LIB" ]]; then
    echo "aid-alert: no shared telegram library at ${AID_ALERT_TELEGRAM_LIB} — alert '${id}' not delivered (non-fatal)" >&2
    return 1
  fi

  # A SUBSHELL, not this one. The library is configurable and defines globals,
  # functions and possibly shell options; sourcing it into a live FSM shell
  # mid-transition is how a helper gets to change `set -e`, a trap or a function
  # the caller depends on. It also makes `declare -F send_alert` honest: in this
  # shell it could be true because some EARLIER library defined it, and the
  # wrong sender would then handle the alert.
  (
    # shellcheck source=/dev/null
    source "$AID_ALERT_TELEGRAM_LIB" 2>/dev/null || exit 3
    declare -F send_alert >/dev/null 2>&1 || exit 4
    send_alert "$severity" "$scope" "$id" "$what" "$action" \
               "$context" "$runbook" "$state" "$source"
  )
  local rc=$?
  case "$rc" in
    0) return 0 ;;
    3) echo "aid-alert: could not source ${AID_ALERT_TELEGRAM_LIB} — alert '${id}' not delivered (non-fatal)" >&2; return 1 ;;
    4) echo "aid-alert: ${AID_ALERT_TELEGRAM_LIB} defines no send_alert() — alert '${id}' not delivered (non-fatal). The standard's shared sender is what carries the mandatory fields." >&2; return 1 ;;
    *) echo "aid-alert: delivery of '${id}' failed (rc=${rc}, non-fatal); the run is unaffected" >&2; return 1 ;;
  esac
}

# aid_alert_run <severity> <id> <plan_or_epic> <what> <action> [context] [runbook]
#
# An alert about work that is RUNNING NOW. `plan_or_epic` is prepended to "Co"
# so the reader knows WHICH run before reading anything else — the state line
# has already told them it is a run at all.
aid_alert_run() {
  local severity="$1" id="$2" subject="$3" what="$4" action="$5"
  local context="${6:-}" runbook="${7:-}"
  local project; project="$(_aid_alert_project)"
  _aid_alert_send "$severity" "${project}-aid-beh" "$id" \
    "${subject} — ${what}" "$action" "$context" "$runbook" \
    "BĚŽÍCÍ PLÁN" "AID · ${project}"
}

# aid_alert_nightly <severity> <id> <what> <action> [context] [runbook]
#
# An alert about the nightly portfolio. Never about a running plan: those two
# were indistinguishable in the free-text era, which is the confusion this pair
# of helpers exists to end.
aid_alert_nightly() {
  local severity="$1" id="$2" what="$3" action="$4"
  local context="${5:-}" runbook="${6:-}"
  local project; project="$(_aid_alert_project)"
  _aid_alert_send "$severity" "${project}-aid-testy" "$id" \
    "$what" "$action" "$context" "$runbook" \
    "NOČNÍ TESTY" "AID · ${project} · noční běh"
}
