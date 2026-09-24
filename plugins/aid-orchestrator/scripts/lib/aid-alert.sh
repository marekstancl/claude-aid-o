#!/usr/bin/env bash
# =============================================================================
# lib/aid-alert.sh — THE one way AID speaks to a human outside the terminal
#
# Two messages, and only two (PM, P098 brainstorm, 2026-09-23): the agent has
# stopped and needs the PM (`aid_alert_waiting`), and a plan is delivered
# (`aid_alert_delivered`). Everything else AID knows lives in the timeline and
# on the pages; a message the PM does not act on teaches them to mute the
# channel. A third kind of message needs a visible change to this file.
#
# THE STANDARD: /ecosystem/operations/alerting-and-automation §2. The shared
# `send_alert()` in /opt/eco/services/scripts/lib/telegram-notify.sh assembles
# the mandatory fields; nothing here formats a message by hand.
#
# IT DEGRADES, NEVER FAILS. AID ships as a plugin into projects that have no
# /opt/eco/services at all: a missing library is a skipped alert and a note on
# stderr. AID_TEST_MODE=1 refuses the production library (a fixture must point
# AID_TELEGRAM_LIB at its own stub).
#
# ONE MESSAGE PER STOP. A waiting message leaves an open record in the session
# store (outside the tree) keyed by workspace and plan; while it is open, no
# session of that workspace sends another. The PM's next prompt clears it
# (`aid_alert_waiting_clear`, called by the UserPromptSubmit hook rule), so the
# next stop is announced again. `delivered` is sent once per plan.
#
# Sourced, never executed. Re-source safe.
# =============================================================================
if [[ -n "${_AID_ALERT_SH_LOADED:-}" ]] && declare -F aid_alert_waiting >/dev/null 2>&1; then
  return 0
fi
_AID_ALERT_SH_LOADED=1

# shellcheck source=aid-session-store.sh
source "$(dirname "${BASH_SOURCE[0]}")/aid-session-store.sh"

_AID_ALERT_PRODUCTION_LIB="/opt/eco/services/scripts/lib/telegram-notify.sh"

# _aid_alert_workspace — the main checkout of the repository this AID runs over:
# the same answer from the checkout and from any of its plan worktrees.
_aid_alert_workspace() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  if [[ -n "$common" ]]; then dirname "$common"; else pwd -P; fi
}

# _aid_alert_project — the project this AID is running over. Never fails: an
# unnamed project is still an alert worth sending, it just says "projekt".
_aid_alert_project() {
  local name
  name="$(basename "$(_aid_alert_workspace)")"
  # Scope is read by humans and grouped by machines; keep it to the characters
  # both handle without quoting.
  name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')"
  printf '%s' "${name:-projekt}"
}

# _aid_alert_send <severity> <scope> <id> <what> <action> <state> <source>
#
# Returns the truth about delivery: 0 delivered, 1 not delivered, 2 suppressed.
_aid_alert_send() {
  local severity="$1" scope="$2" id="$3" what="$4" action="$5" state="$6" source="$7"
  local lib="${AID_TELEGRAM_LIB:-$_AID_ALERT_PRODUCTION_LIB}"

  # Test mode refuses the production library, not a stub: a fixture that
  # forgot to stub cannot reach the real channel.
  if [[ "${AID_TEST_MODE:-0}" == "1" && "$lib" == "$_AID_ALERT_PRODUCTION_LIB" ]]; then
    return 2
  fi

  if [[ ! -f "$lib" ]]; then
    echo "aid-alert: no shared telegram library at ${lib} — alert '${id}' not delivered (non-fatal)" >&2
    return 1
  fi

  # A subshell: the library defines globals, functions and possibly shell
  # options, none of which may leak into the caller.
  (
    # shellcheck source=/dev/null
    source "$lib" 2>/dev/null || exit 3
    declare -F send_alert >/dev/null 2>&1 || exit 4
    send_alert "$severity" "$scope" "$id" "$what" "$action" "" "" "$state" "$source"
  )
  local rc=$?
  case "$rc" in
    0) return 0 ;;
    3) echo "aid-alert: could not source ${lib} — alert '${id}' not delivered (non-fatal)" >&2; return 1 ;;
    4) echo "aid-alert: ${lib} defines no send_alert() — alert '${id}' not delivered (non-fatal). The standard's shared sender is what carries the mandatory fields." >&2; return 1 ;;
    *) echo "aid-alert: delivery of '${id}' failed (rc=${rc}, non-fatal); the run is unaffected" >&2; return 1 ;;
  esac
}

# _aid_alert_record <plan_id> <kind> — the record file of one plan's alert kind.
_aid_alert_record() {
  local dir key
  dir="$(aid_session_store_dir alerts)" || return 1
  key="$(printf '%s' "$(_aid_alert_workspace)" | sha256sum | cut -c1-16)"
  printf '%s/%s_%s.%s\n' "$dir" "$key" "$1" "$2"
}

# _aid_alert_once <plan_id> <kind> <severity> <id> <state> <what> <action>
#   Sends unless the plan's <kind> record exists. The record is CLAIMED before
#   the send (created with noclobber, so of two sessions ending turns at once
#   only one sends) and released again when the send fails, with one line in
#   failures.jsonl — the next stop tries again. A store that cannot be written
#   (or a record nobody could clear again) still sends, without de-duplication.
_aid_alert_once() {
  local plan="$1" kind="$2" severity="$3" id="$4" state="$5" what="$6" action="$7" record project rc=0
  record="$(_aid_alert_record "$plan" "$kind")" || record=""
  if [[ -n "$record" && -w "$(dirname "$record")" ]]; then
    ( set -C; : > "$record" ) 2>/dev/null || return 0
  else
    echo "aid-alert: the alert store is not writable — '${id}' is sent without de-duplication" >&2
    record=""
  fi
  project="$(_aid_alert_project)"
  _aid_alert_send "$severity" "${project}-aid" "$id" "$what" "$action" "$state" "AID · ${project}" || rc=$?
  if (( rc != 0 )) && [[ -n "$record" ]]; then
    rm -f "$record"
    jq -nc --arg p "$plan" --arg id "$id" --argjson rc "$rc" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{at: $at, plan: $p, id: $id, rc: $rc}' >> "$(dirname "$record")/failures.jsonl" 2>/dev/null
  fi
  return "$rc"
}

# aid_alert_waiting <plan_id> <why> <next> — the agent has stopped and needs
# the PM. One message per stop, whichever session ends its turn.
aid_alert_waiting() {
  _aid_alert_once "$1" waiting warning agent-waiting "ČEKÁ NA TEBE" "${1}: agent stojí — ${2}" "$3"
}

# aid_alert_waiting_clear <plan_id> — the PM answered: the next stop is announced.
aid_alert_waiting_clear() {
  local record; record="$(_aid_alert_record "$1" waiting)" && rm -f "$record"
}

# aid_alert_delivered <plan_id> <evidence_dir> [forced] — the plan is delivered;
# sent once per plan. `forced` says the close was forced.
aid_alert_delivered() {
  local what="${1} dodán"
  [[ "${3:-}" == forced ]] && what="${1} dodán (uzavřen vynuceně)"
  _aid_alert_once "$1" delivered info plan-delivered "PLÁN DODÁN" "$what" "stránka dodávky: ${2}"
}
